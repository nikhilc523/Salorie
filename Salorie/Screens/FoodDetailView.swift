import SwiftUI

/// Notion-page-style detail for a single food. Presented as a glass sheet.
struct FoodDetailView: View {
    @Environment(MockStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let food: Food
    @State private var servings: Double = 1
    @State private var slot: MealSlot = .breakfast

    private var macroRings: [Ring] {
        [
            Ring(progress: (food.carbs * servings) / store.targets.carbs, color: .carb,
                 label: "Carb", valueText: "\(Int(food.carbs * servings))g"),
            Ring(progress: (food.protein * servings) / store.targets.protein, color: .protein,
                 label: "Protein", valueText: "\(Int(food.protein * servings))g"),
            Ring(progress: (food.fibre * servings) / store.targets.fibre, color: .fibre,
                 label: "Fibre", valueText: "\(Int(food.fibre * servings))g"),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    ringsRow
                    servingStepper
                    slotPicker
                    properties
                    if !food.ingredients.isEmpty { ingredients }
                }
                .padding(Metrics.pagePadding)
                .padding(.bottom, 90)
            }
            .background(Theme.bg)
            .scrollContentBackground(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { HapticManager.shared.trigger(.light); dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticManager.shared.trigger(.selection)
                        store.toggleFavorite(food)
                    } label: {
                        Image(systemName: food.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(food.isFavorite ? TagColor.yellow.fg : Theme.textSecondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { addBar }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: food.symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(food.tint.fg)
                .frame(width: 58, height: 58)
                .background(food.tint.bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(food.name)
                .font(.screenTitle)
                .foregroundStyle(Theme.textPrimary)
            if let brand = food.brand {
                Text(brand).font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 6) {
                SourceBadge(source: food.source)
                if food.isOpen { GhostBadge("OPEN") }
                ForEach(food.tags) { TagPill($0) }
            }
        }
    }

    private var ringsRow: some View {
        CalmCard {
            HStack(spacing: 22) {
                ActivityRings(
                    rings: macroRings,
                    centerText: "\(Int((Double(food.calories) * servings).rounded()))",
                    centerSubtitle: "kcal"
                )
                .frame(width: 130, height: 130)
                RingLegend(items: macroRings)
            }
        }
    }

    private var properties: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NUTRITION").overlineStyle().padding(.bottom, 4)
            PropertyRow(icon: "scalemass", label: "Serving") {
                Text(food.servingDescription)
            }
            Divider().overlay(Theme.divider)
            PropertyRow(icon: "flame", label: "Calories") {
                Text("\(Int((Double(food.calories) * servings).rounded())) kcal")
            }
            Divider().overlay(Theme.divider)
            PropertyRow(icon: "drop.fill", label: "Fat") {
                Text("\(Int(food.fat * servings)) g")
            }
            Divider().overlay(Theme.divider)
            PropertyRow(icon: "tag", label: "Source") {
                SourceBadge(source: food.source)
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INGREDIENTS").overlineStyle()
            Text(food.ingredients.joined(separator: ", "))
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var servingStepper: some View {
        HStack {
            Text("Servings").font(.sectionTitle).foregroundStyle(Theme.textPrimary)
            Spacer()
            HStack(spacing: 18) {
                stepButton("minus") { servings = max(0.5, servings - 0.5) }
                Text(servings.formatted(.number.precision(.fractionLength(0...1))))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 40)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                stepButton("plus") { servings += 0.5 }
            }
        }
        .padding(.vertical, 4)
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.trigger(.light)
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    private var slotPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MEAL").overlineStyle()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MealSlot.allCases) { s in
                        Button {
                            HapticManager.shared.trigger(.selection)
                            slot = s
                        } label: {
                            Label(s.rawValue, systemImage: s.symbol)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundStyle(slot == s ? Color(hex: 0x1A1A1A) : Theme.textPrimary)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .glassEffect(.regular.tint(slot == s ? s.tagColor.solid : .clear).interactive(),
                                             in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var addBar: some View {
        Button {
            HapticManager.shared.trigger(.success)
            store.addEntry(food, slot: slot, servings: servings)
            dismiss()
        } label: {
            Text("Add \(servings.formatted(.number.precision(.fractionLength(0...1)))) serving to \(slot.rawValue)")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accent)
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.vertical, 10)
    }
}

#Preview {
    FoodDetailView(food: SampleData.foods[1])
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
