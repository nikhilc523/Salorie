# Technical Specification: "MiniLog" — A Minimal, Accuracy-First iOS Calorie & Meal Tracker

**Version 1.0 · Draft · September 22, 2026 · Target: iOS 26 minimum, iOS 27 features**

---

## 1. Overview & Scope

MiniLog is a private, iOS-only (Swift/SwiftUI) calorie and meal tracker for the author and a handful of friends, distributed via TestFlight. It is deliberately minimal: search, scan, log, re-log, write to Apple Health, and log by voice with Siri. No social, coaching, goals/gamification, or photo-AI recognition.

**Design principles:**
1. **Accuracy first.** Prefer lab-analyzed generic data (USDA Foundation/SR Legacy) and structured branded data (USDA Branded, Open Food Facts) over crowd-sourced guesses. Show the data source on every entry, like Cronometer.
2. **Completely free to run.** Only free/public-domain/open data sources. No Nutritionix, no NCCDB (both paid).
3. **Unlimited scans.** Bundle/host the databases; never depend on per-scan rate-limited live APIs.
4. **Clean, minimal UI.** iOS 26/27 "Liquid Glass" design; ~4 primary screens.

**Why database-driven, not photo-AI:** A study presented by Olivia Charles and Aaron Hengist (NIDDK/NIH) at the NUTRITION 2026 President's Oral Session on July 25, 2026 (National Harbor, MD), using photos of 102 meals from a controlled metabolic kitchen, found photo-based apps systematically underestimated intake. Per EurekAlert (news-release 1136415): "All four apps underestimated the calorie content of meals by about 250 to 345 calories, on average, and fat by about 30 grams." That is roughly a one-third (~33%) shortfall — a *consistent, directional* error that does not average out over time, which is exactly what makes it dangerous for daily tracking. This justifies structured database logging over photo AI.

**Per-app breakdown (Healio, Aug 4, 2026):** "Appediet by 252 kcal (95% CI, 295 to 210), MyFitnessPal by 327 kcal (95% CI, 385 to 269), Lose It! by 333 kcal (95% CI, 383 to 282) and Cal AI by 345 kcal (95% CI, 392 to 296)." (Note: this was a conference abstract, considered preliminary until peer-reviewed publication.)

**Accuracy evidence for the database approach:** Morello et al. (2025, *J Hum Nutr Diet* 38(5):e70148), studying 43 three-day food records from Canadian endurance athletes against the Canadian Nutrient File reference, found Cronometer had excellent inter-rater reliability (ICC 0.966 energy, 0.977 carbs) and good validity for most nutrients (except fiber, vitamin A, vitamin D), while MyFitnessPal had low reliability and validity for most nutrients. Cronometer's accuracy comes from using USDA and NCCDB lab-analyzed data rather than crowd-sourced entries — MiniLog replicates the *free* half of that strategy (USDA + structured branded data).

---

## 2. MVP User Stories & Acceptance Criteria

### US-1 Search to add a food
As a user, I can type a food name and get ranked results from the bundled database.
- **AC:** Results appear as I type (debounced); each row shows name, brand (if any), kcal per default serving, and a **source label** (USDA Foundation / SR Legacy / Branded / OFF). Generic lab-analyzed foods rank above branded/crowd-sourced when relevance is comparable.

### US-2 Barcode scan to add a packaged food
As a user, I can scan a product barcode and get the exact product.
- **AC:** Scanning an EAN-13/UPC-A/UPC-E/EAN-8 barcode resolves to a specific product with its label serving size. If not found locally, the app does an optional live OFF/USDA lookup, then offers label-OCR/manual entry saved to My Items.

### US-3 My Items (quick re-log)
As a user, when I log an item I can save it to "My Items" so I can re-log it in one tap with the same size/quantity next time.
- **AC:** Saving stores the food reference plus chosen serving/unit/quantity. Re-logging from My Items requires one tap and pre-fills the last-used quantity.

### US-4 Size & quantity selection
As a user, I can pick a serving size/portion and adjust quantity (servings, g, oz, ml, units).
- **AC:** Scanning a Diet Mountain Dew can resolves to that exact size; searching "Diet Mountain Dew" lets me pick among available sizes (12 oz can, 20 oz bottle, etc.). Nutrients recompute live for any quantity/unit.

### US-5 Apple Health integration
As a user, my logged nutrition is written to Apple Health, and edits/deletes stay in sync.
- **AC:** Each logged item writes an `HKCorrelation` of type `.food` containing per-nutrient `HKQuantitySample`s. Editing/deleting in MiniLog updates/removes the matching HealthKit objects.

### US-6 Siri voice logging (iOS 27)
As a user, I can say "Hey Siri, log a Diet Mountain Dew in MiniLog" and have it logged without opening the app.
- **AC:** An App Intent logs the item in the background, disambiguating size if needed, and confirms via Siri. A plain App Shortcut phrase works even on devices without Apple Intelligence.

---

## 3. Data Sources (Free vs Paid, License, Format, Size, Cadence)

