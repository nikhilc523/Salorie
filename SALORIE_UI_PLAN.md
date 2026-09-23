# Salorie — UI Build Plan (Notion-Minimal, iOS 26 SwiftUI)

**Version 0.1 · UI-first phase · Target: iOS 26 min, iPhone**
**App:** Salorie (calorie & meal tracker — spec name "MiniLog"). This document covers the **UI layer only**. Data/DB/HealthKit/Siri come in a later phase.

---

## 0. Guiding decisions

1. **UI-first, mock-data driven.** Every screen renders from in-memory `Sample*` structs. No SwiftData, no GRDB, no network yet. A single `MockStore` (`@Observable`) feeds all screens so we can later swap it for the real store with zero view changes.
2. **Notion dark aesthetic is the product's visual identity.** Near-black surfaces, thin dividers, gray labels, colored tag pills, emoji/icon leading cells, a blue `New`/`+` action. Reference = the 15 screenshots in `/UI` (see §7 mapping).
3. **Every list view = one reusable `NotionTable`.** Do not hand-roll lists per screen. Tables scroll horizontally with a **pinned first column** (name), exactly like the Notion iOS app (`IMG_4953`, `IMG_4954`).
4. **Liquid Glass only where iOS applies it for free** — tab bar, toolbars, sheets, the floating bottom bar. Content surfaces stay flat Notion-black (no custom blur on rows/cards). This matches `zaki-claude-liquid-glass` law #1 (never hand-roll glass) while keeping the Notion flatness.
5. **Screen-by-screen build order:** Design system → Home → Add/Search → Scan → Detail → My Items → Food Database → History. Each screen is "done" only when it renders on the iPhone 17 / iOS 26 simulator and matches its reference screenshot.

---

## 1. Design system (build this FIRST — `Salorie/DesignSystem/`)

