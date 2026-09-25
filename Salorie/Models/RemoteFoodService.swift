import Foundation

/// Live lookup for barcodes not in the bundled catalog. Tries Open Food Facts
/// (no key) first, then USDA FoodData Central (needs a free key). Offline-first:
/// only called on a local miss; results are cached by the store.
protocol RemoteFoodLookup: Sendable {
    func lookup(barcode: String) async -> Food?
}

struct RemoteFoodService: RemoteFoodLookup {
    var usdaAPIKey: String? = RemoteConfig.usdaAPIKey
    var session: URLSession = .shared

    func lookup(barcode: String) async -> Food? {
        let digits = barcode.filter(\.isNumber)
        guard digits.count >= 8 else { return nil }
        if let off = await lookupOFF(digits) { return off }
        if let usda = await lookupUSDA(digits) { return usda }
        return nil
    }

    // MARK: Open Food Facts

    private func lookupOFF(_ code: String) async -> Food? {
        let fields = "code,product_name,brands,nutriscore_grade,nova_group,serving_quantity,serving_size,nutriments"
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=\(fields)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Salorie/0.1 (barcode lookup)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        guard let data = try? await session.data(for: req).0 else { return nil }
        return Self.parseOFF(data, requestedBarcode: code)
    }

    /// Pure, testable OFF parser: JSON → `Food` (nil if not found / no energy).
    static func parseOFF(_ data: Data, requestedBarcode: String) -> Food? {
        guard let resp = try? JSONDecoder().decode(OFFResponse.self, from: data),
              resp.status == 1, let p = resp.product,
              let n = p.nutriments, let kcal = n.energyKcal100g,
              let name = p.productName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else { return nil }

        let sodiumMg = n.sodium100g.map { $0 * 1000 } ?? n.salt100g.map { $0 / 2.5 * 1000 }
        var parsed = RemoteParsed(
            name: name,
            brand: p.brands?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) },
            barcode: p.code ?? requestedBarcode,
            source: .openFoodFacts,
            servingGrams: (p.servingQuantity ?? 0) > 0 ? p.servingQuantity! : 100,
            servingText: p.servingSize,
            kcal: kcal, carbs: n.carbohydrates100g, protein: n.proteins100g, fat: n.fat100g,
            fibre: n.fiber100g, sugars: n.sugars100g, satfat: n.saturatedFat100g,
            sodiumMg: sodiumMg, cholMg: n.cholesterol100g.map { $0 * 1000 },
            potassium: n.potassium100g.map { $0 * 1000 }, calcium: n.calcium100g.map { $0 * 1000 },
            iron: n.iron100g.map { $0 * 1000 }, magnesium: n.magnesium100g.map { $0 * 1000 },
            zinc: n.zinc100g.map { $0 * 1000 }, vitC: n.vitaminC100g.map { $0 * 1000 },
            caffeine: n.caffeine100g.map { $0 * 1000 },
            nutriScore: p.nutriscoreGrade.flatMap { ["a","b","c","d","e"].contains($0.lowercased()) ? $0.uppercased() : nil },
            novaGroup: p.novaGroup.flatMap { (1...4).contains($0) ? $0 : nil },
            ingredients: nil
        )
        if parsed.servingGrams <= 0 { parsed.servingGrams = 100 }
        return makeFood(parsed)
    }

    // MARK: USDA FoodData Central

    private func lookupUSDA(_ code: String) async -> Food? {
        guard let key = usdaAPIKey, !key.isEmpty, key != "DEMO_KEY" else { return nil }
        var comps = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        comps.queryItems = [
            .init(name: "query", value: code),
            .init(name: "dataType", value: "Branded"),
            .init(name: "pageSize", value: "5"),
            .init(name: "api_key", value: key),
        ]
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url); req.timeoutInterval = 12
        guard let data = try? await session.data(for: req).0 else { return nil }
        return Self.parseUSDA(data, requestedBarcode: code)
    }

    /// Pure, testable USDA parser: pick the branded food whose GTIN matches.
    static func parseUSDA(_ data: Data, requestedBarcode: String) -> Food? {
        guard let resp = try? JSONDecoder().decode(USDASearchResponse.self, from: data) else { return nil }
        let target = GRDBFoodCatalog.normalizeGTIN14(requestedBarcode)
        let food = resp.foods.first { f in
            guard let g = f.gtinUpc else { return false }
            return GRDBFoodCatalog.normalizeGTIN14(g) == target
        } ?? resp.foods.first
        guard let f = food, let name = f.description, !name.isEmpty else { return nil }
        func nutrient(_ ids: [Int]) -> Double? {
            for id in ids { if let v = f.foodNutrients?.first(where: { $0.nutrientId == id })?.value { return v } }
            return nil
        }
        guard let kcal = nutrient([1008, 2048, 2047]) else { return nil }
        let sg = (f.servingSize ?? 0) > 0 ? f.servingSize! : 100
        let parsed = RemoteParsed(
            name: name,
            brand: f.brandName?.nilIfBlank ?? f.brandOwner?.nilIfBlank,
            barcode: f.gtinUpc ?? requestedBarcode,
            source: .usdaBranded,
            servingGrams: sg,
            servingText: f.householdServingFullText,
            kcal: kcal, carbs: nutrient([1005]), protein: nutrient([1003]), fat: nutrient([1004]),
            fibre: nutrient([1079]), sugars: nutrient([2000, 1063]), satfat: nutrient([1258]),
            sodiumMg: nutrient([1093]), cholMg: nutrient([1253]),
            potassium: nutrient([1092]), calcium: nutrient([1087]), iron: nutrient([1089]),
            magnesium: nutrient([1090]), zinc: nutrient([1095]), vitC: nutrient([1162]),
            caffeine: nutrient([1057]),
            nutriScore: nil, novaGroup: nil, ingredients: f.ingredients?.nilIfBlank
        )
        return makeFood(parsed)
    }

    // MARK: Shared per-100g → per-serving Food builder

    static func makeFood(_ p: RemoteParsed) -> Food {
        let sg = p.servingGrams > 0 ? p.servingGrams : 100
        let factor = sg / 100
        func s(_ v: Double?) -> Double { (v ?? 0) * factor }
        let (symbol, tint) = GRDBFoodCatalog.style(for: nil, source: p.source)
        let ext = ExtendedNutrients(
            potassium: p.potassium, calcium: p.calcium, iron: p.iron,
            caffeine: p.caffeine, magnesium: p.magnesium, zinc: p.zinc,
            vitaminC: p.vitC, nutriScore: p.nutriScore, novaGroup: p.novaGroup
        ).scaled(by: factor)
        let gtin = GRDBFoodCatalog.normalizeGTIN14(p.barcode) ?? p.barcode
        return Food(
            symbol: symbol, tint: tint, name: p.name, brand: p.brand, source: p.source,
            servingDescription: p.servingText?.nilIfBlank ?? "\(Int(sg.rounded())) g",
            calories: Int((s(p.kcal)).rounded()),
            carbs: s(p.carbs), protein: s(p.protein), fat: s(p.fat), fibre: s(p.fibre),
            sugars: s(p.sugars), saturatedFat: s(p.satfat), sodium: s(p.sodiumMg), cholesterol: s(p.cholMg),
            extended: ext,
            ingredients: p.ingredients.map { [$0] } ?? [],
            barcode: gtin, catalogID: nil, servingGrams: sg
        )
    }
}