| Source | Free/Paid | License | Format | Size | Update cadence | Use in MiniLog |
|---|---|---|---|---|---|---|
| **USDA FoodData Central — Foundation Foods** | **FREE** | CC0 1.0 (public domain) | CSV/JSON | Dec 2025 CSV ~29 MB unzipped (~3.4 MB zip) | Twice yearly (Apr & Oct) | Primary generic/lab-analyzed |
| **USDA FDC — SR Legacy** | **FREE** | CC0 1.0 | CSV/JSON | Apr 2018 CSV ~54 MB unzipped (~6.7 MB zip) | Static (last Apr 2018) | Generic fallback (broad coverage) |
| **USDA FDC — Branded Foods** | **FREE** | CC0 1.0 | CSV/JSON | Dec 2025 CSV ~2.9 GB unzipped (~427 MB zip) | Monthly (API); download twice yearly | Barcode (US, gtin_upc) |
| **USDA FDC — FNDDS/Survey** | **FREE** | CC0 1.0 | CSV/JSON | FNDDS 2021-2023 CSV ~1.6 GB unzipped | ~Every 2 years | Optional mixed-dish generics |
| **USDA FDC — Full download** | **FREE** | CC0 1.0 | CSV | ~3.1 GB unzipped (~458 MB zip) | — | Convenience full pull |
| **Open Food Facts** | **FREE** | ODbL (DB) + DbCL (contents); images CC-BY-SA | JSONL.gz, CSV.gz, Parquet (HF), MongoDB | JSONL ~10–43 GB uncompressed; CSV.gz ~0.9 GB (~9 GB uncompressed); Parquet smaller | Nightly (full + delta) | Barcode (global) |
| **Nutritionix** | **PAID** | Commercial | API | — | — | **Excluded** (no free tier) |
| **NCCDB (U. Minnesota)** | **PAID** | Proprietary license | Files (no API) | ~20,000 foods, 178 nutrients | — | **Excluded** (paid) |
| **Canadian Nutrient File (CNF)** | **FREE** | Open Government Licence – Canada | CSV/Excel ZIP, API | ~5,700 foods | Periodic | Optional generic supplement |
| **UK CoFID (McCance & Widdowson)** | **FREE** | Open Government Licence (CC-BY compatible) | Excel | — | Periodic | Optional generic supplement |
| **Dutch NEVO** | **FREE (agreement)** | RIVM custom use agreement | Download | version 2025/9.0 | Periodic | Optional (check commercial terms) |
| **Australian AUSNUT/NUTTAB (FSANZ)** | **FREE** | CC BY-SA 3.0 AU (ShareAlike) | Files/API | — | Periodic | **Avoid** (ShareAlike copyleft risk) |
| **Irish IFCDB (UCC)** | **FREE (online)** | Not publicly documented for bulk | Online/EuroFIR | ~938 foods | — | Skip (no clear bulk license) |

**Coverage scale:** Open Food Facts "contains around 4,000,000 products in more than 180 countries" (30+ countries with >10,000 products; 8 with >100,000), per Open Food Facts' press page (world.openproductsfacts.org/press). USDA FoodData Central holds "over 400,000 food entries" per the USDA National Agricultural Library (nal.usda.gov), of which the Global Branded Food Products Database alone is "industry-provided label data for over 350,000 foods" (USDA/PMC8182005).

**Recommendation:** Ship **USDA Foundation + SR Legacy** (generic search) + **USDA Branded** (US barcodes) + **Open Food Facts** (global barcodes) as the core. All three are free and permissively licensed. CNF/CoFID are optional free add-ons. Exclude Nutritionix and NCCDB (paid — these are exactly the sources Cronometer pays for). Avoid NUTTAB (ShareAlike copyleft).

### License implications for a friends-only app
- **USDA (CC0):** Public domain. No restrictions; USDA requests (not requires) attribution: cite "U.S. Department of Agriculture, Agricultural Research Service. FoodData Central."
- **Open Food Facts (ODbL/DbCL):** Per the official OFF data page (world.openfoodfacts.org/data), the ODbL requires attribution in the form **"Contains data from Open Food Facts, available under the Open Database License,"** and if an app "allows users to add new products, update nutrition/ingredients, or submit photos, please send those contributions back to Open Food Facts via our API or SDKs." For a private friends-only app that redistributes a derived database, attribute OFF and note the ODbL; if you add a "correct this product" feature, contribute those edits back via the OFF API.

---

## 4. USDA FoodData Central — In Depth

**Download page:** fdc.nal.usda.gov/download-datasets. Current releases (as of the Dec 2025 download; FDC version 15.x through 2026):
- Foundation Foods 12/2025, SR Legacy 04/2018, FNDDS 2021-2023 (10/2024), Branded 12/2025.
- File formats: CSV (Excel-compatible ASCII) and JSON. All archives include supporting data since April 2023.
- **Update cadence:** Foundation twice yearly (April and October); Branded updated monthly in the API, but download files refreshed twice yearly (April/October), though recent releases have shipped monthly version bumps (14.1–15.4 across 2026).
- **Branded note (Apr 2026, v14.4):** A new data source "EM" (Euromonitor International) was added to branded foods, displayed with the contribution "Provided by Euromonitor International."

**Key tables/fields (confirmed against the USDA data dictionary):**
- `food`: `fdc_id`, `data_type`, `description`, `food_category_id`, `publication_date`.
- `food_nutrient`: `id`, `fdc_id`, `nutrient_id`, `amount` (per 100 g), `data_points`, `derivation_id`, `min`, `max`, `median`.
- `nutrient`: nutrient definitions.
- `food_portion`: portion/household measures (`amount`, `modifier`, `gram_weight`, `portion_description`, `measure_unit_id`) — used for generic serving sizes.
- `branded_food`: `fdc_id`, `brand_owner`, `gtin_upc`, `ingredients`, `serving_size`, `serving_size_unit` (g or ml), `household_serving_fulltext`, `branded_food_category`, `data_source` (GDSN or LI), `modified_date`, `available_date`, `discontinued_date`, `market_country`. (Note: a separate `brand_name` column is **not** confirmed in the current dictionary — verify against the exact release you build from; `brand_owner` is confirmed.)

