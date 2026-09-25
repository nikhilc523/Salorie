import Testing
@testable import Salorie

/// Weight-based logging math: quantity × measure → servings multiplier on the
/// food's per-serving snapshot. Example: a 112 g serving of Costco chicken breast.
@Suite struct MeasureTests {
    let servingGrams = 112.0

    @Test func plainServingIsQuantity() {
        let m = Measure(label: "Serving", gramsPerUnit: servingGrams, kind: .serving, step: 0.5)
        #expect(m.servings(quantity: 1, servingGrams: servingGrams) == 1)
        #expect(m.servings(quantity: 2, servingGrams: servingGrams) == 2)
    }

    @Test func gramsScaleRelativeToServing() {
        let g = Measure(label: "Grams", gramsPerUnit: 1, kind: .grams, step: 10)
        // ate 247 g of a 112 g-serving breast → 247/112 servings
        #expect(g.servings(quantity: 247, servingGrams: servingGrams) == 247.0 / 112.0)
        // → nutrients scale by that; e.g. 106 kcal/100g × 247g = ~262 kcal
        let per100Kcal = 106.0
        let snapshotKcal = per100Kcal * servingGrams / 100      // one serving's kcal
        let logged = snapshotKcal * g.servings(quantity: 247, servingGrams: servingGrams)
        #expect(Int(logged.rounded()) == 262)
    }

    @Test func ouncesConvertToGrams() {
        let oz = Measure(label: "Ounces", gramsPerUnit: 28.3495, kind: .ounces, step: 1)
        // 4 oz = 113.4 g ≈ ~1.012 servings of a 112 g serving
        let s = oz.servings(quantity: 4, servingGrams: servingGrams)
        #expect(abs(s - (4 * 28.3495 / 112)) < 0.0001)
    }

    @Test func hundredGramsIsOnePerHundred() {
        let h = Measure(label: "100 g", gramsPerUnit: 100, kind: .hundred, step: 0.5)
        // quantity 1 of "100 g" against a 112 g serving → 100/112 servings
        #expect(h.servings(quantity: 1, servingGrams: servingGrams) == 100.0 / 112.0)
    }

    @Test func noServingGramsFallsBackToQuantity() {
        let g = Measure(label: "Grams", gramsPerUnit: 1, kind: .grams, step: 10)
        #expect(g.servings(quantity: 3, servingGrams: nil) == 3)   // sample/custom foods
    }
}
