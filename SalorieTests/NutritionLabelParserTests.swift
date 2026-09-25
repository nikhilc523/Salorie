import Testing
@testable import Salorie

/// P4 label OCR: parsing a Nutrition Facts panel's text into structured values.
@Suite struct NutritionLabelParserTests {
    let label = """
    Nutrition Facts
    Serving Size 1 package (272g)
    Amount Per Serving
    Calories 300
    Total Fat 7g
    Saturated Fat 2g
    Trans Fat 0g
    Cholesterol 30mg
    Sodium 830mg
    Total Carbohydrate 41g
    Dietary Fiber 3g
    Total Sugars 5g
    Protein 16g
    """

    @Test func parsesAStandardLabel() {
        let p = NutritionLabelParser.parse(label)
        #expect(p.calories == 300)
        #expect(p.fat == 7)
        #expect(p.satfat == 2)
        #expect(p.cholesterol == 30)
        #expect(p.sodium == 830)
        #expect(p.carbs == 41)
        #expect(p.fibre == 3)
        #expect(p.sugars == 5)
        #expect(p.protein == 16)
        #expect(p.servingGrams == 272)
        #expect(p.servingText?.contains("1 package") == true)
    }

    @Test func handlesCommasAndDecimals() {
        let p = NutritionLabelParser.parse("Calories 1,100\nSodium 1,000mg\nTotal Fat 12.5g")
        #expect(p.calories == 1100)
        #expect(p.sodium == 1000)
        #expect(p.fat == 12.5)
    }

    @Test func prefersTotalSugarsOverAddedSugars() {
        let p = NutritionLabelParser.parse("Total Sugars 12g\nIncludes 8g Added Sugars")
        #expect(p.sugars == 12)
    }

    @Test func emptyTextYieldsNothing() {
        #expect(NutritionLabelParser.parse("hello world") == ParsedLabel())
    }
}
