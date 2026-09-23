import SwiftUI

/// Detail sheet for a single food. Cardless — everything floats on pure black.
/// Instead of a goal ring (which doesn't fit one food), macros are shown as their
/// share of your daily goal: grams + a clean bar + percent.
struct FoodDetailView: View {
    @Environment(MockStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let food: Food
    @State private var servings: Double = 1
    @State private var slot: MealSlot = .breakfast

    private var calories: Int { Int((Double(food.calories) * servings).rounded()) }
    private var caloriePct: Int {
        guard store.targets.calories > 0 else { return 0 }
        return Int((Double(calories) / Double(store.targets.calories) * 100).rounded())
    }

    /// Each macro in this serving, as a share of the daily target.
    private var shares: [MacroShare] {
        [
            MacroShare(label: "Carbs",   grams: food.carbs * servings,   target: store.targets.carbs,   colors: RingColor.carb.stops),
            MacroShare(label: "Protein", grams: food.protein * servings, target: store.targets.protein, colors: RingColor.protein.stops),
            MacroShare(label: "Fat",     grams: food.fat * servings,     target: store.targets.fat,     colors: Theme.macroFatStops),
            MacroShare(label: "Fibre",   grams: food.fibre * servings,   target: store.targets.fibre,   colors: RingColor.fibre.stops),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    macroBreakdown
                    servingStepper
                    slotPicker
                    details
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
                        withAnimation(.snappy) { store.toggleFavorite(food) }
                    } label: {
                        Image(systemName: food.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(food.isFavorite ? RingColor.protein.tint : Theme.textSecondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { addBar }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Header

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

    // MARK: Macro breakdown (share of daily goal)

    private var macroBreakdown: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(calories)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text("kcal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("\(caloriePct)% of daily goal")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }

            VStack(spacing: 8) {
                Text("SHARE OF DAILY GOAL").overlineStyle()
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 14) {
                    ForEach(shares) { macroShareRow($0) }
                }
            }
        }
    }

    private func macroShareRow(_ s: MacroShare) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Circle()
                    .fill(LinearGradient(colors: s.colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: 7, height: 7)
                Text(s.label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                Text("\(Int(s.grams.rounded())) g")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(s.percentText)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 40, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill((s.colors.first ?? .white).opacity(0.14))
                    Capsule()
                        .fill(LinearGradient(colors: s.colors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, geo.size.width * s.pct))
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: Serving stepper

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

    // MARK: Meal slot picker (uniform neutral selection — no per-slot color)

    private var slotPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ADD TO MEAL").overlineStyle()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MealSlot.allCases) { s in
                        let isOn = slot == s
                        Button {
                            HapticManager.shared.trigger(.selection)
                            withAnimation(.snappy) { slot = s }
                        } label: {
                            Label(s.rawValue, systemImage: s.symbol)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundStyle(isOn ? Color(hex: 0x000000) : Theme.textSecondary)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(
                                    Capsule().fill(isOn ? Theme.textPrimary : Theme.surface)
                                )
                                .overlay(
                                    Capsule().stroke(Theme.cardStroke, lineWidth: isOn ? 0 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    // MARK: Details (cardless)

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DETAILS").overlineStyle().padding(.bottom, 4)
            PropertyRow(icon: "scalemass", label: "Serving") {
                Text(food.servingDescription)
            }
            Divider().overlay(Theme.divider)
            PropertyRow(icon: "tag", label: "Source") {
                SourceBadge(source: food.source)
            }
        }
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

    // MARK: Add bar

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

// MARK: - MacroShare

/// One macro's contribution from this serving toward the daily target.
struct MacroShare: Identifiable {
    let label: String
    let grams: Double
    let target: Double
    let colors: [Color]

    var id: String { label }
    var pct: Double { target > 0 ? min(grams / target, 1) : 0 }
    var percentText: String { target > 0 ? "\(Int((grams / target * 100).rounded()))%" : "—" }
}

#Preview {
    FoodDetailView(food: SampleData.foods[1])
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