/// Intermediate between a remote payload and a `Food`. Per-100g values.
struct RemoteParsed {
    var name: String
    var brand: String?
    var barcode: String
    var source: FoodSource
    var servingGrams: Double
    var servingText: String?
    var kcal: Double?, carbs: Double?, protein: Double?, fat: Double?, fibre: Double?
    var sugars: Double?, satfat: Double?, sodiumMg: Double?, cholMg: Double?
    var potassium: Double?, calcium: Double?, iron: Double?, magnesium: Double?, zinc: Double?
    var vitC: Double?, caffeine: Double?
    var nutriScore: String?
    var novaGroup: Int?
    var ingredients: String?
}

enum RemoteConfig {
    /// Free key from https://fdc.nal.usda.gov/api-key-signup.html. Read from the
    /// `USDA_API_KEY` env var, else the baked constant. Empty → USDA fallback is
    /// skipped (OFF still works). Never commit a real key or ship DEMO_KEY.
    static var usdaAPIKey: String? {
        if let e = ProcessInfo.processInfo.environment["USDA_API_KEY"], !e.isEmpty { return e }
        let baked = ""   // ← paste your free data.gov key here for on-device USDA fallback
        return baked.isEmpty ? nil : baked
    }

    /// Location of the catalog **manifest** JSON (plan §10 — hosted DB delivery). When
    /// set, the app checks it in the background and downloads a newer `salorie_foods.sqlite`
    /// from the host (Cloudflare R2 / Background Assets) without an App Store release.
    /// `nil` (default) ⇒ bundled-only, fully offline, no network on launch.
    /// Override at runtime with the `SALORIE_CATALOG_MANIFEST` env var (handy for testing).
    static var catalogManifestURL: URL? {
        if let e = ProcessInfo.processInfo.environment["SALORIE_CATALOG_MANIFEST"], let u = URL(string: e) { return u }
        let baked = ""   // ← e.g. "https://cdn.salorie.app/catalog/manifest.json"
        return baked.isEmpty ? nil : URL(string: baked)
    }