### 1.1 Color tokens (`Theme.swift`)
Pulled from the screenshots. Dark theme only for v1 (Notion's dark palette).

| Token | Hex | Use |
|---|---|---|
| `bg` | `#191919` | Page background |
| `surface` | `#202020` | Cards, board columns, metric cards |
| `surfaceRaised` | `#252525` | Selected/hover row, popovers |
| `divider` | `#FFFFFF @ 9%` (`#2E2E2E`) | Table row lines, column separators |
| `textPrimary` | `#EAEAEA` | Names, big numbers, titles |
| `textSecondary` | `#9B9B9B` | Column headers, property labels |
| `textTertiary` | `#6E6E6E` | Placeholders, "+ New page", empty |
| `accent` | `#2383E2` | `New` button, `+` button, active tab |
| `accentPressed` | `#1B6FC4` | Pressed state |

**Tag pill palette** (Notion's 9 muted dark colors — `TagColor` enum, each `(bg, fg)`):

| Name | bg | fg | Seen in |
|---|---|---|---|
| `gray` | `#373737` | `#D4D4D4` | "Processed", OPEN |
| `brown` | `#4A3B2A` | `#C8A882` | "Hackathon", "Good" |
| `orange`| `#4A3521` | `#D9A066` | — |
| `yellow`| `#453F21` | `#D6C158` | — |
| `green` | `#2B3D2F` | `#7DB38A` | "Snacks", "Paid", "Offsite" |
| `blue`  | `#28374D` | `#6E9FE0` | "Talk", "Sent", "Scheduled" |
| `purple`| `#3D2F4D` | `#B090D0` | "Learning", "Student" |
| `pink`  | `#4A2F3D` | `#C88AA8` | "Satisfying" |
| `red`   | `#4D2F2F` | `#D08A8A` | "Overdue", "Meeting", ERROR |

Filled variant (solid, white text) for emphasis pills like the blue "Homemade" — add `.filled` style.

**Source-label colors** (Salorie-specific, map data source → pill color):
- USDA Foundation → `green`, SR Legacy → `green`, USDA Branded → `blue`, OFF → `orange`, Custom → `gray`.

**Activity-ring colors** (`RingColor` — the 3 macro rings; distinct, Apple-Fitness-vivid, easily reassigned later):

| Ring | Macro | Color (gradient start → end) | Glow |
|---|---|---|---|
| Outer | **Carb** | `#F0463A` → `#FF7A6B` (warm red/coral) | ring color @ 25% |
| Middle | **Protein** | `#B6F03A` → `#8BE05A`... use `#A6E22E` → `#7BD84A` (lime/green) | ” |
| Inner | **Fibre** | `#3AD1F0` → `#5AC8E0` (cyan) | ” |

> These mirror Apple Fitness Move/Exercise/Stand vividness on the calm dark canvas. The `UI/Required/` reference is monochrome amber — we take its **layout, card calm, and ring animation feel**, not its single-hue palette (we need 3 distinguishable rings). Colors live in one `RingColor` enum so swapping macros/hues later is a one-line change.

### 1.5 Calm / Apple-Fitness aesthetic (dashboard cards & rings) — `UI/Required/`
The **list/table** screens stay flat Notion-black (§1.1). The **dashboard (Today) cards + rings** adopt the calmer, more premium feel from `UI/Required/`:
- **Cards:** larger corner radius (~18–20), slightly raised `surface`, generous padding, big-number-over-small-uppercase-gray-label metric style (e.g. `20:36 / 22H`, `87%`, `18 / 21`). Ref: `…11.38.17 PM.png`, `…11.38.32 PM.png`.
- **Rings:** glowing multi-ring with rounded caps + gradient + spring fill; center number; colored-dot legend beside it. Ref: `…11.37.34 PM.png` (hero ring + legend), `…11.38.25 PM.png` / `…11.38.40 PM.png` (session rings, mini per-day rings).
- **Mini rings row:** small per-day rings (like Apple Fitness monthly) for History/streak. Ref: `…11.38.17 PM.png` bottom row.
- **Animation:** rings fill from 0 → target with a spring (`.smooth`/`.snappy`), stagger the 3 rings ~60ms; subtle scale-in on the card. Respect Reduce Motion (snap to final).
- **Stat pills:** small solid mini-pills for compliance-style stats (`33%` green, etc.) — reuse `TagPill.filled`.

Reconciliation rule: **Notion tables for data/lists, calm cards + Apple rings for the dashboard.** One app, two coherent surfaces sharing the dark palette.

### 1.2 Typography (`Typography.swift`)
System font (SF Pro), Notion weights:
- `screenTitle` — 30pt Bold (e.g. "Fitness Tracker", "Company Events")
- `sectionTitle` — 17pt Semibold ("Quick Actions", "INGREDIENTS" uses 12pt Semibold **uppercase tracked**)
- `rowName` — 16pt Semibold (bold food name in first column)
- `cellValue` — 15pt Regular (numeric cells)
- `columnHeader` — 13pt Medium, `textSecondary`
- `metricNumber` — 34pt Bold (dashboard big numbers "29", "3Kkg")
- `metricLabel` — 13pt Regular, `textSecondary`
- `pill` — 13pt Medium

### 1.3 Spacing / metrics
- Page horizontal padding: 16
- Table row height: 44 (touch), cell horizontal padding: 12
- Pinned name column width: ~150–170; other columns sized to content, min 72
- Card corner radius: 10; pill radius: 4 (Notion pills are nearly-square); metric card radius: 12
- Divider: 0.5pt hairline

### 1.4 Reusable components (`Salorie/DesignSystem/Components/`)
Build and preview each in isolation (Xcode Previews) before using in screens.

| Component | Signature (sketch) | Notes / reference |
|---|---|---|
| `TagPill` | `TagPill(text:, color: TagColor, style: .soft/.filled)` | Colored badge. `IMG_4954` tags, "Snacks", "Overdue". |
| `GhostBadge` | `GhostBadge("OPEN")` | Outlined gray capsule, `IMG_4953`/`IMG_4954`. |
| `SourceBadge` | wraps `TagPill` mapping `FoodSource` → color | Every food row shows this. |
| `NotionToolbar` | trailing icon cluster: filter, sort, ⚡︎, ✦, 🔍, ⤢, sliders + `NewButton` | Top-right of every table. `Screenshot 11.14.32`. |
| `NewButton` | blue split button `New ⌄` / on mobile the blue `+ ⌄` | `IMG_4954`, accent color. |
| `NotionTable` | generic: `NotionTable(columns:[Column], rows:[Row])` | **Core component.** Horizontal scroll, pinned first column, hairline dividers, `+ New page` ghost row footer, optional leading checkbox column, optional `COUNT n` footer. |
| `TableRow` | leading emoji/dot + bold name + `GhostBadge?` + trailing cells | Cells can be text, number, `TagPill`s, or a button ("Add To Basket"). |
| `PropertyRow` | `PropertyRow(icon:, label:, value: content)` | Detail page rows. `Butter Milk` / `Office Snacks` screenshots. |
| `MetricCard` | `MetricCard(label:, value:, icon:)` | Dashboard stat card (`Fitness Tracker`: Total Sets 29). |
| `ActivityRings` | `ActivityRings(rings: [Ring])` where `Ring(progress:, color:, label:)` | **Apple-Fitness-style triple concentric ring.** 3 nested rings (outer→inner = **Carb · Protein · Fibre** for now, changeable), each a rounded-cap gradient arc that fills clockwise from 12 o'clock, overshoots past 100% (rings keep wrapping), soft outer glow, center label optional. Spring fill animation on appear/update. Reference: `UI/Required/` (see §1.5). |
| `RingLegend` | `RingLegend(items: [(color, label, value)])` | Colored-dot legend beside/under the rings (e.g. `● Carb 120g`, `● Protein 90g`, `● Fibre 22g`), matching the `Wear / Streak / Tray` dot list in `UI/Required/…11.38.32 PM.png`. |
| `RingChart` (single) | `RingChart(progress:, centerText:, subtitle:, targetText:, color:)` | Single donut w/ center number + "Target at X" — used for secondary stats (calories total, weight goal). `Screenshot …11.25.38 PM.png`. |
| `BoardColumn` / `BoardCard` | kanban column with header+count and stacked cards | For grouped views (meals, My Items gallery). `11.20.34`, `11.21.19`. |
| `QuickActionButton` | `+ Add …` ghost button with green plus | `Fitness Tracker` Quick Actions. |
| `SegmentedTabs` | Notion database-tab strip ("Exercises · Workouts · Splits") | `11.25.31`, Add screen Search/Scan toggle. |
| `SalorieTabBar` | bottom tab bar (native, glass) | Today · Add · Foods · My Items · History |

---

## 2. App shell & navigation (`Salorie/App/`)

- `SalorieApp` → `RootView` with a **`TabView`** (system Liquid Glass tab bar):
  1. **Today** (house / calendar icon) — Home dashboard
  2. **Add** (blue center `+`) — Search + Scan
  3. **Foods** (fork.knife) — Food database table
  4. **My Items** (star / bookmark) — saved re-log table
  5. **History** (clock / calendar) — calendar + day log
- Add can also be a **center accent `+`** that presents the Add flow as a sheet (Notion-style FAB). Decide during Home build; default = tab.
- Each tab is a `NavigationStack`. Detail pages push; Add-food detail can present as a sheet.
- Bottom floating **"Ask AI"-style bar** from `IMG_4953` is optional/pro — stub it as a non-functional bar for now or skip.

---

## 3. Screens (build in this order)

### Screen 1 — **Today (Home dashboard)** `Features/Today/TodayView.swift`
**Reference image(s) — implement to match these exactly:**
- `UI/Required/Screenshot 2026-09-22 at 11.37.34 PM.png` — **primary** (hero **triple activity ring** + colored-dot legend + calm metric cards + bar/segment stats)
- `UI/Required/Screenshot 2026-09-22 at 11.38.32 PM.png` — "Today" card: hero ring + legend rows (Wear/Streak/Tray → **Carb/Protein/Fibre**) + stat pills (`33% Compliance`)
- `UI/Required/Screenshot 2026-09-22 at 11.38.17 PM.png` — calm card layout, big-number/uppercase-label metrics, **mini per-day rings row**
- `UI/Required/Screenshot 2026-09-22 at 11.38.25 PM.png` / `…11.38.40 PM.png` — session ring + metric-cell grid styling
- `UI/Screenshot 2026-09-22 at 11.26.02 PM.png` — Quick Actions + 4 metric cards structure (Notion Fitness Tracker)
- Today's-log table styling → `UI/IMG_4954.jpg` (Notion table, per §8)

Layout (vertical scroll):
1. **Header:** app icon/emoji (🍎) + large title "Today" + date subtitle (`Today, May 4, 2026` style) + optional streak pill.
2. **HERO — `ActivityRings` (3 concentric):** **Carb (outer) · Protein (middle) · Fibre (inner)**, Apple-Fitness style — gradient, rounded caps, glow, spring fill on appear. Center shows the primary number (e.g. calories `1,240` or the leading macro). Beside/below: **`RingLegend`** — `● Carb 120/250g`, `● Protein 90/150g`, `● Fibre 22/30g`. (Macros/colors changeable later via `RingColor`.) Ref: `…11.37.34`, `…11.38.32`.
3. **Quick Actions row:** ghost `QuickActionButton`s `+ Log Food`, `+ Scan`, `+ Quick Add`. Ref: `11.26.02`.
4. **Metric cards row** (calm cards, 3–4): **Calories**, **Protein**, **Carbs**, **Fibre** — `MetricCard` big-number over uppercase-gray-label, today vs target. Calm-card styling from §1.5 / `…11.38.17`.
5. **Today's log = `NotionTable`** grouped by meal (Breakfast / Lunch / Dinner / Snacks). Columns: `Food` (emoji+name) · `kcal` · `C` · `P` · `Fibre` · `Source` pill · time. Swipe row → Edit/Delete. `+ New page` footer.
   - Optional grouped **BoardColumn** per meal (like `Class Schedule` 11.24.16) — table is v1 default.

Mock: `MockStore.todayEntries: [LoggedEntry]`, `MockStore.targets` (carb/protein/fibre goals drive the rings).

**Done when:** the 3 rings render + animate (spring fill, staggered) and reflect mock carb/protein/fibre vs target; legend + calm metric cards render; meal table populated; swipe actions present (no-op ok); Reduce Motion snaps rings to final.

---

### Screen 2 — **Add / Search** `Features/Add/AddView.swift`
**Reference image(s) — implement to match these exactly:**
- `UI/IMG_4954.jpg` — **primary mobile** (Company Events: table w/ name + OPEN badge + Tags column + blue `+`)
- `UI/Screenshot 2026-09-22 at 11.14.32 PM.png` — INGREDIENTS table columns + "Add To Basket" button
- `UI/Screenshot 2026-09-22 at 11.14.43 PM.png` — same table, vertical scroll behaviour
- `UI/Screenshot 2026-09-22 at 11.25.31 PM.png` — segmented database tabs (Search | Scan)

Layout:
1. Title "Add Food" + `SegmentedTabs`: **Search** | **Scan** (Scan switches to Screen 3).
2. **Search field** (rounded, `.searchable`-style) with live filter of mock foods (debounced feel).
3. **Results = `NotionTable`**: columns `Food` (emoji + bold name + `GhostBadge` optional) · `Serving` · `Calories (kcal)` · `Protein (g)` · `Fat (g)` · `Carbs (g)` · `Source` pill · trailing **`Add To Basket`** button (exactly the INGREDIENTS screenshot).
4. Tapping a row → **Screen 4 (Detail)**. Tapping "Add To Basket" → quick-add toast.

Mock: `MockStore.foodDatabase: [Food]` (~30 foods matching the screenshot: Avocado 160, Banana 89, Broccoli 55, Carrot 41, Chocolate 546, Cheese 402, Cucumber 16, Orange 43, Bacon 541, Pork 297, Lamb 143, Turkey 294, Duck 135, Salmon 337, Olive Oil 900, Milk 50, Butter 717, Chicken 165 …).

**Done when:** typing filters the table live; source pills render; "Add To Basket" gives feedback; row → Detail.

---

### Screen 3 — **Scan (barcode)** `Features/Scan/ScanView.swift`
**Reference image(s):** none provided (no camera screenshot in `/UI`) — design as a minimal Liquid-Glass camera overlay consistent with the Notion dark theme. Not-found sheet reuses `TagPill`/button styles from the shared components.

Layout (UI-only, no real camera wiring yet):
1. Full-screen camera placeholder (dark) with a **glass scan frame** overlay + guidance text "Point at a barcode".
2. Top bar: close `✕`, torch toggle, "Enter manually" link.
3. On mock "scan success" (a debug button) → present **Detail** for a sample scanned product (e.g. Diet Mountain Dew, 355 ml, 0 kcal).
4. Not-found state → sheet: "No match — Add manually / Scan label" (buttons only, no OCR yet).

Note: real `DataScannerViewController` (VisionKit) is wired in the data phase; for UI, stub with `Camera unavailable` placeholder on simulator + a "Simulate scan" button.

**Done when:** scan screen presents with glass frame; simulate-scan pushes a Detail; not-found sheet shows.

---

### Screen 4 — **Food / Logged Item Detail** `Features/Detail/FoodDetailView.swift`
**Reference image(s) — implement to match these exactly:**
- `UI/Screenshot 2026-09-22 at 11.17.38 PM.png` — **primary** (Butter Milk: title + Time/Food Source/Comments/Type/Day/Tags property rows w/ pills)
- `UI/Screenshot 2026-09-22 at 11.17.48 PM.png` — Office Snacks: same property layout + bullet notes section

Layout (Notion property page):
1. Large **title** = food name.
2. **PropertyRows** (icon + gray label + value):
   - `Time` (calendar icon) — logged time / date
   - `Food Source` (source pill — "USDA Branded", "Processed"…)
   - `Serving` — **serving picker** (label serving, 100g, g, oz, ml, units) → menu
   - `Quantity` — stepper (recomputes nutrients live)
   - `Type` — meal type pill (Breakfast/Lunch/Dinner/Snacks)
   - `Tags` — multi `TagPill` (Savory / Good / Satisfying style)
   - `Comments` — free text ("Empty" placeholder)
3. **Live nutrient block:** kcal + P/C/F/fiber/sugar/sodium recomputed from quantity × per-100g. Show as a small `NotionTable` or property rows.
4. Optional **bullet notes** section (like Office Snacks' bullets).
5. Bottom actions: **`Log`** (accent) + **`Save to My Items`** (ghost).

Mock: `Food` → derive nutrients via `NutritionMath.compute(food, qty, unit)` (pure UI helper, real math per spec §7).

**Done when:** changing quantity/serving live-updates the nutrient numbers; Log/Save buttons present; pills + property rows match reference.

---

### Screen 5 — **My Items** `Features/MyItems/MyItemsView.swift`
**Reference image(s) — implement to match these exactly:**
- `UI/IMG_4953.PNG` — **primary mobile** (To-dos: checkbox column + emoji + bold name + OPEN badge + bottom floating bar)
- `UI/Screenshot 2026-09-22 at 11.20.34 PM.png` — Invoices gallery/board (optional card-grid variant)

Layout:
1. Title "My Items" + `NotionToolbar`.
2. **`NotionTable`**: `Food` (emoji+name) · `Last size` · `kcal` · `Source` pill · trailing **one-tap `Re-log`** button. Leading checkbox column optional (like To-dos).
3. Sort/segment: Recent | A–Z (`SegmentedTabs`).
4. Empty state: "No saved items yet — save foods from Detail."
5. (Optional) gallery/board variant toggle like Invoices cards.

Mock: `MockStore.myItems: [MyItem]`.

**Done when:** table lists saved items; Re-log fires a toast + (mock) adds to Today.

---

### Screen 6 — **Food Database** `Features/Foods/FoodsView.swift`
**Reference image(s) — implement to match these exactly:**
- `UI/Screenshot 2026-09-22 at 11.14.32 PM.png` — **primary** (Nutrition Targets mini-table on top + full INGREDIENTS table)
- `UI/Screenshot 2026-09-22 at 11.14.43 PM.png` — INGREDIENTS continued (scroll + `+ New page` footer)
- `UI/Screenshot 2026-09-22 at 11.15.56 PM.png` — `COUNT n` footer + multi-tag cell pattern (Exercises table)

This is the browsable full catalog (Add/Search is the quick-filter version).
1. Optional **Nutrition Targets** mini-table at top (Daily Calories / Protein / Carbs / Fats columns with the little ring cells) — matches 11.14.32 top.
2. Main **`NotionTable`** = all foods, same columns as Add, sortable by any column (tap header), source pills, `Add To Basket`.
3. `COUNT n` footer (like Exercises "COUNT 6").

**Done when:** full catalog scrolls (horizontal + vertical), header sort works, count footer shows.

---

### Screen 7 — **History** `Features/History/HistoryView.swift`
**Reference image(s) — implement to match these exactly, one per sub-view:**
- Calendar sub-view → `UI/Screenshot 2026-09-22 at 11.23.18 PM.png` (September month grid w/ event cards + status pills)
- Week sub-view → `UI/Screenshot 2026-09-22 at 11.15.01 PM.png` (Meal Plan: Day × Breakfast/Lunch/Dinner/Other grid)
- Board-by-day variant → `UI/Screenshot 2026-09-22 at 11.24.16 PM.png` (Class Schedule grouped by day)
- Status-pill styling reference → `UI/Screenshot 2026-09-22 at 11.21.19 PM.png` (Bug triage kanban: New/Triaging/In Progress/Fixed pills)

Layout (segmented: **Calendar** | **Week** | **List**):
1. **Calendar view:** month grid; each day cell shows small event cards with **status pill** (Under / Over / On-target color) + kcal total. From 11.23.18.
2. **Week view:** Day × meal grid (Mon…Sun rows × Breakfast/Lunch/Dinner/Other cols) like Meal Plan (11.15.01) — each cell lists logged foods.
3. **List view:** a `NotionTable` of past days: `Day` · `kcal` · `P/C/F` · on-target pill.
4. Tapping a day → day detail (reuse Today's table for that date).

Mock: `MockStore.history: [DayLog]` (14 days of sample data).

**Done when:** all three views render from mock history and switch via segment.

---

### Screen 8 (optional) — **Targets / Settings** `Features/Settings/`
**Reference image(s):** `UI/Screenshot 2026-09-22 at 11.14.32 PM.png` (Nutrition Targets table — top rows: Daily Calories / Protein / Carbs / Fats with ring cells). Editable via sliders/steppers. Powers the rings on Home. Build last.

---

## 4. Mock data layer (`Salorie/Mock/`) — build with the design system

Plain structs (UI-only; mirror spec §8 field names so the real SwiftData models drop in later):

```swift
enum FoodSource: String { case usdaFoundation, srLegacy, usdaBranded, off, custom }
enum MealType: String, CaseIterable { case breakfast, lunch, dinner, snacks }

struct Food: Identifiable {           // catalog entry
    let id: UUID
    var emoji: String                 // leading cell icon
    var name: String
    var brand: String?
    var source: FoodSource
    var per100gKcal, per100gProtein, per100gCarbs, per100gFat: Double
    var per100gFiber, per100gSugar, per100gSodiumMg: Double?
    var defaultServingG: Double?
    var householdServing: String?     // "1 can (355 ml)"
}

struct LoggedEntry: Identifiable {     // a row on Today
    let id: UUID
    var food: Food
    var mealType: MealType
    var quantity: Double
    var unit: String                   // g/ml/oz/serving/unit
    var time: Date
    var tags: [String]
    var kcal, proteinG, carbsG, fatG: Double   // snapshot
}

struct MyItem: Identifiable { let id: UUID; var food: Food; var lastQuantity: Double; var lastUnit: String; var lastUsed: Date }
struct DayLog: Identifiable { let id: UUID; var date: Date; var entries: [LoggedEntry]; var kcalTotal: Double }
struct Targets { var kcal: Double; var proteinG, carbsG, fatG, fibreG: Double }  // fibreG drives the 3rd ring

@Observable final class MockStore {
    var foodDatabase: [Food] = SampleData.foods   // ~30 foods from screenshots
    var todayEntries: [LoggedEntry] = SampleData.today
    var myItems: [MyItem] = SampleData.myItems
    var history: [DayLog] = SampleData.history
    var targets = Targets(kcal: 2000, proteinG: 150, carbsG: 250, fatG: 44, fibreG: 30)  // rings: carb/protein/fibre
}
```

`NutritionMath.compute(food:quantity:unit:)` — pure function, per spec §7 (`nutrient = per100g × grams/100`, oz=28.3495 g, fl oz≈29.5735 ml).

---

## 5. File / folder structure

```
Salorie/
  App/            SalorieApp.swift, RootView.swift, SalorieTabBar.swift
  DesignSystem/   Theme.swift (+ RingColor), Typography.swift, Spacing.swift
    Components/    TagPill, GhostBadge, SourceBadge, NotionTable, TableRow,
                   NotionToolbar, NewButton, PropertyRow, MetricCard,
                   ActivityRings, RingLegend, RingChart,
                   BoardColumn, QuickActionButton, SegmentedTabs
  Mock/           Models.swift, MockStore.swift, SampleData.swift, NutritionMath.swift
  Features/
    Today/  Add/  Scan/  Detail/  MyItems/  Foods/  History/  Settings/
  Resources/      Assets.xcassets (emoji handled as text, SF Symbols for icons)
```

---

## 6. Build order & per-screen checklist

Each screen: **preview components → assemble screen → run on iPhone 17/iOS 26 sim → screenshot vs reference → adjust.**

- [ ] **P0 Design system** — Theme (incl. `RingColor`), Typography, `TagPill`, `GhostBadge`, `NotionTable` + `TableRow`, `NotionToolbar`, `NewButton`, `PropertyRow`, `MetricCard` (calm card), **`ActivityRings` + `RingLegend`** (Apple-Fitness triple ring, spring fill), `RingChart` (single). Preview each — especially test the ring fill animation + Reduce Motion.
- [ ] **P0 App shell** — TabView + `SalorieTabBar`, empty screens wired.
- [ ] **P1 Today** (dashboard + meal table)
- [ ] **P2 Add/Search** (filterable INGREDIENTS table)
- [ ] **P3 Scan** (glass frame + simulate-scan)
- [ ] **P4 Detail** (property page + live nutrient math)
- [ ] **P5 My Items** (table + re-log)
- [ ] **P6 Foods** (full catalog + sort + count)
- [ ] **P7 History** (calendar / week / list)
- [ ] **P8 Targets/Settings** (optional)

### Skills to invoke (from the installed `.claude/skills/` set) — per phase

| Phase / task | Skill(s) to invoke | Why |
|---|---|---|
| **All SwiftUI work** | `dpearson-swiftui-patterns`, `avdlee-swiftui-expert-skill` | @Observable/MV data flow, view composition, modern-API review |
| **iOS 26/27 API correctness** | `xcode27-swiftui-whats-new-27`, `xcode27-swiftui-specialist`, `erkin-ios-swift-master` | Least-trained-on surface (new `@State` macro, toolbar, reorderable, deprecations) — consult before writing |
| **Design system tables/grids/scroll** | `dpearson-swiftui-layout-components` | `NotionTable`, pinned column, LazyVGrid, `.searchable`, forms |
| **Liquid Glass (tab bar, toolbars, sheets, scan frame)** | `dpearson-swiftui-liquid-glass`, `dimillian-swiftui-liquid-glass`, `zaki-claude-liquid-glass` | Native `glassEffect`/glass laws + **mandatory haptics** on every tap |
| **`ActivityRings` + `RingLegend` (Apple-Fitness rings)** | `dpearson-swiftui-animation` (**primary** — spring/phase fill, Reduce Motion), `dpearson-swift-charts` (alt/`Chart`-based), `2dubu-liquid-glass` (glow/material) | The ring fill, stagger, overshoot, and glow |
| **Navigation / tab bar / sheets / deep links** | `dpearson-swiftui-navigation` | TabView, NavigationStack, Detail sheet, Add flow |
| **Swipe actions, tap, steppers, gestures** | `dpearson-swiftui-gestures` | Today row swipe-edit/delete, quantity stepper |
| **Accessibility + Reduce Motion + `accessibilityIdentifier`** | `dpearson-ios-accessibility` | Ring Reduce-Motion snap, VoiceOver, stable ids for `snapshot_ui` |
| **Swift 6 concurrency (@Observable store, async)** | `dpearson-swift-concurrency`, `dimillian-swift-concurrency-expert` | Sendable/@MainActor on `MockStore`, no data races |
| **Number/date formatting (kcal, macros, times)** | `dpearson-swift-formatstyle` | Locale-aware `2,000 kcal`, `120g`, `May 4, 2026` |
| **Table scroll performance** | `dpearson-swiftui-performance`, `dimillian-swiftui-performance-audit` | Big food table smooth scroll, no body thrash |
| **Visual match to references** | `devanshu-design-audit` | Audit each screen vs its reference screenshot |
| **Scan screen (later data phase)** | `dpearson-vision-framework` | `DataScannerViewController`, barcode symbologies |
| **Build / run / screenshot-verify on sim** | `dimillian-ios-debugger-agent`, `dpearson-ios-simulator`, `xcode27-device-interaction` | XcodeBuildMCP build→run→screenshot loop, `simctl` |
| **Later phases** | `dpearson-swiftdata` (persistence), `dpearson-healthkit` (HKCorrelation), `dpearson-app-intents` (Siri), `dpearson-apple-on-device-ai` (NL parsing), `dpearson-swift-testing` (tests) | Out of UI scope; noted for continuity |

**Primary trio for this UI phase:** `dpearson-swiftui-animation` (rings) + `dpearson-swiftui-layout-components` (Notion tables) + `dpearson-swiftui-liquid-glass`/`zaki-claude-liquid-glass` (glass + haptics). Invoke `xcode27-swiftui-whats-new-27` **before** any iOS 27-specific API.

---

## 7. Screenshot → screen mapping (so nothing is missed)

### 7a. `UI/Required/` — calm cards & Apple-Fitness rings (dashboard look)
| Screenshot | Pattern | Salorie use |
|---|---|---|
| `Required/…11.37.34 PM.png` | hero triple activity ring + legend + calm cards + bar stats | **Today** hero rings + `ActivityRings`/`RingLegend` |
| `Required/…11.38.32 PM.png` | "Today" card: ring + dot-legend rows + stat pills | **Today** ring card + `RingLegend` + stat pills |
| `Required/…11.38.17 PM.png` | calm cards, big-number/uppercase metrics, mini per-day rings | **Today** metric cards + **History** mini-ring row |
| `Required/…11.38.25 PM.png` | session ring + metric-cell grid | ring center + metric-cell styling |
| `Required/…11.38.40 PM.png` | ring + compliance stat pills + day chips | stat pills + `RingChart` center |

### 7b. `UI/` — Notion tables, boards, property pages, calendar (data/list look)
| Screenshot | Notion pattern | Salorie screen |
|---|---|---|
| `IMG_4953` To-dos (mobile) | table + checkbox + OPEN badge + bottom bar | **My Items** table baseline / mobile table spec |
| `IMG_4954` Company Events (mobile) | table + Tags column + `+` button | **Add/Search** & any tag column |
| `11.14.32` Nutrition Targets + INGREDIENTS | targets mini-table + food table w/ Add To Basket | **Foods** + **Add** |
| `11.14.43` ingredients cont. | table vertical scroll | **Foods** scroll |
| `11.15.01` Meal Plan grid + Shopping List | Day×meal weekly grid | **History → Week** |
| `11.15.56` Exercise + Muscle Groups | table w/ multi-tag cells | `NotionTable` multi-pill cell |
| `11.17.38` Butter Milk | property page (Time/Source/Type/Day/Tags) | **Detail** |
| `11.17.48` Office Snacks | property page + bullet notes | **Detail** w/ notes |
| `11.20.34` Invoices by client | gallery/board cards | **My Items** gallery option |
| `11.21.19` Bug triage | kanban board + status pills | **History/board** pattern, status pills |
| `11.23.18` September | month calendar w/ event cards | **History → Calendar** |
| `11.24.16` Class Schedule | board grouped by day | **History → Week (board variant)** |
| `11.25.31` Workouts board + ring | board + monthly ring | dashboard board + rings |
| `11.25.38` Body Metrics + rings | table + 2 rings w/ target | **Today** rings |
| `11.26.02` Fitness Tracker | Quick Actions + 4 metric cards + calendar | **Today** primary layout |

---

## 8. Notion-table-on-iPhone spec (the make-or-break component)

From `IMG_4953` / `IMG_4954`, the table must:
- **Pin the first (name) column**; the rest scroll horizontally under it.
- Row = `[optional checkbox] · emoji/dot · bold name (truncate) · GhostBadge? · … trailing cells/pills/button`.
- Column header row: gray icon + gray label, tap to sort (arrow indicator).
- Hairline `divider` between rows and after the header.
- Footer: `+ New page` ghost row (tertiary text) and optional `COUNT n`.
- Toolbar (top-right): filter, sort, ⚡︎, ✦(AI), 🔍, ⤢, sliders, then blue `New ⌄` (or `+ ⌄` on mobile).
- Cells can host: text, number (right-ish), one-or-many `TagPill`, or an inline button ("Add To Basket" / "Re-log").
- Long-press / swipe row → context actions (open, delete). Tap row → Detail.

Implement once as `NotionTable<Row>` with a `[Column]` descriptor (title, icon, width, alignment, cell builder). Every screen configures columns; the component never changes.

---

## 9. Out of scope for this phase (comes later)
Real food DB (GRDB/FTS5), USDA/OFF import, barcode `DataScannerViewController`, HealthKit `HKCorrelation`, SwiftData persistence, App Intents/Siri, Foundation Models NL parsing, Background Assets, TestFlight. The mock `MockStore` is the seam where the real data layer plugs in.
