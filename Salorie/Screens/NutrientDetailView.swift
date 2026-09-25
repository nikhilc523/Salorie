import SwiftUI

/// Full nutrition breakdown — pushed from the food detail sheet's "More nutrients".
/// Clean and meaningful (no wall of bars): quality tiles (Nutri-Score / NOVA) with an
/// info tap, a "Good source of" / "High in" glance, then grouped rows of amount + %DV
/// where notable values are colour-coded. Rows with no data are omitted.
struct NutrientDetailView: View {
    let food: Food
    var servings: Double = 1

    private var ext: ExtendedNutrients { food.extended.scaled(by: servings) }
    private func s(_ v: Double) -> Double { v * servings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if ext.nutriScore != nil || ext.novaGroup != nil { quality }
                if !goodSources.isEmpty || !watchOut.isEmpty { highlights }
                ForEach(sections) { sectionView($0) }
                footnote
            }
            .padding(Metrics.pagePadding)
            .padding(.bottom, 40)
        }
        .background(Theme.bg)
        .scrollContentBackground(.hidden)
        .navigationTitle("Nutrition")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(food.name)
                .font(.screenTitle)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text(servingText)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                SourceBadge(source: food.source)
            }
        }
    }

    private var servingText: String {
        let q = servings.formatted(.number.precision(.fractionLength(0...1)))
        let base = food.servingDescription.isEmpty ? "serving" : food.servingDescription
        let kcal = Int((Double(food.calories) * servings).rounded())
        return "\(q) × \(base) · \(kcal) kcal"
    }

    // MARK: Quality — Nutri-Score / NOVA as tile rows (app's tile language)

    private var quality: some View {
        VStack(spacing: 12) {
            if let ns = ext.nutriScore {
                qualityRow(
                    glyph: ns.uppercased(), color: nutriColor(ns),
                    title: "Nutri-Score \(ns.uppercased())",
                    subtitle: "Overall rating, A (best) to E",
                    info: "A front-of-pack rating from A to E. It balances nutrients to favour — fibre, protein, fruit & veg — against ones to limit: calories, sugar, saturated fat and salt.")
            }
            if let nova = ext.novaGroup {
                qualityRow(
                    glyph: "\(nova)", color: novaColor(nova),
                    title: novaWord(nova),
                    subtitle: "NOVA \(nova) · processing level",
                    info: "How processed a food is, from 1 (unprocessed or minimally processed) to 4 (ultra-processed). Lower is generally better.")
            }
        }
    }

    private func qualityRow(glyph: String, color: TagColor, title: String, subtitle: String, info: String) -> some View {
        HStack(spacing: 13) {
            Text(glyph)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(color.fg)
                .frame(width: 44, height: 44)
                .background(color.bg, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            InfoButton(title: title, message: info)
        }
    }

    private func nutriColor(_ grade: String) -> TagColor {
        switch grade.uppercased() { case "A", "B": .green; case "C": .yellow; case "D": .orange; default: .red }
    }
    private func novaColor(_ n: Int) -> TagColor {
        switch n { case 1: .green; case 2: .yellow; case 3: .orange; default: .red }
    }
    private func novaWord(_ n: Int) -> String {
        switch n { case 1: "Unprocessed"; case 2: "Culinary ingredient"; case 3: "Processed"; default: "Ultra-processed" }
    }

    // MARK: Highlights — good sources & watch-outs (icon-led, no pills)

    /// Beneficial nutrients at ≥20% DV (FDA "good source"), strongest first.
    private var goodSources: [NutrientRow] {
        sections.flatMap(\.rows).filter { $0.kind == .good && ($0.percent ?? 0) >= 20 }
            .sorted { ($0.percent ?? 0) > ($1.percent ?? 0) }
    }
    /// Limit nutrients at ≥20% DV — sodium, saturated fat, added sugars, …
    private var watchOut: [NutrientRow] {
        sections.flatMap(\.rows).filter { $0.kind == .limit && ($0.percent ?? 0) >= 20 }
            .sorted { ($0.percent ?? 0) > ($1.percent ?? 0) }
    }

    private var highlights: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !goodSources.isEmpty {
                summaryLine(icon: "checkmark.seal.fill", color: NutrientDetailView.goodColor,
                            label: "Good source of", rows: goodSources)
            }
            if !watchOut.isEmpty {
                summaryLine(icon: "exclamationmark.triangle.fill", color: NutrientDetailView.watchColor,
                            label: "High in", rows: watchOut)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 15)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
    }

    private func summaryLine(icon: String, color: Color, label: String, rows: [NutrientRow]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                Text(rows.map(\.name).joined(separator: ", "))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    static let goodColor = TagColor.green.fg
    static let watchColor = TagColor.orange.fg

    // MARK: Sections

    private var sections: [NutrientSection] {
        [
            section("Macronutrients", [
                NutrientRow("Total Carbohydrate", s(food.carbs), "g", dv: 275),
                NutrientRow("Dietary Fibre", s(food.fibre), "g", dv: 28, kind: .good),
                NutrientRow("Total Sugars", s(food.sugars), "g", dv: nil),
                NutrientRow("Added Sugars", ext.addedSugars, "g", dv: 50, kind: .limit),
                NutrientRow("Protein", s(food.protein), "g", dv: 50, kind: .good),
                NutrientRow("Total Fat", s(food.fat), "g", dv: 78),
                NutrientRow("Saturated Fat", s(food.saturatedFat), "g", dv: 20, kind: .limit),
                NutrientRow("Trans Fat", ext.transFat, "g", dv: nil, kind: .limit),
                NutrientRow("Monounsaturated Fat", ext.monounsaturatedFat, "g", dv: nil),
                NutrientRow("Polyunsaturated Fat", ext.polyunsaturatedFat, "g", dv: nil),
                NutrientRow("Omega-3", ext.omega3, "g", dv: nil, kind: .good),
                NutrientRow("Cholesterol", s(food.cholesterol), "mg", dv: 300, kind: .limit),
                NutrientRow("Sodium", s(food.sodium), "mg", dv: 2300, kind: .limit),
            ]),
            section("Minerals", [
                NutrientRow("Potassium", ext.potassium, "mg", dv: 4700, kind: .good),
                NutrientRow("Calcium", ext.calcium, "mg", dv: 1300, kind: .good),
                NutrientRow("Iron", ext.iron, "mg", dv: 18, kind: .good),
                NutrientRow("Magnesium", ext.magnesium, "mg", dv: 420, kind: .good),
                NutrientRow("Zinc", ext.zinc, "mg", dv: 11, kind: .good),
            ]),
            section("Vitamins", [
                NutrientRow("Vitamin D", ext.vitaminD, "µg", dv: 20, kind: .good),
                NutrientRow("Vitamin C", ext.vitaminC, "mg", dv: 90, kind: .good),
                NutrientRow("Vitamin A", ext.vitaminA, "µg", dv: 900, kind: .good),
                NutrientRow("Vitamin B12", ext.vitaminB12, "µg", dv: 2.4, kind: .good),
                NutrientRow("Folate", ext.folate, "µg", dv: 400, kind: .good),
            ]),
            section("Other", [
                NutrientRow("Caffeine", ext.caffeine, "mg", dv: nil),
            ]),
        ].filter { !$0.rows.isEmpty }
    }

    private func section(_ title: String, _ rows: [NutrientRow?]) -> NutrientSection {
        NutrientSection(title: title, rows: rows.compactMap { $0 })
    }

    private func sectionView(_ section: NutrientSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            heading(section.title).padding(.bottom, 4)
            ForEach(Array(section.rows.enumerated()), id: \.element.id) { idx, row in
                rowView(row).padding(.vertical, 13)
                if idx < section.rows.count - 1 {
                    Rectangle().fill(Theme.divider).frame(height: 1)
                }
            }
        }
    }

    /// Caramel section heading for clear separation between groups.
    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.overline)
            .textCase(.uppercase)
            .tracking(0.9)
            .foregroundStyle(NutrientDetailView.headingColor)
    }

    static let headingColor = RingColor.protein.tint   // caramel

    // MARK: Row — name · amount · %DV (notable values colour-coded, no bars)

    private func rowView(_ row: NutrientRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(row.name)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 12)
            Text(row.amountText)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(row.percentText)
                .font(.system(size: 13, weight: row.accentColor != nil ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(row.accentColor ?? Theme.textTertiary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var footnote: some View {
        Text("% Daily Value shows how much a nutrient contributes to a daily 2,000-calorie diet. 20% or more counts as a good source (or, for sodium and the like, high) — those are called out above.")
            .font(.system(size: 12))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }
}

// MARK: - Models

/// Whether a nutrient is beneficial (a "good source" when high), one to limit, or
/// neutral — drives the highlight lines and the coloured %DV.
enum NutrientKind { case good, limit, neutral }

/// One line on the full nutrition screen. Fails to init when the amount is `nil`
/// (missing data) so absent nutrients drop out cleanly.
struct NutrientRow: Identifiable {
    let id = UUID()
    let name: String
    let amount: Double
    let unit: String        // "g" | "mg" | "µg"
    let dv: Double?          // Daily Value in the same unit; nil = no established DV
    let kind: NutrientKind

    init?(_ name: String, _ amount: Double?, _ unit: String, dv: Double?, kind: NutrientKind = .neutral) {
        guard let amount else { return nil }
        self.name = name
        self.amount = amount
        self.unit = unit
        self.dv = dv
        self.kind = kind
    }

    var amountText: String {
        let n = amount >= 10
            ? "\(Int(amount.rounded()))"
            : amount.formatted(.number.precision(.fractionLength(0...1)))
        return unit == "g" ? "\(n)g" : "\(n) \(unit)"
    }

    var percent: Double? { dv.map { amount / $0 * 100 } }
    var percentText: String {
        guard let p = percent else { return "" }
        if p >= 1 { return "\(Int(p.rounded()))%" }
        return amount > 0 ? "<1%" : "0%"
    }

    /// Green for a notable good source, amber for a notable limit nutrient, else nil.
    var accentColor: Color? {
        guard (percent ?? 0) >= 20 else { return nil }
        switch kind {
        case .good:  return NutrientDetailView.goodColor
        case .limit: return NutrientDetailView.watchColor
        case .neutral: return nil
        }
    }
}

struct NutrientSection: Identifiable {
    let id = UUID()
    let title: String
    let rows: [NutrientRow]
}

// MARK: - InfoButton

/// A small ⓘ that pops an explanatory note next to a label (Nutri-Score, NOVA, …).
struct InfoButton: View {
    let title: String
    let message: String
    @State private var show = false

    var body: some View {
        Button {
            HapticManager.shared.trigger(.light)
            show = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $show) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(width: 268)
            .presentationCompactAdaptation(.popover)
        }
    }
}

#Preview {
    NavigationStack {
        NutrientDetailView(food: SampleData.foods[9], servings: 1)   // dark chocolate: E / NOVA 4
    }
    .preferredColorScheme(.dark)
}
