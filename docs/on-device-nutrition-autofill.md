# On-Device Nutrition Autofill (Apple models, free, no cloud)

Research + design for the "camera → auto-fill custom food" feature in `ManualFoodEntryView`.
Everything here runs **100% on-device**: Apple's Vision framework (OCR) + the Foundation Models
on-device LLM. **No cloud, no API keys, no per-call cost, works offline.** This is a hard
requirement — the app ships free.

> Status: research complete (4 parallel agents, cited against Apple docs / WWDC). Not yet
> implemented. See "Implementation plan" and the handoff prompt at the end.

---

## 1. Goal & the two cases

User taps a camera control in `ManualFoodEntryView` and points at a product. Two situations:

- **Case A — a clear Nutrition Facts panel is visible.** Read it and fill calories + all macros +
  serving. (High value, high accuracy.)
- **Case B — only the front of pack is visible** (brand/food name faintly printed, no panel).
  Fill only the **identity** (brand + food name + serving text). **Never** invent nutrition numbers.

Barcode remains the strongest signal (already handled by the VisionKit `DataScanner`); this feature
is the fallback for products not in any database, or prepared/loose food.

---

## 2. Hard constraints from the research (read before designing)

These are the load-bearing facts. All verified against Apple developer docs / WWDC 2025.

1. **Foundation Models on iOS 26 is TEXT-ONLY.** `SystemLanguageModel` takes text, returns
   text/structured-text. It **cannot accept an image.** (Image/multimodal input was added in a later
   iOS 27 / WWDC 2026 update and needs newer hardware — do **not** design the iOS 26 baseline around
   it.) → We must OCR the image to text with **Vision**, then feed the **text** to the LLM.
2. **There is no public on-device vision-language model on iOS 26** for third parties. Visual
   Intelligence is a *system* experience (App Intents image-similarity only), not a
   "describe this image" API. So Case B is OCR-of-visible-text + optional coarse image
   classification + LLM text-normalization — not "look at the blurry package and name it."
3. **Availability is not guaranteed.** Foundation Models requires iOS 26 **+ Apple-Intelligence-
   eligible hardware** (iPhone 15 Pro / A17 Pro or later; all M-series iPad/Mac) **+ Apple
   Intelligence turned on + model downloaded**. Everything else returns `.unavailable`. → We must
   keep the existing regex parser as a first-class fallback and gate every call.
4. **4,096-token context budget** (input + output combined), and background use is throttled on
   battery. → Keep prompts terse; use `respond(to:)` (not streaming) if ever backgrounded.
5. **The model hallucinates** (~3B params, ~2023 cutoff). For a health app: instruct "return null,
   never guess", use guided generation (`@Generable`), and **always let the user review before Save.**

---

## 3. Architecture — both paths converge on `ParsedLabel`

The app already has (verified in-repo):

- `ParsedLabel` (`Salorie/Models/NutritionLabelParser.swift`): optional `Double`s —
  `servingText, servingGrams, calories, carbs, protein, fat, fibre, sugars, satfat, sodium, cholesterol`.
- `NutritionLabelParser.parse([String]) -> ParsedLabel` — the existing tolerant regex parser (unit-tested).
- `LabelScannerView` (`VNDocumentCameraViewController` + Vision OCR); its `Coordinator` currently calls
  `NutritionLabelParser.parse(lines)` (line ~39) and hands a `ParsedLabel` to `onResult`.
- `ManualFoodEntryView.apply(_ p: ParsedLabel)` prefills the form; `save()` builds `Food`
  (calories `Int`; carbs/protein/fat/fibre/sugars/saturatedFat in **g**; sodium/cholesterol in **mg**;
  `servingGrams: Double?`).

**Key design decision:** the AI path and the regex path both terminate in a `ParsedLabel`. We swap the
*producer*, never the *consumer* — `apply(_:)` / `save()` stay unchanged. AI is a quality boost, never a
correctness dependency.

