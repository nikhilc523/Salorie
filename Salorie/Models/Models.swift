import SwiftUI

// MARK: - Food source

/// Origin of a food record. Drives the colored SourceBadge on every row.
enum FoodSource: String, CaseIterable, Hashable, Identifiable {
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

struct Tag: Hashable, Identifiable {
    let id = UUID()
    var text: String
    var color: TagColor
    var filled: Bool = false
}

// MARK: - Food

struct Food: Identifiable, Hashable {
    let id = UUID()
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
    var carbs: Double      // g
    var protein: Double    // g
    var fat: Double        // g
    var fibre: Double      // g

    var ingredients: [String] = []
    var isFavorite: Bool = false
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
}
