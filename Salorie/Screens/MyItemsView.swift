import SwiftUI

/// "My Items" — the user's saved foods. A simple two-tab switcher (Favorites / Custom)
/// over a clean vertical list. Marking any food a favorite drops it into the Favorites tab.
struct MyItemsView: View {
    @Environment(MockStore.self) private var store
    @State private var selectedFood: Food?
    @State private var selectedMeal: Food?
    @State private var showBuilder = false
    @State private var showAdd = false
    @State private var tab = 0

    private var favorites: [Food] { store.searchableFoods.filter(\.isFavorite) }
    private var meals: [Food] { store.customMeals }
    private var custom: [Food] { store.foods.filter { $0.source == .openFoodFacts || $0.source == .custom } }
    private var shown: [Food] {
        switch tab { case 0: return favorites; case 1: return meals; default: return custom }
    }

    /// Custom meals open the meal detail; single foods open the food detail.
    private func open(_ food: Food) {
        HapticManager.shared.trigger(.light)
        if food.isCustomMeal { selectedMeal = food } else { selectedFood = food }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    SegmentedTabs(items: ["Favorites", "Meals", "Custom"], selection: $tab)

                    if shown.isEmpty {
                        emptyState
                    } else if tab == 1 {
                        mealGrid
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(shown) { food in
                                SavedItemRow(food: food,
                                             onTap: { open(food) },
                                             onToggleFavorite: {
                                                 HapticManager.shared.trigger(.selection)
                                                 withAnimation(.snappy) { store.toggleFavorite(food) }
                                             })
                            }
                        }
                    }
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedFood) { FoodDetailView(food: $0) }
            .sheet(item: $selectedMeal) { MealDetailView(meal: $0) }
            .sheet(isPresented: $showBuilder) { MealBuilderView() }
            .sheet(isPresented: $showAdd) { AddView() }
            .onAppear {
                switch ProcessInfo.processInfo.environment["SALORIE_ITEMS"] {
                case "meals": tab = 1
                case "custom": tab = 2
                default: break
                }
            }
        }
    }

    /// Tall portrait meal cards, 2-up, with a matching create tile at the end.
    private var mealGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(shown) { meal in
                MealTallCard(
                    meal: meal,
                    onTap: { open(meal) },
                    onToggleFavorite: {
                        withAnimation(.snappy) { store.toggleFavorite(meal) }
                    }
                )
            }
            CreateMealTallCard { showBuilder = true }
        }
    }

    /// Bold title (our screen typography) + a neutral add-meal button. No icon,
    /// no redundant nav title, no count — the segmented strip carries navigation.
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("My Items")
                    .font(.screenTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("Your saved & custom foods")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            // No add on Favorites — you don't create directly into favorites.
            // Meals → build a meal; Custom → the Add (search/scan) screen.
            if tab != 0 {
                Button {
                    HapticManager.shared.trigger(.light)
                    if tab == 2 { showAdd = true } else { showBuilder = true }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 42, height: 42)
                        .background(Theme.surface, in: Circle())
                        .overlay(Circle().stroke(Theme.cardStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: tab)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: tab == 0 ? "star" : (tab == 1 ? "takeoutbag.and.cup.and.straw" : "puzzlepiece"))
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
            Text(tab == 0 ? "No favorites yet" : (tab == 1 ? "No meals yet" : "No custom foods yet"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(tab == 0 ? "Tap the star on any food to save it here."
                 : (tab == 1 ? "Build a meal from your foods to log it in one tap."
                             : "Foods you scan or add by hand show up here."))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
            if tab == 1 {
                Button {
                    HapticManager.shared.trigger(.light)
                    showBuilder = true
                } label: {
                    Label("Create meal", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// MARK: - SavedItemRow

/// Full-width saved-food row: icon · name + tags · calories · star toggle.
struct SavedItemRow: View {
    var food: Food
    var onTap: () -> Void = {}
    var onToggleFavorite: () -> Void = {}

    var body: some View {
        Button {
            HapticManager.shared.trigger(.light)
            onTap()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: food.symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(food.tint.fg)
                    .frame(width: 30, height: 30)
                    .background(food.tint.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(food.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        ForEach(food.tags.prefix(2)) { TagPill($0) }
                    }
                }

                Spacer(minLength: 8)

                Text("\(food.calories) cal")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)

                Button {
                    onToggleFavorite()
                } label: {
                    Image(systemName: food.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 15))
                        .foregroundStyle(food.isFavorite ? TagColor.yellow.fg : Theme.textTertiary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .stroke(Theme.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MyItemsView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
