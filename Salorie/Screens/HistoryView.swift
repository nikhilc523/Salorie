import SwiftUI
import Charts

/// History — trends across Week / Month / Year, built from the logged daily data:
/// average calories, adherence, macro averages, a calorie trend chart, and (for the
/// week) a tappable ring strip + daily table that drills into a day.
struct HistoryView: View {
    @Environment(MockStore.self) private var store

    enum Period: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month", year = "Year"
        var id: String { rawValue }
        var short: String { switch self { case .week: "W"; case .month: "M"; case .year: "Y" } }
    }
    @State private var period: Period = {
        switch ProcessInfo.processInfo.environment["SALORIE_PERIOD"] {
        case "month": return .month
        case "year":  return .year
        default:      return .week
        }
    }()
    @State private var showDayDetail = false
    @State private var dayIndex = 0
    @State private var selectedKind: StatKind?   // screenshot/testing hook only
    @State private var statTestPeriod: StatPeriod = {
        switch ProcessInfo.processInfo.environment["SALORIE_STAT"] {
        case "year": return .year; case "week": return .week
        case "month": return .month; default: return .day
        }
    }()

    // MARK: Period slice

    private var days: [DayLog] {
        switch period {
        case .week:  return store.history                       // curated 7 (matches day-detail)
        case .month: return Array(store.dailyLog.suffix(30))
        case .year:  return store.dailyLog
        }
    }
    private var targets: MacroTargets { store.targets }
    private var periodLabel: String {
        switch period { case .week: "this week"; case .month: "last 30 days"; case .year: "this year" }
    }

    // MARK: Derived stats

    private func onTarget(_ d: DayLog) -> Bool { Double(d.calories) <= Double(targets.calories) * 1.05 }
    private var onTargetCount: Int { days.filter(onTarget).count }
    private var avgCalories: Int { days.isEmpty ? 0 : days.map(\.calories).reduce(0, +) / days.count }
    private var goalPct: Int { targets.calories > 0 ? Int((Double(avgCalories) / Double(targets.calories) * 100).rounded()) : 0 }
    private var adherence: Int { days.isEmpty ? 0 : Int((Double(onTargetCount) / Double(days.count) * 100).rounded()) }
    private func avg(_ kp: (DayLog) -> Double) -> Double { days.isEmpty ? 0 : days.map(kp).reduce(0, +) / Double(days.count) }
    private var avgProtein: Int { Int(avg(\.protein).rounded()) }
    private var bestStreak: Int {
        var best = 0, cur = 0
        for d in days { if onTarget(d) { cur += 1; best = max(best, cur) } else { cur = 0 } }
        return best
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    NotionPageHeader(symbol: "chart.xyaxis.line", tint: .brown, title: "History",
                                     subtitle: "Trends across your logged days")
                    periodPicker
                    trendCard
                    if period == .week {
                        weekRingStrip
                        dailyLogTable
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, 24)
            }
            .onAppear {
                if ProcessInfo.processInfo.environment["SALORIE_SCROLL"] == "bottom" {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                if ProcessInfo.processInfo.environment["SALORIE_STAT"] != nil {
                    selectedKind = .protein
                }
            }
            }
            .background(Theme.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showDayDetail) { DayDetailView(initialIndex: dayIndex) }
            .sheet(item: $selectedKind) { StatDetailView(kind: $0, initialPeriod: statTestPeriod, day: store.history.last, targets: targets) }
        }
    }

    // MARK: Period picker (uniform neutral pills)

    private var periodPicker: some View {
        HStack(spacing: 8) {
            ForEach(Period.allCases) { p in
                let isOn = period == p
                Button {
                    HapticManager.shared.trigger(.selection)
                    withAnimation(.snappy) { period = p }
                } label: {
                    Text(p.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isOn ? Color(hex: 0x000000) : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(isOn ? Theme.textPrimary : Theme.surface))
                        .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: isOn ? 0 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // NOTE: the stat-card carousel was removed from History — per-nutrient charts
    // are now reached by tapping a nutrient in the Day detail. The reusable
    // StackedCardsCarousel / BigStatCard components are kept for future use.

    // MARK: Trend chart

    private struct TrendPoint: Identifiable {
        let id = UUID(); let index: Int; let label: String; let value: Int
    }

    private var trend: [TrendPoint] {
        switch period {
        case .week:
            return days.enumerated().map { i, d in TrendPoint(index: i, label: d.weekdayLetter, value: d.calories) }
        case .month:
            let fmt = DateFormatter(); fmt.dateFormat = "d"
            return days.enumerated().map { i, d in TrendPoint(index: i, label: fmt.string(from: d.date), value: d.calories) }
        case .year:
            return monthlyAverages()
        }
    }

    private func monthlyAverages() -> [TrendPoint] {
        let cal = Calendar.current
        let fmt = DateFormatter(); fmt.dateFormat = "LLL"
        var order: [Int] = []; var sum: [Int: Int] = [:]; var count: [Int: Int] = [:]; var label: [Int: String] = [:]
        for d in store.dailyLog {
            let key = cal.component(.year, from: d.date) * 12 + cal.component(.month, from: d.date)
            if sum[key] == nil { order.append(key); label[key] = fmt.string(from: d.date) }
            sum[key, default: 0] += d.calories; count[key, default: 0] += 1
        }
        return order.enumerated().map { i, key in
            TrendPoint(index: i, label: label[key] ?? "", value: sum[key]! / max(1, count[key]!))
        }
    }

    private var barWidth: CGFloat { switch period { case .week: 22; case .month: 7; case .year: 18 } }
    private var xTicks: [Int] {
        switch period {
        case .week, .year: return Array(trend.indices)
        case .month: return stride(from: 0, to: trend.count, by: 6).map { $0 }
        }
    }
    private var trendMaxY: Double {
        Double(max(targets.calories, trend.map(\.value).max() ?? 0)) * 1.12
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CALORIE TREND").overlineStyle()
            Chart {
                ForEach(trend) { p in
                    BarMark(x: .value("i", p.index), y: .value("kcal", p.value), width: .fixed(barWidth))
                        .foregroundStyle(RingColor.calories.tint)
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                }
                RuleMark(y: .value("goal", targets.calories))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .foregroundStyle(Theme.textTertiary.opacity(0.6))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("goal \(targets.calories)")
                            .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    }
            }
            .frame(height: 150)
            .chartXScale(domain: -0.7 ... (Double(trend.count) - 0.3))
            .chartYScale(domain: 0 ... trendMaxY)
            .chartYAxis {
                AxisMarks(values: [0, targets.calories]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4])).foregroundStyle(Theme.divider)
                    if let v = value.as(Int.self), v > 0 {
                        AxisValueLabel { Text("\(v)").font(.system(size: 11)).foregroundStyle(Theme.textTertiary) }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: xTicks) { value in
                    AxisValueLabel {
                        if let i = value.as(Int.self), let p = trend.first(where: { $0.index == i }) {
                            Text(p.label).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
    }

    // MARK: Week ring strip (tappable → day detail)

    private var weekRingStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("THIS WEEK").overlineStyle()
            HStack(spacing: 0) {
                ForEach(Array(store.history.enumerated()), id: \.element.id) { i, day in
                    Button {
                        HapticManager.shared.trigger(.selection)
                        dayIndex = i; showDayDetail = true
                    } label: {
                        VStack(spacing: 10) {
                            MiniDayRing(rings: rings(for: day), size: 42, lineWidth: 4.5)
                            Text(day.weekdayLetter)
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textTertiary)
                            Text("\(day.calories)")
                                .font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func rings(for day: DayLog) -> [Ring] {
        [
            Ring(progress: Double(day.calories) / Double(targets.calories), color: .calories, label: "Calories", valueText: ""),
            Ring(progress: day.protein / targets.protein, color: .protein, label: "Protein", valueText: ""),
            Ring(progress: day.carbs / targets.carbs, color: .carb, label: "Carbs", valueText: ""),
        ]
    }

    // MARK: Daily log table (week)

    private var dailyLogTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DAILY LOG").overlineStyle()
            NotionTable(
                columns: [
                    NotionColumn(title: "Cal", width: 44, alignment: .trailing),
                    NotionColumn(title: "Protein", width: 54, alignment: .trailing),
                    NotionColumn(title: "Carbs", width: 52, alignment: .trailing),
                ],
                rows: Array(store.history.enumerated()).reversed().map { i, day in
                    NotionRow(
                        icon: "calendar",
                        tint: onTarget(day) ? .brown : .orange,
                        name: day.date.formatted(.dateTime.weekday(.wide).month().day()),
                        cells: [
                            .number("\(day.calories)"),
                            .macro(.protein, "\(Int(day.protein))g"),
                            .macro(.carb, "\(Int(day.carbs))g"),
                        ],
                        onTap: { dayIndex = i; showDayDetail = true }
                    )
                },
                showCount: false,
                showNewRow: false,
                fitWidth: true,
                thickDividers: true
            )
        }
    }
}

// MARK: - Stat metric model

/// The six metrics shown in the History carousel. Encapsulates title, unit,
/// color, goal, and how to read the value off a `DayLog`, so the card and the
/// detail view share one source of truth.
enum StatKind: String, CaseIterable, Identifiable {
    case calories, protein, carbs, fat, fibre, saturatedFat, sugars, sodium, cholesterol, onTarget
    var id: String { rawValue }

    var title: String {
        switch self {
        case .calories: "Calories"; case .protein: "Protein"; case .carbs: "Carbs"
        case .fat: "Total Fat"; case .fibre: "Dietary Fibre"; case .saturatedFat: "Saturated Fat"
        case .sugars: "Sugars"; case .sodium: "Sodium"; case .cholesterol: "Cholesterol"
        case .onTarget: "On Target"
        }
    }
    var unit: String {
        switch self {
        case .calories: "kcal"; case .onTarget: "%"
        case .sodium, .cholesterol: "mg"; default: "g"
        }
    }
    var grouped: Bool { self == .calories }

    /// Number tone — matched to the bars (Apple-authentic: number == bar colour).
    /// Uses the bar gradient's top tone so the number reads as the same hue.
    var numberColor: Color { barColors.first ?? .white }

    /// The bar-graph gradient (top → bottom). One warm tone per metric for now;
    /// the number matches its top tone. (Palette to be finalised later.)
    var barColors: [Color] {
        let hex: [UInt] = switch self {
        case .calories: [0xC97F5A, 0xB3664C]
        case .protein, .sugars: [0xD1A67A, 0xB98A5E]
        case .carbs:    [0xBE6E4E, 0xA85A3E]
        case .fat, .saturatedFat: [0xD3C094, 0xB89E6E]
        case .fibre, .sodium: [0xCE8C5C, 0xB06A42]
        case .cholesterol, .onTarget: [0xC97F5A, 0xB3664C]
        }
        return hex.map { Color(hex: $0) }
    }

    func dayValue(_ d: DayLog) -> Double {
        switch self {
        case .calories, .onTarget: Double(d.calories)
        case .protein: d.protein; case .carbs: d.carbs
        case .fat: d.fat; case .fibre: d.fibre
        case .saturatedFat: d.saturatedFat; case .sugars: d.sugars
        case .sodium: d.sodium; case .cholesterol: d.cholesterol
        }
    }
    /// Per-logged-entry value — powers the hourly Day chart.
    func entryValue(_ e: MealEntry) -> Double {
        switch self {
        case .calories, .onTarget: Double(e.calories)
        case .protein: e.protein; case .carbs: e.carbs
        case .fat: e.fat; case .fibre: e.fibre
        case .saturatedFat: e.saturatedFat; case .sugars: e.sugars
        case .sodium: e.sodium; case .cholesterol: e.cholesterol
        }
    }
    func goal(_ t: MacroTargets) -> Double {
        switch self {
        case .calories, .onTarget: Double(t.calories)
        case .protein: t.protein; case .carbs: t.carbs
        case .fat: t.fat; case .fibre: t.fibre
        case .sodium: 2300
        case .saturatedFat, .sugars, .cholesterol: 0
        }
    }
}

// MARK: - Detail period (D · W · M · Y)

enum StatPeriod: String, CaseIterable, Identifiable {
    case day, week, month, year
    var id: String { rawValue }
    var short: String { switch self { case .day: "D"; case .week: "W"; case .month: "M"; case .year: "Y" } }
}

/// Parse an "8:24 AM" style string into an hour 0…23 (shared with DayDetail).
func statHour(from time: String) -> Int {
    let comps = time.split(separator: " ")
    guard let clock = comps.first, let hStr = clock.split(separator: ":").first,
          var h = Int(hStr) else { return 12 }
    let pm = comps.count > 1 && comps[1].uppercased() == "PM"
    if pm && h != 12 { h += 12 }
    if !pm && h == 12 { h = 0 }
    return h
}

private func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }

private func hourAxisLabel(_ h: Int) -> String {
    switch h { case 0: "12AM"; case 6: "6AM"; case 12: "12PM"; case 18: "6PM"; default: "" }
}

/// Bars for a metric over a detail period. Day → 24 hourly slots for `day`;
/// Week → 7 days; Month → last 30 days; Year → 12 fixed months of `year`.
@MainActor
private func statSeries(_ kind: StatKind, _ period: StatPeriod, year: Int, day: DayLog?, _ store: MockStore) -> (bars: [StatBar], avg: Double) {
    let cal = Calendar.current
    switch period {
    case .day:
        // 24 hourly slots for the referenced day; labels at 12AM·6AM·12PM·6PM.
        let d = day ?? store.history.last ?? DayLog(date: store.today, weekdayLetter: "", entries: [])
        var perHour = [Double](repeating: 0, count: 24)
        for e in d.entries { perHour[min(23, max(0, statHour(from: e.time)))] += kind.entryValue(e) }
        let bars = (0..<24).map { h in StatBar(index: h, label: hourAxisLabel(h), value: perHour[h]) }
        return (bars, mean(perHour.filter { $0 > 0 }))
    case .week:
        // Full week, weekday labels (Apple shows all seven).
        let fmt = DateFormatter(); fmt.dateFormat = "EEE"
        let days = store.history
        let bars = days.enumerated().map { i, d in StatBar(index: i, label: fmt.string(from: d.date), value: kind.dayValue(d)) }
        return (bars, mean(bars.map(\.value)))
    case .month:
        // Last 30 days, day-of-month labels (ticks land on 1·8·15·22·29).
        let days = Array(store.dailyLog.suffix(30))
        let fmt = DateFormatter(); fmt.dateFormat = "d"
        let bars = days.enumerated().map { i, d in StatBar(index: i, label: fmt.string(from: d.date), value: kind.dayValue(d)) }
        return (bars, mean(bars.map(\.value)))
    case .year:
        // Twelve fixed month slots J…D of `year`; empty months show no bar.
        let fmt = DateFormatter(); fmt.dateFormat = "LLLLL"
        var sum = [Double](repeating: 0, count: 12), cnt = [Int](repeating: 0, count: 12)
        for d in store.dailyLog where cal.component(.year, from: d.date) == year {
            let m = cal.component(.month, from: d.date) - 1
            sum[m] += kind.dayValue(d); cnt[m] += 1
        }
        let bars: [StatBar] = (0..<12).map { m in
            let date = cal.date(from: DateComponents(year: year, month: m + 1, day: 1)) ?? store.today
            return StatBar(index: m, label: fmt.string(from: date), value: cnt[m] > 0 ? sum[m] / Double(cnt[m]) : 0)
        }
        return (bars, mean(bars.map(\.value).filter { $0 > 0 }))
    }
}

/// Distinct years present in the log, newest first (for the year dropdown).
@MainActor
private func availableYears(_ store: MockStore) -> [Int] {
    let cal = Calendar.current
    return Set(store.dailyLog.map { cal.component(.year, from: $0.date) }).sorted(by: >)
}

// MARK: - Stat detail (Apple Health single-metric screen: D · W · M · Y)

/// Opened by tapping a nutrient. Mirrors Apple Health's single-metric screen:
/// bold title, a D/W/M/Y switcher (+ a year dropdown in Year), a Total/Average
/// number with unit, and a full-bleed bar chart with a right-side y-axis, faint
/// horizontal gridlines and dashed vertical column gridlines. Day = hourly.
struct StatDetailView: View {
    let kind: StatKind
    let referenceDay: DayLog?
    let targets: MacroTargets
    @Environment(MockStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var period: StatPeriod
    @State private var year: Int

    init(kind: StatKind, initialPeriod: StatPeriod, day: DayLog?, targets: MacroTargets) {
        self.kind = kind
        self.referenceDay = day
        self.targets = targets
        _period = State(initialValue: initialPeriod)
        _year = State(initialValue: Calendar.current.component(.year, from: day?.date ?? SampleData.referenceDate))
    }

    private var barGrad: LinearGradient { LinearGradient(colors: kind.barColors, startPoint: .top, endPoint: .bottom) }
    private var series: (bars: [StatBar], avg: Double) { statSeries(kind, period, year: year, day: referenceDay, store) }
    private var bars: [StatBar] { series.bars }
    private var barWidth: CGFloat {
        switch period { case .day: 5; case .week: 26; case .month: 6; case .year: 16 }
    }
    private func fmt(_ v: Double) -> String { kind.grouped ? Int(v).formatted() : "\(Int(v.rounded()))" }

    private var periodDays: [DayLog] {
        switch period {
        case .day: referenceDay.map { [$0] } ?? []
        case .week: store.history
        case .month: Array(store.dailyLog.suffix(30))
        case .year: store.dailyLog.filter { Calendar.current.component(.year, from: $0.date) == year }
        }
    }
    private var presentValues: [Double] { bars.map(\.value).filter { $0 > 0 } }

    /// Day → total for the day; W/M/Y → average per day; onTarget → adherence %.
    private var headline: Double {
        if kind == .onTarget {
            let d = periodDays
            let on = d.filter { Double($0.calories) <= Double(targets.calories) * 1.05 }.count
            return d.isEmpty ? 0 : Double(on) / Double(d.count) * 100
        }
        return period == .day ? presentValues.reduce(0, +) : series.avg
    }
    private var statLabel: String { period == .day ? "Total" : "Average" }
    private var subtitle: String {
        switch period {
        case .day:
            let d = referenceDay?.date ?? store.today
            return Calendar.current.isDate(d, inSameDayAs: store.today)
                ? "Today" : d.formatted(.dateTime.weekday(.wide).month().day())
        case .week: return "This Week"
        case .month: return "Last 30 Days"
        case .year: return "\(year)"
        }
    }

    /// X positions that get a dashed gridline + label (Apple's column grid).
    private var labelTicks: [Int] {
        switch period {
        case .day: [0, 6, 12, 18]                                          // 12AM·6AM·12PM·6PM
        case .week: Array(bars.indices)                                    // all 7 weekdays
        case .month: stride(from: 0, through: bars.count - 1, by: 7).map { $0 }  // 1·8·15·22·29
        case .year: Array(bars.indices)                                    // all 12 months
        }
    }
    private var xDomain: ClosedRange<Double> {
        let rightPad: Double = period == .week ? 1.0 : (period == .day ? 0.5 : 0.3)
        return -0.6 ... (Double(bars.count) - 0.5 + rightPad)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(kind.title)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    periodPicker
                    if period == .year { yearMenu }
                    numberBlock
                    chart
                }
                .padding(Metrics.pagePadding)
                .padding(.bottom, 30)
            }
            .background(Theme.bg)
            .scrollContentBackground(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { HapticManager.shared.trigger(.light); dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var periodPicker: some View {
        HStack(spacing: 4) {
            ForEach(StatPeriod.allCases) { p in
                let isOn = period == p
                Button {
                    HapticManager.shared.trigger(.selection)
                    withAnimation(.snappy) { period = p }
                } label: {
                    Text(p.short)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isOn ? Theme.textPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isOn ? Theme.surfaceRaised : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.surface, in: Capsule())
    }

    private var yearMenu: some View {
        Menu {
            ForEach(availableYears(store), id: \.self) { y in
                Button {
                    HapticManager.shared.trigger(.selection)
                    withAnimation(.snappy) { year = y }
                } label: {
                    if y == year { Label("\(y)", systemImage: "checkmark") } else { Text(String(y)) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(String(year)).font(.system(size: 15, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))
        }
    }

    private var numberBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(statLabel).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(fmt(headline))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(kind.numberColor).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(kind.unit).font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(kind.numberColor.opacity(0.7))
            }
            Text(subtitle).font(.system(size: 15)).foregroundStyle(Theme.textTertiary)
        }
        .animation(.snappy, value: period)
        .animation(.snappy, value: year)
    }

    private var chart: some View {
        Chart {
            ForEach(bars) { bar in
                if bar.value > 0 {
                    BarMark(x: .value("i", bar.index), y: .value("v", bar.value), width: .fixed(barWidth))
                        .foregroundStyle(barGrad)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
        }
        .frame(height: 260)
        .chartXScale(domain: xDomain)
        .chartYScale(domain: .automatic(includesZero: true))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Theme.divider.opacity(0.55))
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(kind.grouped ? Int(d).formatted() : "\(Int(d))")
                            .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: labelTicks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .foregroundStyle(Theme.divider.opacity(0.8))
                AxisValueLabel {
                    if let i = value.as(Int.self), let b = bars.first(where: { $0.index == i }) {
                        Text(b.label).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }
}

#Preview {
    HistoryView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
