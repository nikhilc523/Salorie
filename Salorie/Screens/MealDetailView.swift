import SwiftUI

/// Detail sheet for a custom meal. Cardless, on pure black — takes the calm
/// Apple-Fitness ring language (hero `ActivityRings` + `RingLegend` for the meal's
/// macro contribution) and pairs it with the ingredient breakdown. One tap logs
/// the whole meal to a slot; the overflow menu edits, expands, or deletes it.
struct MealDetailView: View {
    @Environment(MockStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let meal: Food
    @State private var servings: Double = 1
    @State private var slot: MealSlot = .breakfast
    @State private var editing = false
    @State private var inspectedComponent: Food?

    /// Live copy from the store so edits/favorite reflect immediately.
    private var current: Food { store.customMeals.first { $0.id == meal.id } ?? meal }

    private var calories: Int { Int((Double(current.calories) * servings).rounded()) }
    private var caloriePct: Int {
        guard store.targets.calories > 0 else { return 0 }
        return Int((Double(calories) / Double(store.targets.calories) * 100).rounded())
    }

    /// Full macro breakdown for this serving — same numbers grid as FoodDetailView.
    private var nutrientStats: [NutrientStat] {
        func g(_ v: Double) -> String { "\(Int(v.rounded()))g" }
        func mg(_ v: Double) -> String { "\(Int(v.rounded())) mg" }
        func pct(_ v: Double, _ target: Double) -> String? {
            target > 0 ? "\(Int((v / target * 100).rounded()))% of goal" : nil
        }
        let s = servings
        return [
            NutrientStat(label: "Carbs", value: g(current.carbs * s), sub: pct(current.carbs * s, store.targets.carbs)),
            NutrientStat(label: "Protein", value: g(current.protein * s), sub: pct(current.protein * s, store.targets.protein)),
            NutrientStat(label: "Total Fat", value: g(current.fat * s), sub: pct(current.fat * s, store.targets.fat)),
            NutrientStat(label: "Dietary Fibre", value: g(current.fibre * s), sub: pct(current.fibre * s, store.targets.fibre)),
            NutrientStat(label: "Sugars", value: g(current.sugars * s), sub: nil),
            NutrientStat(label: "Saturated Fat", value: g(current.saturatedFat * s), sub: nil),
            NutrientStat(label: "Sodium", value: mg(current.sodium * s), sub: "of 2,300 mg"),
            NutrientStat(label: "Cholesterol", value: mg(current.cholesterol * s), sub: nil),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    macroBreakdown
                    servingStepper
                    slotPicker
                    ingredientList
                }
                .padding(Metrics.pagePadding)
                .padding(.bottom, 96)
            }
            .background(Theme.bg)
            .scrollContentBackground(.hidden)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { HapticManager.shared.trigger(.light); dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) { favoriteButton }
                ToolbarItem(placement: .topBarTrailing) { overflowMenu }
            }
            .safeAreaInset(edge: .bottom) { addBar }
            .sheet(isPresented: $editing) { MealBuilderView(editing: current) }
            .sheet(item: $inspectedComponent) { FoodDetailView(food: $0) }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: current.symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(current.tint.fg)
                .frame(width: 58, height: 58)
                .background(current.tint.bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(current.name)
                .font(.screenTitle)
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 6) {
                TagPill(text: "CUSTOM MEAL", color: current.tint, style: .soft)
                Text("\(current.components.count) ingredients")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: Macro breakdown (numbers grid — matches FoodDetailView)

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

    private var nutritionGrid: some View {
        let rows = stride(from: 0, to: nutrientStats.count, by: 2).map { i in
            Array(nutrientStats[i..<min(i + 2, nutrientStats.count)])
        }
        return VStack(alignment: .leading, spacing: 0) {
            Text("NUTRITION").overlineStyle().padding(.bottom, 4)
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

    // MARK: Serving stepper (scales the whole meal)

    private var servingStepper: some View {
        HStack {
            Text("Servings").font(.sectionTitle).foregroundStyle(Theme.textPrimary)
            Spacer()
            HStack(spacing: 18) {
                stepButton("minus") { servings = max(0.5, servings - 0.5) }
                Text(servings.formatted(.number.precision(.fractionLength(0...1))))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit().frame(minWidth: 40)
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
                .foregroundStyle(RingColor.carb.tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(RingColor.carb.tint.opacity(0.16)))
                .overlay(Circle().stroke(RingColor.carb.tint.opacity(0.28), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Slot picker

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
                                .lineLimit(1).fixedSize()
                                .foregroundStyle(isOn ? Color(hex: 0x000000) : Theme.textSecondary)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(Capsule().fill(isOn ? Theme.textPrimary : Theme.surface))
                                .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: isOn ? 0 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    // MARK: Ingredient list

    private var ingredientList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("INGREDIENTS").overlineStyle().padding(.bottom, 6)
            ForEach(current.components) { component in
                ingredientRow(component)
                if component.id != current.components.last?.id {
                    Rectangle().fill(Theme.divider).frame(height: 1)
                }
            }
        }
    }

    private func ingredientRow(_ component: MealComponent) -> some View {
        Button {
            HapticManager.shared.trigger(.light)
            inspectedComponent = component.food
        } label: {
            HStack(spacing: 12) {
                Image(systemName: component.food.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(component.food.tint.fg)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(component.food.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(servingLabel(component))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary).monospacedDigit()
                }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(component.calories.rounded()))")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit().foregroundStyle(Theme.textPrimary)
                    Text("cal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func servingLabel(_ c: MealComponent) -> String {
        let mult = c.servings.formatted(.number.precision(.fractionLength(0...1)))
        return "×\(mult) · \(c.food.servingDescription)"
    }

    // MARK: Toolbar buttons

    private var favoriteButton: some View {
        Button {
            HapticManager.shared.trigger(.selection)
            withAnimation(.snappy) { store.toggleFavorite(current) }
        } label: {
            Image(systemName: current.isFavorite ? "star.fill" : "star")
                .foregroundStyle(current.isFavorite ? RingColor.protein.tint : Theme.textSecondary)
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button { HapticManager.shared.trigger(.light); editing = true } label: {
                Label("Edit meal", systemImage: "square.and.pencil")
            }
            Button {
                HapticManager.shared.trigger(.success)
                for c in current.components {
                    store.addEntry(c.food, slot: slot, servings: c.servings * servings)
                }
                dismiss()
            } label: {
                Label("Log as separate items", systemImage: "list.bullet.indent")
            }
            Divider()
            Button(role: .destructive) {
                HapticManager.shared.trigger(.warning)
                store.deleteMeal(current)
                dismiss()
            } label: {
                Label("Delete meal", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle").foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Add bar

    private var addBar: some View {
        HStack {
            Spacer()
            Button {
                HapticManager.shared.trigger(.success)
                store.addEntry(current, slot: slot, servings: servings)
                dismiss()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 15, weight: .bold))
                    Text("Log to \(slot.rawValue)").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22).padding(.vertical, 12)
            }
            .buttonStyle(MealAddPressStyle(tint: RingColor.carb.tint))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 22).padding(.bottom, 8)
        .background(
            LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg, Theme.bg],
                           startPoint: .top, endPoint: .bottom)
        )
    }
}

/// Terracotta capsule CTA that springs on press (shared look with FoodDetail).
private struct MealAddPressStyle: ButtonStyle {
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
    MealDetailView(meal: SampleData.customMeals()[0])
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