**Nutrient IDs (confirmed via USDA docs/API):**
- Energy (kcal) = **1008** (legacy nbr 208)
- Energy, Atwater General Factors = **2047**
- Energy, Atwater Specific Factors = **2048**
- Protein = **1003**; Total lipid (fat) = **1004**; Carbohydrate, by difference = **1005**
- Fiber, total dietary = **1079**; Sugars, total incl. NLEA = **2000**; Sodium = **1093**

**Energy calculation caveat:** Foundation Foods may report energy via multiple methods — pick 1008 (kcal) first; if absent, fall back to 2048 (Atwater Specific), then 2047 (Atwater General). Different foods use different Atwater/Jones factors, so do not assume one conversion.

**API (for optional live lookups only, not per-scan core):**
- Base: `https://api.nal.usda.gov/fdc/v1/` — endpoints `/foods/search`, `/food/{fdcId}`, `/foods`, `/foods/list`.
- **Rate limit: 1,000 requests/hour per IP** with a free data.gov key; DEMO_KEY is ~30/hour. Exceeding returns HTTP 429 and blocks the key for 1 hour. **Never ship DEMO_KEY** (all users behind a NAT share the bucket).
- License CC0. Data is **US-centric**; branded data is manufacturer-submitted (voluntary) so it can have quality gaps and stale entries.

---

## 5. Open Food Facts — In Depth

**Exports (nightly):** JSONL.gz (same data as the MongoDB dump), CSV.gz, Parquet (via Hugging Face `openfoodfacts/product-database`), MongoDB dump, plus daily delta files. Delta files cannot express deletions — periodically re-import the full dump to purge deleted products.
- **Sizes:** JSONL ~10–43 GB uncompressed depending on fields; CSV.gz ~0.9 GB compressed (~9 GB uncompressed). Parquet is column-filtered and smallest for analytics with DuckDB.
- **Products:** ~4,000,000 across 180+ countries.

**License:** Database under **ODbL**; contents under **DbCL**; images CC-BY-SA. Attribution required (see §3).

**API rate limits (for optional live lookups):** OFF asks that apps needing more than a few hundred products **download the bulk exports** rather than crawl. Global rate limits apply irrespective of IP; exceeding returns HTTP 503. Product read endpoint: `https://world.openfoodfacts.org/api/v2/product/{barcode}.json`. Always send a descriptive `User-Agent` (e.g., `MiniLog/1.0 (email)`).

**Nutriments fields (critical):**
- Every nutrient has `_100g` and `_serving` variants: `energy-kcal_100g`, `energy-kcal_serving`, `proteins_100g`, `carbohydrates_100g`, `fat_100g`, `sugars_100g`, `salt_100g` (note: **salt**, not sodium — sodium ≈ salt/2.5).
- **Energy trap:** the bare `energy` field is in **kJ** (e.g., Coca-Cola `energy`=180 is kJ; `energy-kcal`=42). Always read `energy-kcal_*`. Do not assume a fixed kJ↔kcal ratio (~4.184) because label regulations differ.
- Serving denominator: `serving_size` (printed string, e.g., "240 ml") + parsed `serving_quantity` / `serving_quantity_unit`. May be null.
- `nutrition_data_per` = `100g` or `serving`.

**Data quality:** Crowd-sourced — many products missing nutrition fields (the `completeness` field indicates how filled a record is). Filter out records with null `energy-kcal_100g` for search. Coverage strongest in Europe (esp. France); weaker in the US, where USDA Branded is better.

**Barcode field:** `code` (EAN-13 or internal codes; products without a barcode get a number with the reserved `200` prefix).

---

## 6. Barcode Matching & Normalization

**Symbologies to scan:** EAN-13, UPC-A, UPC-E, EAN-8 (all supported by VisionKit/Vision).

**Normalization strategy — store everything as GTIN-14 internally:**
- **UPC-A (12 digits):** left-pad with two zeros to GTIN-14 (or one zero to EAN-13). A UPC-A is an EAN-13 with a leading 0.
- **EAN-13 (13 digits):** left-pad one zero to GTIN-14.
- **EAN-8 (8 digits):** left-pad to GTIN-14.
- **UPC-E (compressed 6/8 digits):** **expand to UPC-A (12 digits) first** using standard zero-suppression rules, then to GTIN-14. iOS returns the symbology so you know when to expand.

**Matching:** When a code is scanned, normalize to GTIN-14, then try in priority order: (1) USDA Branded `gtin_upc` (also normalized), (2) Open Food Facts `code`. USDA `gtin_upc` values may be stored as UPC-A or EAN-13; normalize both sides before comparing. Handle **duplicate/conflicting entries** by preferring: exact-market USDA Branded (US) → OFF record with highest `completeness` → most recently modified. Show the source label so the user can tell.

**Label OCR fallback:** If no barcode match, offer nutrition-label OCR using the **Vision framework** text recognition (or the iOS 27 `OCRTool` available to Foundation Models) to parse the Nutrition Facts panel; the user confirms values; save to My Items as a custom food.

---

## 7. Serving Size & Quantity Math

**Canonical storage:** Store all nutrients **per 100 g (or per 100 ml)** internally (USDA `food_nutrient.amount` is already per 100 g; OFF `_100g` fields are per 100 g/ml). This makes arbitrary quantity math trivial.

**Portion options presented to the user:**
- **Branded (USDA):** `serving_size` + `serving_size_unit` (g/ml) and `household_serving_fulltext` (e.g., "1 can (355 ml)"). Offer: the label serving, 100 g/ml, grams, oz, ml, and "units" (= N servings).
- **Branded (OFF):** `serving_quantity` (+unit) and `serving_size` string. Same options.
- **Generic (USDA Foundation/SR Legacy):** `food_portion` rows give household measures (`gram_weight` per `modifier`/`portion_description`), e.g., "1 cup = 240 g". Offer each portion + grams/oz.

