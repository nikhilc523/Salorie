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
    @State private var selectedStat: StatCardData?

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
                    statsCarousel
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
                if ProcessInfo.processInfo.environment["SALORIE_STAT"] == "1" {
                    selectedStat = statCards[min(1, statCards.count - 1)]
                }
            }
            }
            .background(Theme.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showDayDetail) { DayDetailView(initialIndex: dayIndex) }
            .sheet(item: $selectedStat) { StatDetailView(kind: $0.kind, initialPeriod: period, targets: targets) }
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

    // MARK: Stats carousel — Apple-Health cards (Calories · macros · adherence)

    /// Headline number on a card for the current period.
    private func headline(_ kind: StatKind) -> Double {
        kind == .onTarget ? Double(adherence) : avg(kind.dayValue)
    }
    private func subtitle(_ kind: StatKind) -> String {
        kind == .onTarget ? "of days on target · \(periodLabel)" : "avg / day · \(periodLabel)"
    }
    private func goalCaption(_ kind: StatKind) -> String {
        if kind == .onTarget { return "\(onTargetCount)/\(days.count) days · streak \(bestStreak)" }
        let g = kind.grouped ? Int(kind.goal(targets)).formatted() : "\(Int(kind.goal(targets)))"
        return "goal \(g) \(kind.unit) · \(periodLabel)"
    }

    private var statCards: [StatCardData] {
        StatKind.allCases.map { kind in
            StatCardData(
                kind: kind,
                value: headline(kind),
                subtitle: subtitle(kind),
                caption: goalCaption(kind),
                goal: kind.goal(targets),
                bars: statSeries(kind, period, store).bars
            )
        }
    }

    private var statsCarousel: some View {
        StackedCardsCarousel(items: statCards, cardWidth: 268, cardHeight: 316) { card, isFront in
            BigStatCard(title: card.kind.title, subtitle: card.subtitle, value: card.value,
                        grouped: card.kind.grouped, unit: card.kind.unit, bars: card.bars,
                        goal: card.goal, numberColor: card.kind.numberColor,
                        barColors: card.kind.barColors, animate: isFront)
                .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .onTapGesture { if isFront { HapticManager.shared.trigger(.light); selectedStat = card } }
        }
        .offset(x: -16)   // nudge the deck slightly left (matches the reference framing)
    }

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
    case calories, protein, carbs, fat, fibre, onTarget
    var id: String { rawValue }

    var title: String {
        switch self {
        case .calories: "Calories"; case .protein: "Protein"; case .carbs: "Carbs"
        case .fat: "Fat"; case .fibre: "Fibre"; case .onTarget: "On Target"
        }
    }
    var unit: String { switch self { case .calories: "kcal"; case .onTarget: "%"; default: "g" } }
    var grouped: Bool { self == .calories }

    /// The big number / title tone — the lighter warm shade.
    var numberColor: Color {
        let hex: UInt = switch self {
        case .calories: 0xE7C39A
        case .protein:  0xEAD8B4
        case .carbs:    0xE3A87C
        case .fat:      0xEFE6D2
        case .fibre:    0xE9C79A
        case .onTarget: 0xE7C39A
        }
        return Color(hex: hex)
    }

    /// The bar-graph gradient — a deeper tone, so bars read distinct from the
    /// number (top → bottom, light-deep → deep). Different colour = looks great.
    var barColors: [Color] {
        let hex: [UInt] = switch self {
        case .calories: [0xC97F5A, 0xB3664C]
        case .protein:  [0xD1A67A, 0xB98A5E]
        case .carbs:    [0xBE6E4E, 0xA85A3E]
        case .fat:      [0xD3C094, 0xB89E6E]
        case .fibre:    [0xCE8C5C, 0xB06A42]
        case .onTarget: [0xC97F5A, 0xB3664C]
        }
        return hex.map { Color(hex: $0) }
    }

    func dayValue(_ d: DayLog) -> Double {
        switch self {
        case .calories, .onTarget: Double(d.calories)
        case .protein: d.protein; case .carbs: d.carbs
        case .fat: d.fat; case .fibre: d.fibre
        }
    }
    func goal(_ t: MacroTargets) -> Double {
        switch self {
        case .calories, .onTarget: Double(t.calories)
        case .protein: t.protein; case .carbs: t.carbs
        case .fat: t.fat; case .fibre: t.fibre
        }
    }
}

private struct StatCardData: Identifiable {
    let id = UUID()
    let kind: StatKind
    let value: Double
    let subtitle: String
    let caption: String
    let goal: Double
    let bars: [StatBar]
}

private func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }

/// Per-period bars + average for a metric — shared by the card and its detail.
/// Week → 7 days, Month → 30 days, Year → 12 monthly averages.
@MainActor
private func statSeries(_ kind: StatKind, _ period: HistoryView.Period, _ store: MockStore) -> (bars: [StatBar], avg: Double) {
    let cal = Calendar.current
    switch period {
    case .week:
        // Full week, Mon…Sun weekday labels (Apple shows all seven).
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
        // Twelve fixed month slots J…D of the reference year; empty months show
        // no bar (mirrors Apple's year chart), single-letter month labels.
        let fmt = DateFormatter(); fmt.dateFormat = "LLLLL"
        let year = cal.component(.year, from: store.today)
        var sum = [Double](repeating: 0, count: 12)
        var cnt = [Int](repeating: 0, count: 12)
        for d in store.dailyLog where cal.component(.year, from: d.date) == year {
            let m = cal.component(.month, from: d.date) - 1
            sum[m] += kind.dayValue(d); cnt[m] += 1
        }
        let bars: [StatBar] = (0..<12).map { m in
            let date = cal.date(from: DateComponents(year: year, month: m + 1, day: 1)) ?? store.today
            let v = cnt[m] > 0 ? sum[m] / Double(cnt[m]) : 0
            return StatBar(index: m, label: fmt.string(from: date), value: v)
        }
        let present = bars.map(\.value).filter { $0 > 0 }
        return (bars, mean(present))
    }
}

// MARK: - Stat detail (Apple Health style: title · W/M/Y · detailed chart)

/// Tap a stat card → its own screen: bold title, a W/M/Y period switcher, and a
/// detailed bar chart with a labelled y-axis, gridlines, and a goal line — plus
/// low / avg / high for the period. Day view is intentionally omitted.
private struct StatDetailView: View {
    let kind: StatKind
    let targets: MacroTargets
    @Environment(MockStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var period: HistoryView.Period

    init(kind: StatKind, initialPeriod: HistoryView.Period, targets: MacroTargets) {
        self.kind = kind
        self.targets = targets
        _period = State(initialValue: initialPeriod)
    }

    private var barGrad: LinearGradient { LinearGradient(colors: kind.barColors, startPoint: .top, endPoint: .bottom) }
    private var series: (bars: [StatBar], avg: Double) { statSeries(kind, period, store) }
    private var bars: [StatBar] { series.bars }
    private var goal: Double { kind.goal(targets) }
    private var barWidth: CGFloat {
        switch period { case .week: 26; case .month: 6; case .year: 16 }
    }
    private func fmt(_ v: Double) -> String { kind.grouped ? Int(v).formatted() : "\(Int(v.rounded()))" }

    private var periodDays: [DayLog] {
        switch period { case .week: store.history; case .month: Array(store.dailyLog.suffix(30)); case .year: store.dailyLog }
    }
    private var periodLabel: String {
        switch period { case .week: "This week"; case .month: "Last 30 days"; case .year: "This year" }
    }
    private var presentValues: [Double] { bars.map(\.value).filter { $0 > 0 } }
    private var value: Double {
        if kind == .onTarget {
            let d = periodDays
            let on = d.filter { Double($0.calories) <= Double(targets.calories) * 1.05 }.count
            return d.isEmpty ? 0 : Double(on) / Double(d.count) * 100
        }
        return series.avg
    }
    /// X positions that get a dashed gridline + label (Apple's column grid).
    private var labelTicks: [Int] {
        switch period {
        case .week: Array(bars.indices)                                  // all 7 weekdays
        case .month: stride(from: 0, through: bars.count - 1, by: 7).map { $0 }  // 1·8·15·22·29
        case .year: Array(bars.indices)                                  // all 12 months
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(periodLabel)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    periodPicker
                    chartCard
                    HStack(spacing: 12) {
                        miniStat("LOW", presentValues.min() ?? 0)
                        miniStat("AVG", series.avg)
                        miniStat("HIGH", presentValues.max() ?? 0)
                    }
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

    // W / M / Y capsule switcher (Day intentionally omitted).
    private var periodPicker: some View {
        HStack(spacing: 4) {
            ForEach(HistoryView.Period.allCases) { p in
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

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kind.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(fmt(value))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(kind.numberColor).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(kind.unit).font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(kind.numberColor.opacity(0.7))
            }
            .animation(.snappy, value: period)

            Chart {
                ForEach(bars) { bar in
                    if bar.value > 0 {
                        BarMark(x: .value("i", bar.index), y: .value("v", bar.value), width: .fixed(barWidth))
                            .foregroundStyle(barGrad)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
            }
            .frame(height: 220)
            // Right pad on Week so the last weekday label clears the y-axis labels.
            .chartXScale(domain: -0.6 ... (Double(bars.count) - 0.5 + (period == .week ? 1.0 : 0.3)))
            .chartYScale(domain: .automatic(includesZero: true))
            // Right-side y labels + faint horizontal gridlines (Apple)
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
            // Vertical dashed column gridlines + date labels (Apple)
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
    }

    private func miniStat(_ label: String, _ v: Double) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(Theme.textTertiary)
            Text(fmt(v))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
    }
}

#Preview {
    HistoryView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
