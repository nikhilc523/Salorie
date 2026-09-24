import SwiftUI

/// Dashboard. Calm cards + Apple-style rings over the Notion-dark canvas.
struct TodayView: View {
    @Environment(MockStore.self) private var store
    @State private var selectedFood: Food?
    @State private var showDayDetail = false
    @State private var dayIndex = 0
    @State private var expandedSlots: Set<MealSlot> = []

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
                HStack(alignment: .center, spacing: 26) {
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
                    .padding(.leading, 28)

                    RingLegend(items: macroRings)
                        .offset(y: -6)
                        .padding(.leading, 6)
                }
            }
        }
    }

    // MARK: Meals

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TODAY'S MEALS").overlineStyle()
                .padding(.bottom, 6)
            ForEach(MealSlot.allCases) { slot in
                mealDisclosure(slot: slot, entries: store.entries(for: slot))
            }
        }
    }

    /// One meal as a minimal disclosure row — name + prominent total + a chevron.
    /// Tapping expands the food list in place; collapsed by default. Rows are
    /// separated by the thick line so the stack reads as one clean summary.
    private func mealDisclosure(slot: MealSlot, entries: [MealEntry]) -> some View {
        let isOpen = expandedSlots.contains(slot)
        let total = entries.reduce(0) { $0 + $1.calories }
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticManager.shared.trigger(.light)
                withAnimation(.snappy(duration: 0.28)) {
                    if isOpen { expandedSlots.remove(slot) } else { expandedSlots.insert(slot) }
                }
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: slot.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(slot.tagColor.fg)
                    Text(slot.rawValue)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if !entries.isEmpty {
                        Text("\(entries.count)")
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(total)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(total > 0 ? Theme.textPrimary : Theme.textTertiary)
                            .contentTransition(.numericText())
                        Text("cal")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .frame(width: 14)
                        .padding(.leading, 4)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Group {
                    if entries.isEmpty {
                        Text("Nothing logged yet")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(entries) { entry in
                                mealRow(entry)
                                if entry.id != entries.last?.id {
                                    Rectangle().fill(Theme.divider).frame(height: 1)
                                }
                            }
                        }
                    }
                }
                // Indent + a quiet rail so items read as children of their meal,
                // not as siblings of the next meal header.
                .padding(.leading, 22)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Theme.divider).frame(width: 2)
                        .padding(.vertical, 4)
                }
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.tableLine).frame(height: 1)
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
                    .font(.system(size: 17, weight: .medium, design: .rounded))
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