**Computation:** For any chosen quantity, convert to grams (or ml) then:
`nutrient = nutrient_per_100g × (grams_selected / 100)`.
Unit conversions: 1 oz = 28.3495 g; 1 fl oz ≈ 29.5735 ml; "1 unit"/"1 serving" = `serving_size` grams/ml × quantity. For volume products with density ~1 (drinks), ml≈g is acceptable but prefer the label serving in ml.

**Example — Diet Mountain Dew:**
- Scan a 12 oz (355 ml) can → USDA Branded record → `serving_size`=355, `serving_size_unit`=ml, 0 kcal/100 ml → 0 kcal for the can.
- Search "Diet Mountain Dew" → show the 12 oz can and 20 oz (591 ml) bottle as separate records/portions; user picks size and quantity (e.g., 2 cans).

---

## 8. Data Model (SwiftData) & My Items

Use **SwiftData** for user data (log entries, My Items, custom foods). Keep the read-only food database in a separate **bundled SQLite (GRDB) with FTS5** for search (see §11). Optional CloudKit private sync via SwiftData's cloud option.

```swift
import SwiftData

@Model final class LoggedItem {
    var id: UUID
    var date: Date
    var mealType: String?          // optional: breakfast/lunch/dinner/snack
    // Food identity (denormalized snapshot so DB edits don't change history)
    var foodName: String
    var brand: String?
    var sourceLabel: String        // "USDA Foundation", "USDA Branded", "OFF", "Custom"
    var sourceID: String?          // fdcId or OFF barcode
    // Chosen portion
    var quantity: Double
    var unit: String               // "g","ml","oz","serving","unit"
    var gramsResolved: Double      // canonical grams/ml used for math
    // Nutrient snapshot (as logged)
    var kcal: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double?
    var sugarG: Double?
    var sodiumMg: Double?
    // HealthKit sync
    var hkFoodCorrelationUUID: UUID?   // for edit/delete sync
    var hkSyncVersion: Int
}

@Model final class MyItem {          // quick re-log
    var id: UUID
    var foodName: String
    var brand: String?
    var sourceLabel: String
    var sourceID: String?
    var lastQuantity: Double
    var lastUnit: String
    var per100gKcal: Double
    var per100gProtein: Double
    var per100gCarbs: Double
    var per100gFat: Double
    var per100gFiber: Double?
    var per100gSugar: Double?
    var per100gSodiumMg: Double?
    var lastUsed: Date
}

@Model final class CustomFood {      // manual / label-OCR entry
    var id: UUID
    var name: String
    var brand: String?
    var barcode: String?
    var per100gKcal: Double
    // ...same per-100g macro fields...
    var defaultServingG: Double?
    var householdServingText: String?
}
```

My Items stores per-100g values plus last-used quantity/unit so re-log recomputes exactly and remembers the chosen size.

---

## 9. HealthKit Integration

**Entitlement:** Add the **HealthKit** capability in Xcode (adds `com.apple.developer.healthkit`). **Info.plist strings:** `NSHealthUpdateUsageDescription` (write) and, if reading back, `NSHealthShareUsageDescription`.

**Types written** (`HKQuantityTypeIdentifier`), wrapped in an `HKCorrelation` of type `HKCorrelationType(.food)`:
- `.dietaryEnergyConsumed` (unit: `.largeCalorie()` = kcal)
- `.dietaryProtein`, `.dietaryCarbohydrates`, `.dietaryFatTotal` (unit: `.gram()`)
- `.dietaryFiber`, `.dietarySugar` (grams), `.dietarySodium` (milligrams)

**Metadata:** `HKMetadataKeyFoodType` = food name; add a stable app key (e.g., `"MiniLogItemID"` = LoggedItem.id) so edits/deletes can find the correlation. Use `HKMetadataKeySyncIdentifier` + `HKMetadataKeySyncVersion` so re-saving an edited item supersedes the prior version.

**Why HKCorrelation (not loose samples):** Cronometer's own users have filed bugs noting that logging loose, unstructured samples means other apps (Apple Health, Guava) can't tell what food was eaten — they just see disconnected nutrient points. A `.food` correlation groups all nutrients into one "food" with a `HKMetadataKeyFoodType`. Do this from day one.

**Authorization flow:**
```swift
import HealthKit
let store = HKHealthStore()

let shareTypes: Set = [
    HKQuantityType(.dietaryEnergyConsumed),
    HKQuantityType(.dietaryProtein),
    HKQuantityType(.dietaryCarbohydrates),
    HKQuantityType(.dietaryFatTotal),
    HKQuantityType(.dietaryFiber),
    HKQuantityType(.dietarySugar),
    HKQuantityType(.dietarySodium),
    HKCorrelationType(.food)
]

func requestAuth() async throws {
    guard HKHealthStore.isHealthDataAvailable() else { return }
    try await store.requestAuthorization(toShare: shareTypes, read: [])
}
```

