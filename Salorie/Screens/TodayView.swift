import SwiftUI

/// Dashboard. Calm cards + Apple-style rings over the Notion-dark canvas.
struct TodayView: View {
    @Environment(MockStore.self) private var store
    @State private var selectedFood: Food?
    @State private var selectedMeal: Food?
    @State private var showDayDetail = false
    @State private var dayIndex = 0
    @State private var selectedSlot: MealSlot?
    @State private var expandedMeals: Set<UUID> = []
    @State private var showSettings = false
    @AppStorage(NutrientPrefs.key) private var trackedRaw = NutrientPrefs.default

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    dateHeader
                    heroCard
                    mealsSection.id("meals")
                    insightsSection
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
                        HapticManager.shared.trigger(.light)
                        showSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .sheet(item: $selectedFood) { FoodDetailView(food: $0) }
            .sheet(item: $selectedMeal) { MealDetailView(meal: $0) }
            .sheet(isPresented: $showDayDetail) { DayDetailView(initialIndex: dayIndex) }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .onAppear {
                if ProcessInfo.processInfo.environment["SALORIE_DETAIL"] == "1" {
                    selectedFood = store.foods[1]
                }
                if ProcessInfo.processInfo.environment["SALORIE_DAY"] == "1" {
                    dayIndex = max(0, store.history.count - 3)
                    showDayDetail = true
                }
                if ProcessInfo.processInfo.environment["SALORIE_EXPAND"] == "meal" {
                    for e in store.todayEntries where e.food.isCustomMeal {
                        expandedMeals.insert(e.id)
                        selectedSlot = e.slot
                    }
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
        SalorieMacroSummary(
            calories: .init(consumed: Double(store.caloriesToday), goal: Double(store.targets.calories)),
            protein: .init(consumed: store.proteinToday, goal: store.targets.protein),
            carbs: .init(consumed: store.carbsToday, goal: store.targets.carbs)
        )
        .padding(.top, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.trigger(.light)
            dayIndex = max(0, store.history.count - 1)
            showDayDetail = true
        }
    }

    // MARK: Meals

    // MARK: Insights — streak + tracked nutrients

    private var insightsSection: some View {
        let tracked = NutrientPrefs.list(trackedRaw)
        return VStack(alignment: .leading, spacing: 12) {
            if !tracked.isEmpty {
                HStack {
                    Text("TRACKING").overlineStyle()
                    Spacer()
                    Button {
                        HapticManager.shared.trigger(.light)
                        showSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)

                // Square cards, three-ish across, snapping horizontally. Bleeds to
                // the screen edges so it reads as a scrollable shelf.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(tracked) { kind in
                            NutrientCard(kind: kind,
                                         value: store.todayValue(kind),
                                         goal: kind.goal(store.targets))
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, Metrics.pagePadding)
                }
                .scrollTargetBehavior(.viewAligned)
                .padding(.horizontal, -Metrics.pagePadding)
            }
        }
    }

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY'S MEALS").overlineStyle()

            HStack(spacing: 8) {
                ForEach(MealSlot.allCases) { slot in
                    let entries = store.entries(for: slot)
                    MealCard(
                        slot: slot,
                        calories: entries.reduce(0) { $0 + $1.calories },
                        itemCount: entries.count,
                        goalCalories: store.targets.calories,
                        isSelected: selectedSlot == slot
                    ) {
                        HapticManager.shared.trigger(.light)
                        withAnimation(.snappy(duration: 0.28)) {
                            selectedSlot = (selectedSlot == slot) ? nil : slot
                        }
                    }
                }
            }

            if let slot = selectedSlot {
                mealPanel(slot: slot, entries: store.entries(for: slot))
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity))
            }
        }
    }

    /// Foods for the selected meal card, in a raised panel beneath the cards.
    private func mealPanel(slot: MealSlot, entries: [MealEntry]) -> some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: slot.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(slot.sunColor.opacity(0.6))
                    Text("Nothing logged for \(slot.rawValue.lowercased()) yet")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
            } else {
                ForEach(entries) { entry in
                    SwipeToDeleteRow {
                        HapticManager.shared.trigger(.warning)
                        withAnimation(.snappy(duration: 0.3)) { store.removeEntry(entry) }
                    } content: {
                        mealRow(entry)
                    }
                    if entry.id != entries.last?.id {
                        Rectangle().fill(Theme.divider).frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private func mealRow(_ entry: MealEntry) -> some View {
        let isMeal = entry.food.isCustomMeal
        let isOpen = expandedMeals.contains(entry.id)
        return VStack(alignment: .leading, spacing: 0) {
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
                    Text(isMeal
                         ? "\(entry.food.components.count) items · \(Int(entry.protein))g protein"
                         : "\(Int(entry.protein))g protein · \(Int(entry.carbs))g carbs")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                Text("\(entry.calories)")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                if isMeal {
                    Button {
                        HapticManager.shared.trigger(.light)
                        withAnimation(.snappy(duration: 0.26)) {
                            if isOpen { expandedMeals.remove(entry.id) }
                            else { expandedMeals.insert(entry.id) }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture { openEntry(entry) }

            if isMeal && isOpen {
                VStack(spacing: 0) {
                    ForEach(entry.food.components) { component in
                        componentSubRow(component, mealServings: entry.servings)
                    }
                }
                .padding(.leading, 34)
                .padding(.bottom, 6)
                .transition(.opacity)
            }
        }
    }

    /// One indented ingredient under an expanded meal; opens that food's detail.
    private func componentSubRow(_ component: MealComponent, mealServings: Double) -> some View {
        Button {
            HapticManager.shared.trigger(.light)
            selectedFood = component.food
        } label: {
            HStack(spacing: 10) {
                Image(systemName: component.food.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(component.food.tint.fg)
                    .frame(width: 18)
                Text(component.food.name)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(Int((component.calories * mealServings).rounded()))")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openEntry(_ entry: MealEntry) {
        HapticManager.shared.trigger(.light)
        if entry.food.isCustomMeal { selectedMeal = entry.food } else { selectedFood = entry.food }
    }

}

#Preview {
    TodayView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}

// MARK: - Swipe to delete

/// Wraps a row so a left-swipe reveals a red delete action (the Today lists aren't a
/// `List`, so this stands in for `.swipeActions`). Swipe right — or tap Delete — closes/acts.
/// Only responds to mostly-horizontal drags, so vertical scrolling is unaffected.
private struct SwipeToDeleteRow<Content: View>: View {
    var onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    private let actionWidth: CGFloat = 76

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { offset = 0 }
                onDelete()
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: actionWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.red.opacity(0.9),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(offset < -6 ? 1 : 0)
            .padding(.vertical, 4)

            content()
                .background(Theme.surface)          // opaque so the row hides the action when closed
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 14)
                        .onChanged { v in
                            guard abs(v.translation.width) > abs(v.translation.height) else { return }
                            offset = min(0, max(-actionWidth - 24, v.translation.width))
                        }
                        .onEnded { v in
                            let shouldOpen = v.translation.width < -actionWidth * 0.5
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                offset = shouldOpen ? -actionWidth : 0
                            }
                            if shouldOpen { HapticManager.shared.trigger(.light) }
                        }
                )
        }
    }
}
