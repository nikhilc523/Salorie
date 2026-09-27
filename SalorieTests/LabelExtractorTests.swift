import Testing
@testable import Salorie

/// Phase 2: the producer swap. These are the fallback-contract regression guards —
/// when the on-device model is unavailable (always true on the test simulator), the
/// extractor must reproduce today's regex behaviour EXACTLY.
@Suite struct LabelExtractorTests {
    let labelLines = [
        "Nutrition Facts",
        "Serving Size 1 package (272g)",
        "Amount Per Serving",
        "Calories 300",
        "Total Fat 7g",
        "Saturated Fat 2g",
        "Cholesterol 30mg",
        "Sodium 830mg",
        "Total Carbohydrate 41g",
        "Dietary Fiber 3g",
        "Total Sugars 5g",
        "Protein 16g",
    ]

    @Test func extractEqualsRegexWhenAIUnavailable() async {
        // On the simulator LabelAI.isAvailable == false, so the extractor is a
        // pass-through to NutritionLabelParser.parse — value-for-value identical.
        let out = await LabelExtractor.extract(ocrLines: labelLines)
        #expect(out == NutritionLabelParser.parse(labelLines))
    }

    @Test func scanUnavailableCarriesNoAIMetadata() async {
        let scan = await LabelExtractor.scan(ocrLines: labelLines)
        #expect(scan.usedAI == false)
        #expect(scan.aiFilled.isEmpty)
        #expect(scan.label == NutritionLabelParser.parse(labelLines))
    }

    @Test func mergeAIWinsRegexBackfillsNils() {
        let regex = ParsedLabel(calories: 100, carbs: 10, protein: 5)
        let ai = ParsedLabel(servingText: "1 cup", calories: 120, carbs: nil, protein: 6, fat: 3)
        let (merged, filled) = LabelExtractor.merge(ai: ai, regex: regex)
        #expect(merged.calories == 120)      // AI wins
        #expect(merged.carbs == 10)          // AI nil → regex backfills
        #expect(merged.protein == 6)         // AI wins
        #expect(merged.fat == 3)             // AI-only field
        #expect(merged.servingText == "1 cup")
        #expect(filled.contains(.calories))
        #expect(filled.contains(.fat))
        #expect(filled.contains(.servingText))
        #expect(!filled.contains(.carbs))    // came from regex, not AI
    }

    @Test func isNutritionPanelNeedsCaloriesAndTwoMacros() {
        #expect(LabelExtractor.isNutritionPanel(NutritionLabelParser.parse(labelLines)))
        #expect(!LabelExtractor.isNutritionPanel(ParsedLabel(calories: 100)))         // no macros
        #expect(!LabelExtractor.isNutritionPanel(ParsedLabel(carbs: 10, protein: 5))) // no calories
    }

    @Test func heuristicIdentityPicksNameAndBrand() {
        let scan = LabelExtractor.heuristicIdentity(ocrLines: [
            "OATLY", "Organic Oat Drink Barista Edition", "1 L", "Shake well",
        ])
        #expect(scan.foodName == "Organic Oat Drink Barista Edition")  // longest non-numeric line
        #expect(scan.brand == "OATLY")                                 // short ALL-CAPS line
        #expect(scan.label.calories == nil)                            // never nutrition in Case B
    }
}