**Saving a food correlation:**
```swift
func saveFood(_ item: LoggedItem) async throws {
    var samples = Set<HKSample>()
    let start = item.date, end = item.date
    func q(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ v: Double?) {
        guard let v else { return }
        samples.insert(HKQuantitySample(type: HKQuantityType(id),
            quantity: HKQuantity(unit: unit, doubleValue: v), start: start, end: end))
    }
    q(.dietaryEnergyConsumed, .largeCalorie(), item.kcal)
    q(.dietaryProtein, .gram(), item.proteinG)
    q(.dietaryCarbohydrates, .gram(), item.carbsG)
    q(.dietaryFatTotal, .gram(), item.fatG)
    q(.dietaryFiber, .gram(), item.fiberG)
    q(.dietarySugar, .gram(), item.sugarG)
    q(.dietarySodium, .gramUnit(with: .milli), item.sodiumMg)

    let meta: [String: Any] = [
        HKMetadataKeyFoodType: item.foodName,
        HKMetadataKeySyncIdentifier: item.id.uuidString,
        HKMetadataKeySyncVersion: item.hkSyncVersion
    ]
    let food = HKCorrelation(type: HKCorrelationType(.food),
                             start: start, end: end, objects: samples, metadata: meta)
    try await store.save(food)
    item.hkFoodCorrelationUUID = food.uuid
}
```

**Edit/delete sync:** On edit, either (a) re-save with the same `HKMetadataKeySyncIdentifier` and an incremented `HKMetadataKeySyncVersion` (HealthKit supersedes the old one), or (b) query the old correlation by `HKMetadataKeySyncIdentifier` predicate, `store.delete(...)`, then save fresh. On delete in MiniLog, delete the correlation.

**iOS 26/27 note:** Nutrition type identifiers and `HKCorrelationType(.food)` are unchanged and current in iOS 26/27. No breaking HealthKit changes to dietary types were identified; verify against the final iOS 27 release notes before shipping.

**Privacy:** HealthKit data must never be used for advertising or sold; must not sync to iCloud via generic mechanisms; disclose in the App/TestFlight privacy details that health data is written locally to Apple Health. HealthKit apps require a privacy policy.

---

## 10. Siri / App Intents Integration (iOS 27)

### 10.1 Platform reality (WWDC 2026)
At WWDC 2026 (June 8–9), Apple made **App Intents the only way Siri can call into a third-party app**; SiriKit received a formal deprecation/"legacy" notice with a roughly two-to-three-year migration window, and the rebuilt Siri is Apple-Intelligence/Gemini-backed. (Caveat: as of Sept 14, 2026 some observers found SiriKit symbols labeled "legacy" in prose but **not** yet annotated as `deprecated` in the SDK metadata — regardless, App Intents is the forward path.) **MiniLog should implement App Intents from day one; do not use SiriKit.**

### 10.2 Is there a nutrition/food-logging App Schema domain?
**No.** The App Schema domains in iOS 27 are: **12 primary domains** — Audio, Calendar, Camera, Clock, Mail, Maps, Messages, Notes, Phone, Photos, Reminders, and "System and in-app search"; **2 single-purpose domains** — Assistant and Visual Intelligence; and **9 Shortcuts-specific domains** — books, browsers, files, journaling, presentations, readers, spreadsheets, whiteboards, word processors. **There is no health/fitness/nutrition/food-logging schema domain.** (Flag: this may change in a future release — re-check the app-schema-domains documentation before each release.)

**Implication:** MiniLog cannot adopt a predefined `@AssistantIntent(schema:)` for food logging. Instead, use a **custom `AppIntent` + `AppShortcutsProvider`** with natural-language phrases (this still integrates fully with Siri, Spotlight, and Shortcuts). Optionally adopt the "System and in-app search" schema so Siri/Spotlight can surface My Items search.

### 10.3 Architecture
- **`LogFoodIntent`** (custom `AppIntent`) — logs a food. `openAppWhenRun = false` so it runs in the background without opening the app.
- **`FoodEntity`** (`AppEntity` + `IndexedEntity`) — represents a My Item / known food; indexed into Spotlight's semantic index so Siri can resolve "Diet Mountain Dew" to a saved item.
- **`FoodEntityQuery`** (`EntityStringQuery`) — resolves a spoken/typed string to candidate `FoodEntity`s.
- **`MiniLogShortcuts`** (`AppShortcutsProvider`) — phrases; each phrase must include `\(.applicationName)`; max 1 parameter per phrase; 1,000-phrase budget total.
- **Disambiguation:** if multiple sizes match, use `requestDisambiguation` on a size parameter; **confirmation** via `requestConfirmation` before writing.

### 10.4 Code skeleton
```swift
import AppIntents

// Size options for a food
enum ServingChoice: String, AppEnum {
    case can12oz, bottle20oz, oneServing, grams
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Serving")
    static var caseDisplayRepresentations: [ServingChoice: DisplayRepresentation] = [
        .can12oz: "12 oz can", .bottle20oz: "20 oz bottle",
        .oneServing: "1 serving", .grams: "grams"
    ]
}

struct FoodEntity: AppEntity, IndexedEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Food")
    static var defaultQuery = FoodEntityQuery()
    var id: String                 // fdcId or OFF barcode or MyItem UUID
    @Property(title: "Name") var name: String
    var brand: String?
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: brand.map { "\($0)" } ?? "")
    }
}

struct FoodEntityQuery: EntityStringQuery {
    func entities(for ids: [String]) async throws -> [FoodEntity] {
        FoodStore.shared.foods(withIDs: ids)
    }
    func entities(matching string: String) async throws -> [FoodEntity] {
        FoodStore.shared.searchMyItemsAndDB(string)   // prefer My Items, then DB
    }
    func suggestedEntities() async throws -> [FoodEntity] {
        FoodStore.shared.recentMyItems()
    }
}

struct LogFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Food"
    static let openAppWhenRun = false                 // run in background
    static var isDiscoverable = true

    @Parameter(title: "Food") var food: FoodEntity
    @Parameter(title: "Quantity", default: 1) var quantity: Double
    @Parameter(title: "Serving") var serving: ServingChoice?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Disambiguate size if the food has multiple and none chosen
        let sizes = FoodStore.shared.servingOptions(for: food)
        let chosen: ServingChoice
        if let serving { chosen = serving }
        else if sizes.count > 1 {
            chosen = try await $serving.requestDisambiguation(
                among: sizes, dialog: "Which size?")
        } else { chosen = sizes.first ?? .oneServing }

        let logged = try await FoodStore.shared.log(food, quantity: quantity, serving: chosen)
        try await HealthKitWriter.shared.saveFood(logged)   // writes HKCorrelation
        return .result(dialog: "Logged \(Int(logged.kcal)) calories of \(food.name).")
    }
}

struct MiniLogShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogFoodIntent(),
            phrases: [
                "Log \(\.$food) in \(.applicationName)",
                "Log a \(\.$food) in \(.applicationName)",
                "Add \(\.$food) to \(.applicationName)"
            ],
            shortTitle: "Log Food",
            systemImageName: "fork.knife"
        )
    }
}
```
Call `MiniLogShortcuts.updateAppShortcutParameters()` whenever My Items change so Siri's parameter options stay current.

