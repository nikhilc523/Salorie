import SwiftUI
import Charts

/// Full day breakdown, shown when tapping into a specific day (ref: day-detail screenshot).
/// Week selector · large hero ring · big value/target metric · clean intake bar chart.
struct DayDetailView: View {
    @Environment(MockStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var index: Int
    @State private var selectedNutrient: StatKind?
    @State private var selectedFood: Food?
    @State private var selectedMeal: Food?
    init(initialIndex: Int) { _index = State(initialValue: initialIndex) }

    private var day: DayLog {
        let h = store.history
        guard !h.isEmpty else { return store.todayLog }          // never subscript an empty history
        return h[max(0, min(index, h.count - 1))]                 // clamp into range (no negative index)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    weekSelector
                    heroRing
                    macroCards
                    nutritionDetails
                    timelineSection
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.vertical, 8)
                .padding(.bottom, 30)
            }
            .background(Theme.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.shared.trigger(.light)
                        dismiss()
                    } label: { Image(systemName: "xmark") }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            // Screenshot hook: SALORIE_STAT=carbs opens that metric's D/W/M/Y detail.
            if let raw = ProcessInfo.processInfo.environment["SALORIE_STAT"],
               let kind = StatKind(rawValue: raw) {
                selectedNutrient = kind
            }
        }
        .sheet(item: $selectedNutrient) { kind in
            StatDetailView(kind: kind, initialPeriod: .day, day: day, targets: store.targets)
        }
        .sheet(item: $selectedFood) { FoodDetailView(food: $0) }
        .sheet(item: $selectedMeal) { MealDetailView(meal: $0) }
    }

    /// Open a tapped timeline entry: a custom meal shows the full meal detail (with all its
    /// items); a single food shows the food detail.
    private func openEntry(_ food: Food) {
        HapticManager.shared.trigger(.light)
        if food.isCustomMeal { selectedMeal = food } else { selectedFood = food }
    }

    /// Present the per-metric D/W/M/Y detail for a tapped nutrient.
    private func openNutrient(_ kind: StatKind) {
        HapticManager.shared.trigger(.light)
        selectedNutrient = kind
    }

    // MARK: Week day selector

    private var weekSelector: some View {
        HStack(spacing: 4) {
            ForEach(Array(store.history.enumerated()), id: \.element.id) { i, d in
                Button {
                    HapticManager.shared.trigger(.selection)
                    withAnimation(.snappy) { index = i }
                } label: {
                    VStack(spacing: 8) {
                        Text(d.weekdayLetter)
                            .font(.system(size: 12, weight: i == index ? .bold : .semibold))
                            .foregroundStyle(i == index ? Color.white : Theme.textTertiary)
                        MiniSunRings(calories: frac(d.calories, over: store.targets.calories),
                                     protein: frac(d.protein, over: store.targets.protein),
                                     carbs: frac(d.carbs, over: store.targets.carbs))
                            .frame(width: 34)
                            .opacity(i == index ? 1 : 0.45)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    // Selection is shown by the white day-letter + full-opacity rings —
                    // no grey rectangle behind the day.
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Hero ring

    private var heroRing: some View {
        // Same rising-sun rings as Home (no pills, no weight line). The per-macro
        // numbers live in the cards below, so there's no stats row here.
        SalorieRings(
            calories: frac(day.calories, over: store.targets.calories),
            protein: frac(day.protein, over: store.targets.protein),
            carbs: frac(day.carbs, over: store.targets.carbs),
            showPills: false
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: Per-macro mini cards (Apple-Health style: number + hourly chart + arrow)

    private struct MacroHourBar: Identifiable {
        let id = UUID()
        let hour: Int
        let value: Double  // this hour's amount (non-cumulative)
    }

    /// One bar per hour of the day (non-cumulative), midnight → 11 pm.
    private func macroPerHour(_ valueFor: (MealEntry) -> Double) -> [MacroHourBar] {
        var perHour = [Double](repeating: 0, count: 24)
        for e in day.entries {
            perHour[min(23, max(0, Self.hour(from: e.time)))] += valueFor(e)
        }
        return (0..<24).map { MacroHourBar(hour: $0, value: perHour[$0]) }
    }

    /// Three compact cards side by side — each shows the day's total for a macro,
    /// a mini hourly chart, and a chevron into the full D/W/M/Y detail.
    private var macroCards: some View {
        HStack(spacing: 8) {
            macroMiniCard(.calories, title: "Calories", value: day.calories, unit: "",
                          tint: RingColor.calories.tint, hourly: macroPerHour { Double($0.calories) })
            macroMiniCard(.protein, title: "Protein", value: Int(day.protein.rounded()), unit: "g",
                          tint: RingColor.protein.tint, hourly: macroPerHour { $0.protein })
            macroMiniCard(.carbs, title: "Carbs", value: Int(day.carbs.rounded()), unit: "g",
                          tint: RingColor.carb.tint, hourly: macroPerHour { $0.carbs })
        }
    }

    private func macroMiniCard(_ kind: StatKind, title: String, value: Int, unit: String,
                               tint: Color, hourly: [MacroHourBar]) -> some View {
        Button { openNutrient(kind) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(value)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                    if !unit.isEmpty {
                        Text(unit).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint.opacity(0.6))
                    }
                }
                miniHourChart(hourly, tint: tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.metricCardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.metricCardRadius, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Compact hourly bars with a 12a·6a·12p·6p axis (empty day → axis only).
    private func miniHourChart(_ bars: [MacroHourBar], tint: Color) -> some View {
        let peak = max(bars.map(\.value).max() ?? 1, 1)
        return Chart(bars.filter { $0.value > 0 }) { bar in
            BarMark(x: .value("Hour", bar.hour), y: .value("Value", bar.value), width: .fixed(2.5))
                .foregroundStyle(tint)
                .clipShape(Capsule())
        }
        .frame(height: 46)
        // Pad both edges so the outer 12AM / 6PM caps labels aren't clipped.
        .chartXScale(domain: -2.5...25.5)
        .chartYScale(domain: 0...(peak * 1.12))
        .chartYAxis(.hidden)
        .chartXAxis {
            // Dotted gridlines + all four caps labels: 12AM · 6AM · 12PM · 6PM.
            AxisMarks(values: [0, 6, 12, 18]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .foregroundStyle(Theme.divider.opacity(0.8))
                AxisValueLabel {
                    if let h = value.as(Int.self) {
                        Text(Self.hourCaps(h)).font(.system(size: 6.5)).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: Nutrition details grid (ref: Apple Health "Steps / Distance" stat grid)

    private struct NutrientStat: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let target: String?   // e.g. "of 30g", nil when we have no daily target
        let kind: StatKind    // tap → per-metric D/W/M/Y detail
    }

    /// The full macro breakdown consumed across the day.
    private var nutrientStats: [NutrientStat] {
        func g(_ v: Double) -> String { "\(Int(v.rounded()))g" }
        func mg(_ v: Double) -> String { "\(Int(v.rounded())) mg" }
        return [
            NutrientStat(label: "Total Fat", value: g(day.fat), target: "of \(Int(store.targets.fat.rounded()))g", kind: .fat),
            NutrientStat(label: "Saturated Fat", value: g(day.saturatedFat), target: nil, kind: .saturatedFat),
            NutrientStat(label: "Sugars", value: g(day.sugars), target: nil, kind: .sugars),
            NutrientStat(label: "Dietary Fibre", value: g(day.fibre), target: "of \(Int(store.targets.fibre.rounded()))g", kind: .fibre),
            NutrientStat(label: "Sodium", value: mg(day.sodium), target: "of 2,300 mg", kind: .sodium),
            NutrientStat(label: "Cholesterol", value: mg(day.cholesterol), target: nil, kind: .cholesterol),
        ]
    }

    private var nutritionDetails: some View {
        // Two-column grid, hairline divider between rows (Apple Health layout).
        let rows = stride(from: 0, to: nutrientStats.count, by: 2).map { i in
            Array(nutrientStats[i..<min(i + 2, nutrientStats.count)])
        }
        return CalmCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("Nutrition Details")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.bottom, 4)

                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(row) { stat in
                            nutrientCell(stat)
                        }
                        if row.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                    }
                    .padding(.vertical, 16)

                    if idx < rows.count - 1 {
                        Rectangle()
                            .fill(Theme.divider)
                            .frame(height: 1)
                    }
                }
            }
        }
    }

    private func nutrientCell(_ stat: NutrientStat) -> some View {
        Button {
            openNutrient(stat.kind)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(stat.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(stat.value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                if let target = stat.target {
                    Text(target)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Your Day timeline — a flat, minimal feed: one row per logged entry, in order.

    /// True when the day being viewed is the most recent (today) — drives the NOW marker.
    private var isToday: Bool { index == store.history.count - 1 }

    /// Every logged entry for the day, earliest → latest (no meal grouping).
    private var sortedEntries: [MealEntry] {
        day.entries.sorted { Self.minutes(from: $0.time) < Self.minutes(from: $1.time) }
    }

    private var timelineSection: some View {
        let entries = sortedEntries
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YOUR DAY").overlineStyle()
                Spacer()
                if !entries.isEmpty {
                    Text("\(entries.count) entr\(entries.count == 1 ? "y" : "ies")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            if entries.isEmpty {
                Text("Nothing logged this day.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 12)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entryRow($0).modifier(TimelineReveal()) }
                    if isToday { nowRow().modifier(TimelineReveal()) }
                }
            }
        }
    }

    /// One clean line per entry: time · category dot · name · macros · calories.
    private func entryRow(_ e: MealEntry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            timeStack(e.time)
                .frame(width: 50, alignment: .trailing)
                .padding(.top, Self.rowInset)
            rail(color: mealSlotColor(e.slot))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(e.food.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    Text("\(e.calories)")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
                HStack(spacing: 5) {
                    Text(e.slot.rawValue.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(mealSlotColor(e.slot))
                    Text(macros(e))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, Self.rowInset)
        }
        .contentShape(Rectangle())
        .onTapGesture { openEntry(e.food) }
    }

    private func nowRow() -> some View {
        HStack(alignment: .top, spacing: 14) {
            timeStack(Date().formatted(date: .omitted, time: .shortened))
                .frame(width: 50, alignment: .trailing)
                .padding(.top, Self.rowInset)
            ZStack(alignment: .top) {
                // Short stub so the incoming rail meets the NOW dot cleanly.
                Rectangle().fill(Theme.divider).frame(width: 1.5, height: Self.rowInset + 4)
                NowDot(color: RingColor.carb.tint)
                    .padding(.top, Self.rowInset - 3)
            }
            .frame(width: 12)
            Text("NOW")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(RingColor.carb.tint)
                .padding(.top, Self.rowInset)
            Spacer()
        }
    }

    // MARK: Timeline building blocks

    /// Vertical hairline filling the row height, with a small category dot at the entry's line.
    private func rail(color: Color) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Theme.divider)
                .frame(width: 1.5)
                .frame(maxHeight: .infinity)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .padding(.top, Self.rowInset + 4)
        }
        .frame(width: 12)
    }

    private func timeStack(_ time: String) -> some View {
        // Split on any whitespace — `Date.formatted` uses a narrow no-break space before AM/PM.
        let parts = time.split(whereSeparator: \.isWhitespace)
        return VStack(alignment: .trailing, spacing: 0) {
            Text(parts.first.map(String.init) ?? time)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            if parts.count > 1 {
                Text(String(parts[1]))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .monospacedDigit()
    }

    private func macros(_ e: MealEntry) -> String {
        if e.food.isCustomMeal {
            return "\(e.food.components.count) items · \(Int(e.protein))g protein"
        }
        return "\(Int(e.protein))g protein · \(Int(e.carbs))g carbs"
    }

    /// Shared top inset so the time, dot, and name line up across every row.
    private static let rowInset: CGFloat = 13

    /// Rows fade + rise into place as they scroll up into view — a live, one-at-a-time reveal.
    /// Only the entering (bottom) edge animates; rows already read stay crisp at the top.
    private struct TimelineReveal: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        func body(content: Content) -> some View {
            content.scrollTransition(.interactive, axis: .vertical) { view, phase in
                let t = reduceMotion ? 0 : max(0, phase.value)   // 0 at rest/top, → 1 approaching from bottom
                return view
                    .opacity(1 - t)
                    .offset(y: t * 26)
                    .blur(radius: t * 2.5)
            }
        }
    }

    /// The "now" marker: a solid dot with a soft outward pulse, so the present reads as alive.
    private struct NowDot: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var pulse = false
        let color: Color
        var body: some View {
            ZStack {
                Circle()
                    .fill(color.opacity(0.4))
                    .frame(width: 9, height: 9)
                    .scaleEffect(pulse ? 2.6 : 1)
                    .opacity(pulse ? 0 : 0.5)
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
        }
    }

    private static func minutes(from time: String) -> Int {
        let comps = time.split(separator: " ")
        guard let clock = comps.first else { return 12 * 60 }
        let parts = clock.split(separator: ":")
        guard let hStr = parts.first, var h = Int(hStr) else { return 12 * 60 }
        let m = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        let pm = comps.count > 1 && comps[1].uppercased() == "PM"
        if pm && h != 12 { h += 12 }
        if !pm && h == 12 { h = 0 }
        return h * 60 + m
    }

    // MARK: Helpers

    private func frac(_ value: Int, over target: Int) -> Double {
        target > 0 ? Double(value) / Double(target) : 0
    }
    private func frac(_ value: Double, over target: Double) -> Double {
        target > 0 ? value / target : 0
    }

    private static func hour(from time: String) -> Int {
        let comps = time.split(separator: " ")
        guard let clock = comps.first,
              let hStr = clock.split(separator: ":").first,
              var h = Int(hStr) else { return 12 }
        let pm = comps.count > 1 && comps[1].uppercased() == "PM"
        if pm && h != 12 { h += 12 }
        if !pm && h == 12 { h = 0 }
        return h
    }

    private static func hourLabel(_ h: Int) -> String {
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return "\(hour12)\(h < 12 ? "a" : "p")"
    }

    /// Apple-style caps hour label for the mini charts: 12AM · 6AM · 12PM · 6PM.
    private static func hourCaps(_ h: Int) -> String {
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return "\(hour12)\(h < 12 ? "AM" : "PM")"
    }
}

#Preview {
    DayDetailView(initialIndex: 6)
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
