import SwiftUI

/// Create or edit a custom meal: name it, pick an icon/tint, add ingredients from
/// the full catalog, tune each ingredient's servings, and watch the running macro
/// total update live. Saving stores it in `MockStore.customMeals`.
struct MealBuilderView: View {
    @Environment(MockStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Non-nil when editing an existing meal (preserves its id / favorite state).
    private let editingMeal: Food?

    @State private var name: String
    @State private var symbol: String
    @State private var tint: TagColor
    @State private var components: [MealComponent]
    @State private var pickingIngredient = false

    private static let symbolChoices = [
        "takeoutbag.and.cup.and.straw.fill", "fork.knife", "cup.and.saucer.fill",
        "carrot.fill", "birthday.cake.fill", "leaf.fill", "mug.fill"
    ]

    init(editing meal: Food? = nil) {
        self.editingMeal = meal
        _name = State(initialValue: meal?.name ?? "")
        _symbol = State(initialValue: meal?.symbol ?? "takeoutbag.and.cup.and.straw.fill")
        _tint = State(initialValue: meal?.tint ?? .green)
        _components = State(initialValue: meal?.components ?? [])
    }

    // Live totals from the current component set.
    private var totalCalories: Int { Int(components.reduce(0.0) { $0 + $1.calories }.rounded()) }
    private var totalCarbs: Double { components.reduce(0) { $0 + $1.carbs } }
    private var totalProtein: Double { components.reduce(0) { $0 + $1.protein } }
    private var totalFibre: Double { components.reduce(0) { $0 + $1.fibre } }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !components.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    identityCard
                    liveTotals
                    ingredientsSection
                }
                .padding(Metrics.pagePadding)
                .padding(.bottom, 96)
            }
            .background(Theme.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle(editingMeal == nil ? "New Meal" : "Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { HapticManager.shared.trigger(.light); dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { saveBar }
            .sheet(isPresented: $pickingIngredient) {
                IngredientPickerView { food in
                    withAnimation(.snappy) {
                        components.append(MealComponent(food: food, servings: 1))
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Identity — icon tile, name, appearance

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(tint.fg)
                    .frame(width: 58, height: 58)
                    .background(tint.bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                TextField("", text: $name, prompt: Text("Meal name")
                    .foregroundColor(Theme.textTertiary))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }

            Text("ICON").overlineStyle()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Self.symbolChoices, id: \.self) { s in
                        Button {
                            HapticManager.shared.trigger(.selection)
                            withAnimation(.snappy) { symbol = s }
                        } label: {
                            Image(systemName: s)
                                .font(.system(size: 16))
                                .foregroundStyle(symbol == s ? tint.fg : Theme.textSecondary)
                                .frame(width: 40, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(symbol == s ? tint.bg : Theme.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .stroke(Theme.cardStroke, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }

            Text("COLOR").overlineStyle()
            HStack(spacing: 12) {
                ForEach(TagColor.allCases, id: \.self) { c in
                    Button {
                        HapticManager.shared.trigger(.selection)
                        withAnimation(.snappy) { tint = c }
                    } label: {
                        Circle()
                            .fill(c.fg)
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle().stroke(Theme.textPrimary,
                                                lineWidth: tint == c ? 2 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Live totals

    private var liveTotals: some View {
        HStack(spacing: 12) {
            totalCell("CALORIES", "\(totalCalories)", RingColor.calories.tint)
            totalCell("CARBS", "\(Int(totalCarbs.rounded()))g", RingColor.carb.tint)
            totalCell("PROTEIN", "\(Int(totalProtein.rounded()))g", RingColor.protein.tint)
            totalCell("FIBRE", "\(Int(totalFibre.rounded()))g", RingColor.fibre.tint)
        }
    }

    private func totalCell(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 10, weight: .bold)).tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color).monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12).padding(.horizontal, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
    }

    // MARK: Ingredients

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("INGREDIENTS").overlineStyle()
                Spacer()
                Text("\(components.count)")
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.bottom, 8)

            if components.isEmpty {
                Text("No ingredients yet — add foods to build your meal.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
            } else {
                ForEach($components) { $component in
                    ingredientRow($component)
                    if component.id != components.last?.id {
                        Rectangle().fill(Theme.divider).frame(height: 1)
                    }
                }
            }

            addIngredientButton.padding(.top, 14)
        }
    }

    private func ingredientRow(_ component: Binding<MealComponent>) -> some View {
        let c = component.wrappedValue
        return HStack(spacing: 12) {
            Image(systemName: c.food.symbol)
                .font(.system(size: 15)).foregroundStyle(c.food.tint.fg).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.food.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text("\(Int(c.calories.rounded())) cal · \(c.food.servingDescription)")
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 6)
            HStack(spacing: 10) {
                miniStep("minus") {
                    component.wrappedValue.servings = max(0.5, c.servings - 0.5)
                }
                Text(c.servings.formatted(.number.precision(.fractionLength(0...1))))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit().frame(minWidth: 26)
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                miniStep("plus") { component.wrappedValue.servings = c.servings + 0.5 }
            }
        }
        .padding(.vertical, 10)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { remove(c) } label: { Label("Remove", systemImage: "trash") }
        }
        .contextMenu {
            Button(role: .destructive) { remove(c) } label: { Label("Remove", systemImage: "trash") }
        }
    }

    private func remove(_ c: MealComponent) {
        HapticManager.shared.trigger(.light)
        withAnimation(.snappy) { components.removeAll { $0.id == c.id } }
    }

    private func miniStep(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.trigger(.light)
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(RingColor.carb.tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(RingColor.carb.tint.opacity(0.16)))
        }
        .buttonStyle(.plain)
    }

    private var addIngredientButton: some View {
        Button {
            HapticManager.shared.trigger(.light)
            pickingIngredient = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").font(.system(size: 16, weight: .semibold))
                Text("Add ingredient").font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Save

    private var saveBar: some View {
        Button {
            HapticManager.shared.trigger(.success)
            save()
            dismiss()
        } label: {
            Text(editingMeal == nil ? "Save Meal" : "Save Changes")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    Capsule().fill(canSave ? Theme.accent : Theme.surfaceRaised)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.top, 20).padding(.bottom, 8)
        .background(
            LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg, Theme.bg],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if var meal = editingMeal {
            meal.name = trimmed
            meal.symbol = symbol
            meal.tint = tint
            meal.components = components
            meal.recomputeFromComponents()
            store.saveMeal(meal)
        } else {
            store.saveMeal(Food.customMeal(name: trimmed, symbol: symbol, tint: tint, components: components))
        }
    }
}

#Preview("New") {
    MealBuilderView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}

#Preview("Edit") {
    MealBuilderView(editing: SampleData.customMeals()[0])
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
