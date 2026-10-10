import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Which `ParsedLabel` fields a value landed in — used by the UI to highlight the
/// cells the on-device model filled (so the user knows what to double-check).
enum LabelField: String, Hashable, CaseIterable {
    case servingText, servingGrams, calories, carbs, protein, fat
    case fibre, sugars, satfat, sodium, cholesterol
}

/// The full outcome of a scan: the per-serving `ParsedLabel` the form consumes, plus
/// metadata the UX layer wants (was AI used, how confident, which fields it filled,
/// and any front-of-pack identity). SDK-agnostic on purpose — carries plain strings,
/// not the `@Generable` `IdentifiedProduct`, so it compiles without FoundationModels.
struct LabelScan: Equatable {
    var label: ParsedLabel
    var brand: String?
    var foodName: String?
    var usedAI: Bool = false
    var confidence: Double?
    /// Fields whose value came from the LLM (not the regex fallback).
    var aiFilled: Set<LabelField> = []
}

/// The producer swap point. Both the AI path and the regex path terminate in a
/// `ParsedLabel`, so the consumer (`ManualFoodEntryView.apply`/`save`) never branches.
/// AI is a quality boost layered on top of the free, deterministic regex parser —
/// never a correctness dependency. Availability is re-checked on every call.
enum LabelExtractor {

    // MARK: Case A — nutrition panel

    /// The tested contract: always returns a `ParsedLabel`, and when the model is
    /// unavailable (or errors) the result is EXACTLY `NutritionLabelParser.parse` —
    /// the regression guard for the fallback contract. This is the Case A path only;
    /// case detection lives in ``scan(ocrLines:)``.
    static func extract(ocrLines: [String]) async -> ParsedLabel {
        await extractNutrition(ocrLines: ocrLines).label
    }

    /// View-facing entry point. Deterministically decides the case from the free regex
    /// pass (a real nutrition panel has calories + ≥2 macros); otherwise treats the
    /// capture as front-of-pack and extracts identity only. Always returns a
    /// `LabelScan` whose `label` the form can consume.
    static func scan(ocrLines: [String]) async -> LabelScan {
        let regex = NutritionLabelParser.parse(ocrLines)
        if isNutritionPanel(regex) {
            return await extractNutrition(ocrLines: ocrLines)
        }
        return await identify(ocrLines: ocrLines)
    }

    /// Case A: calories printed and at least two of the core macros → it's a panel.
    static func isNutritionPanel(_ p: ParsedLabel) -> Bool {
        guard p.calories != nil else { return false }
        let macros = [p.carbs, p.protein, p.fat, p.fibre, p.sugars, p.satfat, p.sodium]
        return macros.compactMap { $0 }.count >= 2
    }

