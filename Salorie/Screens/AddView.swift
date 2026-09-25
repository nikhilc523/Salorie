import SwiftUI

/// The single place to log food. One screen — search, quick actions (scan / new meal /
/// quick add), and browsable tabs (History · Meals · Favorites · Foods). Every "+"
/// logs a **known** portion into the meal you pick up top, so a one-tap add is never a
/// guess; tapping a row opens the detail to fine-tune the amount first.
struct AddView: View {
    @Environment(MockStore.self) private var store

    @State private var query: String
    @State private var slot: MealSlot
    @State private var tab: Int              // 0 History · 1 Meals · 2 Favorites · 3 Foods
    @State private var results: [Food] = []
    @State private var searching = false
    @State private var selectedFood: Food?
    @State private var selectedMeal: Food?
    @State private var showScan = false
    @State private var showBuilder = false
    @State private var showManualFood = false

    private static let tabs = ["History", "Meals", "Favorites", "Foods"]
    /// Warm quick-add tint from the palette (terracotta), matching the food-detail CTA.
    static let addTint = RingColor.carb.tint

    init() {
        let env = ProcessInfo.processInfo.environment
        _query = State(initialValue: env["SALORIE_QUERY"] ?? "")
        _slot = State(initialValue: AddView.timeSlot())
        // Screenshot hooks: land on a specific browse tab.
        let initialTab: Int
        switch env["SALORIE_ITEMS"] ?? env["SALORIE_TAB_ADD"] {
        case "meals": initialTab = 1
        case "favorites": initialTab = 2
        case "foods", "custom": initialTab = 3
        default: initialTab = 0
        }
        _tab = State(initialValue: initialTab)
    }

