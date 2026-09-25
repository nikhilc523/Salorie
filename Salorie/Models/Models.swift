import SwiftUI

// MARK: - Food source

/// Origin of a food record. Drives the colored SourceBadge on every row.
enum FoodSource: String, CaseIterable, Hashable, Identifiable, Codable {
    case usdaFoundation = "USDA Foundation"
    case srLegacy       = "SR Legacy"
    case usdaBranded    = "USDA Branded"
    case openFoodFacts  = "Open Food Facts"
    case custom         = "Custom"

    var id: String { rawValue }

    var short: String {
        switch self {
        case .usdaFoundation: return "Foundation"
        case .srLegacy:       return "SR Legacy"
        case .usdaBranded:    return "Branded"
        case .openFoodFacts:  return "OFF"
        case .custom:         return "Custom"
        }
    }

    var tagColor: TagColor {
        switch self {
        case .usdaFoundation, .srLegacy: return .green
        case .usdaBranded:               return .blue
        case .openFoodFacts:             return .orange
        case .custom:                    return .gray
        }
    }
}

// MARK: - Tag

struct Tag: Hashable, Identifiable, Codable, Sendable {
    var id = UUID()
    var text: String
    var color: TagColor
    var filled: Bool = false
}

// MARK: - Food

/// Whether a `Food` is a single catalog item or a user-built composite meal.
/// A `.custom` meal stores its ingredients in `components`; its macro fields
/// (calories/carbs/…) are the *snapshot sum* of those components, so a custom
/// meal flows through search / favorites / logging exactly like any other food.
enum FoodKind: String, Hashable, Codable {
    case single
    case custom
}

// MARK: - Extended nutrients (progressive disclosure)

/// Everything beyond the core macro grid. Every field is **optional** on purpose:
/// `nil` means "the data source didn't have this value" and the UI hides the row —
/// no fake zeros. Populated from USDA lab data (rich) or a product label (sparse).
///
/// Numeric fields are per `Food.servingDescription`, so they scale with servings
/// exactly like the core macros. Qualitative fields (Nutri-Score / NOVA) are label
/// properties of the product and never scale.
struct ExtendedNutrients: Hashable, Codable, Sendable {
    // Tier A — reliably present across USDA + most labels
    var potassium: Double?          // mg
    var transFat: Double?           // g
    var addedSugars: Double?        // g
    var calcium: Double?            // mg
    var iron: Double?               // mg
    var vitaminD: Double?           // µg
    // Tier B — mostly USDA generics (lab-analyzed whole foods)
    var caffeine: Double?           // mg
    var magnesium: Double?          // mg
    var zinc: Double?               // mg
    var monounsaturatedFat: Double? // g
    var polyunsaturatedFat: Double? // g
    var omega3: Double?             // g
    var vitaminC: Double?           // mg
    var vitaminA: Double?           // µg RAE
    var vitaminB12: Double?         // µg
    var folate: Double?             // µg DFE
    // Tier C — qualitative product properties (Open Food Facts). Not scaled.
    var nutriScore: String?         // "A"…"E"
    var novaGroup: Int?             // 1…4 (processing level)

    /// Every numeric (scalable) field, in one place so scale/sum stay DRY.
    /// Computed (not stored) so it needs no `Sendable` keypath storage under Swift 6.
    static var numericKeyPaths: [WritableKeyPath<ExtendedNutrients, Double?>] {
        [\.potassium, \.transFat, \.addedSugars, \.calcium, \.iron, \.vitaminD,
         \.caffeine, \.magnesium, \.zinc, \.monounsaturatedFat, \.polyunsaturatedFat,
         \.omega3, \.vitaminC, \.vitaminA, \.vitaminB12, \.folate]
    }

    /// True if any value at all is present — drives whether "Show more" appears.
    var hasAny: Bool {
        nutriScore != nil || novaGroup != nil
            || Self.numericKeyPaths.contains { self[keyPath: $0] != nil }
    }

