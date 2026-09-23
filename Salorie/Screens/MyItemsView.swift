import SwiftUI

/// "My Items" — a kanban/gallery of the user's saved foods, grouped into board columns.
struct MyItemsView: View {
    @Environment(MockStore.self) private var store
    @State private var selectedFood: Food?

    private var favorites: [Food] { store.foods.filter(\.isFavorite) }
    private var custom: [Food] { store.foods.filter { $0.source == .openFoodFacts || $0.source == .custom } }
    private var recent: [Food] { Array(store.foods.suffix(5)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    NotionPageHeader(symbol: "square.stack.3d.up.fill", tint: .purple, title: "My Items",
                                     subtitle: "Your saved & custom foods")

                    HStack {
                        FilterChip(systemImage: "square.grid.2x2", title: "Board")
                        Spacer()
                        NotionToolbar(onNew: {})
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            column("Favorites", "star.fill", favorites, .yellow)
                            column("Custom & OFF", "puzzlepiece.fill", custom, .orange)
                            column("Recent", "clock.fill", recent, .blue)
                        }
                        .padding(.horizontal, 2)
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

    private func column(_ title: String, _ symbol: String, _ foods: [Food], _ tint: TagColor) -> some View {
        BoardColumn(title: title, symbol: symbol, count: foods.count, tint: tint) {
            VStack(spacing: 10) {
                ForEach(foods) { food in
                    BoardCard(food: food) { selectedFood = food }
                }
                Button {
                    HapticManager.shared.trigger(.light)
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("New")
                        Spacer()
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .frame(width: 220)
                    .background(Theme.surface.opacity(0.5),
                                in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    MyItemsView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
