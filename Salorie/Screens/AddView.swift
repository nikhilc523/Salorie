import SwiftUI

/// The single place to log food. One screen — search, quick actions (scan / new meal /
/// quick add), and browsable tabs (History · Meals · Favorites · Foods). Every "+"
/// logs a **known** portion into the meal you pick up top, so a one-tap add is never a
/// guess; tapping a row opens the detail to fine-tune the amount first.
struct AddView: View {
    @Environment(MockStore.self) private var store

    @State private var query: String
    @State private var slot: MealSlot
    @State private var slotMenuOpen = false
    @State private var tab: Int              // 0 History · 1 Meals · 2 Favorites · 3 Foods
    @State private var results: [Food] = []
    @State private var searching = false
    @State private var selectedFood: Food?
    @State private var selectedMeal: Food?
    @State private var showScan = false
    @State private var showBuilder = false
    @State private var showManualFood = false
    @State private var searchExpanded = false            // control strip → search bar morph
    @FocusState private var searchFocused: Bool

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
                controlStrip
                    .padding(.horizontal, Metrics.pagePadding)
                    .padding(.top, 14)

                if !searchExpanded {
                    SegmentedTabs(items: Self.tabs, selection: $tab)
                        .padding(.horizontal, Metrics.pagePadding)
                        .padding(.top, 22)
                        .transition(.opacity)
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
            .mealSlotMenu(isOpen: $slotMenuOpen, slot: $slot)
        }
    }

    // MARK: Header — just the title (the meal target now lives in the control strip)

    private var header: some View {
        HStack {
            Text("Add Food")
                .font(.screenTitle)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.top, 6)
    }

    // MARK: Control strip — circular actions that collapse into a search bar
    //
    // Resting: [meal ▾] [New Meal] [Quick Add]  ···  [Scan] [Search], each a glass circle
    // with a label. Tapping Search: New Meal / Quick Add / Scan fade out, and the search
    // capsule (always present) animates its width from a circle to full, with Scan flying
    // to its trailing edge and Cancel sliding in. Only the small scan icon uses matched
    // geometry — the glass capsule just animates its own frame, which stays buttery.

    private let strip: CGFloat = 52
    private let pillWidth: CGFloat = 132

    private var controlStrip: some View {
        HStack(alignment: .center, spacing: 10) {
            mealCircle
            if !searchExpanded {
                actionsPill
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                Spacer(minLength: 6)
                scanCircle
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
            searchColumn
            if searchExpanded {
                cancelButton
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: searchExpanded)
    }

    /// Leading circle: the meal target. Shows the slot glyph in its meal colour with a
    /// matching ring; tapping opens the slot menu (hosted on the screen). The label hides
    /// while searching so the circle lines up with the search capsule.
    private var mealCircle: some View {
        VStack(spacing: 7) {
            DropdownTrigger(isOpen: $slotMenuOpen) {
                circleFace(icon: slot.symbol,
                           tint: mealSlotColor(slot),
                           fill: mealSlotColor(slot).opacity(0.2),
                           ring: mealSlotColor(slot).opacity(0.6),
                           ringWidth: 2)
                    .contentTransition(.symbolEffect(.replace))
            }
            if !searchExpanded {
                stripLabel(slot.rawValue, tint: mealSlotColor(slot))
            }
        }
        .frame(width: 60)
    }

    /// New Meal + Quick Add, together in one glass pill (two segments, hairline divider).
    private var actionsPill: some View {
        VStack(spacing: 7) {
            HStack(spacing: 0) {
                segButton("fork.knife", tint: Self.addTint) {
                    HapticManager.shared.trigger(.light); showBuilder = true
                }
                segDivider
                segButton("square.and.pencil", tint: Self.addTint) {
                    HapticManager.shared.trigger(.light); showManualFood = true
                }
            }
            .frame(height: strip)
            .glassEffect(.regular.interactive(), in: Capsule())
            .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))
            HStack(spacing: 0) {
                stripLabel("New Meal", tint: Theme.textSecondary).frame(maxWidth: .infinity)
                stripLabel("Quick Add", tint: Theme.textSecondary).frame(maxWidth: .infinity)
            }
        }
        .frame(width: pillWidth)
    }

    /// Scan — its own circle, kept separate from Search since their colours differ.
    private var scanCircle: some View {
        VStack(spacing: 7) {
            Button { HapticManager.shared.trigger(.light); showScan = true } label: {
                circleFace(icon: "barcode.viewfinder", tint: Self.addTint,
                           fill: Self.addTint.opacity(0.14), ring: Theme.cardStroke)
            }
            .buttonStyle(CirclePress())
            stripLabel("Scan", tint: Theme.textSecondary)
        }
        .frame(width: 60)
    }

    /// Search — a glass circle that grows into the full search field when tapped. Only the
    /// capsule's own frame animates (no matched-geometry), so it stays smooth.
    private var searchColumn: some View {
        VStack(spacing: 7) {
            searchBar
            if !searchExpanded { stripLabel("Search", tint: Theme.textSecondary) }
        }
        .frame(maxWidth: searchExpanded ? .infinity : 60)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: searchExpanded ? 16 : 19, weight: .semibold))
                .foregroundStyle(searchExpanded ? Theme.textSecondary : Theme.textPrimary)
                .frame(maxWidth: searchExpanded ? nil : .infinity)   // centre while collapsed

            if searchExpanded {
                TextField("", text: $query, prompt: Text("Search foods, brands, barcodes")
                    .foregroundColor(Theme.textTertiary))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Self.addTint)
                    .focused($searchFocused)
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button { HapticManager.shared.trigger(.light); query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
                Button { HapticManager.shared.trigger(.light); showScan = true } label: {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            LinearGradient(colors: [Self.addTint, Self.addTint.opacity(0.82)],
                                           startPoint: .top, endPoint: .bottom),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan")
                .transition(.opacity)
            }
        }
        .padding(.leading, searchExpanded ? 16 : 0)
        .padding(.trailing, searchExpanded ? 6 : 0)
        .frame(width: searchExpanded ? nil : strip, height: strip)
        .frame(maxWidth: searchExpanded ? .infinity : nil)
        .glassEffect(.regular.interactive(), in: Capsule())
        .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))
        .contentShape(Capsule())
        .onTapGesture { if !searchExpanded { expandSearch() } }
    }

    private var cancelButton: some View {
        Button {
            HapticManager.shared.trigger(.light)
            searchFocused = false
            query = ""
            withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { searchExpanded = false }
        } label: {
            Text("Cancel")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Self.addTint)
                .fixedSize()
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private func expandSearch() {
        HapticManager.shared.trigger(.light)
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { searchExpanded = true }
        DispatchQueue.main.async { searchFocused = true }
    }

    /// One tappable icon segment inside a pill.
    private func segButton(_ icon: String, tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: strip)
                .contentShape(Rectangle())
        }
        .buttonStyle(CirclePress())
    }

    private var segDivider: some View {
        Rectangle().fill(Theme.divider).frame(width: 1, height: 24)
    }

    /// A 52pt glass circle with an icon — the meal target's face.
    private func circleFace(icon: String, tint: Color, fill: Color, ring: Color, ringWidth: CGFloat = 1) -> some View {
        Image(systemName: icon)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: strip, height: strip)
            .glassEffect(.regular.tint(fill).interactive(), in: Circle())
            .overlay(Circle().stroke(ring, lineWidth: ringWidth))
    }

    private func stripLabel(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
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
        if env["SALORIE_SLOTMENU"] == "1" { slotMenuOpen = true }
        if env["SALORIE_SEARCH"] == "1" { searchExpanded = true }
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

// MARK: - Press style

/// Quick spring scale-down for the circular strip buttons.
private struct CirclePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
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
