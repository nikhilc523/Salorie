import Testing
@testable import Salorie

/// FoodDetailView ingredient rows: split on top-level commas only (don't shatter
/// inside parentheses), so compound ingredients stay on one row.
@Suite struct IngredientSplitTests {
    @Test func splitsTopLevelCommas() {
        let out = FoodDetailView.splitIngredients("Water, Salt, Sugar")
        #expect(out == ["Water", "Salt", "Sugar"])
    }

    @Test func keepsParentheticalGroupsIntact() {
        let s = "Milk chocolate (sugar, cocoa butter, soy lecithin (an emulsifier)), corn syrup, salt"
        let out = FoodDetailView.splitIngredients(s)
        #expect(out.count == 3)
        #expect(out.first == "Milk chocolate (sugar, cocoa butter, soy lecithin (an emulsifier))")
        #expect(out.last == "salt")
    }

    @Test func trimsAndDropsEmpties() {
        #expect(FoodDetailView.splitIngredients("  Oats ,, Honey ,") == ["Oats", "Honey"])
    }

    @Test func singleIngredientPassesThrough() {
        #expect(FoodDetailView.splitIngredients("Avocado") == ["Avocado"])
    }
}

/// De-shouting ALL-CAPS catalog names/brands while respecting intentional casing.
@Suite struct DisplayCasingTests {
    @Test func lowercasesShoutingText() {
        #expect("COOKED SHRIMP RING".titleCasedIfShouting == "Cooked Shrimp Ring")
        #expect("1% LOWFAT MILK".titleCasedIfShouting == "1% Lowfat Milk")
        #expect("DRIFTWOOD".titleCasedIfShouting == "Driftwood")
    }

    @Test func leavesIntentionalCasingUntouched() {
        #expect("Greek Yogurt, Plain".titleCasedIfShouting == "Greek Yogurt, Plain")
        #expect("Fage".titleCasedIfShouting == "Fage")
        #expect("iPhone".titleCasedIfShouting == "iPhone")
    }

    @Test func handlesNonAlphaGracefully() {
        #expect("100%".titleCasedIfShouting == "100%")
        #expect("".titleCasedIfShouting == "")
    }
}
