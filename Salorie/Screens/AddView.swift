import SwiftUI

/// Add screen with a Notion-style Search / Scan segmented strip.
struct AddView: View {
    @Environment(MockStore.self) private var store
    @State private var tab = ProcessInfo.processInfo.environment["SALORIE_SCAN"] == "1" ? 1 : 0
    @State private var query = ""
    @State private var selectedFood: Food?

    private var results: [Food] {
        guard !query.isEmpty else { return store.foods }
        return store.foods.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SegmentedTabs(items: ["Search", "Scan"], selection: $tab)
                    .padding(.horizontal, Metrics.pagePadding)
                    .padding(.top, 8)

                if tab == 0 { searchTab } else { ScanView() }
            }
            .background(Theme.bg)
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedFood) { FoodDetailView(food: $0) }
        }
    }

    private var searchTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                searchField

                if query.isEmpty {
                    Text("RECENT & FAVORITES").overlineStyle()
                }

                NotionTable(
                    columns: [
                        NotionColumn(title: "Cal", icon: "flame", width: 66, alignment: .trailing),
                        NotionColumn(title: "Protein", icon: "bolt.fill", width: 88),
                        NotionColumn(title: "Source", icon: "tag", width: 110),
                        NotionColumn(title: "", width: 110),
                    ],
                    rows: results.map { food in
                        NotionRow(
                            icon: food.symbol,
                            tint: food.tint,
                            name: food.name,
                            ghost: food.isFavorite ? nil : (food.isOpen ? "OPEN" : nil),
                            cells: [
                                .number("\(food.calories)"),
                                .macro(.protein, "\(Int(food.protein))g"),
                                .source(food.source),
                                .button(title: "Add", color: .blue) {
                                    store.addEntry(food, slot: .snacks)
                                },
                            ],
                            onTap: { selectedFood = food }
                        )
                    },
                    showCount: false,
                    showNewRow: false
                )
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.bg)
        .scrollContentBackground(.hidden)
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