### 10.5 Natural-language parsing with Foundation Models (optional, free)
For phrases like "two cans of diet mountain dew and a banana," use the **Foundation Models framework** (iOS 26+, free, on-device, no API key) with **guided generation** (`@Generable`) to parse text into structured `{name, quantity, unit}` items, then map each to a `FoodEntity`. iOS 27 adds image input, `OCRTool`, and `BarcodeReaderTool` that the model can call on-device.

- **Device requirement:** an Apple-Intelligence-capable device (iPhone 15 Pro / A17 Pro or later; Apple Intelligence enabled in Settings; feature available in region). The ~3B on-device model is for focused tasks, not world knowledge.
- **Fallback:** Devices without Apple Intelligence return non-available from `SystemLanguageModel.default.availability`. Branch the UI: if unavailable, fall back to plain App Shortcut phrases (single item + quantity) and in-app search. Treat the model as a feature flag, not a guarantee.

```swift
import FoundationModels

@Generable struct ParsedFoodItem {
    @Guide(description: "food name") var name: String
    @Guide(description: "count/quantity") var quantity: Double
    @Guide(description: "unit e.g. can, g, serving") var unit: String
}

func parse(_ phrase: String) async throws -> [ParsedFoodItem] {
    guard case .available = SystemLanguageModel.default.availability else {
        return fallbackRegexParse(phrase)     // non-AI path
    }
    let session = LanguageModelSession()
    let out = try await session.respond(
        to: "Extract food items with quantities from: \(phrase)",
        generating: [ParsedFoodItem].self)
    return out.content
}
```

### 10.6 Testing
Use the **AppIntentsTesting** framework (WWDC26 session 295) to unit-test intent resolution, disambiguation, and `perform()` without the UI. Test on a device with and without Apple Intelligence.

**Key WWDC26 references:** Session 240 "Build intelligent Siri experiences with App Schemas"; Session 343 "Explore advanced App Intents features for Siri and Apple Intelligence"; Session 344 "Code-along: Make your app available to Siri"; Session 295 "Validate your App Intents adoption with AppIntentsTesting."

---

## 11. Architecture: On-Device vs Backend

**Recommendation: bundle a trimmed, read-only SQLite (FTS5) database on-device; refresh via Background Assets. No backend required at the friends-only scale.**

### Why on-device
- Guarantees **unlimited scans/search** with zero API dependency (satisfies the hard requirement).
- The full raw data is huge (USDA Branded ~2.9 GB, OFF ~9 GB CSV), but **after trimming** to only the fields MiniLog needs (barcode, name, brand, serving, and ~8 nutrients), a combined USDA Foundation+SR Legacy+Branded+high-completeness OFF subset compresses dramatically. Realistic target: **a few hundred MB to ~1–2 GB SQLite** depending on how much of OFF/Branded you keep. Trimming levers: keep only US + friends' countries for OFF; drop products with null `energy-kcal_100g`; keep 8–12 nutrients not 140.

### Pipeline (download → trim → build SQLite → ship/update)
1. **Download** USDA CSVs (Foundation, SR Legacy, Branded) + OFF Parquet/JSONL.
2. **Trim/transform** with **DuckDB** (reads Parquet/CSV/JSONL fast): select needed columns, filter null-energy, normalize barcodes to GTIN-14, normalize all nutrients to per-100g, unify into one `foods` + `nutrients` schema with a `source` column.
3. **Build SQLite** with an **FTS5** virtual table over `name`+`brand` for typo-tolerant prefix search; store per-100g nutrients and portion rows.
4. **Ship**: bundle a base DB in the app; deliver updates via **Background Assets** (Apple-hosted) or **On-Demand Resources** so the multi-hundred-MB DB isn't in the initial App/TestFlight download.
5. **Refresh cadence:** rebuild when USDA releases (Apr/Oct) and monthly for OFF/Branded; push a new asset version. For a handful of users, a manually rebuilt asset every 1–3 months is fine.

### Backend comparison (only if you later want server-side updates)
| Option | Free tier (2026) | Fit |
|---|---|---|
| **CloudKit public DB** | Free with the Apple Developer account; generous per-app quota | Best "free + Apple-native" for hosting the food DB and private user sync |
| **Cloudflare R2 + Workers** | R2 free storage tier + Workers free req/day | Great for hosting the SQLite asset file for Background Assets download |
| **Supabase** | Free tier (Postgres + storage, paused after inactivity) | Overkill; Postgres full-text possible but unnecessary |

