import SwiftUI

/// The food database — the flagship Notion table. Pinned name column + scrolling macro columns.
struct FoodDatabaseView: View {
    @Environment(MockStore.self) private var store
    @State private var selectedFood: Food?
    @State private var query = ""

    private var filtered: [Food] {
        guard !query.isEmpty else { return store.foods }
        return store.foods.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NotionPageHeader(symbol: "fork.knife", tint: .orange, title: "Food Database",
                                     subtitle: "\(store.foods.count) foods across 5 sources")

                    HStack {
                        FilterChip(title: "All foods")
                        Spacer()
                        NotionToolbar(onNew: {})
                    }

                    NotionTable(
                        columns: columns,
                        rows: rows,
                        newRowTitle: "New food",
                        onNewRow: {}
                    )
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle("Foods")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search foods")
            .sheet(item: $selectedFood) { FoodDetailView(food: $0) }
        }
    }

    private var columns: [NotionColumn] {
        [
            NotionColumn(title: "Tags", icon: "tag", width: 170),
            NotionColumn(title: "Cal", icon: "flame", width: 66, alignment: .trailing),
            NotionColumn(title: "Protein", icon: "bolt.fill", width: 88),
            NotionColumn(title: "Carb", icon: "leaf.fill", width: 78),
            NotionColumn(title: "Fibre", icon: "circle.grid.cross", width: 74),
            NotionColumn(title: "Source", icon: "shippingbox", width: 110),
            NotionColumn(title: "", width: 120),
        ]
    }

    private var rows: [NotionRow] {
        filtered.map { food in
            NotionRow(
                icon: food.symbol,
                tint: food.tint,
                name: food.name,
                ghost: food.isOpen ? "OPEN" : nil,
                cells: [
                    .tags(food.tags),
                    .number("\(food.calories)"),
                    .macro(.protein, "\(Int(food.protein))g"),
                    .macro(.carb, "\(Int(food.carbs))g"),
                    .macro(.fibre, "\(Int(food.fibre))g"),
                    .source(food.source),
                    .button(title: "Add", color: .blue) {
                        store.addEntry(food, slot: .snacks)
                    },
                ],
                onTap: { selectedFood = food }
            )
        }
    }
}

#Preview {
    FoodDatabaseView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
