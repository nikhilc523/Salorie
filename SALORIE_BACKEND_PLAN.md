# Salorie — Food Database Backend Plan

**Accuracy-first, $0-data, on-device food catalog for search + barcode scan.**
Derived from the two MiniLog research briefs + a full audit of the current Salorie UI.
Version 0.1 · draft for review.

---

## Locked decisions (from review)

| Decision | Choice |
|---|---|
| Region scope | **US only** — USDA Branded (US) + OFF filtered to US. Leanest, ~80–150 MB. |
| Storage | **Hybrid, offline-first.** Small seed bundled in-app (works instantly offline) + full US DB hosted on Cloudflare R2, downloaded on first launch; updated without an app release. |
| Lookup order | local DB → live API (OFF→USDA) on a miss → label OCR (Vision) → manual entry. Every remote hit is cached locally. |
| Search engine | **GRDB (SQLite + FTS5)** — added via SPM. |
| Nutrient depth | Core 9 (always) **+ Extended (Tier A+B) as optionals** incl. caffeine, potassium, minerals, vitamins **+ Tier C qualitative** (Nutri-Score, NOVA). `nil` ⇒ hide the row. |
| UI | Progressive disclosure in `FoodDetailView`: core grid + **"Show more nutrients"** expandable groups. *(Implemented.)* |
| Build scope | **Catalog first** — search + barcode + serving math against the real DB. User-data → SwiftData in a later pass. |

---

## 0. The money question first: what does the data cost?

**$0.** Every source we rely on is free and permissively licensed:

| Source | License | Cost | Role |
|---|---|---|---|
| USDA FoodData Central — Foundation | CC0 (public domain) | Free | Generic, lab-analyzed foods (highest accuracy) |
| USDA FDC — SR Legacy | CC0 | Free | Broad generic fallback |
| USDA FDC — Branded | CC0 | Free | US packaged foods (barcodes) |
| Open Food Facts (OFF) | ODbL / DbCL | Free | Global packaged foods (barcodes) |

The **only** things that cost money are already paid or optional:
- Apple Developer Program — **$99/yr, already have it.** Nothing else required.
- Optional cloud hosting for DB updates (Cloudflare R2 / CloudKit) — **free tiers cover us** at friends-only scale.

The "cost" of accuracy is **your time + bandwidth + disk on your Mac** to download and trim the raw data once. Concrete download sizes and a tiered recommendation are in §3. **There is no paid data tier to buy** — the paid sources (Nutritionix, NCCDB) are explicitly excluded, exactly as the brief recommends.

---

## 1. How this plugs into the app (architecture fit)

The app is already built for this swap. Nothing in the views changes.

```
Views (TodayView, AddView, FoodDetailView, ScanView, …)
        │  speak only in  Food / MealEntry
        ▼
   FoodStore  (protocol)         ← today: MockStore.  tomorrow: RealFoodStore.
        │
   ┌────┴───────────────────────────────────────┐
   ▼                                             ▼
Read-only Food Catalog                    User data (SwiftData)
(bundled SQLite + FTS5 via GRDB)          logged entries, My Items,
  · text search                           custom meals, favorites
  · barcode lookup
  · per-100g nutrients + portions
        │
        ▼  optional, only on a miss
  Live API fallback (USDA + OFF)  →  Label OCR (Vision)  →  manual entry
```

### 1.1 Introduce a `FoodStore` protocol (the seam)
`MockStore` already exposes exactly the surface the real store needs. We extract a protocol so views depend on the abstraction, then ship `RealFoodStore` behind the same surface:

```swift
@MainActor protocol FoodStore: AnyObject {
    // search / discovery
    func search(_ query: String) async -> [Food]
    func food(forBarcode code: String) async -> Food?
    var favorites: [Food] { get }
    var recentFoods: [Food] { get }
    var frequentFoods: [Food] { get }
    // logging (user data)
    func addEntry(_ food: Food, slot: MealSlot, servings: Double, time: String)
    // … everything MockStore already has
}
```

`search`/`food(forBarcode:)` become `async` (they hit SQLite/GRDB). This is the only view-facing change, and it's mechanical — `AddView`'s substring filter and `ScanView.handleScan` move behind an `await`.

### 1.2 The per-serving vs per-100g decision (**resolved**)
`Food` today stores macros **per its `servingDescription`** (e.g. `calories: 100` for a 170 g container). The food databases store everything **per 100 g**. We reconcile with a thin conversion layer and **keep `Food` unchanged**:

- New value type `FoodRecord` = the raw per-100g row from the catalog DB (+ portion list + barcode + category).
- A pure function `Food(from: FoodRecord, portion:)` builds a per-serving `Food` snapshot for a chosen portion — this is the serving math from §6.
- `Food` stays the logged snapshot (denormalized), so **history never changes when the DB updates** — matching the brief's "denormalized snapshot" principle.

**Why keep `Food` per-serving:** zero view changes, history integrity, and the serving stepper in `FoodDetailView` already re-scales a per-serving `Food` correctly. We just need the *initial* portion resolved from per-100g data.

---

## 2. Exactly what the UI needs from the DB

From the UI audit, every food must resolve these fields (defaults in parens):

**Nutrients (9):** `calories` (kcal, Int), `carbs`, `protein`, `fat`, `fibre` (g) — required; `sugars`, `saturatedFat` (g), `sodium`, `cholesterol` (mg) — optional (0).
**Identity/metadata:** `name` (req), `brand` (opt), `source` (enum), `servingDescription`, `barcode` (opt), `ingredients` ([]).
**UI enrichment (derived, not in raw data):** `symbol` (SF Symbol), `tint` (TagColor), `tags` ([]), `isOpen` (false). → generated by a **category → glyph/tint** mapper (§7).

**Indexes we must build:** full-text over `name` + `brand` (FTS5); exact over normalized `barcode` (GTIN-14).

**Nutrient source IDs** we extract:

| Nutrient | USDA `nutrient_id` | OFF field |
|---|---|---|
| Energy kcal | 1008 → fallback 2048 → 2047 | `energy-kcal_100g` |
| Protein | 1003 | `proteins_100g` |
| Total fat | 1004 | `fat_100g` |
| Carbs (by difference) | 1005 | `carbohydrates_100g` |
| Fibre | 1079 | `fiber_100g` |
| Sugars (incl. NLEA) | 2000 | `sugars_100g` |
| Saturated fat | 1258 | `saturated-fat_100g` |
| Sodium | 1093 | `sodium_100g`, else `salt_100g`/2.5×1000 |
| Cholesterol | 1253 | `cholesterol_100g` (often null) |