    /// Regex first (instant, free), then — if the model is available — refine with the
    /// LLM and let the regex backfill anything the model left nil.
    static func extractNutrition(ocrLines: [String]) async -> LabelScan {
        let regex = NutritionLabelParser.parse(ocrLines)
        #if canImport(FoundationModels)
        guard #available(iOS 26, *), LabelAI.isAvailable else {
            return LabelScan(label: regex)
        }
        do {
            // Uses SystemLanguageModel.default (the session's default model) — Apple's
            // latest on-device foundation model for the running OS (the updated iOS 27
            // model on iOS 27 devices). On-device only: no network, free, offline.
            let session = LanguageModelSession(instructions: Self.nutritionInstructions)
            let response = try await session.respond(
                to: ocrLines.joined(separator: "\n"),
                generating: NutritionFacts.self,
                options: GenerationOptions(temperature: 0))   // deterministic
            let facts = response.content
            let ai = facts.toParsedLabel()
            let (merged, filled) = merge(ai: ai, regex: regex)
            return LabelScan(label: merged, usedAI: true,
                             confidence: facts.confidence, aiFilled: filled)
        } catch {
            return LabelScan(label: regex)   // any failure → safe fallback
        }
        #else
        return LabelScan(label: regex)
        #endif
    }

    /// AI wins where it produced a value; the regex result backfills every field the
    /// model left `nil`. Returns which fields the AI supplied (for UX highlighting).
    static func merge(ai: ParsedLabel, regex: ParsedLabel) -> (ParsedLabel, Set<LabelField>) {
        var out = regex
        var filled: Set<LabelField> = []
        func take(_ field: LabelField, _ aiVal: Double?, _ set: (inout ParsedLabel, Double) -> Void) {
            if let v = aiVal { set(&out, v); filled.insert(field) }
        }
        if let t = ai.servingText, !t.isEmpty { out.servingText = t; filled.insert(.servingText) }
        take(.servingGrams, ai.servingGrams) { $0.servingGrams = $1 }
        take(.calories, ai.calories) { $0.calories = $1 }
        take(.carbs, ai.carbs) { $0.carbs = $1 }
        take(.protein, ai.protein) { $0.protein = $1 }
        take(.fat, ai.fat) { $0.fat = $1 }
        take(.fibre, ai.fibre) { $0.fibre = $1 }
        take(.sugars, ai.sugars) { $0.sugars = $1 }
        take(.satfat, ai.satfat) { $0.satfat = $1 }
        take(.sodium, ai.sodium) { $0.sodium = $1 }
        take(.cholesterol, ai.cholesterol) { $0.cholesterol = $1 }
        return (out, filled)
    }

    // MARK: Case B — front-of-pack identity (no nutrition)

    /// Extract only brand / food name / serving text from messy front-of-pack OCR.
    /// Never returns nutrition numbers. Falls back to a deterministic heuristic when
    /// the model is unavailable.
    static func identify(ocrLines: [String]) async -> LabelScan {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), LabelAI.isAvailable {
            do {
                let session = LanguageModelSession(instructions: Self.identityInstructions)
                let response = try await session.respond(
                    to: ocrLines.joined(separator: "\n"),
                    generating: IdentifiedProduct.self,
                    options: GenerationOptions(temperature: 0))
                let p = response.content
                let name = p.foodName.trimmingCharacters(in: .whitespacesAndNewlines)
                return LabelScan(
                    label: ParsedLabel(servingText: p.servingText),
                    brand: p.brand,
                    foodName: name.isEmpty ? nil : name,
                    usedAI: true)
            } catch { /* fall through to heuristic */ }
        }
        #endif
        return heuristicIdentity(ocrLines: ocrLines)
    }

    /// No-model fallback: the longest non-numeric line is the name; a short ALL-CAPS
    /// line is the brand. Deterministic and free.
    static func heuristicIdentity(ocrLines: [String]) -> LabelScan {
        let lines = ocrLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let nonNumeric = lines.filter { $0.rangeOfCharacter(from: .decimalDigits) == nil }
        let name = nonNumeric.max(by: { $0.count < $1.count })
        let brand = nonNumeric.first {
            $0.count <= 20 && $0 == $0.uppercased() && $0 != name && $0.contains(where: \.isLetter)
        }
        return LabelScan(label: ParsedLabel(), brand: brand, foodName: name)
    }

    // MARK: Prompts

    /// Case A session instructions (see docs/on-device-nutrition-autofill.md §7).
    static let nutritionInstructions = """
    You extract nutrition facts from raw OCR text of a nutrition label. OCR may have wrong spacing, \
    split lines, and misread characters. Output the structured schema only.
    Rules: (1) Report values for ONE serving. If both 'per serving' and 'per 100g' are shown, use the \
    per-serving column and set basis=perServing. If only per-100g is shown, copy those numbers and set \
    basis=per100g (the app rescales). (2) IGNORE all % Daily Value numbers — never put a %DV into a \
    gram/mg field. (3) Units: carbs, protein, fat, fibre, sugars, saturated fat, serving weight in \
    GRAMS; sodium and cholesterol in MILLIGRAMS (grams→mg = ×1000). (4) If a field is not printed, \
    return null — do NOT guess, estimate, or infer. (5) Never invent a brand or product name. \
    (6) Copy digits exactly; do not round or 'fix' values.
    """

    /// Case B session instructions: identity only, never nutrition.
    static let identityInstructions = """
    You read messy OCR text from the FRONT of a food package. Identify only the product. \
    Rules: (1) Return the brand and the product/food name, title-cased, with slogans and marketing \
    removed. (2) If a net-weight or serving text is printed (e.g. '500ml', '12 oz'), return it. \
    (3) Do NOT output any nutrition numbers. (4) If you cannot identify the name, return an empty \
    string; if you cannot identify the brand, return null. Never invent a brand or name.
    """
}
