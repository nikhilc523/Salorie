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
                 label: "Calories", valueText: "\(store.caloriesToday)/\(store.targets.calories)", unit: "CAL"),
            Ring(progress: store.progress(.protein), color: .protein,
                 label: "Protein", valueText: "\(Int(store.proteinToday.rounded()))/\(Int(store.targets.protein))", unit: "G"),
            Ring(progress: store.progress(.carb), color: .carb,
                 label: "Carbs", valueText: "\(Int(store.carbsToday.rounded()))/\(Int(store.targets.carbs))", unit: "G"),
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
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(caloriesLeft)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("kcal left")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                HStack(alignment: .center, spacing: 30) {
                    ActivityRings(
                        rings: macroRings,
                        lineWidth: 11,
                        spacing: 4
                    )
                    .frame(width: 104, height: 104)
                    .contentShape(Circle())
                    .onTapGesture {
                        HapticManager.shared.trigger(.light)
                        dayIndex = store.history.count - 1
                        showDayDetail = true
                    }
                    .padding(.leading, 10)

                    RingLegend(items: macroRings)
                        .offset(y: -6)
                        .padding(.leading, 14)
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

    /// One meal slot — minimal, Apple-clean. Plain slot name + a prominent total,
    /// then food rows with the calorie number pulled out and macros as a quiet
    /// subtitle. No column header, no OPEN badges, no macro dots, no colored pills.
    private func mealGroup(slot: MealSlot, entries: [MealEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: slot.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(slot.tagColor.fg)
                Text(slot.rawValue)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(entries.reduce(0) { $0 + $1.calories })")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text("cal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.bottom, 10)

            // Thick line delimits the whole meal; items get quiet hairlines.
            Rectangle().fill(Theme.tableLine).frame(height: 1)

            ForEach(entries) { entry in
                mealRow(entry)
                if entry.id != entries.last?.id {
                    Rectangle().fill(Theme.divider).frame(height: 1)
                }
            }
        }
    }

    private func mealRow(_ entry: MealEntry) -> some View {
        Button {
            HapticManager.shared.trigger(.light)
            selectedFood = entry.food
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.food.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(entry.food.tint.fg)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.food.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("\(Int(entry.protein))g protein · \(Int(entry.carbs))g carbs")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                Text("\(entry.calories)")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

}

#Preview {
    TodayView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
