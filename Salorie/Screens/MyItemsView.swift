import SwiftUI

/// "My Items" — the user's saved foods. A simple two-tab switcher (Favorites / Custom)
/// over a clean vertical list. Marking any food a favorite drops it into the Favorites tab.
struct MyItemsView: View {
    @Environment(MockStore.self) private var store
    @State private var selectedFood: Food?
    @State private var tab = 0

    private var favorites: [Food] { store.foods.filter(\.isFavorite) }
    private var custom: [Food] { store.foods.filter { $0.source == .openFoodFacts || $0.source == .custom } }
    private var shown: [Food] { tab == 0 ? favorites : custom }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NotionPageHeader(symbol: "square.stack.3d.up.fill", tint: .purple, title: "My Items",
                                     subtitle: "Your saved & custom foods")

                    HStack(spacing: 10) {
                        switcherPill
                        Spacer()
                        Text("\(shown.count) \(shown.count == 1 ? "item" : "items")")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    if shown.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(shown) { food in
                                SavedItemRow(food: food,
                                             onTap: { selectedFood = food },
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
            .navigationTitle("My Items")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedFood) { FoodDetailView(food: $0) }
        }
    }

    /// The glass "✳ Favorites ⌄" dropdown pill (ref: Food Database's "All foods" chip).
    /// Opens a menu to switch the visible list between Favorites and Custom.
    private var switcherPill: some View {
        Menu {
            Button {
                HapticManager.shared.trigger(.selection)
                withAnimation(.snappy) { tab = 0 }
            } label: {
                Label("Favorites", systemImage: tab == 0 ? "checkmark" : "star")
            }
            Button {
                HapticManager.shared.trigger(.selection)
                withAnimation(.snappy) { tab = 1 }
            } label: {
                Label("Custom", systemImage: tab == 1 ? "checkmark" : "puzzlepiece")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "asterisk")
                    .font(.system(size: 13, weight: .semibold))
                Text(tab == 0 ? "Favorites" : "Custom")
                    .font(.system(size: 15, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: tab == 0 ? "star" : "puzzlepiece")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
            Text(tab == 0 ? "No favorites yet" : "No custom foods yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(tab == 0 ? "Tap the star on any food to save it here."
                          : "Foods you scan or add by hand show up here.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
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
