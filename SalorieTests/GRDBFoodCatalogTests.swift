import Testing
import GRDB
@testable import Salorie

/// P2: the real GRDB catalog — pure helpers + query/mapping against an in-memory DB.
@Suite struct GRDBCatalogHelperTests {
    @Test func gtinNormalizationPadsToFourteen() {
        #expect(GRDBFoodCatalog.normalizeGTIN14("883572133501") == "00883572133501")  // UPC-A (12)
        #expect(GRDBFoodCatalog.normalizeGTIN14("0049000006344") == "00049000006344") // EAN-13
        #expect(GRDBFoodCatalog.normalizeGTIN14("12-345-678") == "00000012345678")    // strips non-digits (8)
    }

    @Test func gtinRejectsBadInput() {
        #expect(GRDBFoodCatalog.normalizeGTIN14("123") == nil)   // too short
        #expect(GRDBFoodCatalog.normalizeGTIN14("abc") == nil)   // no digits
    }

    @Test func ftsPatternBuildsPrefixTokens() {
        #expect(GRDBFoodCatalog.ftsPattern("greek yog") == "greek* yog*")
        #expect(GRDBFoodCatalog.ftsPattern("choc-chip!") == "choc* chip*")
        #expect(GRDBFoodCatalog.ftsPattern("   ") == nil)
    }
}

@Suite struct GRDBCatalogQueryTests {
    /// A tiny in-memory catalog: one generic banana (priority 0) + one branded/OFF
    /// banana bread (priority 3) with a barcode.
    private func makeCatalog() throws -> GRDBFoodCatalog {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE foods(
                  id TEXT, source TEXT, source_priority INT, name TEXT, brand TEXT, barcode TEXT,
                  kcal_100 REAL, carbs_100 REAL, protein_100 REAL, fat_100 REAL, fibre_100 REAL, sugars_100 REAL,
                  satfat_100 REAL, sodium_100 REAL, chol_100 REAL, potassium_100 REAL, calcium_100 REAL, iron_100 REAL,
                  magnesium_100 REAL, zinc_100 REAL, vit_d_100 REAL, vit_c_100 REAL, vit_a_100 REAL, vit_b12_100 REAL,
                  folate_100 REAL, caffeine_100 REAL, added_sugars_100 REAL, trans_fat_100 REAL, mono_fat_100 REAL,
                  poly_fat_100 REAL, nutri_score TEXT, nova_group INT, default_serving_g REAL, serving_text TEXT,
                  category TEXT, ingredients TEXT)
                """)
            try db.execute(sql: """
                INSERT INTO foods VALUES ('usda:1','USDA Foundation',0,'Banana, raw',NULL,NULL,
                  89,22.8,1.1,0.3,2.6,12.2,0.1,1,0, 358,5,0.3,27,0.2, 0,8.7,3,0,20,
                  NULL,NULL,NULL,NULL,NULL, NULL,NULL, 100,'100 g','Fruits',NULL)
                """)
            try db.execute(sql: """
                INSERT INTO foods VALUES ('off:2','Open Food Facts',3,'Banana Bread','ACME','00012345678905',
                  350,50,5,15,2,20,8,300,10, NULL,NULL,NULL,NULL,NULL, NULL,NULL,NULL,NULL,NULL,
                  10,NULL,NULL,NULL,NULL, 'C',4, 50,'1 slice (50 g)',NULL,'flour, banana')
                """)
            try db.execute(sql: "CREATE VIRTUAL TABLE foods_fts USING fts5(id UNINDEXED, name, brand, tokenize='porter unicode61')")
            try db.execute(sql: "INSERT INTO foods_fts(id, name, brand) SELECT id, name, COALESCE(brand,'') FROM foods")
        }
        return GRDBFoodCatalog(dbQueue: queue)
    }

    @Test func searchRanksGenericAboveBranded() async throws {
        let cat = try makeCatalog()
        let hits = await cat.search("banana")
        #expect(hits.first?.source == .usdaFoundation)   // priority 0 beats OFF priority 3
    }

    @Test func genericBananaPer100gServing() async throws {
        let cat = try makeCatalog()
        let b = await cat.search("banana raw").first { $0.name == "Banana, raw" }
        #expect(b?.calories == 89)                                       // 89/100g × 100g
        #expect(Int((b?.extended.potassium ?? 0).rounded()) == 358)
        #expect(b?.source == .usdaFoundation)
    }

    @Test func servingMathScalesToDefaultServing() async throws {
        let cat = try makeCatalog()
        let bread = await cat.search("banana bread").first { $0.name == "Banana Bread" }
        #expect(bread?.calories == 175)               // 350/100g × 50g serving
        #expect(bread?.extended.caffeine == 5)        // 10/100g × 50g
        #expect(bread?.extended.novaGroup == 4)       // qualitative, not scaled
        #expect(bread?.extended.nutriScore == "C")
        #expect(bread?.brand == "Acme")   // ALL-CAPS catalog brand de-shouted for display
    }

    @Test func barcodeNormalizesAndResolves() async throws {
        let cat = try makeCatalog()
        // stored as 00012345678905; scan the 12-digit UPC-A form
        let f = await cat.food(forBarcode: "012345678905")
        #expect(f?.name == "Banana Bread")
    }

    @Test func unknownBarcodeReturnsNil() async throws {
        let cat = try makeCatalog()
        #expect(await cat.food(forBarcode: "99999999999999") == nil)
    }
}
