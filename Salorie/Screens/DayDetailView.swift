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

    private var day: DayLog { store.history[min(index, store.history.count - 1)] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    weekSelector
                    heroRing
                    chart.contentShape(Rectangle()).onTapGesture { openNutrient(.calories) }
                    proteinChart.contentShape(Rectangle()).onTapGesture { openNutrient(.protein) }
                    carbsChart.contentShape(Rectangle()).onTapGesture { openNutrient(.carbs) }
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
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(i == index ? Theme.textPrimary : Theme.textTertiary)
                        MiniSunRings(calories: frac(d.calories, over: store.targets.calories),
                                     protein: frac(d.protein, over: store.targets.protein),
                                     carbs: frac(d.carbs, over: store.targets.carbs))
                            .frame(width: 34)
                            .opacity(i == index ? 1 : 0.45)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(i == index ? Theme.surface : .clear,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Hero ring

    private var heroRing: some View {
        SalorieRings(
            calories: frac(day.calories, over: store.targets.calories),
            protein: frac(day.protein, over: store.targets.protein),
            carbs: frac(day.carbs, over: store.targets.carbs)
        )
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: Through-the-day charts (unified Apple Activity detail style)

    private struct MacroHourBar: Identifiable {
        let id = UUID()
        let hour: Int
        let value: Double  // this hour's amount (non-cumulative)
    }

    /// One bar per hour, the amount logged in that hour (non-cumulative).
    private func macroPerHour(_ valueFor: (MealEntry) -> Double) -> [MacroHourBar] {
        var perHour = [Double](repeating: 0, count: 24)
        for e in day.entries {
            let h = min(23, max(0, Self.hour(from: e.time)))
            perHour[h] += valueFor(e)
        }
        return (6...23).map { MacroHourBar(hour: $0, value: perHour[$0]) }
    }

    /// Big colored value header — Apple Fitness "Move / Exercise / Stand" style.
    private func activityHeader(_ title: String, value: Int, target: Int, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(value)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                Text("/\(target)\(unit)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.55))
            }
            .monospacedDigit()
        }
    }

    /// Small y-max cap shown top-left of each chart (ref: "60 MIN" / "11CAL").
    private func capLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
            .monospacedDigit()
    }

    /// Colored "TOTAL …" footer under each chart (ref: "TOTAL 20H 36M").
    private func totalFooter(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(tint)
    }

    /// Shared 4-mark time axis (6a · 12p · 6p · 10p).
    private var timeAxisMarks: some AxisContent {
        AxisMarks(values: [6, 12, 18, 22]) { value in
            AxisValueLabel {
                if let h = value.as(Int.self) {
                    Text(Self.hourLabel(h)).font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    // Calories — thick cumulative bars filling the day (ref: 11:37 screenshot).
    private var chart: some View {
        let per = macroPerHour { Double($0.calories) }
        var run = 0.0
        let bars = per.map { b -> MacroHourBar in run += b.value; return MacroHourBar(hour: b.hour, value: run) }
        let total = run
        let target = Double(store.targets.calories)
        let tint = RingColor.calories.tint
        return CalmCard {
            VStack(alignment: .leading, spacing: 12) {
                activityHeader("Calories", value: day.calories,
                               target: store.targets.calories, unit: "", tint: tint)
                capLabel("\(store.targets.calories)")
                Chart(bars.filter { $0.value > 0 }) { bar in
                    BarMark(
                        x: .value("Hour", bar.hour),
                        y: .value("Calories", bar.value),
                        width: .fixed(12)
                    )
                    .foregroundStyle(tint)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .frame(height: 120)
                .chartXScale(domain: 5.5...23.5)
                .chartYScale(domain: 0...max(target, total))
                .chartYAxis(.hidden)
                .chartXAxis { timeAxisMarks }
                totalFooter("TOTAL \(day.calories) KCAL", tint: tint)
            }
        }
    }

    // Protein — Apple "Stand / Wear" design: fat rounded capsules packed across the width.
    private var proteinChart: some View {
        let bars = macroPerHour { $0.protein }
        let peak = max(bars.map(\.value).max() ?? 1, 1)
        let floor = peak * 0.06                     // short stub for empty hours (ref: the one short bar)
        let tint = RingColor.protein.tint
        return CalmCard {
            VStack(alignment: .leading, spacing: 12) {
                activityHeader("Protein", value: Int(day.protein.rounded()),
                               target: Int(store.targets.protein), unit: "G", tint: tint)
                capLabel("\(Int(peak.rounded()))G")
                Chart(bars) { bar in
                    BarMark(
                        x: .value("Hour", bar.hour),
                        y: .value("Protein", max(bar.value, floor)),
                        width: .fixed(13)
                    )
                    .foregroundStyle(tint.opacity(bar.value > 0 ? 1 : 0.28))
                    .clipShape(Capsule())
                }
                .frame(height: 120)
                .chartXScale(domain: 5.5...23.5)
                .chartYScale(domain: 0...(peak * 1.08))
                .chartYAxis(.hidden)
                .chartXAxis { timeAxisMarks }
                totalFooter("TOTAL \(Int(day.protein.rounded())) G", tint: tint)
            }
        }
    }

    // Carbs — Apple "Exercise" design: dotted baseline + thin tall spikes.
    private var carbsChart: some View {
        let bars = macroPerHour { $0.carbs }
        let peak = max(bars.map(\.value).max() ?? 1, 1)
        let tint = RingColor.carb.tint
        return CalmCard {
            VStack(alignment: .leading, spacing: 12) {
                activityHeader("Carbs", value: Int(day.carbs.rounded()),
                               target: Int(store.targets.carbs), unit: "G", tint: tint)
                capLabel("\(Int(peak.rounded()))G")
                Chart {
                    RuleMark(y: .value("Base", 0))
                        .foregroundStyle(tint.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [1, 5]))
                    ForEach(bars.filter { $0.value > 0 }) { bar in
                        BarMark(
                            x: .value("Hour", bar.hour),
                            y: .value("Carbs", bar.value),
                            width: .fixed(4)
                        )
                        .foregroundStyle(tint)
                        .clipShape(Capsule())
                    }
                }
                .frame(height: 120)
                .chartXScale(domain: 5.5...23.5)
                .chartYScale(domain: 0...(peak * 1.08))
                .chartYAxis(.hidden)
                .chartXAxis { timeAxisMarks }
                totalFooter("TOTAL \(Int(day.carbs.rounded())) G", tint: tint)
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
}

#Preview {
    DayDetailView(initialIndex: 6)
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