```
Case A (nutrition panel)
  Camera/VNDocumentCamera → UIImage
    → Vision RecognizeDocumentsRequest (iOS 26, reads panel as a TABLE)   ← preferred
        else RecognizeTextRequest (.accurate, customWords, correction off) ← iOS 18–25 / no table
    → [String] OCR lines
    → if SystemLanguageModel available:
          LanguageModelSession.respond(generating: NutritionFacts.self, temp 0)
          → map → ParsedLabel   (regex result backfills any nil field)
       else:
          NutritionLabelParser.parse(lines)   ← today's behaviour, untouched
    → ManualFoodEntryView.apply(_:)  → USER REVIEWS → save()

Case B (front-of-pack, identity only)
  Camera photo
    → (optional) GenerateAttentionBasedSaliencyImageRequest → crop to product
    → Vision RecognizeTextRequest → messy [String]
    → (optional) ClassifyImageRequest → coarse category prior
    → if available: LLM generating IdentifiedProduct.self (NO nutrition fields)
       else: heuristic (longest non-numeric line = name; ALL-CAPS short line = brand)
    → ParsedLabel with only servingText (+ name/brand applied to the identity card)
```

**Case detection:** run the free regex parser first; if it finds calories + ≥2 macros → Case A.
Otherwise → Case B (identity only). Deterministic and free.

---

## 4. Vision OCR specifics (Case A)

- **iOS 26: `RecognizeDocumentsRequest`** returns the panel as a `DocumentObservation` with
  `.document.tables` → rows → cells (`cell.content.text.transcript`). Near-ideal: rows are
  pre-associated, so you don't re-pair label↔value by geometry. Also exposes `container.barcodes`
  (grab the UPC in the same pass).
- **iOS 18–25 fallback: `RecognizeTextRequest`** — settings that matter for a dense label:
  - `recognitionLevel = .accurate` (biggest lever for small type; `.fast` only for live preview)
  - `recognitionLanguages = [Locale.Language(identifier: "en-US")]`
  - `usesLanguageCorrection = false` for numeric extraction (correction mangles `0g`→`Og`, merges tokens)
  - `customWords = [nutrition lexicon…]` ("Total Fat", "Saturated Fat", "Cholesterol", "Sodium",
    "Dietary Fiber", "kcal", "mg", "mcg", "%DV", …)
  - `minimumTextHeightFraction ≈ 0.01–0.02` (fraction of image height; drops fine print).
    NOTE: modern API is `minimumTextHeightFraction`, **not** `minimumTextHeight`, and there is
    **no** `regionOfInterest` — crop the `CGImage` to the panel instead.
  - `topCandidates(3)` — when a value doesn't parse as number+unit, try the next candidate.
- **Preprocessing for curved/rotated/low-light:** prefer `VNDocumentCameraViewController` (system
  doc scanner: edge detection, auto-capture, perspective correction → flat high-res page). Or
  `DetectRectanglesRequest` + `CIPerspectiveCorrection`. Always OCR a **sharp still**, never a
  preview frame (blur drops decimals, confuses mg/mcg). The app already uses `VNDocumentCameraViewController`.

---

## 5. `@Generable` schemas (the LLM contract)

Guided generation constrains decoding to the schema and returns a **validated typed instance** — no
JSON parsing, no invented fields. Units are pinned in `@Guide` so the model normalizes, not our code.
Every field optional → the model returns `nil` for "not printed" (never a fabricated `0`).

```swift
import FoundationModels

/// Case A — a Nutrition Facts panel normalized to ONE serving.
@Generable
struct NutritionFacts {
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
    @Guide(description: "0.0-1.0 confidence the panel was legible and values are correct.")
    var confidence: Double
    @Generable enum Basis { case perServing, per100g, unknown }
}

/// Case B — identity only, structurally CANNOT emit nutrition (prevents hallucinated calories).
@Generable
struct IdentifiedProduct {
    @Guide(description: "Brand / manufacturer, title-cased. Null if not identifiable.")
    var brand: String?
    @Guide(description: "Product / food name, title-cased, without the brand and without slogans.")
    var foodName: String
    @Guide(description: "Serving/net-weight text if printed, e.g. '500ml'. Null otherwise.")
    var servingText: String?
}
```