    /// Scale numeric fields by a serving multiplier; qualitative fields pass through.
    func scaled(by s: Double) -> ExtendedNutrients {
        guard s != 1 else { return self }
        var out = self
        for kp in Self.numericKeyPaths where out[keyPath: kp] != nil {
            out[keyPath: kp]! *= s
        }
        return out
    }

    /// Sum many rows (for a composite meal). A field stays `nil` only if *no*
    /// contributor had it; otherwise missing contributors count as 0. Qualitative
    /// fields don't sum, so a composite meal has no Nutri-Score/NOVA.
    static func sum(_ items: [ExtendedNutrients]) -> ExtendedNutrients {
        var out = ExtendedNutrients()
        for kp in numericKeyPaths {
            let values = items.compactMap { $0[keyPath: kp] }
            out[keyPath: kp] = values.isEmpty ? nil : values.reduce(0, +)
        }
        return out
    }
}

struct Food: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var symbol: String        // SF Symbol leading glyph
    var tint: TagColor        // glyph tint
    var name: String
    var brand: String?
    var source: FoodSource
    var isOpen: Bool = false            // shows the OPEN ghost badge
    var tags: [Tag] = []

    /// Per `servingDescription` (e.g. "1 cup (240g)").
    var servingDescription: String
    var calories: Int
    var carbs: Double         // g
    var protein: Double       // g
    var fat: Double           // g
    var fibre: Double         // g
    var sugars: Double = 0        // g
    var saturatedFat: Double = 0  // g
    var sodium: Double = 0        // mg
    var cholesterol: Double = 0   // mg

    /// Optional deep nutrients revealed by "Show more" in the detail view.
    var extended: ExtendedNutrients = ExtendedNutrients()

    var ingredients: [String] = []
    var isFavorite: Bool = false
    var barcode: String? = nil          // scannable code (Code128/EAN/QR)

    /// Catalog row id ("usda:…" / "off:…") for fetching household portions. nil for
    /// sample/custom foods.
    var catalogID: String? = nil
    /// Grams represented by this food's per-serving macro snapshot (the label
    /// serving). Enables gram/oz logging — e.g. a variable-weight Costco breast.
    /// nil when unknown (custom meals, sample data).
    var servingGrams: Double? = nil

    // MARK: Custom meal (composite of single foods)

    var kind: FoodKind = .single
    /// Ingredients when `kind == .custom`. Empty for single foods.
    var components: [MealComponent] = []

    var isCustomMeal: Bool { kind == .custom }
}

// MARK: - Meal component (one ingredient inside a custom meal)

/// One line inside a custom meal: a single `Food` plus how many servings of it
/// go into the meal. Its macros are the food's macros scaled by `servings`.
struct MealComponent: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var food: Food
    var servings: Double

    var calories: Double { Double(food.calories) * servings }
    var carbs: Double { food.carbs * servings }
    var protein: Double { food.protein * servings }
    var fat: Double { food.fat * servings }
    var fibre: Double { food.fibre * servings }
    var sugars: Double { food.sugars * servings }
    var saturatedFat: Double { food.saturatedFat * servings }
    var sodium: Double { food.sodium * servings }
    var cholesterol: Double { food.cholesterol * servings }
}

// MARK: - Custom meal building

extension Food {
    /// Build a composite meal `Food` from its ingredients. Macro fields are the
    /// summed snapshot of the components, so the returned value logs, searches,
    /// and renders like any other food.
    static func customMeal(name: String,
                           symbol: String = "takeoutbag.and.cup.and.straw.fill",
                           tint: TagColor = .green,
                           isFavorite: Bool = false,
                           components: [MealComponent]) -> Food {
        var meal = Food(symbol: symbol, tint: tint, name: name, brand: nil,
                        source: .custom, servingDescription: "",
                        calories: 0, carbs: 0, protein: 0, fat: 0, fibre: 0,
                        isFavorite: isFavorite)
        meal.kind = .custom
        meal.components = components
        meal.recomputeFromComponents()
        return meal
    }

