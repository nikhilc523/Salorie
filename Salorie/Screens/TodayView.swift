import SwiftUI
import Charts

/// Dashboard. Calm cards + Apple-style rings over the Notion-dark canvas.
struct TodayView: View {
    @Environment(MockStore.self) private var store
    @State private var selectedFood: Food?
    @State private var showDayDetail = false
    @State private var dayIndex = 0

    /// Hero rings — Calories (outer) · Protein (middle) · Carbs (inner). Fibre lives in detail, not the glance.
    private var macroRings: [Ring] {
        [
            Ring(progress: store.progress(.calories), color: .calories,
                 label: "Calories", valueText: "\(store.caloriesToday) / \(store.targets.calories)"),
            Ring(progress: store.progress(.protein), color: .protein,
                 label: "Protein", valueText: "\(Int(store.proteinToday.rounded())) / \(Int(store.targets.protein))g"),
            Ring(progress: store.progress(.carb), color: .carb,
                 label: "Carbs", valueText: "\(Int(store.carbsToday.rounded())) / \(Int(store.targets.carbs))g"),
        ]
    }

    private var caloriesLeft: Int { max(0, store.targets.calories - store.caloriesToday) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dateHeader
                    heroCard
                    macroStrip
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
                        dayIndex = store.history.count - 1
                        showDayDetail = true
                    } label: { Image(systemName: "calendar") }
                }
            }
            .safeAreaInset(edge: .bottom) { AskAIBar() }
            .sheet(item: $selectedFood) { FoodDetailView(food: $0) }
            .sheet(isPresented: $showDayDetail) { DayDetailView(initialIndex: dayIndex) }
            .onAppear {
                if ProcessInfo.processInfo.environment["SALORIE_DETAIL"] == "1" {
                    selectedFood = store.foods[1]
                }
                if ProcessInfo.processInfo.environment["SALORIE_DAY"] == "1" {
                    dayIndex = store.history.count - 3
                    showDayDetail = true
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
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("TODAY'S MACROS").overlineStyle()
                    Spacer()
                    StatPill(text: "\(caloriesLeft) kcal left", color: .green)
                }
                HStack(spacing: 22) {
                    ActivityRings(
                        rings: macroRings,
                        lineWidth: 15,
                        spacing: 5,
                        centerText: "\(store.caloriesToday)",
                        centerSubtitle: "kcal"
                    )
                    .frame(width: 152, height: 152)

                    RingLegend(items: macroRings)
                }
            }
        }
    }

    // MARK: Macro glance strip

    private var macroStrip: some View {
        HStack(spacing: 12) {
            MacroProgressCard(label: "Protein", consumed: store.proteinToday,
                              target: store.targets.protein, colors: RingColor.protein.stops)
            MacroProgressCard(label: "Carbs", consumed: store.carbsToday,
                              target: store.targets.carbs, colors: RingColor.carb.stops)
            MacroProgressCard(label: "Fat", consumed: store.fatToday,
                              target: store.targets.fat,
                              colors: Theme.macroFatStops)
        }
    }

    // MARK: Calorie-by-hour chart

    private struct HourBar: Identifiable {
        let id = UUID()
        let hour: Int      // 2-hour bin start
        let calories: Int
    }

    /// Bucket today's entries into 2-hour bins → fewer, wider bars (clean like the reference).
    private var hourlyData: [HourBar] {
        var buckets: [Int: Int] = [:]
        for e in store.todayEntries {
            let bin = (Self.hour(from: e.time) / 2) * 2
            buckets[bin, default: 0] += e.calories
        }
        return stride(from: 6, through: 22, by: 2).map { HourBar(hour: $0, calories: buckets[$0] ?? 0) }
    }

    private var peakBin: Int { max(1, hourlyData.map(\.calories).max() ?? 0) }

    private var calorieChartCard: some View {
        CalmCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("INTAKE BY HOUR").overlineStyle()
                    Spacer()
                    StatPill(text: "\(Int((store.caloriesProgress * 100).rounded()))% of goal", color: .green)
                }
                Text("\(store.todayEntries.count) meals · peak \(peakBin) kcal")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(RingColor.protein.tint) // caramel

                Chart(hourlyData) { bar in
                    BarMark(
                        x: .value("Time", bar.hour),
                        y: .value("Calories", bar.calories),
                        width: .fixed(15)
                    )
                    .foregroundStyle(RingColor.carb.tint) // terracotta
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .frame(height: 130)
                .chartXScale(domain: 5...23)
                .chartYScale(domain: 0...(Double(peakBin) * 1.15))
                .chartYAxis {
                    AxisMarks(values: [0, peakBin]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                            .foregroundStyle(Theme.divider)
                        if let v = value.as(Int.self), v > 0 {
                            AxisValueLabel {
                                Text("\(v)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: [6, 12, 18, 22]) { value in
                        AxisValueLabel {
                            if let h = value.as(Int.self) {
                                Text(Self.hourLabel(h))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }

                Text("TOTAL \(store.caloriesToday) KCAL")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(RingColor.carb.tint)
            }
        }
    }

    // MARK: Week mini-rings

    private var weekRingsCard: some View {
        CalmCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("THIS WEEK").overlineStyle()
                HStack(spacing: 0) {
                    ForEach(Array(store.history.enumerated()), id: \.element.id) { i, day in
                        Button {
                            HapticManager.shared.trigger(.selection)
                            dayIndex = i
                            showDayDetail = true
                        } label: {
                            VStack(spacing: 8) {
                                MiniDayRing(rings: rings(for: day))
                                Text(day.weekdayLetter)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func rings(for day: DayLog) -> [Ring] {
        [
            Ring(progress: Double(day.calories) / Double(store.targets.calories), color: .calories, label: "Calories", valueText: ""),
            Ring(progress: day.protein / store.targets.protein, color: .protein, label: "Protein", valueText: ""),
            Ring(progress: day.carbs / store.targets.carbs, color: .carb, label: "Carbs", valueText: ""),
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