For MiniLog, use **CloudKit private DB** for user data sync (optional) and **Cloudflare R2 or Apple-hosted Background Assets** to serve DB updates. No always-on server, no cost.

---

## 12. Barcode Scanning Implementation

**Use `DataScannerViewController` (VisionKit)** — it wraps AVFoundation + Vision with a live preview, guidance, tap-to-focus, and pinch-to-zoom.
- **Availability:** check `DataScannerViewController.isSupported` (requires A12 Bionic+ chip) **and** `.isAvailable` (camera permission granted).
- **Symbologies:** `.barcode(symbologies: [.ean13, .ean8, .upce])` — UPC-A arrives as EAN-13 with a leading 0.
- **Permission string:** `NSCameraUsageDescription` in Info.plist ("MiniLog uses the camera to scan product barcodes.").
- **Fallback:** For older devices or more control, use `AVCaptureMetadataOutput` with `metadataObjectTypes = [.ean13, .ean8, .upce]`.

```swift
import VisionKit
guard DataScannerViewController.isSupported,
      DataScannerViewController.isAvailable else { /* fallback */ return }
let scanner = DataScannerViewController(
    recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
    qualityLevel: .balanced,
    recognizesMultipleItems: false)
present(scanner, animated: true) { try? scanner.startScanning() }
```

---

## 13. Search Flow & Quality

- **Engine:** SQLite **FTS5** with the `porter` tokenizer + prefix indexes for typeahead. Debounce input ~250 ms.
- **Ranking:** (1) exact/prefix name match; (2) source priority — USDA Foundation/SR Legacy (lab-analyzed generics) above Branded/OFF for generic queries; (3) `completeness`/nutrient-count as a tiebreaker (prefer entries with full macros).
- **Typo tolerance:** FTS5 prefix + optional `trigram` tokenizer for fuzzy matches; maintain a small synonyms table ("soda"↔"soft drink", "pop").
- **Source labels:** show a small tag per row (USDA Foundation / SR Legacy / USDA Branded / OFF / Custom), mirroring Cronometer's "Common Foods" vs branded distinction so users can prefer accurate lab-analyzed entries.

---

## 14. UI Screens (iOS 26/27 Liquid Glass, minimal)

Follow the current Human Interface Guidelines and the iOS 26/27 **Liquid Glass** design language (translucent, layered materials; system components adopt it automatically when built with the iOS 26+ SDK). Keep it to **four primary screens**:

1. **Today (log):** date header, running kcal + macro totals, list of logged items grouped by meal; swipe to edit/delete (syncs to Health).
2. **Add:** segmented Search / Scan. Search field with live results (source tags); Scan opens the DataScanner.
3. **Item Detail (size & quantity):** food name + source; serving picker (label serving, household measures, g/oz/ml/units); quantity stepper; live-recomputed nutrients; "Log" and "Save to My Items."
4. **My Items:** saved foods with one-tap re-log (remembers last size/quantity); search/sort by recent.

Use SF Symbols, standard navigation, large titles, and system materials. No custom chrome.

---

## 15. Tech Stack

- **Language/UI:** Swift 6.x, SwiftUI, Xcode 27.
- **Min OS:** iOS 26 (Foundation Models, Liquid Glass); iOS 27 for the newest Siri/App Intents behavior. Graceful degradation on non-Apple-Intelligence devices.
- **User data:** SwiftData (+ optional CloudKit private sync).
- **Food DB:** bundled SQLite via **GRDB** with FTS5 (read-only), updated by Background Assets.
- **Scanning:** VisionKit `DataScannerViewController`; Vision for label OCR.
- **Health:** HealthKit.
- **Voice/Automation:** App Intents + AppShortcutsProvider; Foundation Models (optional NL parsing).
- **Data build tooling (offline):** DuckDB + Python/Swift script to trim USDA/OFF → SQLite.

---

## 16. Build & Distribution (TestFlight)

- **Account:** existing paid Apple Developer Program ($99/yr) — sufficient; no other required costs.
- **Testers:** **Internal** (up to 100, must be App Store Connect team members, install within minutes, **no Beta App Review**) vs **External** (up to 10,000, require **Beta App Review** for the first build of each version). For a handful of friends, add them as **internal testers** if you can add them to your team; otherwise use a small **external** group (one-time beta review per version). Each external tester needs only a compatible device, the free TestFlight app, and an invite — no developer account.
- **Build expiry:** every TestFlight build **expires 90 days** after upload — upload a fresh build (incremented build number) before expiry to keep friends running.
- **Beta review triggers:** changes to entitlements (HealthKit), encryption/export compliance, privacy details, or the beta description trigger re-review for external testers.
- **HealthKit/App Intents on TestFlight:** both work in TestFlight builds. Provide the HealthKit privacy usage strings and a privacy policy; App Intents/Shortcuts register on install.
- **DB delivery:** ship the large food DB via Background Assets/ODR, not inside the base IPA, to keep the build lean.

---

## 17. Privacy

- Health data is written to Apple Health locally; MiniLog stores its own logs in SwiftData (on-device, optional private CloudKit). No third-party analytics on health data.
- Provide `NSHealthUpdateUsageDescription`, `NSCameraUsageDescription`; a privacy policy URL (required for HealthKit).
- TestFlight/App Store privacy "nutrition label": declare Health & Fitness data as stored on-device / not linked to identity / not used for tracking.
- Foundation Models runs on-device; no data leaves the phone for NL parsing.

---

## 18. Phased Development Plan

