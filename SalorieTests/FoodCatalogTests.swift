import Testing
@testable import Salorie

/// P0 seam: the async `FoodCatalog` and the store's search/barcode plumbing.
@Suite struct FoodCatalogTests {
    let catalog = SampleFoodCatalog(foods: SampleData.foods)

    @Test func searchFindsByName() async {
        let hits = await catalog.search("avocado")
        #expect(hits.contains { $0.name == "Avocado, Raw" })
    }

    @Test func searchFindsByBrand() async {
        let hits = await catalog.search("fage")   // Greek Yogurt, brand Fage
        #expect(hits.contains { $0.brand == "Fage" })
    }

    @Test func searchEmptyQueryReturnsNothing() async {
        #expect(await catalog.search("").isEmpty)
        #expect(await catalog.search("   ").isEmpty)
    }

    @Test func searchRespectsLimit() async {
        let hits = await catalog.search("a", limit: 2)   // matches many
        #expect(hits.count <= 2)
    }

    @Test func barcodeResolvesDemoItem() async {
        let food = await catalog.food(forBarcode: "SALORIE-DEMO-01")
        #expect(food?.name == "Protein Bar (Demo)")
    }

    @Test func barcodeUnknownReturnsNil() async {
        #expect(await catalog.food(forBarcode: "0000000000") == nil)
        #expect(await catalog.food(forBarcode: "") == nil)
    }
}

@MainActor
@Suite struct StoreSearchTests {
    // Inject the sample catalog so these stay deterministic and don't load the
    // 298 MB bundled DB.
    private func store() -> MockStore {
        MockStore(catalog: SampleFoodCatalog(foods: SampleData.foods))
    }

    @Test func searchMergesCustomMealsFirst() async {
        let hits = await store().search("bowl")   // "Protein Oat Bowl", "Chicken Rice Bowl"
        #expect(hits.first?.isCustomMeal == true)
        #expect(hits.contains { $0.name == "Protein Oat Bowl" })
    }

    @Test func barcodeGoesThroughStore() async {
        let food = await store().food(forBarcode: "SALORIE-DEMO-01")
        #expect(food?.barcode == "SALORIE-DEMO-01")
    }
}
