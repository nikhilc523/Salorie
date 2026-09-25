import Foundation
import GRDB

/// The real food catalog: a read-only, bundled SQLite (GRDB + FTS5) built by
/// `tools/db-build`. Implements `FoodCatalog`, so it drops into `MockStore` in
/// place of `SampleFoodCatalog` with no view changes.
///
/// - Search uses FTS5 with **source-priority ranking** (generic > branded > OFF),
///   matching the pipeline's `source_priority` column.
/// - Barcode lookup normalizes the scanned code to GTIN-14 (same as the build).
/// - Rows are per-100g; each result is mapped to a per-serving `Food` snapshot
///   for its default serving (the detail view's stepper scales from there).
struct GRDBFoodCatalog: FoodCatalog {
    let dbQueue: DatabaseQueue

    /// Inject a queue directly (used by tests with an in-memory DB).
    init(dbQueue: DatabaseQueue) { self.dbQueue = dbQueue }

    /// Open a read-only catalog at an explicit path (a downloaded build or the bundled
    /// seed). Fails (→ nil) if the file is missing or unreadable, so callers can fall
    /// through to the next candidate and ultimately `SampleFoodCatalog`.
    init?(fileURL: URL) {
        var config = Configuration()
        config.readonly = true
        guard let queue = try? DatabaseQueue(path: fileURL.path, configuration: config) else { return nil }
        self.dbQueue = queue
    }

    /// Open the bundled read-only catalog. Fails (→ nil) if it isn't in the bundle.
    init?(bundledResource name: String = "salorie_foods", ext: String = "sqlite") {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
        self.init(fileURL: url)
    }

    // MARK: FoodCatalog