**Phase 0 — Data pipeline (1 wk):** DuckDB scripts to trim USDA (Foundation, SR Legacy, Branded) + OFF into a unified SQLite w/ FTS5 + GTIN-14 normalization + per-100g nutrients. Ship a base DB.

**Phase 1 — Core logging (2 wk):** Today screen, Add→Search, Item Detail with serving/quantity math, SwiftData models, source labels.

**Phase 2 — Scanning (1 wk):** DataScanner, barcode normalization/matching, not-found → OFF/USDA optional live lookup → OCR/manual fallback.

**Phase 3 — My Items + Health (1.5 wk):** save/re-log; HealthKit auth + `HKCorrelation` write + edit/delete sync.

**Phase 4 — Siri/App Intents (1.5 wk):** LogFoodIntent, FoodEntity/IndexedEntity, AppShortcutsProvider phrases, disambiguation/confirmation; optional Foundation Models NL parsing with fallback; AppIntentsTesting.

**Phase 5 — Polish + TestFlight (1 wk):** Liquid Glass pass, privacy strings/policy, Background Assets DB delivery, internal TestFlight, then external group if needed.

**Phase 6 — Maintenance:** rebuild DB on USDA Apr/Oct releases + monthly OFF/Branded; upload a fresh TestFlight build before 90-day expiry.

---

## 19. Risks & Open Questions

1. **No nutrition App Schema domain** in iOS 27 — must use custom App Intents (works, but no first-class Siri "log food" grammar). Re-check each release.
2. **SiriKit deprecation ambiguity** — reported as "legacy"/deprecated at WWDC26 but SDK metadata as of Sept 14, 2026 may not yet mark symbols `deprecated`. Using App Intents avoids the issue entirely.
3. **OFF data quality/coverage** — crowd-sourced, US coverage weaker than USDA Branded; filter null-energy; prefer USDA Branded for US barcodes.
4. **USDA Branded quality** — manufacturer-submitted, voluntary, can be stale; SR Legacy is frozen at April 2018.
5. **DB size vs app footprint** — must offload the large DB to Background Assets/ODR; validate the final trimmed size.
6. **Foundation Models availability** — only on Apple-Intelligence devices; NL multi-item parsing must degrade gracefully.
7. **`brand_name` column** — not confirmed in the current USDA `branded_food` dictionary; verify against the exact release; `brand_owner` is confirmed.
8. **HealthKit iOS 27 changes** — none identified affecting dietary types; verify against the final iOS 27 release notes.
9. **ODbL share-alike** — for a friends-only app this is low-risk, but if users edit/add products, contribute back to OFF via its API.
10. **Nutritionix/NCCDB excluded** — MiniLog will not match Cronometer's micronutrient depth (NCCDB is a paid U. Minnesota license; Nutritionix has no free tier). Acceptable for an accuracy-focused macro tracker using USDA + OFF.

---

## 20. Source Links

- USDA FoodData Central downloads: https://fdc.nal.usda.gov/download-datasets ; API guide: https://fdc.nal.usda.gov/api-guide ; update log: https://fdc.nal.usda.gov/log/ ; GBFPD docs: https://fdc.nal.usda.gov/GBFPD_Documentation
- Open Food Facts data: https://world.openfoodfacts.org/data ; nutrients handling: https://wiki.openfoodfacts.org/Nutrients_handling_in_Open_Food_Facts ; data fields: https://static.openfoodfacts.org/data/data-fields.txt ; Hugging Face Parquet: https://huggingface.co/datasets/openfoodfacts/product-database ; press/scale: https://world.openproductsfacts.org/press
- Cronometer data sources: https://support.cronometer.com/hc/en-us/articles/360018239472-Data-Sources ; accuracy tips: https://cronometer.com/blog/accurate-data-tips/
- Morello et al. 2025 (Cronometer vs MFP): https://pubmed.ncbi.nlm.nih.gov/41133373/ (doi:10.1111/jhn.70148)
- Hengist/Charles NUTRITION 2026 (photo-app underestimation): https://www.eurekalert.org/news-releases/1136415 ; https://www.healio.com/news/primary-care/20260804/
- App Schema domains: https://developer.apple.com/documentation/appintents/app-schema-domains ; App intent domains: https://developer.apple.com/documentation/appintents/app-intent-domains ; WWDC26 s240: https://developer.apple.com/videos/play/wwdc2026/240/
- HealthKit nutrition types: https://developer.apple.com/documentation/healthkit/nutrition-type-identifiers ; HKCorrelation food bug thread: https://forums.cronometer.com/discussion/6845/
- Foundation Models (WWDC26 guide): https://developer.apple.com/wwdc26/guides/apple-intelligence/
- VisionKit DataScannerViewController: https://developer.apple.com/documentation/visionkit/datascannerviewcontroller ; Vision barcodes: https://www.createwithswift.com/reading-qr-codes-and-barcodes-with-the-vision-framework/
- TestFlight: https://developer.apple.com/testflight/ ; App Store Connect help: https://www.developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview
- NCCDB license (paid): https://license.umn.edu/product/food-and-nutrient-database-for-application-development-and-nutrition-research
- Nutritionix API (no free tier): https://www.nutritionix.com/api ; https://developer.nutritionix.com/
- Canadian Nutrient File: https://open.canada.ca/data/en/dataset/089885f9-ed53-44e6-854a-14d21a1ec2e0 ; FSANZ data licence: https://www.foodstandards.gov.au/science-data/monitoringnutrients/afcd/datauserlicenceagreement ; NEVO request: https://www.rivm.nl/en/dutch-food-composition-database/use-of-nevo-online/request-dataset