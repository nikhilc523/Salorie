import SwiftUI

/// Full-catalog picker used while building a custom meal. Same search surface as
/// `AddView` (search field + FREQUENT / RECENT / FAVORITES shortcuts), but every
/// tap adds the food to the meal as an ingredient instead of logging it. Custom
/// meals themselves are excluded so meals never nest inside meals.
struct IngredientPickerView: View {
    @Environment(MockStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Called once per tapped food. The builder appends it as a component.
    var onPick: (Food) -> Void

    @State private var query = ""
    @State private var addedCount = 0

    private var singles: [Food] { store.foods }   // no custom meals here

    private var results: [Food] {
        guard !query.isEmpty else { return [] }
        return singles.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    searchField
                    if query.isEmpty {
                        section("FREQUENT", Array(store.frequentFoods.filter { !$0.isCustomMeal }.prefix(6)))
                        section("FAVORITES", store.favorites.filter { !$0.isCustomMeal })
                        section("ALL FOODS", singles)
                    } else if results.isEmpty {
                        emptyResults
                    } else {
                        section("RESULTS", results)
                    }
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle("Add Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(addedCount > 0 ? "Done (\(addedCount))" : "Done") {
                        HapticManager.shared.trigger(.light); dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func section(_ title: String, _ foods: [Food]) -> some View {
        if !foods.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).overlineStyle().padding(.bottom, 6)
                ForEach(Array(foods.enumerated()), id: \.element.id) { i, food in
                    if i > 0 { Divider().overlay(Theme.divider) }
                    row(food)
                }
            }
        }
    }

    private func row(_ food: Food) -> some View {
        HStack(spacing: 12) {
            Image(systemName: food.symbol)
                .font(.system(size: 16))
                .foregroundStyle(food.tint.fg)
                .frame(width: 34, height: 34)
                .background(food.tint.bg, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(food.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text("\(food.calories) cal · \(food.servingDescription)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                HapticManager.shared.trigger(.success)
                onPick(food)
                withAnimation(.snappy) { addedCount += 1 }
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
            HapticManager.shared.trigger(.success)
            onPick(food)
            withAnimation(.snappy) { addedCount += 1 }
        }
    }

    private var emptyResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30)).foregroundStyle(Theme.textTertiary)
            Text("No matches for \u{201C}\(query)\u{201D}")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("", text: $query, prompt: Text("Search foods to add")
                .foregroundColor(Theme.textTertiary))
                .foregroundStyle(Theme.textPrimary)
            if !query.isEmpty {
                Button {
                    HapticManager.shared.trigger(.light); query = ""
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
    IngredientPickerView(onPick: { _ in })
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
