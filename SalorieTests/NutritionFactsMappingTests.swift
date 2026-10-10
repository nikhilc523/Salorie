import Testing
@testable import Salorie

#if canImport(FoundationModels)
/// Phase 1: the pure `NutritionFacts.toParsedLabel()` mapper. No model is invoked —
/// these exercise only the deterministic unit/basis arithmetic in Swift.
@Suite struct NutritionFactsMappingTests {

    @Test func perServingPassesThroughUnchanged() {
        let facts = NutritionFacts(servingText: "1 package", servingGrams: 272, calories: 300,
                                   carbs: 41, protein: 16, fat: 7, sodium: 830, basis: .perServing)
        let p = facts.toParsedLabel()
        #expect(p.calories == 300)
        #expect(p.carbs == 41)
        #expect(p.protein == 16)
        #expect(p.fat == 7)
        #expect(p.sodium == 830)          // sodium stays in mg (model already normalized)
        #expect(p.servingGrams == 272)
        #expect(p.servingText == "1 package")
    }

    @Test func per100gRescalesByServingWeight() {
        // 200g serving, numbers printed per 100g → ×2.
        let facts = NutritionFacts(servingGrams: 200, calories: 100, carbs: 20, protein: 5,
                                   fat: 2, sodium: 50, cholesterol: 10, basis: .per100g)
        let p = facts.toParsedLabel()
        #expect(p.calories == 200)
        #expect(p.carbs == 40)
        #expect(p.protein == 10)
        #expect(p.fat == 4)
        #expect(p.sodium == 100)          // mg scales with the serving too
        #expect(p.cholesterol == 20)
    }

    @Test func per100gWithoutServingWeightDoesNotRescale() {
        // No serving weight → we can't safely rescale, so pass through untouched.
        let facts = NutritionFacts(servingGrams: nil, calories: 250, carbs: 30, basis: .per100g)
        let p = facts.toParsedLabel()
        #expect(p.calories == 250)
        #expect(p.carbs == 30)
    }

    @Test func nilFieldsStayNil() {
        let facts = NutritionFacts(calories: 120, basis: .perServing)
        let p = facts.toParsedLabel()
        #expect(p.calories == 120)
        #expect(p.carbs == nil)
        #expect(p.protein == nil)
        #expect(p.fat == nil)
        #expect(p.sodium == nil)
        #expect(p.cholesterol == nil)
        #expect(p.servingText == nil)
    }
}
#endif