    /// The meal that fits the current time of day — the sensible default target.
    private static func timeSlot() -> MealSlot {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11:  return .breakfast
        case 11..<15: return .lunch
        case 15..<21: return .dinner
        default:      return .snacks
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                searchField
                    .padding(.horizontal, Metrics.pagePadding)
                    .padding(.top, 16)

                if query.isEmpty {
                    quickActions
                        .padding(.horizontal, Metrics.pagePadding)
                        .padding(.top, 16)
                    SegmentedTabs(items: Self.tabs, selection: $tab)
                        .padding(.horizontal, Metrics.pagePadding)
                        .padding(.top, 24)
                }

                content
            }
            .background(Theme.bg)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedFood) { FoodDetailView(food: $0) }
            .sheet(item: $selectedMeal) { MealDetailView(meal: $0) }
            .sheet(isPresented: $showBuilder) { MealBuilderView() }
            .sheet(isPresented: $showManualFood) { ManualFoodEntryView(initialSlot: slot) }
            .sheet(isPresented: $showScan) { scanSheet }
            .task(id: query) { await runSearch(query) }
            .onAppear(perform: applyScreenshotHooks)
        }
    }

    // MARK: Header — title + meal-slot target

    private var header: some View {
        HStack(alignment: .center) {
            Text("Add Food")
                .font(.screenTitle)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            slotMenu
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.top, 6)
    }

    /// The one control that removes the "which meal?" ambiguity — every "+" logs here.
    private var slotMenu: some View {
        Menu {
            Picker("Meal", selection: $slot) {
                ForEach(MealSlot.allCases) { s in
                    Label(s.rawValue, systemImage: s.symbol).tag(s)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: slot.symbol).font(.system(size: 13, weight: .semibold))
                Text(slot.rawValue).font(.system(size: 15, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Self.addTint)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))
        }
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("", text: $query, prompt: Text("Search foods, brands, barcodes")
                .foregroundColor(Theme.textTertiary))
                .foregroundStyle(Theme.textPrimary)
            if !query.isEmpty {
                Button {
                    HapticManager.shared.trigger(.light)
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
    }

    // MARK: Quick actions — scan / new meal / quick add (icons, not a second half-screen)

    /// One grouped bar, three segments — reads as a single quiet control instead of a
    /// row of look-alike glass pills. Flat surface + hairlines, matching the food rows.
    private var quickActions: some View {
        HStack(spacing: 0) {
            actionSegment("Scan", "barcode.viewfinder") { HapticManager.shared.trigger(.light); showScan = true }
            segDivider
            actionSegment("New Meal", "fork.knife") { HapticManager.shared.trigger(.light); showBuilder = true }
            segDivider
            actionSegment("Quick Add", "square.and.pencil") { HapticManager.shared.trigger(.light); showManualFood = true }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
    }

    private var segDivider: some View {
        Rectangle().fill(Theme.divider).frame(width: 1, height: 22)
    }

    private func actionSegment(_ label: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(label).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .foregroundStyle(Self.addTint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Content — search results or the selected browse tab

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if !query.isEmpty {
                    if !results.isEmpty {
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, food in
                            if i > 0 { rowDivider }
                            row(for: food)
                        }
                    } else if !searching {
                        emptyResults
                    }
                } else {
                    tabContent
                }
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 16)
            .padding(.bottom, 28)
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case 1: mealsList
        case 2: foodList(store.favorites, empty: "No favorites yet", hint: "Tap the star on any food to save it here.")
        case 3: foodList(customFoods, empty: "No custom foods yet", hint: "Scan or Quick Add a food and it shows up here.")
        default: historyList
        }
    }

    // History — one-tap re-log of the exact portion you logged last time.
    @ViewBuilder
    private var historyList: some View {
        let items = store.recentLogItems
        if items.isEmpty {
            emptyState("clock.arrow.circlepath", "Nothing logged yet",
                       "Foods you log will appear here for a fast one-tap re-log.")
        } else {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                if i > 0 { rowDivider }
                AddRow(food: item.food,
                       subtitle: recentSubtitle(item),
                       slotName: slot.rawValue,
                       onAdd: { store.addEntry(item.food, slot: slot, servings: item.servings) },
                       onOpen: { open(item.food) })
            }
        }
    }

    // Meals — log a whole custom meal in one tap, or open it to tweak.
    @ViewBuilder
    private var mealsList: some View {
        if store.customMeals.isEmpty {
            emptyState("takeoutbag.and.cup.and.straw", "No meals yet",
                       "Build a meal from your foods to log it in one tap.", cta: "Create meal") {
                showBuilder = true
            }
        } else {
            ForEach(Array(store.customMeals.enumerated()), id: \.element.id) { i, meal in
                if i > 0 { rowDivider }
                AddRow(food: meal,
                       subtitle: foodSubtitle(meal),
                       slotName: slot.rawValue,
                       onAdd: { store.addEntry(meal, slot: slot, servings: 1) },
                       onOpen: { selectedMeal = meal })
            }
        }
    }

    @ViewBuilder
    private func foodList(_ foods: [Food], empty: String, hint: String) -> some View {
        if foods.isEmpty {
            emptyState(tab == 2 ? "star" : "puzzlepiece", empty, hint)
        } else {
            ForEach(Array(foods.enumerated()), id: \.element.id) { i, food in
                if i > 0 { rowDivider }
                row(for: food)
            }
        }
    }

    /// A single food/meal row with a portion-aware "+" (logs one known serving).
    private func row(for food: Food) -> some View {
        AddRow(food: food,
               subtitle: foodSubtitle(food),
               slotName: slot.rawValue,
               onAdd: { store.addEntry(food, slot: slot, servings: 1) },
               onOpen: { open(food) })
    }

    private var rowDivider: some View { Divider().overlay(Theme.divider) }

    // MARK: Subtitles (always show what "+" will log)

    private func foodSubtitle(_ f: Food) -> String {
        if f.isCustomMeal { return "\(f.components.count) ingredients · \(f.calories) cal" }
        let tail = f.brand ?? f.source.short
        return "\(f.calories) cal · \(f.servingDescription)" + (tail.isEmpty ? "" : " · \(tail)")
    }

    private func recentSubtitle(_ r: MockStore.RecentLog) -> String {
        let cal = Int((Double(r.food.calories) * r.servings).rounded())
        let tail = r.food.brand ?? r.food.source.short
        return "\(cal) cal · \(portionText(r.food, r.servings))" + (tail.isEmpty ? "" : " · \(tail)")
    }

    private func portionText(_ f: Food, _ servings: Double) -> String {
        if let g = f.servingGrams, g > 0 { return "\(Int((g * servings).rounded())) g" }
        if servings == 1 { return f.servingDescription }
        let s = servings.formatted(.number.precision(.fractionLength(0...1)))
        return "\(s) × \(f.servingDescription)"
    }

    private var customFoods: [Food] {
        store.foods.filter { $0.source == .custom || $0.source == .openFoodFacts }
    }

    // MARK: Search

    /// Debounced search against the store's async catalog. `.task(id: query)` cancels
    /// the in-flight run on each keystroke, so the sleep debounces cleanly.
    private func runSearch(_ raw: String) async {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { results = []; searching = false; return }
        searching = true
        try? await Task.sleep(for: .milliseconds(200))
        if Task.isCancelled { return }
        let hits = await store.search(q)
        if Task.isCancelled { return }
        results = hits
        searching = false
    }

    // MARK: Helpers

    private func open(_ food: Food) {
        HapticManager.shared.trigger(.light)
        if food.isCustomMeal { selectedMeal = food } else { selectedFood = food }
    }

    private var emptyResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30)).foregroundStyle(Theme.textTertiary)
            Text("No matches for \u{201C}\(query)\u{201D}")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("Try a different name, or scan the barcode.")
                .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
    }

    @ViewBuilder
    private func emptyState(_ icon: String, _ title: String, _ hint: String,
                            cta: String? = nil, action: @escaping () -> Void = {}) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30)).foregroundStyle(Theme.textTertiary)
            Text(title)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            Text(hint)
                .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
            if let cta {
                Button {
                    HapticManager.shared.trigger(.light); action()
                } label: {
                    Label(cta, systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Self.addTint)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Self.addTint.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 52)
    }

    // MARK: Scan sheet (the scanner is now an action, not half the screen)

    private var scanSheet: some View {
        NavigationStack {
            ScanView()
                .navigationTitle("Scan")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { HapticManager.shared.trigger(.light); showScan = false }
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }

    private func applyScreenshotHooks() {
        let env = ProcessInfo.processInfo.environment
        if env["SALORIE_SCAN"] == "1" { showScan = true }
        switch env["SALORIE_MEAL"] {
        case "detail": selectedMeal = store.customMeals.first
        case "builder": showBuilder = true
        default: break
        }
        if let code = env["SALORIE_OPEN_BARCODE"] {
            Task { selectedFood = await store.food(forBarcode: code) }
        }
    }
}

