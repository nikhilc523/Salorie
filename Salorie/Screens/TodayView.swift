import SwiftUI
import Charts

/// Dashboard. Calm cards + Apple-style rings over the Notion-dark canvas.
struct TodayView: View {
    @Environment(MockStore.self) private var store
    @State private var selectedFood: Food?

    private var macroRings: [Ring] {
        [
            Ring(progress: store.progress(.carb), color: .carb,
                 label: "Carb", valueText: "\(Int(store.carbsToday))g"),
            Ring(progress: store.progress(.protein), color: .protein,
                 label: "Protein", valueText: "\(Int(store.proteinToday))g"),
            Ring(progress: store.progress(.fibre), color: .fibre,
                 label: "Fibre", valueText: "\(Int(store.fibreToday))g"),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dateHeader
                    heroCard
                    metricsRow
                    calorieChartCard
                    weekRingsCard
                    quickActions
                    mealsSection
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.shared.trigger(.light)
                    } label: { Image(systemName: "calendar") }
                }
            }
            .sheet(item: $selectedFood) { FoodDetailView(food: $0) }
            .onAppear {
                if ProcessInfo.processInfo.environment["SALORIE_DETAIL"] == "1" {
                    selectedFood = store.foods[1]
                }
            }
        }
    }

    // MARK: Date header

    private var dateHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("TODAY").overlineStyle()
                Text(store.today.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: Hero rings

    private var heroCard: some View {
        CalmCard {
            HStack(spacing: 22) {
                ActivityRings(
                    rings: macroRings,
                    centerText: "\(store.caloriesToday)",
                    centerSubtitle: "kcal"
                )
                .frame(width: 148, height: 148)

                VStack(alignment: .leading, spacing: 14) {
                    Text("MACROS").overlineStyle()
                    RingLegend(items: macroRings)
                }
            }
        }
    }

    // MARK: Metrics row

    private var metricsRow: some View {
        HStack(spacing: 12) {
            MetricCard(
                label: "Calories",
                value: "\(store.caloriesToday)",
                icon: "flame.fill",
                accent: Theme.textPrimary,
                footnote: "of \(store.targets.calories) kcal"
            )
            MetricCard(
                label: "Remaining",
                value: "\(max(0, store.targets.calories - store.caloriesToday))",
                icon: "target",
                accent: TagColor.green.fg,
                footnote: "\(Int((store.caloriesProgress * 100).rounded()))% of goal"
            )
        }
    }

    // MARK: Calorie-by-hour chart

    private struct HourBar: Identifiable {
        let id = UUID()
        let hour: Int
        let calories: Int
    }

    private var hourlyData: [HourBar] {
        // Bucket today's entries into hours from their display time.
        var buckets: [Int: Int] = [:]
        for e in store.todayEntries {
            let h = Self.hour(from: e.time)
            buckets[h, default: 0] += e.calories
        }
        return (6...22).map { HourBar(hour: $0, calories: buckets[$0] ?? 0) }
    }

    private var calorieChartCard: some View {
        CalmCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("INTAKE BY HOUR").overlineStyle()
                        Text("\(store.caloriesToday) / \(store.targets.calories)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Spacer()
                    StatPill(text: "\(Int((store.caloriesProgress * 100).rounded()))%", color: .green)
                }
                Chart(hourlyData) { bar in
                    BarMark(
                        x: .value("Hour", bar.hour),
                        y: .value("Calories", bar.calories),
                        width: .fixed(9)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.5)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .cornerRadius(3)
                }
                .frame(height: 120)
                .chartXScale(domain: 6...22)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: [6, 12, 18, 22]) { value in
                        AxisValueLabel {
                            if let h = value.as(Int.self) {
                                Text(Self.hourLabel(h))
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Week mini-rings

    private var weekRingsCard: some View {
        CalmCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("THIS WEEK").overlineStyle()
                HStack(spacing: 0) {
                    ForEach(store.history) { day in
                        VStack(spacing: 8) {
                            MiniDayRing(rings: rings(for: day))
                            Text(day.weekdayLetter)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func rings(for day: DayLog) -> [Ring] {
        [
            Ring(progress: day.carbs / store.targets.carbs, color: .carb, label: "Carb", valueText: ""),
            Ring(progress: day.protein / store.targets.protein, color: .protein, label: "Protein", valueText: ""),
            Ring(progress: day.fibre / store.targets.fibre, color: .fibre, label: "Fibre", valueText: ""),
        ]
    }

    // MARK: Quick actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUICK ACTIONS").overlineStyle()
            ForEach(MealSlot.allCases) { slot in
                QuickActionButton(title: "Add to \(slot.rawValue)", systemImage: "plus") {}
            }
        }
    }

    // MARK: Meals

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("TODAY'S MEALS").overlineStyle()
            ForEach(MealSlot.allCases) { slot in
                let entries = store.entries(for: slot)
                if !entries.isEmpty {
                    mealTable(slot: slot, entries: entries)
                }
            }
        }
    }

    private func mealTable(slot: MealSlot, entries: [MealEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: slot.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(slot.tagColor.fg)
                TagPill(text: slot.rawValue, color: slot.tagColor)
                Spacer()
                Text("\(entries.reduce(0) { $0 + $1.calories }) cal")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            NotionTable(
                columns: [
                    NotionColumn(title: "Cal", icon: "flame", width: 64, alignment: .trailing),
                    NotionColumn(title: "Protein", icon: "bolt.fill", width: 90),
                    NotionColumn(title: "Carb", icon: "leaf.fill", width: 80),
                    NotionColumn(title: "Source", icon: "tag", width: 110),
                ],
                rows: entries.map { entry in
                    NotionRow(
                        icon: entry.food.symbol,
                        tint: entry.food.tint,
                        name: entry.food.name,
                        ghost: entry.food.isOpen ? "OPEN" : nil,
                        cells: [
                            .number("\(entry.calories)"),
                            .macro(.protein, "\(Int(entry.protein))g"),
                            .macro(.carb, "\(Int(entry.carbs))g"),
                            .source(entry.food.source),
                        ],
                        onTap: { selectedFood = entry.food }
                    )
                },
                showCount: false,
                newRowTitle: "Add food"
            )
        }
    }

    // MARK: Time helpers

    private static func hour(from time: String) -> Int {
        // Parses "8:24 AM" / "12:45 PM" → 24h hour.
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
    TodayView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