**Energy trap (OFF):** always read `energy-kcal_*`, never bare `energy` (that's kJ). **Sodium trap (OFF):** OFF reports **salt**, convert `sodium_mg = salt_g / 2.5 × 1000`.

---

## 3. What to download — sizes & tiered recommendation

Raw downloads (from `fdc.nal.usda.gov/download-datasets` and OFF exports):

| File | Zip | Unzipped | Notes |
|---|---|---|---|
| USDA Foundation (CSV) | ~3.4 MB | ~29 MB | tiny, always include |
| USDA SR Legacy (CSV) | ~6.7 MB | ~54 MB | tiny, always include |
| USDA Branded (CSV) | ~427 MB | ~2.9 GB | US barcodes |
| OFF **Parquet** (Hugging Face `openfoodfacts/product-database`) | — | column-filtered, smallest for DuckDB | **best format** |
| OFF CSV.gz (alternative) | ~0.9 GB | ~9 GB | if Parquet is awkward |

After trimming to **9 nutrients + name/brand/serving/barcode/category** and dropping null-energy rows, the shipped SQLite is a fraction of the raw. Three build tiers:

| Tier | Contents | Est. shipped SQLite | Best for |
|---|---|---|---|
| **T1 — Lean** | USDA Foundation + SR Legacy + USDA Branded (US) + OFF filtered to your countries, macros-complete only | **~80–250 MB** | fastest, US-centric |
| **T2 — Balanced** (recommended) | T1 + OFF for a handful of countries, higher completeness threshold | **~300–700 MB** | good global barcode hit-rate |
| **T3 — Max** | T1 + OFF global (high-completeness) | **~1–2 GB** | maximum scan coverage |

**Accuracy-first note:** accuracy comes from *which source wins a match*, not from raw size. Generic USDA Foundation/SR Legacy (lab-analyzed) always outrank branded/crowd-sourced for generic queries (§8 ranking). More OFF data only widens **barcode** coverage; it doesn't reduce accuracy because we tag every row with its source and prefer USDA for US barcodes.

**One region decision drives the size** (see Decisions, §12): US-only vs US+India vs multi-country vs global.

---

## 4. Offline build pipeline (runs on your Mac, once per refresh)

Tooling: **DuckDB** (reads Parquet/CSV/JSONL directly, no server) + a small Python/SQL script. Output: one `salorie_foods.sqlite` with FTS5.

**Steps:**
1. **Download** the raw files for the chosen tier into `data/raw/`.
2. **USDA transform (DuckDB SQL):** join `food` × `food_nutrient` × `branded_food`; pivot the 9 nutrient rows into columns (per 100 g); pick energy 1008→2048→2047; pull `food_portion` (household measures → grams) for generics and `serving_size`/`household_serving_fulltext` for branded; normalize `gtin_upc` → GTIN-14; tag `source`.
3. **OFF transform (DuckDB SQL):** select the 9 `_100g` fields + `code`, `product_name`, `brands`, `serving_size`/`serving_quantity`, `categories_tags`, `countries_tags`; **filter** to chosen countries + non-null `energy-kcal_100g` + a `completeness` threshold; convert salt→sodium; normalize `code` → GTIN-14; tag `source = openFoodFacts`.
4. **Unify** into two tables: `foods` (per-100g nutrients + metadata + `source` + `category_raw`) and `food_portion` (fdc/off id → label, grams). Dedup barcodes: prefer USDA Branded (US) → OFF highest `completeness` → most recently modified.
5. **Build SQLite:** create `foods`, `food_portion`, an FTS5 virtual table (`porter` tokenizer + prefix index, optional `trigram` for typo tolerance) over `name`+`brand`, and a unique index on normalized `barcode`.
6. **Enrich:** run the category→symbol/tint mapper (§7) to precompute `symbol`/`tint` per row (or do it at read time; precompute is faster).
7. **Ship:** bundle T1 in the app, or host the DB on R2/Background Assets and download on first launch (see §10).

The pipeline is **deterministic and re-runnable**: rebuild on USDA's Apr/Oct releases and monthly for OFF. Scripts live in `tools/db-build/` (not in the app target).

---

## 5. On-device schema & GRDB integration

**Read-only catalog** — separate from user data. Recommended: **GRDB** (SPM) for SQLite + FTS5.

```
foods(
  id TEXT PRIMARY KEY,          -- "usda:1234567" | "off:0012345678905"
  source TEXT,                  -- FoodSource.rawValue
  name TEXT, brand TEXT,
  barcode TEXT,                 -- normalized GTIN-14, indexed, nullable
  kcal_100 REAL, carbs_100 REAL, protein_100 REAL, fat_100 REAL,
  fibre_100 REAL, sugars_100 REAL, satfat_100 REAL,
  sodium_mg_100 REAL, chol_mg_100 REAL,
  default_serving_g REAL,       -- label serving or a sensible portion
  serving_text TEXT,            -- "1 container (170 g)"
  category_raw TEXT,
  symbol TEXT, tint TEXT,       -- precomputed UI enrichment
  ingredients TEXT              -- joined string, nullable
)
food_portion(food_id TEXT, label TEXT, grams REAL)   -- household measures
foods_fts(name, brand)                               -- FTS5, external content
```

**Dependency decision:** GRDB is the brief's recommendation (mature FTS5 support). Alternatives if you'd rather avoid a dependency: `SQLite.swift`, raw `SQLite3` C API, or a preloaded read-only SwiftData store (weakest FTS story). **Recommend GRDB.** (See Decisions, §12.)

**User data stays in SwiftData** (logged entries, My Items, custom foods, favorites) — a clean split: read-only catalog (GRDB) vs mutable user data (SwiftData). This matches the brief and keeps the catalog swappable/updatable without migrating user data.

---

## 6. Serving & quantity math (`FoodRecord` → `Food`)

Canonical storage is per-100g. To present/log a portion:

1. Resolve chosen portion → **grams** (or ml; density ≈1 for drinks):
   - label serving = `default_serving_g` × quantity
   - household measure from `food_portion` (e.g. "1 cup" = 240 g)
   - direct g / oz (1 oz = 28.3495 g) / ml (1 fl oz ≈ 29.5735 ml)
2. Scale every nutrient: `value = per_100 × grams / 100`.
3. Build the `Food` snapshot with `servingDescription` = the chosen portion label.

This is **pure, unit-testable** logic (TDD target #1). The Diet-Mtn-Dew example from the brief becomes a test case.

---

## 7. Category → symbol / tint / tags (UI enrichment)

Raw data has no SF Symbols or tint. A deterministic mapper turns USDA `food_category` / OFF `categories_tags` into `symbol` + `tint` (+ optional auto-tags like "Protein"/"Processed"):

- dairy → `cup.and.saucer.fill`/blue · produce → `leaf.fill`/green · meat → `fork.knife`/orange · grain/bread → `takeoutbag…`/yellow · nuts/spreads → `circle.hexagongrid.fill`/brown · sweets → `square.grid.2x2.fill`/brown · beverage → `waterbottle.fill`/blue · fallback → `circle.fill`/gray.

Precompute during the build (step 6) so search is a straight SELECT. Keep the mapping table in `tools/db-build/` so it's tweakable.

---

## 8. Search & barcode matching

**Search (FTS5):** debounce ~250 ms; rank by (1) exact/prefix name, (2) **source priority** — USDA Foundation/SR Legacy above Branded/OFF for generic queries (accuracy-first), (3) nutrient completeness tiebreaker. Optional synonyms table ("soda"↔"pop"). Typo tolerance via prefix + optional `trigram`.

**Barcode:** normalize scanned code → **GTIN-14** (UPC-A pad 2 zeros; EAN-13 pad 1; EAN-8 pad; **UPC-E expand to UPC-A first**). Match priority: USDA Branded → OFF. Normalize both sides before compare. `ScanView` already scans EAN13/EAN8/UPCE/QR/Code128 and calls `food(forBarcode:)` — we swap the in-memory lookup for a GRDB query + normalization. GTIN normalization is TDD target #2.

---

## 9. Live API fallback (only on a local miss)

Never per-scan by default (offline-first). On a barcode/search miss, optionally hit:
- **USDA FDC API** — `api.nal.usda.gov/fdc/v1/` — **needs a free data.gov key**, 1,000 req/hr/IP. **Never ship DEMO_KEY.**
- **OFF API** — `world.openfoodfacts.org/api/v2/product/{barcode}.json` — send a descriptive `User-Agent` (`Salorie/1.0 (email)`).

On success, insert into the user's My Items (SwiftData) as a cached custom food so it's instant next time.

---

## 10. Update delivery & hosting

- **Ship:** bundle T1 in the IPA, or (for T2/T3) host `salorie_foods.sqlite` and download on first launch via **Background Assets** (Apple-hosted) or **Cloudflare R2** (free tier). Keeps the base build lean.
- **Refresh:** rebuild on USDA Apr/Oct + monthly OFF; bump an asset version; clients download the new DB. For a handful of friends, a manual rebuild every 1–3 months is fine.
- **User data sync (optional):** SwiftData + CloudKit private DB (free with the developer account).

---

## 11. Skills to use (from the installed marketplace)

Invoke these as we hit each area (all present in this environment):

| Area | Skill |
|---|---|
| Barcode scan + nutrition-label OCR | **`dpearson-vision-framework`** |
| User data store, read-only preload split | **`dpearson-swiftdata`** |
| Async store, actor isolation, Sendable `Food` | **`dpearson-swift-concurrency`** / `dimillian-swift-concurrency-expert` |
| TDD for serving math, GTIN norm, ranking | **`dpearson-swift-testing`** / `xcode27-test-modernizer` |
| Live API fallback (USDA/OFF) | **`dpearson-ios-networking`** |
| DB update download / background refresh | **`dpearson-background-processing`** |
| Optional cloud hosting + private sync | **`dpearson-cloudkit`** |
| HealthKit `HKCorrelation .food` writes (later) | **`dpearson-healthkit`** |
| Siri "log a …" | **`dpearson-app-intents`** |
| On-device NL parsing ("two cans of…") | **`dpearson-apple-on-device-ai`** + `dpearson-natural-language` |
| Wiring search/detail views to async store | **`avdlee-swiftui-expert-skill`** / `dimillian-swiftui-view-refactor` |
| Build/run/screenshot verification | **`dpearson-ios-simulator`** / `dimillian-ios-debugger-agent` / `run` |

No skill exists for GRDB/DuckDB specifically — those are handled directly (SPM + offline scripts).

---

## 12. Decisions I need from you (these lock the pipeline)

1. **Region scope for Open Food Facts** — drives DB size & barcode hit-rate. (US-only ≈ leanest; US+India if friends are in India; multi-country; or global/max.)
2. **DB delivery** — bundle in the app (simplest) vs download-on-first-launch (leaner build, needs a host).
3. **GRDB dependency** — OK to add GRDB via SPM (recommended), or avoid third-party deps.
4. **Scope of this build** — food *catalog* only (search + scan + serving math), or also wire the SwiftData user-data store (logging/My Items) in the same pass.

---

## 13. Phased execution

- **P0 — Seam:** ✅ **DONE.** Added `FoodCatalog` protocol (`Sendable`, async `search`/`food(forBarcode:)`) + `SampleFoodCatalog`; `MockStore` owns a swappable `catalog` and exposes async `search`/`food(forBarcode:)`; `AddView` uses debounced `.task(id: query)`, `ScanView` awaits the lookup. New `SalorieTests` target (Swift Testing) — 14 tests green. P2's GRDB store now drops in by implementing `FoodCatalog`.
- **P1 — Pipeline:** ✅ **DONE (all sources + follow-ups).** `tools/db-build/` (download.sh · build.sh · validate.sh · README). DuckDB → `out/salorie_foods.sqlite`: **466,411 foods** (396,245 US Branded + 62,033 OFF-US + 7,756 SR Legacy + 377 Foundation), per-100g nutrients + `food_portion` + FTS5, **298 MB**. Includes: **Open Food Facts US** (streamed from its 1.2 GB gzip; adds barcodes + `nutri_score`/`nova_group` badges), **sanity clamps** (dropped ~19.6k branded rows with impossible >902 kcal/100g; NULLs impossible macros/sodium/caffeine), **`source_priority` column** driving generic > branded > OFF search ranking, cross-source GTIN-14 barcode dedup (Branded wins over OFF). Validated end-to-end: integrity ok, 0 dup ids/barcodes, 0 clamp violations, generic ranks above branded ("avocado" → USDA Foundation first), banana = 89 kcal/358 mg K, barcode lookup ~1 ms. Canonical search query documented in README (`ORDER BY source_priority, rank`).
- **P2 — Catalog store:** ✅ **DONE.** `GRDBFoodCatalog` (GRDB v7 via SPM) implements `FoodCatalog`: FTS5 search `ORDER BY source_priority, rank`, GTIN-14 barcode lookup, per-100g→per-serving `Food` mapping (core + extended nutrients + Nutri-Score/NOVA + category→SF-Symbol/tint enrichment). DB bundled at `Salorie/Resources/salorie_foods.sqlite` (gitignored — copy from `tools/db-build/out`). Pure helpers (GTIN norm, FTS pattern) + query/mapping unit-tested against an in-memory DB. **22 tests green.**
- **P3 — Swap:** ✅ **DONE.** `MockStore.defaultCatalog` = `GRDBFoodCatalog()` (falls back to `SampleFoodCatalog` for previews / missing DB). Verified in simulator: "chicken breast" → USDA Foundation ranked first (generic > branded), fork.knife icon; scanning UPC `883572133501` → GTIN-14 → "1% Lowfat Milk / Driftwood" detail with dairy icon + Branded badge. `SALORIE_QUERY` screenshot hook added; demo scan now uses a real barcode.
- **P4 — Fallback:** ✅ **Live lookup + cache DONE.** `RemoteFoodService` (`RemoteFoodLookup`): on a local+cache miss, queries **Open Food Facts** (no key) then **USDA FDC** (needs a free key in `RemoteConfig.usdaAPIKey` / `USDA_API_KEY` env; skipped if absent), maps per-100g→`Food` (incl. Nutri-Score/NOVA, serving grams for weight logging). `BarcodeCache` persists resolved foods (JSON in Documents, keyed by GTIN-14) so a miss resolves once, then instant & offline. Chain in `MockStore.food(forBarcode:)`: catalog → cache → OFF → USDA. `ScanView` shows a "Looking up…" overlay. Verified live: scanning `025000121142` (absent from bundled DB) → OFF → "Zero Sugar Lemonade / Minute Maid". **Total-miss tail also DONE:** `ManualFoodEntryView` (form → custom `Food`, cached by barcode + logged) with **nutrition-label OCR** — `LabelScannerView` (VNDocumentCameraViewController + Vision `RecognizeTextRequest`) → `NutritionLabelParser` (regex) prefills the fields. Not-found alert → "Add Manually". **38 tests green** (parsers, cache, fallback chain, label parser). **P4 COMPLETE.**
- **P5 — User data:** ✅ **DONE.** SwiftData now persists all mutable user data — logged entries, custom meals, saved/custom foods (with favorite flag), and macro targets. Design: `Salorie/Models/Persistence.swift` holds `@Model` rows (`StoredFood`/`StoredMeal`/`StoredEntry`/`StoredTargets`) that each store the **Codable JSON snapshot** of the value struct (denormalized — not re-modelled as relations, so the value-type UI needs **zero changes** and a logged food never changes if its catalog entry later does), plus a `@MainActor PersistenceController` owning the `ModelContainer` (in-memory fallback on failure). `MockStore` gained an optional `persistence:` param: it **seeds from `SampleData` on first launch**, loads the four collections, and **writes through** on every mutation (add/remove entry, toggle favorite, save/delete meal, save custom food). `persistence == nil` (previews/tests) = the original in-memory demo path. Read-only demo data (7-day history, 120-day trend log, friends) is **never persisted** — rebuilt from `SampleData` each launch. `MealEntry.id` became a settable `var` so reloaded entries keep identity; `saveCustomFood` now also joins `foods` so hand-entered foods appear in My Items → Custom. `SALORIE_RESET=1` wipes+reseeds for deterministic screenshots/UI tests. **45 tests green** (7 new in `PersistenceTests.swift`: seed, log/remove/favorite/meal/custom-food round-trips, extended-nutrient survival). Verified in simulator: relaunch (no reset) reads the persisted store and renders identical seeded data with favorites intact. **P5 COMPLETE.**
- **P6 — Delivery & scale:** ✅ **DONE (client mechanism; infra config documented).** Three pillars, all dormant-by-default so the bundled-only, fully-offline build is unchanged until a host / iCloud is configured.
  - **Hosted DB delivery** — `CatalogInstaller` (pure, unit-tested) resolves the active SQLite **downloaded → bundled seed → none** (`GRDBFoodCatalog(fileURL:)`; `MockStore.defaultCatalog` tries candidates, a corrupt download falls through). A `CatalogManifest` JSON (`{version,url,sha256,bytes}`) on the host drives updates; `CatalogInstaller.verifyAndInstall` checks size + streaming **SHA-256** then swaps in atomically and records the installed version. New DB goes live next launch. Host via Cloudflare R2 / Background Assets — set `RemoteConfig.catalogManifestURL` (or `SALORIE_CATALOG_MANIFEST` env).
  - **Refresh cadence** — `CatalogDownloadManager` runs the transfer on a **background `URLSession`** (`sessionSendsLaunchEvents`, Wi-Fi-only, delegate moves the temp file then verifies/installs off-thread) so a ~300 MB download survives suspension/termination. Driven by SwiftUI `.backgroundTask(.appRefresh("com.salorie.app.catalog-refresh"))` (Info.plist `BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes: fetch`), rescheduled on `scenePhase == .background`, with a tiny `@UIApplicationDelegateAdaptor` shim forwarding `handleEventsForBackgroundURLSession`. Also an opportunistic foreground `check()` on launch.
  - **CloudKit sync** — SwiftData models made CloudKit-compatible (dropped `#Unique`, every attribute has a default). `PersistenceController` is a 3-tier fallback: **CloudKit private DB** (`cloudKitDatabase: .private(id)`) → **local file** (`.none`, same store URL so existing P5 data is preserved and later mirrored up) → **in-memory**. Off by default (`RemoteConfig.cloudKitContainerID == nil`); enable by setting the container id + `CODE_SIGN_ENTITLEMENTS: Salorie/Salorie.entitlements` (template committed: iCloud + CloudKit + `remote-notification`) + a `DEVELOPMENT_TEAM`.
  - **51 tests green** (6 new `CatalogInstallerTests`: manifest decode, SHA-256 vector, version gate, verify+install, bad-checksum & size-mismatch rejection). Verified in simulator: app builds, launches, seeds + reads persisted user data under the CloudKit-attempting container (local fallback), catalog resolves via the installer. **Remaining = infra, not code:** provision the R2/Background-Assets host + manifest, and (for sync) create the iCloud container + set team. **P6 COMPLETE.**
- **P7 — Later features (separate briefs):** HealthKit writes, Siri App Intents, FM NL parsing.
