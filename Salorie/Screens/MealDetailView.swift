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
    @State private var servingsText: String = "1"   // string-backed field (caret never jumps)
    @State private var slot: MealSlot = .breakfast
    @State private var editing = false
    @State private var inspectedComponent: Food?
    @State private var favToast: ToastMessage?
    @State private var favToastToken = 0
    @FocusState private var amountFocused: Bool

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
                VStack(alignment: .leading, spacing: 22) {
                    header
                    macroBreakdown
                    ingredientList
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
                ToolbarItem(placement: .topBarTrailing) { favoriteButton }
                ToolbarItem(placement: .topBarTrailing) { overflowMenu }
            }
            .safeAreaInset(edge: .bottom) { addBar }
            .sheet(isPresented: $editing) { MealBuilderView(editing: current) }
            .sheet(item: $inspectedComponent) { FoodDetailView(food: $0) }
        }
        .salorieToast($favToast)
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

    // MARK: Bottom command bar (mirrors FoodDetailView) — meal cycle · servings · add

    /// Left control: circular button showing the target meal's glyph; tap cycles the slot.
    private var mealCycleButton: some View {
        Button {
            HapticManager.shared.trigger(.selection)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { slot = slot.next }
        } label: {
            Image(systemName: slot.symbol)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(mealSlotColor(slot))
                .contentTransition(.symbolEffect(.replace.downUp))
                .frame(width: 54, height: 54)
                .glassEffect(.regular.tint(mealSlotColor(slot).opacity(0.22)).interactive(), in: Circle())
                .overlay(Circle().stroke(mealSlotColor(slot).opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(MealBouncyPress())
        .accessibilityLabel("Meal: \(slot.rawValue). Tap to change.")
    }

    /// Centre control: `−  servings  +` with the unit pushed right (no measure dropdown —
    /// a whole meal is only ever counted in servings).
    private var amountCapsule: some View {
        HStack(spacing: 6) {
            if amountFocused {
                Spacer(minLength: 0)
            } else {
                stepButton("minus", enabled: servings > 0.5 + 0.0001) { stepServings(-0.5) }
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
            quantityField
            if amountFocused {
                Spacer(minLength: 0)
            } else {
                stepButton("plus", enabled: true) { stepServings(0.5) }
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                Spacer(minLength: 8)
            }
            Text(servings == 1 ? "serving" : "servings")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: amountFocused)
        .padding(.horizontal, 12)
        .frame(height: 54)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: Capsule())
        .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))
    }

    private func stepButton(_ system: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.trigger(.light)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { action() }
        } label: {
            Image(systemName: system)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(enabled ? RingColor.carb.tint : Theme.textTertiary.opacity(0.4))
                .frame(width: 40, height: 40)
                .symbolEffect(.bounce, value: servings)
                .contentShape(Circle())
        }
        .buttonStyle(MealBouncyPress())
        .disabled(!enabled)
    }

    /// The servings count, edited in place — bold number with a quiet terracotta underline.
    private var quantityField: some View {
        TextField("0", text: $servingsText)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(.system(size: amountFocused ? 30 : 18, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .tint(RingColor.carb.tint)
            .focused($amountFocused)
            .fixedSize()
            .padding(.horizontal, 4)
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(RingColor.carb.tint.opacity(amountFocused ? 1 : 0.55))
                    .frame(height: amountFocused ? 2.5 : 2)
                    .offset(y: amountFocused ? 7 : 5)
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.78), value: amountFocused)
            .onChange(of: servingsText) { _, t in
                if let v = Double(t) { servings = v } else if t.isEmpty { servings = 0 }
            }
            .onChange(of: servings) { _, v in
                if Double(servingsText) != v { servingsText = formatQuantity(v) }
            }
            .onChange(of: amountFocused) { _, focused in
                if !focused {
                    if servings <= 0 { servings = 0.5 }
                    servingsText = formatQuantity(servings)
                }
            }
    }

    private func stepServings(_ dir: Double) {
        servings = max(0.5, ((servings + dir) * 100).rounded() / 100)
    }

    private func formatQuantity(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String((v * 100).rounded() / 100)
    }

    /// Right control: solid terracotta button. Editing → checkmark (commits the number);
    /// otherwise `+` logs the whole meal to the selected slot.
    private var addCircleButton: some View {
        Button {
            if amountFocused {
                HapticManager.shared.trigger(.light)
                amountFocused = false
            } else {
                HapticManager.shared.trigger(.success)
                store.addEntry(current, slot: slot, servings: servings)
                dismiss()
            }
        } label: {
            Image(systemName: amountFocused ? "checkmark" : "plus")
                .font(.system(size: amountFocused ? 21 : 23, weight: .bold))
                .foregroundStyle(RingColor.carb.tint)      // terracotta glyph — matches FoodDetailView
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 54, height: 54)
                .glassEffect(.regular.interactive(), in: Circle())   // liquid glass, no fill
                .overlay(Circle().stroke(RingColor.carb.tint.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(MealBouncyPress())
        .accessibilityLabel(amountFocused ? "Done editing amount"
                                          : "Add \(calories) calories to \(slot.rawValue)")
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
        let fav = store.isFavorite(current)
        return Button {
            HapticManager.shared.trigger(.selection)
            let added = withAnimation(.snappy) { store.toggleFavorite(current) }
            favToastToken += 1
            favToast = ToastMessage(text: added ? "Added to Favorites" : "Removed from Favorites",
                                    symbol: added ? "star.fill" : "star.slash.fill",
                                    token: favToastToken)
        } label: {
            Image(systemName: fav ? "star.fill" : "star")
                .foregroundStyle(fav ? RingColor.protein.tint : Theme.textSecondary)
                .contentTransition(.symbolEffect(.replace))
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
        HStack(spacing: 10) {
            mealCycleButton
            amountCapsule
            addCircleButton
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.top, 22)
        .padding(.bottom, 8)
        .background(
            LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg, Theme.bg],
                           startPoint: .top, endPoint: .bottom)
        )
    }
}

/// Quick spring scale-down while held — matches the food-detail command bar feel.
private struct MealBouncyPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

#Preview {
    MealDetailView(meal: SampleData.customMeals()[0])
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