// MARK: - AddRow

/// A tappable food/meal row with a portion-aware quick-add. The "+" logs the portion
/// shown in the subtitle and flips to a checkmark for a beat as confirmation; tapping
/// the row opens the detail to adjust the amount first.
private struct AddRow: View {
    let food: Food
    let subtitle: String
    let slotName: String
    let onAdd: () -> Void
    let onOpen: () -> Void
    @State private var added = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 12) {
            // Row body opens the detail (proper button, so VoiceOver sees the action).
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    Image(systemName: food.symbol)
                        .font(.system(size: 16))
                        .foregroundStyle(food.tint.fg)
                        .frame(width: 34, height: 34)
                        .background(food.tint.bg, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(food.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(food.name), \(subtitle)")
            .accessibilityHint("Opens details")

            // Quick-add: logs the portion in the subtitle; flips to a check as feedback.
            // Rapid taps keep logging (each tap adds) — only the reset timer is debounced.
            Button {
                HapticManager.shared.trigger(.success)
                onAdd()
                withAnimation(.snappy) { added = true }
                resetTask?.cancel()
                resetTask = Task {
                    try? await Task.sleep(for: .seconds(1))
                    if !Task.isCancelled { withAnimation(.snappy) { added = false } }
                }
            } label: {
                Image(systemName: added ? "checkmark" : "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(added ? RingColor.protein.tint : AddView.addTint)
                    .frame(width: 36, height: 36)
                    .background((added ? RingColor.protein.tint : AddView.addTint).opacity(0.14), in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(food.name) to \(slotName)")
        }
        .padding(.vertical, 9)
    }
}

#Preview {
    AddView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
