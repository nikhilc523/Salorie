import SwiftUI

/// Detail sheet for a single food. Cardless — everything floats on pure black.
/// Instead of a goal ring (which doesn't fit one food), macros are shown as their
/// share of your daily goal: grams + a clean bar + percent.
struct FoodDetailView: View {
    @Environment(MockStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let food: Food
    @State private var slot: MealSlot = .breakfast
    @State private var quantity: Double = 1
    @State private var portions: [FoodPortion] = []
    @State private var measures: [Measure] = []
    @State private var selectedMeasureID: Measure.ID?
    // Screenshot/testing hook: SALORIE_NUTRIENTS=1 pushes the full nutrition screen.
    @State private var showNutrients =
        ProcessInfo.processInfo.environment["SALORIE_NUTRIENTS"] == "1"

    private var selectedMeasure: Measure? { measures.first { $0.id == selectedMeasureID } }

    /// The multiplier applied to the food's per-serving snapshot. For weight-based
    /// measures it's `grams eaten / grams per serving`; for a plain serving it's the
    /// quantity. This is what gets logged and what scales the displayed nutrients.
    private var servings: Double {
        selectedMeasure?.servings(quantity: quantity, servingGrams: food.servingGrams) ?? quantity
    }

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
                    slotPicker             // which meal — the thing people care about, up top
                    amountControl          // how much…
                    macroBreakdown         // …then nutrition updates live below
                    details
                    if !food.ingredients.isEmpty { ingredients }
                }
                .padding(Metrics.pagePadding)
                .padding(.bottom, 90)
            }
            .background(Theme.bg)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .task {
                portions = await store.portions(for: food)
                measures = buildMeasures()
                if selectedMeasureID == nil { selectedMeasureID = measures.first?.id }
            }
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
            .navigationDestination(isPresented: $showNutrients) {
                NutrientDetailView(food: food, servings: servings)
            }
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
            moreNutrientsLink
        }
    }

    /// A single quiet row that pushes the full Nutrition Facts screen. Only shown
    /// when the food actually carries data beyond the core grid.
    @ViewBuilder private var moreNutrientsLink: some View {
        if food.extended.hasAny {
            VStack(spacing: 0) {
                Rectangle().fill(Theme.divider).frame(height: 1)
                Button {
                    HapticManager.shared.trigger(.light)
                    showNutrients = true
                } label: {
                    HStack(spacing: 8) {
                        Text("More nutrients")
                            .font(.system(size: 15, weight: .semibold))
                        if food.extended.caffeine != nil {
                            Text("· incl. caffeine")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .foregroundStyle(RingColor.carb.tint)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Core two-column numbers grid (Apple Health layout).
    private var nutritionGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("NUTRITION").overlineStyle()
                .padding(.bottom, 4)
            numbersGrid(nutrientStats)
        }
    }

    /// Two-column grid with hairline row dividers (Apple Health layout).
    private func numbersGrid(_ stats: [NutrientStat]) -> some View {
        let rows = stride(from: 0, to: stats.count, by: 2).map { i in
            Array(stats[i..<min(i + 2, stats.count)])
        }
        return VStack(alignment: .leading, spacing: 0) {
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

    // MARK: Amount (measure picker + quantity — supports grams / oz / portions)

    private var amountControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AMOUNT").overlineStyle()

            // Type the quantity, pick the measure from a dropdown — no steppers.
            HStack(spacing: 12) {
                quantityField
                measureMenu
                Spacer(minLength: 8)
                if !gramsText.isEmpty {
                    Text(gramsText)
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.top, 2)
        }
    }

    /// Editable quantity — tap to type an exact amount. No +/- adjustment. Small white
    /// pill (the old selected-chip look) so the number reads as the key value.
    private var quantityField: some View {
        TextField("", value: $quantity, format: .number.precision(.fractionLength(0...2)))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color(hex: 0x000000))
            .frame(width: 76, height: 40)
            .background(Theme.textPrimary, in: Capsule())
    }

    /// Measure dropdown — Serving · household portions · 100 g · Grams · Ounces.
    /// A warm terracotta pill; switching animates and converts the quantity.
    private var measureMenu: some View {
        Menu {
            ForEach(measures) { m in
                Button {
                    HapticManager.shared.trigger(.selection)
                    withAnimation(.snappy) { select(m) }
                } label: {
                    if m.id == selectedMeasureID {
                        Label(m.label, systemImage: "checkmark")
                    } else {
                        Text(m.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedMeasure?.label ?? "Serving")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(RingColor.carb.tint)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(RingColor.carb.tint.opacity(0.14), in: Capsule())
        }
    }

    /// Available measures for this food. Weight options (100 g / Grams / Ounces)
    /// only appear when we know the serving's gram weight.
    private func buildMeasures() -> [Measure] {
        guard let sg = food.servingGrams, sg > 0 else {
            return [Measure(label: "Serving", gramsPerUnit: 1, kind: .serving, step: 0.5)]
        }
        var out: [Measure] = [Measure(label: "Serving", gramsPerUnit: sg, kind: .serving, step: 0.5)]
        for p in portions where p.grams > 0 {
            out.append(Measure(label: p.label, gramsPerUnit: p.grams, kind: .household, step: 0.5))
        }
        out.append(Measure(label: "100 g", gramsPerUnit: 100, kind: .hundred, step: 0.5))
        out.append(Measure(label: "Grams", gramsPerUnit: 1, kind: .grams, step: 10))
        out.append(Measure(label: "Ounces", gramsPerUnit: 28.3495, kind: .ounces, step: 1))
        return out
    }

    /// Switch measure while preserving the grams eaten (acts like a unit converter).
    private func select(_ m: Measure) {
        guard m.id != selectedMeasureID else { return }
        if let sg = food.servingGrams, sg > 0, let cur = selectedMeasure {
            let grams = quantity * cur.gramsPerUnit
            let q = grams / m.gramsPerUnit
            quantity = m.kind == .grams ? q.rounded() : (q * 100).rounded() / 100
        }
        selectedMeasureID = m.id
    }

    /// "= 247 g" hint for non-gram measures, so the exact weight is always visible.
    private var gramsText: String {
        guard let m = selectedMeasure, let sg = food.servingGrams, sg > 0, m.kind != .grams else { return "" }
        return "= \(Int((quantity * m.gramsPerUnit).rounded())) g"
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
        VStack(alignment: .leading, spacing: 4) {
            Text("INGREDIENTS").overlineStyle().padding(.bottom, 4)
            ForEach(Array(ingredientList.enumerated()), id: \.offset) { i, item in
                HStack(spacing: 12) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 18)
                    Text(item)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 40)
                if i < ingredientList.count - 1 {
                    Divider().overlay(Theme.divider)
                }
            }
        }
    }

    /// Ingredients as individual rows. Splits a label string on **top-level** commas
    /// only, so a compound ingredient like "Milk chocolate (sugar, cocoa butter)"
    /// stays on one row instead of shattering inside its parentheses.
    private var ingredientList: [String] {
        food.ingredients.flatMap(Self.splitIngredients).filter { !$0.isEmpty }
    }

    nonisolated static func splitIngredients(_ s: String) -> [String] {
        var out: [String] = []
        var depth = 0
        var current = ""
        for ch in s {
            switch ch {
            case "(", "[": depth += 1; current.append(ch)
            case ")", "]": depth = max(0, depth - 1); current.append(ch)
            case "," where depth == 0:
                out.append(current.trimmingCharacters(in: .whitespaces)); current = ""
            default: current.append(ch)
            }
        }
        out.append(current.trimmingCharacters(in: .whitespaces))
        return out.filter { !$0.isEmpty }
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
                    Text("Add \(calories) cal to \(slot.rawValue)")
                        .font(.system(size: 15, weight: .semibold))
                        .contentTransition(.numericText())
                }
                // Clear Liquid Glass (matches the "+" add buttons): neutral frosted
                // material, warm copper content — no color fill.
                .foregroundStyle(RingColor.carb.tint)
                .padding(.horizontal, 26)
                .padding(.vertical, 15)
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.plain)
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

/// A serving measure the user can pick in the food detail (a plain serving, a
/// household portion, 100 g, or a direct weight in g / oz). `gramsPerUnit` is the
/// grams for one unit; `step` is the +/- increment for that measure.
struct Measure: Identifiable, Hashable {
    enum Kind: Hashable { case serving, household, hundred, grams, ounces }
    let id = UUID()
    let label: String
    let gramsPerUnit: Double
    let kind: Kind
    let step: Double

    /// Multiplier on the food's per-serving snapshot for the given quantity.
    /// Weight-aware when the serving's gram weight is known.
    func servings(quantity: Double, servingGrams: Double?) -> Double {
        if let sg = servingGrams, sg > 0 { return quantity * gramsPerUnit / sg }
        return quantity
    }
}

/// One nutrient in the food-detail numbers grid.
struct NutrientStat: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let sub: String?
}

#Preview {
    FoodDetailView(food: SampleData.foods[1])
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