Mapper (the only glue) — normalize per-100g→per-serving in Swift, keep arithmetic out of the model:

```swift
extension NutritionFacts {
    func toParsedLabel() -> ParsedLabel {
        let k: Double = (basis == .per100g && (servingGrams ?? 0) > 0) ? servingGrams! / 100 : 1
        func s(_ v: Double?) -> Double? { v.map { $0 * k } }
        return ParsedLabel(servingText: servingText, servingGrams: servingGrams,
            calories: s(calories), carbs: s(carbs), protein: s(protein), fat: s(fat),
            fibre: s(fibre), sugars: s(sugars), satfat: s(satfat),
            sodium: s(sodium), cholesterol: s(cholesterol))
    }
}
```

---

## 6. Availability gate + fallback

```swift
import FoundationModels

enum LabelAI {
    static var isAvailable: Bool {
        guard #available(iOS 26, *) else { return false }
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }
    @available(iOS 26, *)
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible):           return "This device can't run on-device AI."
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence to auto-fill."
        case .unavailable(.modelNotReady):               return "AI model still downloading — using basic scan."
        @unknown default:                                return "Using basic scan."
        }
    }
}

enum LabelExtractor {
    /// Always returns a ParsedLabel, so callers never branch.
    static func extract(ocrLines: [String]) async -> ParsedLabel {
        let regex = NutritionLabelParser.parse(ocrLines)          // free, deterministic
        guard #available(iOS 26, *), LabelAI.isAvailable else { return regex }
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let out = try await session.respond(
                to: Prompt(ocrLines.joined(separator: "\n")),
                generating: NutritionFacts.self,
                options: GenerationOptions(temperature: 0))         // deterministic
            return merge(ai: out.content.toParsedLabel(), regex: regex) // AI wins; regex backfills nils
        } catch { return regex }                                    // any failure → safe fallback
    }
}
```

Integration seam: `LabelScannerView.Coordinator` currently calls
`onResult(NutritionLabelParser.parse(lines))` — route it through `await LabelExtractor.extract(ocrLines: lines)`
instead (make the callback async / hop to a `Task`). Nothing downstream changes.

### Capability matrix

