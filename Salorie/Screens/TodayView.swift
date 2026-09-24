import SwiftUI

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
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    dateHeader
                    heroCard
                    mealsSection.id("meals")
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, 24)
            }
            .onAppear {
                if ProcessInfo.processInfo.environment["SALORIE_SCROLL"] == "meals" {
                    proxy.scrollTo("meals", anchor: .top)
                }
            }
            .background(Theme.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Calendar button unwired — day detail now opens by tapping the rings.
                        // TODO: assign new behavior (pending direction).
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
                    Spacer()
                    StatPill(text: "\(caloriesLeft) kcal left", color: .brown)
                }
                HStack(spacing: 22) {
                    ActivityRings(
                        rings: macroRings,
                        lineWidth: 12,
                        spacing: 4
                    )
                    .frame(width: 120, height: 120)
                    .contentShape(Circle())
                    .onTapGesture {
                        HapticManager.shared.trigger(.light)
                        dayIndex = store.history.count - 1
                        showDayDetail = true
                    }

                    RingLegend(items: macroRings)
                }
            }
        }
    }

    // MARK: Meals

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("TODAY'S MEALS").overlineStyle()
            ForEach(MealSlot.allCases) { slot in
                let entries = store.entries(for: slot)
                if !entries.isEmpty {
                    mealGroup(slot: slot, entries: entries)
                }
            }
        }
    }

    /// One meal slot as a fit-to-width Notion table (ref: Body Metrics) — slot pill +
    /// total, then a clearly-labelled Cal/Protein/Carbs table with thick row lines,
    /// name column flexed so there's no horizontal scroll and no wasted gap.
    private func mealGroup(slot: MealSlot, entries: [MealEntry]) -> some View {
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
                    NotionColumn(title: "Cal", width: 36, alignment: .trailing),
                    NotionColumn(title: "Protein", width: 52, alignment: .trailing),
                    NotionColumn(title: "Carbs", width: 46, alignment: .trailing),
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
                        ],
                        onTap: { selectedFood = entry.food }
                    )
                },
                showCount: false,
                newRowTitle: "Add food",
                fitWidth: true,
                thickDividers: true
            )
        }
    }

}

#Preview {
    TodayView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
