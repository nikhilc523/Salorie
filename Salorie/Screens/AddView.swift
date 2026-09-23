import SwiftUI

/// Add food. Search / Scan strip. With no query, auto-populates the fastest re-log
/// candidates — Frequent, Recent, Favorites — so logging is one tap and no re-scan.
struct AddView: View {
    @Environment(MockStore.self) private var store
    @State private var tab = ProcessInfo.processInfo.environment["SALORIE_SCAN"] == "1" ? 1 : 0
    @State private var query = ""
    @State private var selectedFood: Food?

    private var results: [Food] {
        guard !query.isEmpty else { return [] }
        return store.foods.filter { $0.name.localizedCaseInsensitiveContains(query) }
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

    // MARK: Search + auto-populated lists

    private var searchTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                searchField

                if query.isEmpty {
                    section("FREQUENT", Array(store.frequentFoods.prefix(5)))
                    section("RECENT", Array(store.recentFoods.prefix(6)))
                    section("FAVORITES", store.favorites)
                } else if results.isEmpty {
                    emptyResults
                } else {
                    section("RESULTS", results)
                }
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.bg)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func section(_ title: String, _ foods: [Food]) -> some View {
        if !foods.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).overlineStyle().padding(.bottom, 6)
                ForEach(Array(foods.enumerated()), id: \.element.id) { i, food in
                    if i > 0 { Divider().overlay(Theme.divider) }
                    foodRow(food)
                }
            }
        }
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
                Text("\(food.calories) cal · \(food.source.rawValue)")
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
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.accent.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.trigger(.light)
            selectedFood = food
        }
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
