import Foundation

/// Parsed values from a Nutrition Facts panel (all optional — OCR is imperfect).
struct ParsedLabel: Equatable {
    var servingText: String?
    var servingGrams: Double?
    var calories: Double?
    var carbs: Double?
    var protein: Double?
    var fat: Double?
    var fibre: Double?
    var sugars: Double?
    var satfat: Double?
    var sodium: Double?
    var cholesterol: Double?
}

/// Pure parser: turns OCR'd Nutrition Facts text into structured values via
/// tolerant regexes (OCR spacing/casing is unreliable). Unit-tested.
enum NutritionLabelParser {
    static func parse(_ lines: [String]) -> ParsedLabel { parse(lines.joined(separator: "\n")) }

    static func parse(_ raw: String) -> ParsedLabel {
        let text = raw.replacingOccurrences(of: ",", with: "")   // "1,000mg" → "1000mg"
        var out = ParsedLabel()
        out.calories    = num(#"calories[^0-9]{0,12}([0-9]{1,4})"#, text)
        out.fat         = num(#"total\s*fat[^0-9]{0,8}([0-9]+(?:\.[0-9]+)?)"#, text)
        out.satfat      = num(#"sat(?:urated)?\.?\s*fat[^0-9]{0,8}([0-9]+(?:\.[0-9]+)?)"#, text)
        out.cholesterol = num(#"cholesterol[^0-9]{0,8}([0-9]+(?:\.[0-9]+)?)"#, text)
        out.sodium      = num(#"sodium[^0-9]{0,8}([0-9]+(?:\.[0-9]+)?)"#, text)
        out.carbs       = num(#"(?:total\s*)?carb(?:ohydrate)?s?[^0-9]{0,8}([0-9]+(?:\.[0-9]+)?)"#, text)
        out.fibre       = num(#"(?:dietary\s*)?fib(?:er|re)[^0-9]{0,8}([0-9]+(?:\.[0-9]+)?)"#, text)
        out.sugars      = num(#"total\s*sugars?[^0-9]{0,8}([0-9]+(?:\.[0-9]+)?)"#, text)
                            ?? num(#"sugars?[^0-9]{0,8}([0-9]+(?:\.[0-9]+)?)"#, text)
        out.protein     = num(#"protein[^0-9]{0,8}([0-9]+(?:\.[0-9]+)?)"#, text)
        // Serving grams: prefer a parenthesized "(272g)"; else "serving size … 272 g".
        out.servingGrams = num(#"\(([0-9]+(?:\.[0-9]+)?)\s*g\)"#, text)
                            ?? num(#"serving size[^0-9]{0,24}([0-9]+(?:\.[0-9]+)?)\s*g"#, text)
        out.servingText  = firstGroup(#"serving size[:\s]+(.+)"#, raw)?.trimmingCharacters(in: .whitespaces)
        return out
    }

    // MARK: Regex helpers

    private static func num(_ pattern: String, _ text: String) -> Double? {
        firstGroup(pattern, text).flatMap { Double($0) }
    }

    private static func firstGroup(_ pattern: String, _ text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