    func search(_ query: String, limit: Int) async -> [Food] {
        guard let pattern = Self.ftsPattern(query) else { return [] }
        do {
            return try await dbQueue.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT f.* FROM foods_fts x JOIN foods f ON f.id = x.id
                    WHERE foods_fts MATCH ?
                    ORDER BY f.source_priority, rank
                    LIMIT ?
                    """, arguments: [pattern, limit])
                return rows.map(Self.food(from:))
            }
        } catch {
            return []
        }
    }

    func portions(forID id: String) async -> [FoodPortion] {
        do {
            return try await dbQueue.read { db in
                try Row.fetchAll(
                    db,
                    sql: "SELECT label, grams FROM food_portion WHERE food_id = ? AND grams > 0 ORDER BY seq",
                    arguments: [id]
                ).compactMap { row in
                    guard let label: String = row["label"], let grams: Double = row["grams"] else { return nil }
                    return FoodPortion(label: label, grams: grams)
                }
            }
        } catch {
            return []
        }
    }

    func food(forBarcode code: String) async -> Food? {
        guard let gtin = Self.normalizeGTIN14(code) else { return nil }
        do {
            return try await dbQueue.read { db in
                guard let row = try Row.fetchOne(
                    db, sql: "SELECT * FROM foods WHERE barcode = ? LIMIT 1", arguments: [gtin]
                ) else { return nil }
                return Self.food(from: row)
            }
        } catch {
            return nil
        }
    }

    // MARK: Query helpers (pure — unit-tested)

    /// Build an FTS5 prefix query: each alphanumeric token becomes `token*`, ANDed.
    /// Returns nil when the input has no usable tokens (so search yields `[]`).
    static func ftsPattern(_ query: String) -> String? {
        let tokens = query.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\($0)*" }.joined(separator: " ")
    }

    /// Normalize a scanned/typed barcode to GTIN-14 (digits, left-padded to 14) —
    /// exactly how the build stores `barcode`. Returns nil for non-8…14-digit input.
    static func normalizeGTIN14(_ code: String) -> String? {
        let digits = code.filter(\.isNumber)
        guard (8...14).contains(digits.count) else { return nil }
        return String(repeating: "0", count: 14 - digits.count) + digits
    }

    // MARK: Row → Food (per-100g → per-serving snapshot)

    static func food(from row: Row) -> Food {
        func dbl(_ col: String) -> Double? { row[col] }
        let servingG: Double = row["default_serving_g"] ?? 100
        let factor = servingG / 100
        func scaled(_ col: String) -> Double { (dbl(col) ?? 0) * factor }

        let source = FoodSource(rawValue: row["source"] ?? "") ?? .custom
        let (symbol, tint) = style(for: row["category"], source: source)

        // Extended nutrients are stored per-100g; scale to the default serving.
        let ext = ExtendedNutrients(
            potassium: dbl("potassium_100"), transFat: dbl("trans_fat_100"),
            addedSugars: dbl("added_sugars_100"), calcium: dbl("calcium_100"),
            iron: dbl("iron_100"), vitaminD: dbl("vit_d_100"),
            caffeine: dbl("caffeine_100"), magnesium: dbl("magnesium_100"),
            zinc: dbl("zinc_100"), monounsaturatedFat: dbl("mono_fat_100"),
            polyunsaturatedFat: dbl("poly_fat_100"), omega3: nil,
            vitaminC: dbl("vit_c_100"), vitaminA: dbl("vit_a_100"),
            vitaminB12: dbl("vit_b12_100"), folate: dbl("folate_100"),
            nutriScore: row["nutri_score"], novaGroup: row["nova_group"]
        ).scaled(by: factor)

        let ingredientsText: String? = row["ingredients"]

        return Food(
            symbol: symbol,
            tint: tint,
            name: row["name"] ?? "Unknown",
            brand: row["brand"],
            source: source,
            servingDescription: row["serving_text"] ?? "100 g",
            calories: Int((scaled("kcal_100")).rounded()),
            carbs: scaled("carbs_100"),
            protein: scaled("protein_100"),
            fat: scaled("fat_100"),
            fibre: scaled("fibre_100"),
            sugars: scaled("sugars_100"),
            saturatedFat: scaled("satfat_100"),
            sodium: scaled("sodium_100"),
            cholesterol: scaled("chol_100"),
            extended: ext,
            ingredients: ingredientsText.map { [$0] } ?? [],
            barcode: row["barcode"],
            catalogID: row["id"],
            servingGrams: servingG
        )
    }

    /// Map a raw category string → an SF Symbol + tint, so DB rows get the same
    /// glyph language as hand-authored foods. Keyword-based; falls back to a dot.
    static func style(for category: String?, source: FoodSource) -> (String, TagColor) {
        let c = (category ?? "").lowercased()
        func has(_ words: [String]) -> Bool { words.contains { c.contains($0) } }
        switch true {
        case has(["dairy", "milk", "yogurt", "yoghurt", "cheese", "cream"]): return ("cup.and.saucer.fill", .blue)
        case has(["vegetable", "legume", "bean"]):                            return ("leaf.fill", .green)
        case has(["fruit", "berry", "juice"]):                               return ("leaf.fill", .yellow)
        case has(["poultry", "beef", "pork", "meat", "fish", "seafood", "lamb", "sausage", "chicken"]): return ("fork.knife", .orange)
        case has(["cereal", "grain", "pasta", "rice", "bread", "bakery", "baked"]): return ("takeoutbag.and.cup.and.straw.fill", .yellow)
        case has(["nut", "seed", "spread", "peanut", "almond"]):             return ("circle.hexagongrid.fill", .brown)
        case has(["sweet", "candy", "chocolate", "dessert", "sugar", "snack"]): return ("square.grid.2x2.fill", .brown)
        case has(["beverage", "drink", "soda", "water", "coffee", "tea"]):    return ("waterbottle.fill", .blue)
        case has(["fat", "oil"]):                                            return ("drop.fill", .yellow)
        default:                                                            return ("circle.fill", .gray)
        }
    }
}