| | Case A (nutrition panel) | Case B (front-of-pack, identity) |
|---|---|---|
| **AI available** | OCR → LLM `NutritionFacts` (temp 0) → normalize units/basis → `ParsedLabel`; regex backfills nils | OCR (+ optional classify) → LLM `IdentifiedProduct` → prefill name/brand/serving; nutrition blank |
| **AI unavailable** | OCR → existing `NutritionLabelParser` → `ParsedLabel` (today's behaviour) | OCR → heuristic name/brand; user types the rest |

Terminal type is always `ParsedLabel`; consumer is always the unchanged `apply(_:)` → review → `save()`.

---

## 7. Prompt engineering (session `instructions`)

> "You extract nutrition facts from raw OCR text of a nutrition label. OCR may have wrong spacing,
> split lines, and misread characters. Output the structured schema only.
> Rules: (1) Report values for ONE serving. If both 'per serving' and 'per 100g' are shown, use the
> per-serving column and set basis=perServing. If only per-100g is shown, copy those numbers and set
> basis=per100g (the app rescales). (2) IGNORE all % Daily Value numbers — never put a %DV into a
> gram/mg field. (3) Units: carbs, protein, fat, fibre, sugars, saturated fat, serving weight in
> GRAMS; sodium and cholesterol in MILLIGRAMS (grams→mg = ×1000). (4) If a field is not printed,
> return null — do NOT guess, estimate, or infer. (5) Never invent a brand or product name.
> (6) Copy digits exactly; do not round or 'fix' values."

Levers: `temperature: 0` (reproducible); the "%DV trap" and "null-over-guess" rules are the two most
important; keep `basis` decision in the model but the arithmetic in Swift (`toParsedLabel`).

---

## 8. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Hallucinated numbers | null-over-guess (instructions + `@Guide`); optionals → nil not 0; Case B schema has no nutrition fields; **user reviews before Save** (never auto-commit) |
| Wrong units (mg↔g, %DV as grams) | units fixed in `@Guide`; g→mg rule; %DV-ignore; sanity checks in mapper (reject `carbs > servingGrams`; flag calories far from 4·C+4·P+9·F) |
| per-100g vs per-serving | `basis` enum + deterministic rescale only when `servingGrams` known |
| Latency (~seconds) | prefill regex instantly, then LLM refines (progressive fill); spinner; timeout → keep regex |
| Empty/blurry input | `confidence` + regex-found-nothing → "Couldn't read the label — enter manually" |
| Model unavailable mid-use | `LabelExtractor` re-checks each call → regex; `unavailableReason` hint |
| Privacy / App Review | 100% on-device, no network — strengthens free/private positioning; note in privacy manifest |

---

## 9. Implementation plan (phased)

- **Phase 0 — availability guard:** add `Salorie/Models/LabelAI.swift` (`isAvailable`, `unavailableReason`,
  behind `#available(iOS 26,*)`). Test: compiles and returns `false` on simulator / <iOS 26.
- **Phase 1 — schema + mapper:** add `Salorie/Models/NutritionFacts.swift` (both `@Generable` structs +
  `toParsedLabel()`). Tests: per-100g rescale, mg conversion, nil passthrough (pure, no model).
- **Phase 2 — extractor + fallback:** add `Salorie/Models/LabelExtractor.swift`
  (`extract(ocrLines:) async -> ParsedLabel`, `merge(ai:regex:)`). Route `LabelScannerView.Coordinator`
  through it. Test: with AI unavailable, output == `NutritionLabelParser.parse` exactly (regression guard).
- **Phase 3 — Case B identity:** OCR + optional `ClassifyImageRequest` → `IdentifiedProduct` → map
  name/brand/serving; UI prefills identity card, focuses Calories.
- **Phase 4 — UX polish:** progressive fill + spinner on cards; confidence-highlight LLM-filled fields;
  `unavailableReason` hint under the scan icon. Test: fields editable, Save still gated by `canSave`.

Files — **add:** `LabelAI.swift`, `NutritionFacts.swift`, `LabelExtractor.swift`,
`NutritionFactsMappingTests.swift`, `LabelExtractorTests.swift`. **Change:** `LabelScannerView.swift`
(route through extractor), `ManualFoodEntryView.swift` (spinner/confidence/hint — `apply`/`save`
unchanged), xcodegen/pbxproj for new files. **Untouched (fallback contract must keep passing):**
`NutritionLabelParser.swift`, `ParsedLabel`, `Food`, `NutritionLabelParserTests`.

Requires building against the iOS 26 SDK; `import FoundationModels` only exists there — keep it behind
`#available` / `canImport(FoundationModels)` so lower deployment targets still compile.

---

## 10. Sources

Foundation Models: developer.apple.com/documentation/FoundationModels · WWDC25 sessions 286, 301, 248 ·
guided generation: developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation ·
availability: .../systemlanguagemodel · languages: .../supporting-languages-and-locales-with-foundation-models ·
(image input is iOS 27: .../analyzing-images-with-multimodal-prompting).
Vision: developer.apple.com/documentation/vision · RecognizeTextRequest · RecognizeDocumentsRequest ·
WWDC25 session 272 (document reading) · classifyimagerequest · saliency.
VisionKit: DataScannerViewController · ImageAnalyzer · VNDocumentCameraViewController.
