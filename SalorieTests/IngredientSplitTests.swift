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