    /// CloudKit container backing SwiftData user-data sync (plan §10). `nil` (default)
    /// ⇒ local-only persistence (no iCloud, no entitlement needed). Set to the real
    /// container id to turn on cross-device sync of logs / meals / favorites.
    static var cloudKitContainerID: String? {
        if let e = ProcessInfo.processInfo.environment["SALORIE_CLOUDKIT_CONTAINER"], !e.isEmpty { return e }
        let baked = ""   // ← e.g. "iCloud.com.salorie.app"  (requires the iCloud capability)
        return baked.isEmpty ? nil : baked
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

// MARK: - Open Food Facts response (robust decoding)

struct OFFResponse: Decodable {
    let status: Int
    let product: OFFProduct?
}

struct OFFProduct: Decodable {
    let code: String?
    let productName: String?
    let brands: String?
    let nutriscoreGrade: String?
    let novaGroup: Int?
    let servingQuantity: Double?
    let servingSize: String?
    let nutriments: OFFNutriments?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try? c.decodeIfPresent(String.self, forKey: .code)
        productName = try? c.decodeIfPresent(String.self, forKey: .productName)
        brands = try? c.decodeIfPresent(String.self, forKey: .brands)
        nutriscoreGrade = try? c.decodeIfPresent(String.self, forKey: .nutriscoreGrade)
        novaGroup = c.lenientInt(.novaGroup)
        servingQuantity = c.lenientDouble(.servingQuantity)
        servingSize = try? c.decodeIfPresent(String.self, forKey: .servingSize)
        nutriments = try? c.decodeIfPresent(OFFNutriments.self, forKey: .nutriments)
    }
    enum CodingKeys: String, CodingKey {
        case code, brands, nutriments
        case productName = "product_name"
        case nutriscoreGrade = "nutriscore_grade"
        case novaGroup = "nova_group"
        case servingQuantity = "serving_quantity"
        case servingSize = "serving_size"
    }
}

struct OFFNutriments: Decodable {
    let energyKcal100g, carbohydrates100g, proteins100g, fat100g, fiber100g, sugars100g: Double?
    let saturatedFat100g, sodium100g, salt100g, cholesterol100g: Double?
    let potassium100g, calcium100g, iron100g, magnesium100g, zinc100g, vitaminC100g, caffeine100g: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d(_ k: CodingKeys) -> Double? { c.lenientDouble(k) }
        energyKcal100g = d(.energyKcal100g); carbohydrates100g = d(.carbohydrates100g)
        proteins100g = d(.proteins100g); fat100g = d(.fat100g); fiber100g = d(.fiber100g)
        sugars100g = d(.sugars100g); saturatedFat100g = d(.saturatedFat100g)
        sodium100g = d(.sodium100g); salt100g = d(.salt100g); cholesterol100g = d(.cholesterol100g)
        potassium100g = d(.potassium100g); calcium100g = d(.calcium100g); iron100g = d(.iron100g)
        magnesium100g = d(.magnesium100g); zinc100g = d(.zinc100g); vitaminC100g = d(.vitaminC100g)
        caffeine100g = d(.caffeine100g)
    }
    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case proteins100g = "proteins_100g"
        case fat100g = "fat_100g"
        case fiber100g = "fiber_100g"
        case sugars100g = "sugars_100g"
        case saturatedFat100g = "saturated-fat_100g"
        case sodium100g = "sodium_100g"
        case salt100g = "salt_100g"
        case cholesterol100g = "cholesterol_100g"
        case potassium100g = "potassium_100g"
        case calcium100g = "calcium_100g"
        case iron100g = "iron_100g"
        case magnesium100g = "magnesium_100g"
        case zinc100g = "zinc_100g"
        case vitaminC100g = "vitamin-c_100g"
        case caffeine100g = "caffeine_100g"
    }
}

// Lenient number decoding — OFF fields can be number or string across versions.
private extension KeyedDecodingContainer {
    func lenientDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }
    func lenientInt(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(s) ?? Double(s).map(Int.init) }
        return nil
    }
}

// MARK: - USDA search response

struct USDASearchResponse: Decodable { let foods: [USDAFood] }
struct USDAFood: Decodable {
    let description: String?
    let brandOwner: String?
    let brandName: String?
    let gtinUpc: String?
    let servingSize: Double?
    let householdServingFullText: String?
    let ingredients: String?
    let foodNutrients: [USDANutrient]?
}
struct USDANutrient: Decodable {
    let nutrientId: Int?
    let value: Double?
}
