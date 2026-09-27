import SwiftUI

/// The single place to log food. One screen — search, quick actions (scan / new meal /
/// quick add), and browsable tabs (History · Meals · Favorites · Foods). Every "+"
/// logs a **known** portion into the meal you pick up top, so a one-tap add is never a
/// guess; tapping a row opens the detail to fine-tune the amount first.
struct AddView: View {
    @Environment(MockStore.self) private var store
    @Environment(IslandController.self) private var island
    @Environment(\.dismiss) private var dismiss

    /// When set, the screen runs in **ingredient mode**: no meal section (Meals tab hidden,
    /// custom meals excluded everywhere), and every tap hands the food back to the builder
    /// instead of logging it. `nil` = the normal Add/log screen.
    private let onPickIngredient: ((Food) -> Void)?
    private var ingredientMode: Bool { onPickIngredient != nil }

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
    /// Quick-add "+" and filled CTAs — caramel (the protein-ring tone), deliberately
    /// *not* terracotta so the Add hub reads as its own accent.
    static let addTint = RingColor.protein.tint
    /// Control-strip glyphs (New Meal / Quick Add / Scan) — oatmeal, the calorie-ring tone.
    static let stripTint = RingColor.calories.tint

    init(pickIngredient: ((Food) -> Void)? = nil) {
        self.onPickIngredient = pickIngredient
        let env = ProcessInfo.processInfo.environment
        _query = State(initialValue: env["SALORIE_QUERY"] ?? "")
        _slot = State(initialValue: AddView.timeSlot())
        // Ingredient mode always starts on History (tab 0); its tab set has no Meals.
        let initialTab: Int
        if pickIngredient != nil {
            initialTab = 0
        } else {
            // Screenshot hooks: land on a specific browse tab.
            switch env["SALORIE_ITEMS"] ?? env["SALORIE_TAB_ADD"] {
            case "meals": initialTab = 1
            case "favorites": initialTab = 2
            case "foods", "custom": initialTab = 3
            default: initialTab = 0
            }
        }
        _tab = State(initialValue: initialTab)
    }

    /// History · Favorites · Foods in ingredient mode (Meals removed); full set otherwise.
    private var visibleTabs: [String] {
        ingredientMode ? ["History", "Favorites", "Foods"] : Self.tabs
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
                    SegmentedTabs(items: visibleTabs, selection: $tab, accent: RingColor.calories.tint)
                        .padding(.horizontal, Metrics.pagePadding)
                        .padding(.top, 22)
                        .transition(.opacity)
                }

