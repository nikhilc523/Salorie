import SwiftUI

/// Add food. Search / Scan strip. With no query, auto-populates the fastest re-log
/// candidates — Frequent, Recent, Favorites — so logging is one tap and no re-scan.
struct AddView: View {
    @Environment(MockStore.self) private var store
    @State private var tab = ProcessInfo.processInfo.environment["SALORIE_SCAN"] == "1" ? 1 : 0
    @State private var query = ProcessInfo.processInfo.environment["SALORIE_QUERY"] ?? ""
    @State private var selectedFood: Food?
    @State private var selectedMeal: Food?
    @State private var showBuilder = false
    @State private var expandedSections: Set<String> = []   // sections showing all rows
    @State private var results: [Food] = []
    @State private var searching = false

    /// Debounced search against the store's async catalog. `.task(id: query)`
    /// cancels the in-flight run on each keystroke, so the sleep debounces cleanly.
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

    /// One-tap adds land in the meal that fits the time of day.
    private var defaultSlot: MealSlot {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11:  return .breakfast
        case 11..<15: return .lunch
        case 15..<21: return .dinner
        default:      return .snacks
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Metrics.pagePadding)
                    .padding(.top, 4)

                SegmentedTabs(items: ["Search", "Scan"], selection: $tab, equalWidths: true)
                    .padding(.horizontal, Metrics.pagePadding)
                    .padding(.top, 14)

                if tab == 0 { searchTab } else { ScanView() }
            }
            .background(Theme.bg)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedFood) { FoodDetailView(food: $0) }
            .sheet(item: $selectedMeal) { MealDetailView(meal: $0) }
            .sheet(isPresented: $showBuilder) { MealBuilderView() }
            .onAppear {
                // Screenshot/testing hooks: SALORIE_MEAL=detail|builder.
                switch ProcessInfo.processInfo.environment["SALORIE_MEAL"] {
                case "detail": selectedMeal = store.customMeals.first
                case "builder": showBuilder = true
                default: break
                }
                // Screenshot hook: open a real catalog food's detail by barcode.
                if let code = ProcessInfo.processInfo.environment["SALORIE_OPEN_BARCODE"] {
                    Task { selectedFood = await store.food(forBarcode: code) }
                }
            }
        }
    }

    /// Bold screen heading matching the other tabs (My Items / Sharing).
    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Add Food")
                .font(.screenTitle)
                .foregroundStyle(Theme.textPrimary)
            Text("Search or scan to log a food")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Custom meals open the meal detail; single foods open the food detail.
    private func open(_ food: Food) {
        HapticManager.shared.trigger(.light)
        if food.isCustomMeal { selectedMeal = food } else { selectedFood = food }
    }

    // MARK: Search + auto-populated lists

    private var searchTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                searchField

                if query.isEmpty {
                    myMealsSection
                    section("FREQUENT", Array(store.frequentFoods.filter { !$0.isCustomMeal }.prefix(10)))
                    section("RECENT", Array(store.recentFoods.filter { !$0.isCustomMeal }.prefix(10)))
                    section("FAVORITES", store.favorites)
                } else if results.isEmpty {
                    if !searching { emptyResults }   // stay quiet during the debounce
                } else {
                    section("RESULTS", results, collapsible: false)
                }
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.bg)
        .scrollContentBackground(.hidden)
        .task(id: query) { await runSearch(query) }
    }

    // MARK: MY MEALS — a normal list (the hero cards live in My Items → Meals)

    private var myMealsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("MY MEALS").overlineStyle()
                Spacer()
                Button {
                    HapticManager.shared.trigger(.light)
                    showBuilder = true
                } label: {
                    Label("Create", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Self.addTint)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 6)

            if store.customMeals.isEmpty {
                Text("No meals yet — tap Create to build one.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 6)
            } else {
                rows("MY MEALS", store.customMeals)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ foods: [Food], collapsible: Bool = true) -> some View {
        if !foods.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).overlineStyle().padding(.bottom, 6)
                rows(title, foods, collapsible: collapsible)
            }
        }
    }

    private func toggleSection(_ title: String) {
        HapticManager.shared.trigger(.light)
        withAnimation(.snappy(duration: 0.26)) {
            if expandedSections.contains(title) { expandedSections.remove(title) }
            else { expandedSections.insert(title) }
        }
    }

    /// First 3 rows; the rest revealed on demand via a "Show N more" disclosure.
    @ViewBuilder
    private func rows(_ title: String, _ foods: [Food], collapsible: Bool = true) -> some View {
        let expanded = expandedSections.contains(title)
        let canCollapse = collapsible && foods.count > 3
        let shown = (canCollapse && !expanded) ? Array(foods.prefix(3)) : foods
        ForEach(Array(shown.enumerated()), id: \.element.id) { i, food in
            if i > 0 { Divider().overlay(Theme.divider) }
            foodRow(food)
        }
        if canCollapse {
            Button { toggleSection(title) } label: {
                HStack(spacing: 4) {
                    Text(expanded ? "Show less" : "Show \(foods.count - 3) more")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Self.addTint)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Warm quick-add tint from the palette (terracotta), matching the food-detail CTA.
    private static let addTint = RingColor.carb.tint

    /// Row subtitle — leads with the **brand** so brand searches are legible
    /// (e.g. "Minute Maid · 5 cal · OFF"), falls back to source for generics.
    private func rowSubtitle(_ food: Food) -> String {
        if food.isCustomMeal {
            return "\(food.components.count) ingredients · \(food.calories) cal"
        }
        let parts = [food.brand, "\(food.calories) cal", food.source.short]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private func foodRow(_ food: Food) -> some View {
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
                Text(rowSubtitle(food))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                HapticManager.shared.trigger(.success)
                store.addEntry(food, slot: defaultSlot)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Self.addTint)
                    .frame(width: 34, height: 34)
                    .glassEffect(.regular, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { open(food) }
    }

    private var emptyResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(Theme.textTertiary)
            Text("No matches for \u{201C}\(query)\u{201D}")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text("Try a different name, or scan the barcode.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

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
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    AddView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
