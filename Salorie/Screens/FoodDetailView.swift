import SwiftUI

/// Detail sheet for a single food. Cardless — everything floats on pure black.
/// Instead of a goal ring (which doesn't fit one food), macros are shown as their
/// share of your daily goal: grams + a clean bar + percent.
struct FoodDetailView: View {
    @Environment(MockStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let food: Food
    @State private var slot: MealSlot = .breakfast
    @State private var measureMenuOpen = false
    @State private var scrollToTopTick = 0          // bump to scroll the page back to the hero calories
    @FocusState private var amountFocused: Bool
    @State private var quantity: Double = 1
    @State private var quantityText: String = "1"   // string-backed so the caret never jumps
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
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    macroBreakdown         // calories is the hero, right below
                    details
                    if !food.ingredients.isEmpty { ingredients }
                }
                .padding(Metrics.pagePadding)
                .padding(.bottom, 90)
                .id("top")
            }
            .background(Theme.bg)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            // Any amount input snaps back to the hero calories at the top, so the live
            // total is always in view while the user tweaks the quantity.
            .onChange(of: scrollToTopTick) { _, _ in
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("top", anchor: .top) }
            }
            .task {
                portions = await store.portions(for: food)
                measures = buildMeasures()
                if selectedMeasureID == nil { selectedMeasureID = measures.first?.id }
                if ProcessInfo.processInfo.environment["SALORIE_MEASUREMENU"] == "1" { measureMenuOpen = true }
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
            .glassMenu(isOpen: $measureMenuOpen,
                       items: measureItems,
                       selectedID: selectedMeasureID?.uuidString ?? "",
                       accent: RingColor.carb.tint,
                       width: 180) { id in
                if let m = measures.first(where: { $0.id.uuidString == id }) {
                    withAnimation(.snappy) { select(m) }
                }
            }
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
            // Source lives in the Details section below — only surface OPEN / tags here.
            if food.isOpen || !food.tags.isEmpty {
                HStack(spacing: 6) {
                    if food.isOpen { GhostBadge("OPEN") }
                    ForEach(food.tags) { TagPill($0) }
                }
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

    // MARK: Bottom controls — meal picker + serving, in one glass bar

    /// Left control: a circular button showing the current meal's glyph. Tapping it
    /// cycles breakfast → lunch → dinner → snacks — the icon symbol-swaps and the glass
    /// tint morphs to that meal's colour.
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
        .buttonStyle(BouncyPress())
        .accessibilityLabel("Meal: \(slot.rawValue). Tap to change.")
    }

    /// Centre control: `−  number  +` on the left with the unit pushed to the right.
    /// The `−` / `+` step by the measure's natural increment and hide while the number
    /// is being typed (keyboard up) — tapping the checkmark brings them back.
    private var amountCapsule: some View {
        HStack(spacing: 6) {
            if amountFocused {
                Spacer(minLength: 0)                 // centre the enlarged number while typing
            } else {
                stepButton("minus", enabled: canDecrement) { step(-1) }
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
            quantityField                           // tap the number to type in place
            if amountFocused {
                Spacer(minLength: 0)
            } else {
                stepButton("plus", enabled: true) { step(1) }
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                Spacer(minLength: 8)
            }
            DropdownTrigger(isOpen: $measureMenuOpen) {
                HStack(spacing: 5) {
                    Text(amountValue.unit)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(RingColor.carb.tint)
                        .rotationEffect(.degrees(measureMenuOpen ? 180 : 0))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentShape(Rectangle())
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: amountFocused)
        .padding(.horizontal, 12)
        .frame(height: 54)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.interactive(), in: Capsule())
        .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))
    }

    /// A compact terracotta `−`/`+` nudge. Small glyph, but a generous 40pt hit area so
    /// taps always register. Steps by the measure increment and snaps the page to the
    /// hero calories so the live total is visible.
    private func stepButton(_ system: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.trigger(.light)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { action() }
            scrollToTopTick &+= 1
        } label: {
            Image(systemName: system)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(enabled ? RingColor.carb.tint : Theme.textTertiary.opacity(0.4))
                .frame(width: 40, height: 40)                       // big, reliable tap target — no fill
                .symbolEffect(.bounce, value: quantity)
                .contentShape(Circle())
        }
        .buttonStyle(BouncyPress())
        .disabled(!enabled)
    }

    /// The quantity, edited in place. Reads as a plain bold number with a quiet
    /// terracotta underline that thickens and lights up on focus — so it's clearly
    /// tappable to type a custom value, without a boxy chip crowding the bar.
    private var quantityField: some View {
        TextField("0", text: $quantityText)
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
            // String-backed: typing never triggers a value→format re-render, so the caret
            // stays put at the end instead of jumping to the left.
            .onChange(of: quantityText) { _, t in
                if let v = Double(t) { quantity = v } else if t.isEmpty { quantity = 0 }
            }
            .onChange(of: quantity) { _, v in
                if Double(quantityText) != v { quantityText = formatQuantity(v) }
            }
            .onChange(of: amountFocused) { _, focused in
                if focused { scrollToTopTick &+= 1 }          // show live calories while typing
                if !focused {
                    if quantity <= 0 { quantity = selectedMeasure?.step ?? 1 }
                    quantityText = formatQuantity(quantity)   // normalise (e.g. "1." → "1")
                }
            }
    }

    /// Compact numeric string: whole numbers show no decimals, else up to two.
    private func formatQuantity(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String((v * 100).rounded() / 100)
    }

    /// Right control: the solid terracotta button. While the amount field is being
    /// edited it shows a checkmark (Done) in the *same spot* — tapping it commits the
    /// number and dismisses the keyboard; it then morphs back to `+`, which logs the
    /// food to the selected meal. Keeping one button avoids any Done/＋ misalignment.
    private var addCircleButton: some View {
        Button {
            if amountFocused {
                HapticManager.shared.trigger(.light)
                amountFocused = false                 // commit the typed amount
            } else {
                HapticManager.shared.trigger(.success)
                store.addEntry(food, slot: slot, servings: servings)
                dismiss()
            }
        } label: {
            Image(systemName: amountFocused ? "checkmark" : "plus")
                .font(.system(size: amountFocused ? 21 : 23, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 54, height: 54)
                .background(
                    LinearGradient(colors: [RingColor.carb.tint, RingColor.carb.tint.opacity(0.82)],
                                   startPoint: .top, endPoint: .bottom),
                    in: Circle()
                )
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: RingColor.carb.tint.opacity(0.5), radius: 12, y: 5)
        }
        .buttonStyle(BouncyPress())
        .accessibilityLabel(amountFocused ? "Done editing amount"
                                          : "Add \(calories) calories to \(slot.rawValue)")
    }

    /// Whether the quantity can still be decremented (kept at ≥ one step).
    private var canDecrement: Bool {
        quantity > (selectedMeasure?.step ?? 1) + 0.0001
    }

    /// Step the quantity by the measure's increment, clamped to a single-unit minimum.
    private func step(_ dir: Double) {
        let s = selectedMeasure?.step ?? 1
        quantity = max(s, ((quantity + dir * s) * 100).rounded() / 100)
    }

    /// The unit shown beside the editable quantity — grams/oz for weight, or the count
    /// noun for servings and household portions. (The number itself is `quantityField`.)
    private var amountValue: (num: String, unit: String) {
        func f(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.2g", v) }
        guard let m = selectedMeasure else { return (f(quantity), "serving") }
        switch m.kind {
        case .grams:     return (f(quantity), "g")
        case .ounces:    return (f(quantity), "oz")
        case .hundred:   return (f(quantity), "× 100 g")
        case .serving:   return (f(quantity), quantity == 1 ? "serving" : "servings")
        case .household: return (f(quantity), m.label.lowercased())
        }
    }

    /// The measure options as glass-dropdown items (Serving · portions · 100 g · …).
    private var measureItems: [GlassMenuItem] {
        measures.map { GlassMenuItem(id: $0.id.uuidString, title: $0.label) }
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
        VStack(alignment: .leading, spacing: 10) {
            Text("INGREDIENTS").overlineStyle()
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(ingredientList.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("•")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textTertiary)
                        Text(item)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    /// Ingredients as individual rows. Splits a label string on **top-level** commas
    /// only, so a compound ingredient like "Milk chocolate (sugar, cocoa butter)"
    /// stays on one row instead of shattering inside its parentheses.
    private var ingredientList: [String] {
        food.ingredients.flatMap(Self.splitIngredients).map(\.titleCasedIfShouting).filter { !$0.isEmpty }
    }

    nonisolated static func splitIngredients(_ s: String) -> [String] {
        var out: [String] = []
        var depth = 0
        var current = ""
        for ch in s {
            switch ch {
            case "(", "[": depth += 1; current.append(ch)
            case ")", "]": depth = max(0, depth - 1); current.append(ch)
            case ",", ";":                        // both are used as label separators
                if depth == 0 {
                    out.append(current.trimmingCharacters(in: .whitespaces)); current = ""
                } else {
                    current.append(ch)
                }
            default: current.append(ch)
            }
        }
        out.append(current.trimmingCharacters(in: .whitespaces))
        return out.filter { !$0.isEmpty }
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

/// Circular/inline control press feel: a quick spring scale-down while held. Used across
/// the food-detail command bar so every tap has the same tactile bounce.
private struct BouncyPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
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
