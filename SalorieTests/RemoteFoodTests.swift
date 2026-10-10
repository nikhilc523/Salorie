import Testing
import Foundation
@testable import Salorie

/// P4: live OFF/USDA fallback parsing + caching + store fallback chain.
@Suite struct RemoteFoodParseTests {
    // Real OFF payload shape for 025000121142 (Minute Maid Zero Sugar Lemonade).
    let offJSON = """
    {"status":1,"product":{"code":"0025000121142","product_name":"Zero Sugar Lemonade",
    "brands":"Minute Maid","nutriscore_grade":"c","nova_group":4,"serving_quantity":355,
    "serving_size":"355ml","nutriments":{"energy-kcal_100g":1.40845070422535,
    "carbohydrates_100g":0.563,"proteins_100g":0,"fat_100g":0,"fiber_100g":0,"sugars_100g":0,
    "saturated-fat_100g":0,"sodium_100g":0.1408,"salt_100g":0.352}}}
    """

    @Test func parsesOFFPayloadToFood() {
        let f = RemoteFoodService.parseOFF(Data(offJSON.utf8), requestedBarcode: "0025000121142")
        #expect(f?.name == "Zero Sugar Lemonade")
        #expect(f?.brand == "Minute Maid")
        #expect(f?.source == .openFoodFacts)
        #expect(f?.barcode == "00025000121142")        // normalized to GTIN-14
        #expect(f?.servingGrams == 355)
        #expect(f?.calories == 5)                        // 1.408 kcal/100g × 355 g
        #expect(f?.extended.nutriScore == "C")
        #expect(f?.extended.novaGroup == 4)
    }

    @Test func offMissReturnsNil() {
        let notFound = #"{"status":0,"status_verbose":"product not found"}"#
        #expect(RemoteFoodService.parseOFF(Data(notFound.utf8), requestedBarcode: "000") == nil)
    }

    // USDA branded search shape.
    let usdaJSON = """
    {"foods":[{"description":"CHICKEN BREAST","brandName":"KIRKLAND","gtinUpc":"00233841823921",
    "servingSize":112,"servingSizeUnit":"g","householdServingFullText":"4 oz",
    "foodNutrients":[{"nutrientId":1008,"value":107},{"nutrientId":1003,"value":22}]}]}
    """

    @Test func parsesUSDAPayloadMatchingGTIN() {
        let f = RemoteFoodService.parseUSDA(Data(usdaJSON.utf8), requestedBarcode: "233841823921")
        #expect(f?.name == "Chicken Breast")   // ALL-CAPS USDA name de-shouted for display
        #expect(f?.source == .usdaBranded)
        #expect(f?.calories == 120)                      // 107 × 112/100
        #expect(Int((f?.protein ?? 0).rounded()) == 25)  // 22 × 1.12
        #expect(f?.servingGrams == 112)
    }
}

@MainActor
@Suite struct BarcodeCacheTests {
    @Test func roundTrips() {
        let cache = BarcodeCache(inMemory: [])
        let f = Food(symbol: "circle.fill", tint: .gray, name: "Cached", source: .openFoodFacts,
                     servingDescription: "100 g", calories: 50, carbs: 10, protein: 1, fat: 0, fibre: 0,
                     barcode: "00011110002013")
        cache.insert(f)
        #expect(cache.food(for: "00011110002013")?.name == "Cached")
        #expect(cache.food(for: "does-not-exist") == nil)
    }
}

@MainActor
@Suite struct StoreFallbackTests {
    struct StubRemote: RemoteFoodLookup {
        let result: Food?
        func lookup(barcode: String) async -> Food? { result }
    }

    private func remoteFood() -> Food {
        Food(symbol: "waterbottle.fill", tint: .blue, name: "Zero Sugar Lemonade",
             source: .openFoodFacts, servingDescription: "355 ml", calories: 5,
             carbs: 2, protein: 0, fat: 0, fibre: 0, barcode: "00025000121142")
    }

    @Test func missFallsBackToRemoteThenCaches() async {
        let cache = BarcodeCache(inMemory: [])
        let store = MockStore(
            catalog: SampleFoodCatalog(foods: SampleData.foods),   // does NOT have this barcode
            remote: StubRemote(result: remoteFood()),
            cache: cache
        )
        let hit = await store.food(forBarcode: "025000121142")     // 12-digit UPC
        #expect(hit?.name == "Zero Sugar Lemonade")
        #expect(cache.food(for: "00025000121142") != nil)          // cached under GTIN-14
    }

    @Test func customFoodWithBarcodeIsCachedAndResolvable() async {
        let cache = BarcodeCache(inMemory: [])
        let store = MockStore(
            catalog: SampleFoodCatalog(foods: SampleData.foods),
            remote: StubRemote(result: nil),          // nothing online
            cache: cache
        )
        let custom = Food(symbol: "fork.knife", tint: .gray, name: "My Snack Bar",
                          source: .custom, servingDescription: "1 bar", calories: 200,
                          carbs: 20, protein: 10, fat: 8, fibre: 2, barcode: "00099999999999")
        store.saveCustomFood(custom)
        let got = await store.food(forBarcode: "099999999999")   // 12-digit → GTIN-14
        #expect(got?.name == "My Snack Bar")
    }

    @Test func localCatalogWinsOverRemote() async {
        let store = MockStore(
            catalog: SampleFoodCatalog(foods: SampleData.foods),
            remote: StubRemote(result: remoteFood()),
            cache: BarcodeCache(inMemory: [])
        )
        // SALORIE-DEMO-01 is in the sample catalog → remote must not be consulted.
        let hit = await store.food(forBarcode: "SALORIE-DEMO-01")
        #expect(hit?.name == "Protein Bar (Demo)")
    }
}
