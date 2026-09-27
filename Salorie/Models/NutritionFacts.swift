import Foundation
#if canImport(FoundationModels)
import FoundationModels

/// The LLM contract for **Case A** (a Nutrition Facts panel). Guided generation
/// constrains decoding to this schema and hands back a validated typed instance —
/// no JSON parsing, no invented fields. Units are pinned in `@Guide` so the model
/// normalizes rather than our code. Every nutrient is optional so "not printed"
/// comes back as `nil` (never a fabricated `0`); the arithmetic (per-100g → per
/// serving) is done in Swift by ``toParsedLabel()``, never by the model.
@Generable
struct NutritionFacts: Equatable {
    /// The basis the panel printed its numbers on. Kept in the model (a reading
    /// decision); the rescale itself is deterministic Swift.
    @Generable
    enum Basis: Equatable {
        case perServing
        case per100g
        case unknown
    }

    @Guide(description: "Serving description exactly as printed, e.g. '1 package', '2 cookies (30g)'. Null if absent.")
    var servingText: String?
    @Guide(description: "Serving weight in grams for ONE serving. Convert oz→g if only oz printed. Null if not stated.")
    var servingGrams: Double?
    @Guide(description: "Calories (kcal) per ONE serving as printed. Null if absent.")
    var calories: Double?
    @Guide(description: "Total carbohydrate in GRAMS per serving. Null if absent.")
    var carbs: Double?
    @Guide(description: "Protein in GRAMS per serving. Null if absent.")
    var protein: Double?
    @Guide(description: "Total fat in GRAMS per serving. Null if absent.")
    var fat: Double?
    @Guide(description: "Dietary fiber in GRAMS per serving. Null if absent.")
    var fibre: Double?
    @Guide(description: "Total sugars in GRAMS per serving. Null if absent.")
    var sugars: Double?
    @Guide(description: "Saturated fat in GRAMS per serving. Null if absent.")
    var satfat: Double?
    @Guide(description: "Sodium in MILLIGRAMS per serving. If printed in grams, multiply by 1000. Null if absent.")
    var sodium: Double?
    @Guide(description: "Cholesterol in MILLIGRAMS per serving. Null if absent.")
    var cholesterol: Double?
    @Guide(description: "The basis the numbers were printed on.")
    var basis: Basis
    @Guide(description: "0.0-1.0 confidence the panel was legible and the values are correct.")
    var confidence: Double

    /// Explicit memberwise init (with defaults) so the mapper can be unit-tested
    /// without invoking the model.
    init(servingText: String? = nil, servingGrams: Double? = nil, calories: Double? = nil,
         carbs: Double? = nil, protein: Double? = nil, fat: Double? = nil, fibre: Double? = nil,
         sugars: Double? = nil, satfat: Double? = nil, sodium: Double? = nil, cholesterol: Double? = nil,
         basis: Basis = .unknown, confidence: Double = 0) {
        self.servingText = servingText; self.servingGrams = servingGrams; self.calories = calories
        self.carbs = carbs; self.protein = protein; self.fat = fat; self.fibre = fibre
        self.sugars = sugars; self.satfat = satfat; self.sodium = sodium; self.cholesterol = cholesterol
        self.basis = basis; self.confidence = confidence
    }
}

extension NutritionFacts {
    /// Normalize to the app's per-serving `ParsedLabel`. Only rescales when the model
    /// said the numbers were per-100g AND a serving weight is known — otherwise the
    /// numbers pass through untouched (safer than guessing a factor). Sodium and
    /// cholesterol stay in mg; the LLM already put them there per its `@Guide`.
    func toParsedLabel() -> ParsedLabel {
        let factor: Double = (basis == .per100g && (servingGrams ?? 0) > 0) ? servingGrams! / 100 : 1
        func scale(_ v: Double?) -> Double? { v.map { $0 * factor } }
        return ParsedLabel(
            servingText: servingText,
            servingGrams: servingGrams,
            calories: scale(calories),
            carbs: scale(carbs),
            protein: scale(protein),
            fat: scale(fat),
            fibre: scale(fibre),
            sugars: scale(sugars),
            satfat: scale(satfat),
            sodium: scale(sodium),
            cholesterol: scale(cholesterol)
        )
    }
}

/// The LLM contract for **Case B** (front-of-pack, identity only). By construction it
/// has NO nutrition fields, so the model structurally cannot emit hallucinated
/// calories — the whole point of a separate schema.
@Generable
struct IdentifiedProduct: Equatable {
    @Guide(description: "Brand / manufacturer, title-cased. Null if not identifiable.")
    var brand: String?
    @Guide(description: "Product / food name, title-cased, without the brand and without slogans.")
    var foodName: String
    @Guide(description: "Serving / net-weight text if printed, e.g. '500ml'. Null otherwise.")
    var servingText: String?

    init(brand: String? = nil, foodName: String = "", servingText: String? = nil) {
        self.brand = brand; self.foodName = foodName; self.servingText = servingText
    }
}
#endif
