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
                    hero
                    trendCard
                    statsGrid
                    macroCard
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
            }
            }
            .background(Theme.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showDayDetail) { DayDetailView(initialIndex: dayIndex) }
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

    // MARK: Hero — avg calories + adherence ring

    private var hero: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("AVG DAILY CALORIES").overlineStyle()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(avgCalories)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("kcal")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text("goal \(targets.calories) · \(periodLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            RingChart(progress: Double(adherence) / 100,
                      centerText: "\(adherence)%", subtitle: "on goal",
                      color: RingColor.protein.tint, lineWidth: 9)
                .frame(width: 92, height: 92)
                .id(period)   // re-animate the ring when the period changes
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
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

    // MARK: Kanban-style stat cards

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            statCard("On target", .brown, "\(onTargetCount)/\(days.count)", "days within goal")
            statCard("Protein", .orange, "\(avgProtein)g", "avg · goal \(Int(targets.protein))g")
            statCard("Streak", .blue, "\(bestStreak) days", "best on-target run")
            statCard("Vs goal", .purple, "\(goalPct)%", "avg intake of goal")
        }
    }

    private func statCard(_ tag: String, _ tagColor: TagColor, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TagPill(text: tag, color: tagColor)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
    }

    // MARK: Macro averages (share of goal)

    private var macroShares: [MacroShare] {
        [
            MacroShare(label: "Carbs",   grams: avg(\.carbs),   target: targets.carbs,   colors: RingColor.carb.stops),
            MacroShare(label: "Protein", grams: avg(\.protein), target: targets.protein, colors: RingColor.protein.stops),
            MacroShare(label: "Fat",     grams: avg(\.fat),     target: targets.fat,     colors: Theme.macroFatStops),
            MacroShare(label: "Fibre",   grams: avg(\.fibre),   target: targets.fibre,   colors: RingColor.fibre.stops),
        ]
    }

    private var macroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AVG MACROS · SHARE OF GOAL").overlineStyle()
            ForEach(macroShares) { s in
                VStack(spacing: 7) {
                    HStack(spacing: 8) {
                        Circle().fill(LinearGradient(colors: s.colors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: 7, height: 7)
                        Text(s.label).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 8)
                        Text("\(Int(s.grams.rounded())) g")
                            .font(.system(size: 14, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                        Text(s.percentText)
                            .font(.system(size: 12, weight: .medium)).monospacedDigit()
                            .foregroundStyle(Theme.textTertiary).frame(width: 40, alignment: .trailing)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill((s.colors.first ?? .white).opacity(0.14))
                            Capsule().fill(LinearGradient(colors: s.colors, startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(4, geo.size.width * s.pct))
                        }
                    }
                    .frame(height: 6)
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

#Preview {
    HistoryView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