                content
            }
            .background(Theme.bg)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if ingredientMode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { HapticManager.shared.trigger(.light); dismiss() }
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(item: $selectedFood) { FoodDetailView(food: $0) }
            .sheet(item: $selectedMeal) { MealDetailView(meal: $0) }
            .sheet(isPresented: $showBuilder) { MealBuilderView() }
            .sheet(isPresented: $showManualFood) { ManualFoodEntryView(initialSlot: slot) }
            .fullScreenCover(isPresented: $showScan) { ScanView() }
            .task(id: query) { await runSearch(query) }
            .onAppear(perform: applyScreenshotHooks)
            .mealSlotMenu(isOpen: $slotMenuOpen, slot: $slot)
        }
    }

    // MARK: Header — just the title (the meal target now lives in the control strip)

    private var header: some View {
        HStack {
            Text(ingredientMode ? "Add Ingredient" : "Add Food")
                .font(.screenTitle)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.top, 6)
    }

    // MARK: Control strip — a meal chip, two glass action pills, and a morphing search
    //
    // Resting: [🥕 Snacks ▾]        [New Meal · Quick Add]  [Scan · Search]
    // Each pair sits in its own glass pill. Tapping Search: New Meal / Quick Add and the
    // Scan segment fade out while the search capsule animates its width from a circle to
    // full — a barcode button flies to its trailing edge and Cancel slides in. Only the
    // search capsule animates its own frame, so the morph stays buttery (unchanged).

    private let strip: CGFloat = 52
    private let pillWidth: CGFloat = 108

    private var controlStrip: some View {
        HStack(alignment: .center, spacing: 12) {
            mealChip
            if !searchExpanded {
                Spacer(minLength: 8)
                actionsPill
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
            searchGroup
            if searchExpanded {
                cancelButton
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: searchExpanded)
    }

    /// Leading chip: the meal target. Slot glyph + name + chevron in the slot's colour;
    /// tapping opens the slot menu (hosted on the screen). While searching it collapses to
    /// just the glyph so the search field gets the room.
    private var mealChip: some View {
        DropdownTrigger(isOpen: $slotMenuOpen) {
            HStack(spacing: 7) {
                Image(systemName: slot.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                if !searchExpanded {
                    Text(slot.rawValue)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)   // shrink before it can shove the pills off-edge
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundStyle(mealSlotColor(slot))
        }
    }

    /// New Meal + Quick Add, together in one glass pill (two icon segments, hairline divider).
    private var actionsPill: some View {
        HStack(spacing: 0) {
            segButton("fork.knife", tint: Self.stripTint) {
                HapticManager.shared.trigger(.light); showBuilder = true
            }
            segDivider
            segButton("square.and.pencil", tint: Self.stripTint) {
                HapticManager.shared.trigger(.light); showManualFood = true
            }
        }
        .frame(width: pillWidth, height: strip)
        .glassEffect(.regular.interactive(), in: Capsule())
        .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))
    }

    /// Scan + Search share one glass pill — their capsules merge inside the container.
    /// Tapping Search expands the search capsule to full width; the Scan segment fades out.
    private var searchGroup: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if !searchExpanded {
                    scanButton
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
                searchBar
            }
        }
        .frame(maxWidth: searchExpanded ? .infinity : nil)
    }

    /// Scan — its own glass circle, sitting flush beside Search in the shared pill.
    private var scanButton: some View {
        Button { HapticManager.shared.trigger(.light); showScan = true } label: {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Self.stripTint)
                .frame(width: strip, height: strip)
                .glassEffect(.regular.interactive(), in: Circle())
                .overlay(Circle().stroke(Theme.cardStroke, lineWidth: 1))
        }
        .buttonStyle(CirclePress())
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
                        .foregroundStyle(Theme.bg)                // dark glyph on the light fill
                        .frame(width: 40, height: 40)
                        .background(Self.stripTint, in: Circle()) // oatmeal (calorie) solid fill
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
                .foregroundStyle(Self.stripTint)
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
        if ingredientMode {
            // History · Favorites · Foods (no Meals); meals filtered out of every list.
            switch tab {
            case 1: foodList(store.favorites.filter { !$0.isCustomMeal }, empty: "No favorites yet", hint: "Tap the star on any food to save it here.", icon: "star")
            case 2: foodList(customFoods.filter { !$0.isCustomMeal }, empty: "No custom foods yet", hint: "Scan or Quick Add a food and it shows up here.", icon: "fork.knife")
            default: historyList
            }
        } else {
            switch tab {
            case 1: mealsList
            case 2: foodList(store.favorites, empty: "No favorites yet", hint: "Tap the star on any food to save it here.", icon: "star")
            case 3: foodList(customFoods, empty: "No custom foods yet", hint: "Scan or Quick Add a food and it shows up here.", icon: "fork.knife")
            default: historyList
            }
        }
    }

    // History — one-tap re-log of the exact portion you logged last time.
    @ViewBuilder
    private var historyList: some View {
        let items = ingredientMode ? store.recentLogItems.filter { !$0.food.isCustomMeal } : store.recentLogItems
        if items.isEmpty {
            emptyState("clock.arrow.circlepath", "Nothing logged yet",
                       "Foods you log will appear here for a fast one-tap re-log.")
        } else {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                if i > 0 { rowDivider }
                AddRow(food: item.food,
                       subtitle: recentSubtitle(item),
                       slotName: ingredientMode ? "meal" : slot.rawValue,
                       onAdd: { frame in addOrPick(item.food, servings: item.servings, from: frame) },
                       onOpen: { onRowOpen(item.food) })
            }
        }
    }

    // Meals — a 3-column grid of compact meal cards (tap opens the detail; the dashed tile
    // at the end creates a new meal). Cards, not a list — meals read as composed dishes.
    private var mealsGridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 8),
         GridItem(.flexible(), spacing: 8),
         GridItem(.flexible(), spacing: 8)]
    }

    private var mealsList: some View {
        LazyVGrid(columns: mealsGridColumns, spacing: 8) {
            ForEach(store.customMeals) { meal in
                MealTallCard(meal: meal,
                             onTap: { HapticManager.shared.trigger(.light); selectedMeal = meal },
                             onToggleFavorite: { withAnimation(.snappy) { _ = store.toggleFavorite(meal) } })
            }
            CreateMealTallCard(action: { showBuilder = true })
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func foodList(_ foods: [Food], empty: String, hint: String, icon: String) -> some View {
        if foods.isEmpty {
            emptyState(icon, empty, hint)
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
               slotName: ingredientMode ? "meal" : slot.rawValue,
               onAdd: { frame in addOrPick(food, servings: 1, from: frame) },
               onOpen: { onRowOpen(food) })
    }

    /// Log to the target slot (flown into the island), or hand the food to the meal
    /// builder in ingredient mode (flown into the island's live tray).
    private func addOrPick(_ food: Food, servings: Double, from frame: CGRect) {
        if let pick = onPickIngredient {
            pick(food)
            island.addToTray(food, from: frame)
        } else {
            // The controller performs the store write itself so the card rolls in sync.
            island.log(food, slot: slot, servings: servings, from: frame, store: store)
        }
    }

    /// Row tap: open the detail normally; in ingredient mode a tap just adds the ingredient
    /// (the detail's Log-to-slot CTA would be meaningless while composing a meal).
    private func onRowOpen(_ food: Food) {
        // In ingredient mode a row tap adds it; fly from the island itself (no tile).
        if onPickIngredient != nil { addOrPick(food, servings: 1, from: island.islandCenter) }
        else { open(food) }
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
        results = ingredientMode ? hits.filter { !$0.isCustomMeal } : hits
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

    private func applyScreenshotHooks() {
        guard !ingredientMode else { return }
        let env = ProcessInfo.processInfo.environment
        if env["SALORIE_SCAN"] == "1" { showScan = true }
        if env["SALORIE_QUICKADD"] == "1" { showManualFood = true }
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
    /// Passes the tile's frame (in the "screen" space) so the island can fly a
    /// token from exactly here.
    let onAdd: (CGRect) -> Void
    let onOpen: () -> Void
    @State private var added = false
    @State private var pressed = false
    @State private var tileFrame: CGRect = .zero
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
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("screen")) } action: { tileFrame = $0 }

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
                onAdd(tileFrame)
                // The + becomes a green check (0.3 → 1) and the row tile presses.
                withAnimation(.snappy) { added = true }
                withAnimation(.snappy) { pressed = true }
                resetTask?.cancel()
                resetTask = Task {
                    try? await Task.sleep(for: .milliseconds(140))
                    if !Task.isCancelled { withAnimation(.snappy) { pressed = false } }
                    try? await Task.sleep(for: .seconds(1))
                    if !Task.isCancelled { withAnimation(.snappy) { added = false } }
                }
            } label: {
                Image(systemName: added ? "checkmark" : "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(added ? Color(hex: 0x86B98E) : AddView.stripTint)
                    .frame(width: 36, height: 36)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(food.name) to \(slotName)")
        }
        .scaleEffect(pressed ? 0.96 : 1)
        .padding(.vertical, 9)
    }
}

#Preview {
    AddView()
        .environment(MockStore())
        .environment(IslandController())
        .preferredColorScheme(.dark)
}