    /// Re-sum all macro fields from `components`. Call after editing ingredients.
    mutating func recomputeFromComponents() {
        guard kind == .custom else { return }
        calories     = Int(components.reduce(0.0) { $0 + $1.calories }.rounded())
        carbs        = components.reduce(0) { $0 + $1.carbs }
        protein      = components.reduce(0) { $0 + $1.protein }
        fat          = components.reduce(0) { $0 + $1.fat }
        fibre        = components.reduce(0) { $0 + $1.fibre }
        sugars       = components.reduce(0) { $0 + $1.sugars }
        saturatedFat = components.reduce(0) { $0 + $1.saturatedFat }
        sodium       = components.reduce(0) { $0 + $1.sodium }
        cholesterol  = components.reduce(0) { $0 + $1.cholesterol }
        extended     = ExtendedNutrients.sum(components.map { $0.food.extended.scaled(by: $0.servings) })
        ingredients  = components.map(\.food.name)
        let n = components.count
        servingDescription = "\(n) item\(n == 1 ? "" : "s")"
    }
}

// MARK: - Meal

enum MealSlot: String, CaseIterable, Identifiable {
    case breakfast = "Breakfast"
    case lunch     = "Lunch"
    case dinner    = "Dinner"
    case snacks    = "Snacks"

    var id: String { rawValue }

    /// Monochrome time-of-day glyphs (breakfast→dinner) + a carrot for snacks.
    /// Filled for legibility, rendered in one neutral tone (see TodayView) — no
    /// rainbow tints, so they sit quietly on the warm-black theme.
    var symbol: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch:     return "sun.max.fill"
        case .dinner:    return "moon.stars.fill"
        case .snacks:    return "carrot.fill"
        }
    }

    var tagColor: TagColor {
        switch self {
        case .breakfast: return .yellow
        case .lunch:     return .green
        case .dinner:    return .blue
        case .snacks:    return .purple
        }
    }
}

struct MealEntry: Identifiable, Hashable {
    var id = UUID()
    var food: Food
    var slot: MealSlot
    var servings: Double
    var time: String   // display only, e.g. "8:24 AM"

    var calories: Int { Int((Double(food.calories) * servings).rounded()) }
    var carbs: Double { food.carbs * servings }
    var protein: Double { food.protein * servings }
    var fibre: Double { food.fibre * servings }
    var fat: Double { food.fat * servings }
    var sugars: Double { food.sugars * servings }
    var saturatedFat: Double { food.saturatedFat * servings }
    var sodium: Double { food.sodium * servings }
    var cholesterol: Double { food.cholesterol * servings }
}

// MARK: - Macro targets & day summary

struct MacroTargets: Hashable {
    var calories: Int
    var carbs: Double
    var protein: Double
    var fibre: Double
    var fat: Double
}

/// A single logged day — used by the dashboard and history.
struct DayLog: Identifiable, Hashable {
    let id = UUID()
    var date: Date
    var weekdayLetter: String   // "S" "M" ...
    var entries: [MealEntry]

    var calories: Int { entries.reduce(0) { $0 + $1.calories } }
    var carbs: Double { entries.reduce(0) { $0 + $1.carbs } }
    var protein: Double { entries.reduce(0) { $0 + $1.protein } }
    var fibre: Double { entries.reduce(0) { $0 + $1.fibre } }
    var fat: Double { entries.reduce(0) { $0 + $1.fat } }
    var sugars: Double { entries.reduce(0) { $0 + $1.sugars } }
    var saturatedFat: Double { entries.reduce(0) { $0 + $1.saturatedFat } }
    var sodium: Double { entries.reduce(0) { $0 + $1.sodium } }
    var cholesterol: Double { entries.reduce(0) { $0 + $1.cholesterol } }
}
