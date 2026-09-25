import SwiftUI

/// Full nutrition breakdown — pushed from the food detail sheet's "More nutrients".
/// Clean, meaningful label (no wall of bars): a "Good source of" summary up top, then
/// grouped rows of amount + %DV where notable values (≥20% DV) are highlighted so the
/// eye lands on what the food actually delivers. Rows with no data are omitted.
struct NutrientDetailView: View {
    let food: Food
    var servings: Double = 1

    private var ext: ExtendedNutrients { food.extended.scaled(by: servings) }
    private func s(_ v: Double) -> Double { v * servings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                if ext.nutriScore != nil || ext.novaGroup != nil { badges }
                if !goodSources.isEmpty { highlights }
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

    // MARK: Highlights — what this food is actually a good source of

    /// Nutrients at ≥20% DV (FDA "good source"), strongest first — the meaningful glance.
    private var goodSources: [NutrientRow] {
        sections.flatMap(\.rows)
            .filter { ($0.percent ?? 0) >= 20 }
            .sorted { ($0.percent ?? 0) > ($1.percent ?? 0) }
    }

    private var highlights: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GOOD SOURCE OF").overlineStyle()
            FlowLayout(spacing: 8) {
                ForEach(goodSources.prefix(8)) { row in
                    HStack(spacing: 6) {
                        Text(row.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(row.percentText)
                            .font(.system(size: 12, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(NutrientDetailView.goodColor)
                    }
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(Capsule().fill(NutrientDetailView.goodColor.opacity(0.14)))
                }
            }
        }
    }

    /// Warm-friendly "good" green from the palette — one accent, no rainbow.
    static let goodColor = TagColor.green.fg

    // MARK: Quality badges (Open Food Facts)

    private var badges: some View {
        HStack(spacing: 8) {
            if let ns = ext.nutriScore { nutriScorePill(ns) }
            if let nova = ext.novaGroup { novaPill(nova) }
            Spacer(minLength: 0)
        }
    }

    private func nutriScorePill(_ s: String) -> some View {
        let color: TagColor = switch s.uppercased() {
            case "A", "B": .green
            case "C":      .yellow
            case "D":      .orange
            default:       .red
        }
        return HStack(spacing: 7) {
            Text("Nutri-Score")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text(s.uppercased())
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(color.fg)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(color.bg))
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))
    }

    private func novaPill(_ n: Int) -> some View {
        let (color, word): (TagColor, String) = switch n {
            case 1:  (.green, "Unprocessed")
            case 2:  (.yellow, "Culinary")
            case 3:  (.orange, "Processed")
            default: (.red, "Ultra-processed")
        }
        return HStack(spacing: 6) {
            Text("NOVA \(n)")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(color.fg)
            Text(word)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))
    }

    // MARK: Sections

    private var sections: [NutrientSection] {
        [
            section("Macronutrients", [
                NutrientRow("Total Carbohydrate", s(food.carbs), "g", dv: 275),
                NutrientRow("Dietary Fibre", s(food.fibre), "g", dv: 28),
                NutrientRow("Total Sugars", s(food.sugars), "g", dv: nil),
                NutrientRow("Added Sugars", ext.addedSugars, "g", dv: 50),
                NutrientRow("Protein", s(food.protein), "g", dv: 50),
                NutrientRow("Total Fat", s(food.fat), "g", dv: 78),
                NutrientRow("Saturated Fat", s(food.saturatedFat), "g", dv: 20),
                NutrientRow("Trans Fat", ext.transFat, "g", dv: nil),
                NutrientRow("Monounsaturated Fat", ext.monounsaturatedFat, "g", dv: nil),
                NutrientRow("Polyunsaturated Fat", ext.polyunsaturatedFat, "g", dv: nil),
                NutrientRow("Omega-3", ext.omega3, "g", dv: nil),
                NutrientRow("Cholesterol", s(food.cholesterol), "mg", dv: 300),
                NutrientRow("Sodium", s(food.sodium), "mg", dv: 2300),
            ]),
            section("Minerals", [
                NutrientRow("Potassium", ext.potassium, "mg", dv: 4700),
                NutrientRow("Calcium", ext.calcium, "mg", dv: 1300),
                NutrientRow("Iron", ext.iron, "mg", dv: 18),
                NutrientRow("Magnesium", ext.magnesium, "mg", dv: 420),
                NutrientRow("Zinc", ext.zinc, "mg", dv: 11),
            ]),
            section("Vitamins", [
                NutrientRow("Vitamin D", ext.vitaminD, "µg", dv: 20),
                NutrientRow("Vitamin C", ext.vitaminC, "mg", dv: 90),
                NutrientRow("Vitamin A", ext.vitaminA, "µg", dv: 900),
                NutrientRow("Vitamin B12", ext.vitaminB12, "µg", dv: 2.4),
                NutrientRow("Folate", ext.folate, "µg", dv: 400),
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
            Text(section.title).overlineStyle().padding(.bottom, 4)
            ForEach(Array(section.rows.enumerated()), id: \.element.id) { idx, row in
                rowView(row).padding(.vertical, 13)
                if idx < section.rows.count - 1 {
                    Rectangle().fill(Theme.divider).frame(height: 1)
                }
            }
        }
    }

    // MARK: Row — name · amount · %DV (notable values highlighted, no bars)

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
                .font(.system(size: 13, weight: row.isNotable ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(row.isNotable ? NutrientDetailView.goodColor : Theme.textTertiary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var footnote: some View {
        Text("% Daily Value shows how much a nutrient contributes to a daily 2,000-calorie diet. 20% DV or more is considered a good source — those are highlighted above.")
            .font(.system(size: 12))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }
}

// MARK: - Models

/// One line on the full nutrition screen. Fails to init when the amount is `nil`
/// (missing data) so absent nutrients drop out cleanly.
struct NutrientRow: Identifiable {
    let id = UUID()
    let name: String
    let amount: Double
    let unit: String        // "g" | "mg" | "µg"
    let dv: Double?          // Daily Value in the same unit; nil = no established DV

    init?(_ name: String, _ amount: Double?, _ unit: String, dv: Double?) {
        guard let amount else { return nil }
        self.name = name
        self.amount = amount
        self.unit = unit
        self.dv = dv
    }

    var amountText: String {
        let n = amount >= 10
            ? "\(Int(amount.rounded()))"
            : amount.formatted(.number.precision(.fractionLength(0...1)))
        return unit == "g" ? "\(n)g" : "\(n) \(unit)"
    }

    var percent: Double? { dv.map { amount / $0 * 100 } }
    /// A "good source" — FDA threshold; drives the highlight + coloured %DV.
    var isNotable: Bool { (percent ?? 0) >= 20 }
    var percentText: String {
        guard let p = percent else { return "" }
        if p >= 1 { return "\(Int(p.rounded()))%" }
        return amount > 0 ? "<1%" : "0%"
    }
}

struct NutrientSection: Identifiable {
    let id = UUID()
    let title: String
    let rows: [NutrientRow]
}

// MARK: - FlowLayout

/// Left-to-right wrapping layout for chips/pills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowMaxX: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowMaxX = max(rowMaxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : rowMaxX, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    NavigationStack {
        NutrientDetailView(food: SampleData.foods[1], servings: 1)
    }
    .preferredColorScheme(.dark)
}
