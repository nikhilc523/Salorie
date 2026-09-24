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

    /// The full macro breakdown for this serving — Apple Health numbers grid
    /// (mirrors the day-detail Nutrition Details layout).
    private var nutrientStats: [NutrientStat] {
        func g(_ v: Double) -> String { "\(Int(v.rounded()))g" }
        func mg(_ v: Double) -> String { "\(Int(v.rounded())) mg" }
        func pct(_ v: Double, _ target: Double) -> String? {
            target > 0 ? "\(Int((v / target * 100).rounded()))% of goal" : nil
        }
        return [
            NutrientStat(label: "Carbs", value: g(food.carbs * servings), sub: pct(food.carbs * servings, store.targets.carbs)),
            NutrientStat(label: "Protein", value: g(food.protein * servings), sub: pct(food.protein * servings, store.targets.protein)),
            NutrientStat(label: "Total Fat", value: g(food.fat * servings), sub: pct(food.fat * servings, store.targets.fat)),
            NutrientStat(label: "Dietary Fibre", value: g(food.fibre * servings), sub: pct(food.fibre * servings, store.targets.fibre)),
            NutrientStat(label: "Sugars", value: g(food.sugars * servings), sub: nil),
            NutrientStat(label: "Saturated Fat", value: g(food.saturatedFat * servings), sub: nil),
            NutrientStat(label: "Sodium", value: mg(food.sodium * servings), sub: "of 2,300 mg"),
            NutrientStat(label: "Cholesterol", value: mg(food.cholesterol * servings), sub: nil),
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

            nutritionGrid
        }
    }

    // Two-column numbers grid with hairline row dividers (Apple Health layout).
    private var nutritionGrid: some View {
        let rows = stride(from: 0, to: nutrientStats.count, by: 2).map { i in
            Array(nutrientStats[i..<min(i + 2, nutrientStats.count)])
        }
        return VStack(alignment: .leading, spacing: 0) {
            Text("NUTRITION").overlineStyle()
                .padding(.bottom, 4)
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(row) { nutrientCell($0) }
                    if row.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                }
                .padding(.vertical, 14)
                if idx < rows.count - 1 {
                    Rectangle().fill(Theme.divider).frame(height: 1)
                }
            }
        }
    }

    private func nutrientCell(_ stat: NutrientStat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(stat.label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text(stat.value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
            if let sub = stat.sub {
                Text(sub)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .foregroundStyle(RingColor.carb.tint)                 // terracotta glyph
                .frame(width: 38, height: 38)
                .background(Circle().fill(RingColor.carb.tint.opacity(0.16)))
                .overlay(Circle().stroke(RingColor.carb.tint.opacity(0.28), lineWidth: 1))
        }
        .buttonStyle(.plain)
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
        HStack {
            Spacer()
            Button {
                HapticManager.shared.trigger(.success)
                store.addEntry(food, slot: slot, servings: servings)
                dismiss()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("Add \(servings.formatted(.number.precision(.fractionLength(0...1)))) to \(slot.rawValue)")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
            }
            .buttonStyle(AddPressStyle(tint: RingColor.carb.tint))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
        .padding(.bottom, 8)
        .background(
            LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg, Theme.bg],
                           startPoint: .top, endPoint: .bottom)
        )
    }
}

// MARK: - Small view helpers

/// One nutrient in the food-detail numbers grid.
struct NutrientStat: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let sub: String?
}

/// Terracotta capsule CTA that springs on press.
private struct AddPressStyle: ButtonStyle {
    var tint: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule().fill(
                    LinearGradient(colors: [tint.opacity(0.92), tint], startPoint: .top, endPoint: .bottom)
                )
            )
            .shadow(color: tint.opacity(configuration.isPressed ? 0.15 : 0.35), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

#Preview {
    FoodDetailView(food: SampleData.foods[1])
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
