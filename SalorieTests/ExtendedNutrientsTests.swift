import Testing
@testable import Salorie

/// Pure serving-math / aggregation logic for the extended nutrient model.
@Suite struct ExtendedNutrientsTests {
    @Test func scaleMultipliesNumericAndKeepsQualitative() {
        let e = ExtendedNutrients(potassium: 100, caffeine: 10, nutriScore: "B", novaGroup: 1)
        let s = e.scaled(by: 2)
        #expect(s.potassium == 200)
        #expect(s.caffeine == 20)
        #expect(s.nutriScore == "B")   // qualitative never scales
        #expect(s.novaGroup == 1)
    }

    @Test func scaleByOneIsIdentity() {
        let e = ExtendedNutrients(potassium: 42, iron: 1.5)
        #expect(e.scaled(by: 1) == e)
    }

    @Test func scaleLeavesMissingValuesNil() {
        let e = ExtendedNutrients(potassium: 100)   // iron is nil
        #expect(e.scaled(by: 3).iron == nil)
    }

    @Test func sumIsNilUnlessAnyContributorHasIt() {
        let a = ExtendedNutrients(potassium: 100)
        let b = ExtendedNutrients(caffeine: 5)
        let total = ExtendedNutrients.sum([a, b])
        #expect(total.potassium == 100)   // b missing → counts as 0
        #expect(total.caffeine == 5)
        #expect(total.iron == nil)         // nobody had it
    }

    @Test func sumAddsPresentValues() {
        let total = ExtendedNutrients.sum([
            ExtendedNutrients(potassium: 100),
            ExtendedNutrients(potassium: 250),
        ])
        #expect(total.potassium == 350)
    }

    @Test func hasAnyReflectsContent() {
        #expect(ExtendedNutrients().hasAny == false)
        #expect(ExtendedNutrients(caffeine: 1).hasAny == true)
        #expect(ExtendedNutrients(nutriScore: "A").hasAny == true)
    }
}
