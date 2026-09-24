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

    var ingredients: [String] = []
    var isFavorite: Bool = false
    var barcode: String? = nil          // scannable code (Code128/EAN/QR)

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

    var symbol: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch:     return "sun.max.fill"
        case .dinner:    return "moon.stars.fill"
        case .snacks:    return "leaf.fill"
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
    let id = UUID()
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
