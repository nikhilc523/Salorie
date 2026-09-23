import SwiftUI
import Charts

/// Full day breakdown, shown when tapping into a specific day (ref: day-detail screenshot).
/// Week selector · large hero ring · big value/target metric · clean intake bar chart.
struct DayDetailView: View {
    @Environment(MockStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var index: Int
    init(initialIndex: Int) { _index = State(initialValue: initialIndex) }

    private var day: DayLog { store.history[min(index, store.history.count - 1)] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    weekSelector
                    heroRing
                    metric
                    chart
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
                        MiniDayRing(rings: rings(for: d), size: 32, lineWidth: 4)
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
        HStack {
            Spacer()
            ActivityRings(rings: rings(for: day), lineWidth: 20, spacing: 6)
                .frame(width: 210, height: 210)
                .background(
                    Circle()
                        .fill(RingColor.calories.tint.opacity(0.10))
                        .blur(radius: 44)
                )
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: Big metric

    private var metric: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Calories")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(day.calories)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(" / \(store.targets.calories) kcal")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .monospacedDigit()
            legend
                .padding(.top, 12)
        }
    }

    private var legend: some View {
        RingLegend(items: [
            Ring(progress: 0, color: .calories, label: "Calories", valueText: "\(day.calories) / \(store.targets.calories)"),
            Ring(progress: 0, color: .protein, label: "Protein", valueText: "\(Int(day.protein.rounded())) / \(Int(store.targets.protein))g"),
            Ring(progress: 0, color: .carb, label: "Carbs", valueText: "\(Int(day.carbs.rounded())) / \(Int(store.targets.carbs))g"),
        ])
    }

    // MARK: Calories-through-the-day chart (dense cream bars, ref: Wear histogram)

    private struct HourBar: Identifiable {
        let id = UUID()
        let hour: Int      // 0…23
        let calories: Int  // cumulative total up to end of this hour
    }

    /// One bar per hour across the day, each the running calorie total — fills the full width.
    private var cumulative: [HourBar] {
        var perHour = [Int](repeating: 0, count: 24)
        for e in day.entries {
            let h = min(23, max(0, Self.hour(from: e.time)))
            perHour[h] += e.calories
        }
        var run = 0
        var out: [HourBar] = []
        for h in 0...23 {
            run += perHour[h]
            if h >= 6 { out.append(HourBar(hour: h, calories: run)) }
        }
        return out
    }

    private var chart: some View {
        CalmCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("CALORIES THROUGH THE DAY").overlineStyle()

                Chart(cumulative) { bar in
                    BarMark(
                        x: .value("Hour", bar.hour),
                        y: .value("Calories", bar.calories),
                        width: .fixed(11)
                    )
                    .foregroundStyle(RingColor.calories.tint) // oatmeal cream
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                .frame(height: 140)
                .chartXScale(domain: 5.5...23.5)
                .chartYScale(domain: 0...Double(store.targets.calories))
                .chartYAxis {
                    AxisMarks(values: [0, store.targets.calories]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                            .foregroundStyle(Theme.divider)
                        if let v = value.as(Int.self), v > 0 {
                            AxisValueLabel {
                                Text("\(v)").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: [6, 12, 18, 22]) { value in
                        AxisValueLabel {
                            if let h = value.as(Int.self) {
                                Text(Self.hourLabel(h)).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }

                Text("TOTAL \(day.calories) KCAL")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(RingColor.calories.tint)
            }
        }
    }

    // MARK: Helpers

    private func rings(for d: DayLog) -> [Ring] {
        [
            Ring(progress: Double(d.calories) / Double(store.targets.calories), color: .calories, label: "Calories", valueText: ""),
            Ring(progress: d.protein / store.targets.protein, color: .protein, label: "Protein", valueText: ""),
            Ring(progress: d.carbs / store.targets.carbs, color: .carb, label: "Carbs", valueText: ""),
        ]
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
