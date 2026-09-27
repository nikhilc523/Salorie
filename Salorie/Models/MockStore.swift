import SwiftUI
import Observation
import SwiftData

/// Single source of truth for the UI phase. `@Observable` so views update automatically.
/// Later this is replaced by the real (SwiftData/GRDB) store with identical surface.
@MainActor
@Observable
final class MockStore {
    var foods: [Food]
    var customMeals: [Food]        // user-built composite meals (kind == .custom)
    var todayEntries: [MealEntry]
    var targets: MacroTargets
    var friends: [SharedFriend]    // Sharing tab: me + family/friends' rings

    /// Seeded demo history — the past days. The final element is `today`
    /// (referenceDate); we never read its seeded entries directly. `history` /
    /// `dailyLog` below overlay the live `todayEntries` onto that last day so the
    /// week strips, DayDetail, and the trend graphs all show what Home shows.
    private var seededHistory: [DayLog]      // last 7 days (Today / DayDetail week strips)
    private var seededDailyLog: [DayLog]     // long run for trends (Week / Month / Year)
    /// Stable identity for today's live day so SwiftUI list/animation state survives recomputes.
    private let todayLogID = UUID()

    /// Today, built live from `todayEntries` — the single source that Home already uses.
    var todayLog: DayLog {
        DayLog(id: todayLogID, date: today,
               weekdayLetter: Self.weekdayLetter(for: today), entries: todayEntries)
    }

    /// Curated last 7 days, with today's slot replaced by the live `todayLog`.
    var history: [DayLog] { Self.overlayingToday(seededHistory, with: todayLog) }
    /// Long trend run, with today's slot replaced by the live `todayLog`.
    var dailyLog: [DayLog] { Self.overlayingToday(seededDailyLog, with: todayLog) }

    /// Replace the last (today) element of a seeded run with the live `today`,
    /// preserving that element's calendar date and weekday letter.
    private static func overlayingToday(_ days: [DayLog], with todayLog: DayLog) -> [DayLog] {
        // No seeded history (a fresh user) → today is still a real day: return it so
        // `history` is never empty (Day Detail / streak / sharing index into it safely).
        guard let last = days.last else { return [todayLog] }
        var out = days
        out[out.count - 1] = DayLog(id: todayLog.id, date: last.date,
                                    weekdayLetter: last.weekdayLetter, entries: todayLog.entries)
        return out
    }

    private static func weekdayLetter(for date: Date) -> String {
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        return letters[(Calendar.current.component(.weekday, from: date) - 1) % 7]
    }

    /// The read-only catalog behind search + barcode. Swap `SampleFoodCatalog`
    /// for the GRDB/SQLite store in P2 with no other change here.
    private let catalog: FoodCatalog
    /// Live lookup (OFF → USDA) for barcodes not in the bundled catalog.
    private let remote: RemoteFoodLookup
    /// Persistent cache of remotely-resolved foods, so a miss resolves once.
    private let cache: BarcodeCache
    /// SwiftData store for user data (entries / meals / saved foods / targets).
    /// `nil` in previews & tests → pure in-memory demo (the original behavior).
    private let persistence: PersistenceController?

    /// Fixed display date to match reference screens deterministically.
    let today: Date = SampleData.referenceDate

    /// The best available real catalog — a downloaded build (plan §10) if one is
    /// installed, else the bundled seed (466k+ foods), else the in-memory sample
    /// (previews / missing DB). A corrupt download falls through to the next candidate.
    static var defaultCatalog: FoodCatalog {
        for url in CatalogInstaller.shared.candidateDatabaseURLs() {
            if let catalog = GRDBFoodCatalog(fileURL: url) { return catalog }
        }
        return SampleFoodCatalog(foods: SampleData.foods)
    }

    init(catalog: FoodCatalog = MockStore.defaultCatalog,
         remote: RemoteFoodLookup = RemoteFoodService(),
         cache: BarcodeCache = BarcodeCache(),
         persistence: PersistenceController? = nil) {
        self.catalog = catalog
        self.remote = remote
        self.cache = cache
        self.persistence = persistence
        // "Empty start" (set by Settings → Delete all data) keeps the app blank on every
        // future launch: no demo history/trends and no reseed of foods/meals/entries.
        let emptyStart = UserDefaults.standard.bool(forKey: Self.emptyStartKey)
        // Read-only demo data — rebuilt from SampleData every launch, never persisted.
        // The last day of each is `today`; `history`/`dailyLog` overlay live entries there.
        self.seededHistory = emptyStart ? [] : SampleData.history()
        self.seededDailyLog = emptyStart ? [] : SampleData.extendedHistory()
        // User data — loaded from SwiftData when persistence is present (seeded from
        // SampleData on first launch), else the in-memory demo (previews / tests).
        self.foods = []
        self.customMeals = []
        self.todayEntries = []
        self.targets = SampleData.targets
        self.friends = []

        if let persistence {
            loadOrSeed(persistence.context)
        } else if !emptyStart {
            self.foods = SampleData.foods
            self.customMeals = SampleData.customMeals()
            self.todayEntries = SampleData.todayEntries()
        }

        // Me is built from this store's own day/history + friends are seeded.
        self.friends = [meFriend] + SampleData.otherFriends()
    }

    // MARK: Derived — today's totals

    var caloriesToday: Int { todayEntries.reduce(0) { $0 + $1.calories } }
    var carbsToday: Double { todayEntries.reduce(0) { $0 + $1.carbs } }
    var proteinToday: Double { todayEntries.reduce(0) { $0 + $1.protein } }
    var fibreToday: Double { todayEntries.reduce(0) { $0 + $1.fibre } }
    var fatToday: Double { todayEntries.reduce(0) { $0 + $1.fat } }

    /// Today's total for any nutrient — powers the user-selectable home cards.
    func todayValue(_ kind: StatKind) -> Double {
        todayEntries.reduce(0) { $0 + kind.entryValue($1) }
    }

    /// Consecutive most-recent days whose calories landed within ±10% of goal.
    /// Drives the home "goal streak" module (bounded by the demo history window).
    var goalStreak: Int {
        guard targets.calories > 0 else { return 0 }
        let lo = Double(targets.calories) * 0.9, hi = Double(targets.calories) * 1.1
        var streak = 0
        for day in history.reversed() {
            let c = Double(day.calories)
            if c >= lo && c <= hi { streak += 1 } else { break }
        }
        return streak
    }

    /// 0…∞ progress against target (rings can overshoot past 1).
    func progress(_ ring: RingColor) -> Double {
        switch ring {
        case .calories: return targets.calories > 0 ? Double(caloriesToday) / Double(targets.calories) : 0
        case .carb:     return targets.carbs    > 0 ? carbsToday   / targets.carbs   : 0
        case .protein:  return targets.protein  > 0 ? proteinToday / targets.protein : 0
        case .fibre:    return targets.fibre    > 0 ? fibreToday   / targets.fibre   : 0
        }
    }

    func consumed(_ ring: RingColor) -> Double {
        switch ring {
        case .calories: return Double(caloriesToday)
        case .carb: return carbsToday
        case .protein: return proteinToday
        case .fibre: return fibreToday
        }
    }

    func target(_ ring: RingColor) -> Double {
        switch ring {
        case .calories: return Double(targets.calories)
        case .carb: return targets.carbs
        case .protein: return targets.protein
        case .fibre: return targets.fibre
        }
    }

    var caloriesProgress: Double {
        targets.calories > 0 ? Double(caloriesToday) / Double(targets.calories) : 0
    }

    // MARK: Sharing — my own rings, exposed as a SharedFriend

    /// Build a `RingProgress` (fractions of my targets) from raw day totals.
    func ringProgress(calories: Int, protein: Double, carbs: Double) -> RingProgress {
        RingProgress(
            caloriesPct: targets.calories > 0 ? Double(calories) / Double(targets.calories) : 0,
            proteinPct:  targets.protein  > 0 ? protein / targets.protein : 0,
            carbsPct:    targets.carbs    > 0 ? carbs   / targets.carbs   : 0,
            consumedCal: calories, goalCal: targets.calories
        )
    }

    /// The current user as a `SharedFriend` — today from live totals, last 7 from history.
    var meFriend: SharedFriend {
        let last7 = history.map { day in
            FriendDay(date: day.date, weekdayLetter: day.weekdayLetter,
                      progress: ringProgress(calories: day.calories, protein: day.protein, carbs: day.carbs))
        }
        return SharedFriend(
            name: "Me", avatar: "person.fill", avatarTint: .blue, appleID: "you@icloud.com", isMe: true, hasShared: true,
            today: ringProgress(calories: caloriesToday, protein: proteinToday, carbs: carbsToday),
            last7: last7
        )
    }

    // MARK: Grouping

    func entries(for slot: MealSlot) -> [MealEntry] {
        todayEntries.filter { $0.slot == slot }
    }

    /// Single foods + custom meals, the full set favorites/My Items draw from.
    var searchableFoods: [Food] { customMeals + foods }

    /// Text search: your custom meals (shown first) merged with catalog hits.
    /// Async because the real catalog is a database query.
    func search(_ query: String) async -> [Food] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let meals = customMeals.filter { $0.name.localizedCaseInsensitiveContains(q) }
        let catalogHits = await catalog.search(q)
        return meals + catalogHits
    }

    /// Resolve a scanned barcode: bundled catalog → local cache → live OFF/USDA
    /// (cached on success). Returns nil only if nothing anywhere has it.
    func food(forBarcode code: String) async -> Food? {
        if let local = await catalog.food(forBarcode: code) { return local }
        let gtin = GRDBFoodCatalog.normalizeGTIN14(code) ?? code
        if let cached = cache.food(for: gtin) { return cached }
        if let fetched = await remote.lookup(barcode: code) {
            cache.insert(fetched)
            return fetched
        }
        return nil
    }

    /// Household measures (cup, slice, …) for a food's serving picker.
    func portions(for food: Food) async -> [FoodPortion] {
        guard let id = food.catalogID else { return [] }
        return await catalog.portions(forID: id)
    }

    /// Persist a hand-entered custom food. It joins "My Items" (Custom tab) and, if
    /// it has a barcode, is cached so a future scan of the same product resolves
    /// instantly. Idempotent by id (re-saving replaces the existing row).
    func saveCustomFood(_ food: Food) {
        if food.barcode != nil { cache.insert(food) }
        if let idx = foods.firstIndex(where: { $0.id == food.id }) {
            foods[idx] = food
        } else {
            foods.insert(food, at: 0)   // newest custom food on top of the Custom tab
        }
        persistFoods()
    }

    var favorites: [Food] { searchableFoods.filter(\.isFavorite) }

    // MARK: Recent & frequent (for quick re-log — derived from what you've logged)

    /// Every entry logged today + across history, newest first. Today comes from the
    /// live `todayEntries`; the past days come from `history` minus its last (today)
    /// slot, which now mirrors `todayEntries` and would otherwise double-count.
    private var loggedEntries: [MealEntry] {
        todayEntries.reversed() + history.dropLast().reversed().flatMap { $0.entries.reversed() }
    }

    /// Foods you log most often — the fastest re-log candidates.
    var frequentFoods: [Food] {
        var counts: [Food: Int] = [:]
        for entry in loggedEntries { counts[entry.food, default: 0] += 1 }
        return counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.name < $1.key.name }
            .map(\.key)
    }

    /// Foods you logged recently, newest first, de-duplicated.
    var recentFoods: [Food] {
        var seen = Set<Food>()
        return loggedEntries.compactMap { seen.insert($0.food).inserted ? $0.food : nil }
    }

    /// Recently-logged items paired with the **exact portion** they were logged at, so
    /// a one-tap re-log reproduces that portion (no guessing grams/servings). Deduped
    /// by food (name + brand), newest first — the fastest, unambiguous "+".
    struct RecentLog: Identifiable, Hashable {
        let id: UUID
        let food: Food
        let servings: Double
    }

    var recentLogItems: [RecentLog] {
        var seen = Set<String>()
        var out: [RecentLog] = []
        for entry in loggedEntries {
            let key = (entry.food.name + "|" + (entry.food.brand ?? "")).lowercased()
            if seen.insert(key).inserted {
                out.append(RecentLog(id: entry.id, food: entry.food, servings: entry.servings))
            }
        }
        return out
    }

    // MARK: Mutation (UI-phase only)

    /// Log a food/meal to a slot. `time` defaults to the current clock time (e.g.
    /// "3:42 PM") so the entry lands at the right spot on the DayDetail timeline and
    /// hourly charts; pass an explicit string only for seeded/demo data.
    func addEntry(_ food: Food, slot: MealSlot, servings: Double = 1, time: String? = nil) {
        let stamp = time ?? Date().formatted(date: .omitted, time: .shortened)
        let entry = MealEntry(food: food, slot: slot, servings: servings, time: stamp)
        todayEntries.append(entry)
        persistInsertEntry(entry)
    }

    /// Current favorite state for a food, resolved against the live store. A catalog
    /// or scanned food that hasn't been saved yet falls back to its own flag (false).
    func isFavorite(_ food: Food) -> Bool {
        if let m = customMeals.first(where: { $0.id == food.id }) { return m.isFavorite }
        if let f = foods.first(where: { $0.id == food.id }) { return f.isFavorite }
        return food.isFavorite
    }

    /// Flip favorite for any food and persist. A stored food/meal toggles in place; a
    /// catalog or scanned food that isn't saved yet is inserted into `foods` (favorited)
    /// so it shows up under Favorites and survives relaunch. Returns the new state.
    @discardableResult
    func toggleFavorite(_ food: Food) -> Bool {
        if let idx = customMeals.firstIndex(where: { $0.id == food.id }) {
            customMeals[idx].isFavorite.toggle()
            persistMeals()
            return customMeals[idx].isFavorite
        }
        if let idx = foods.firstIndex(where: { $0.id == food.id }) {
            foods[idx].isFavorite.toggle()
            persistFoods()
            return foods[idx].isFavorite
        }
        // Not saved yet → favoriting it saves a favorited copy so it's reachable & sticky.
        var copy = food
        copy.isFavorite = true
        foods.insert(copy, at: 0)
        persistFoods()
        return true
    }

    func removeEntry(_ entry: MealEntry) {
        todayEntries.removeAll { $0.id == entry.id }
        persistDeleteEntry(entry.id)
    }

    // MARK: Custom meals

    /// Add every ingredient of a custom meal to a slot as its own entry —
    /// used when the user wants the components broken out instead of one row.
    func logMealExpanded(_ meal: Food, slot: MealSlot, time: String? = nil) {
        // Stamp every component with one shared time so they group together on the timeline.
        let stamp = time ?? Date().formatted(date: .omitted, time: .shortened)
        for component in meal.components {
            addEntry(component.food, slot: slot, servings: component.servings, time: stamp)
        }
    }

    /// Insert a new custom meal (newest first) or replace an existing one by id.
    func saveMeal(_ meal: Food) {
        guard meal.kind == .custom else { return }
        if let idx = customMeals.firstIndex(where: { $0.id == meal.id }) {
            customMeals[idx] = meal
        } else {
            customMeals.insert(meal, at: 0)
        }
        persistMeals()
    }

    func deleteMeal(_ meal: Food) {
        customMeals.removeAll { $0.id == meal.id }
        persistMeals()
    }

    // MARK: - SwiftData persistence (no-ops when persistence == nil)

    /// JSON coders reused across every read/write of a value snapshot.
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Bump this whenever the bundled seed/catalog changes and stale persisted user data
    /// should be flushed on the next launch. A mismatch with the stored version wipes and
    /// reseeds automatically — no env var needed.
    static let seedVersion = 3
    private static let seedVersionKey = "salorie.seedVersion"

    /// Set once the user taps "Delete all data": keeps the app permanently empty
    /// (no demo seed) on every future launch. Cleared only by deleting/reinstalling
    /// the app, which restores the original demo start.
    static let emptyStartKey = "salorie.emptyStart"

    /// Wipe every piece of stored data and keep the app blank going forward — a true
    /// "start from the very beginning, empty" reset. Clears the live in-memory state
    /// immediately so the UI empties without a relaunch. Demo `otherFriends` remain
    /// (they're other people's mock rings, not your data); "Me" goes to zero.
    func resetAllData() {
        if let ctx = persistence?.context { wipe(ctx) }
        UserDefaults.standard.set(true, forKey: Self.emptyStartKey)
        foods = []
        customMeals = []
        todayEntries = []
        seededHistory = []
        seededDailyLog = []
        friends = [meFriend] + SampleData.otherFriends()
    }

    /// Load user data from SwiftData, seeding it from `SampleData` on first launch.
    /// Wipes + reseeds when `SALORIE_RESET=1` (screenshots/tests) or when the stored
    /// `seedVersion` is out of date (flushes stale data so new seed data is picked up).
    private func loadOrSeed(_ ctx: ModelContext) {
        let defaults = UserDefaults.standard
        let storedVersion = defaults.object(forKey: Self.seedVersionKey) as? Int
        let versionChanged = storedVersion != Self.seedVersion
        let reset = ProcessInfo.processInfo.environment["SALORIE_RESET"] == "1" || versionChanged
        if reset { wipe(ctx) }

        let isEmpty = (try? ctx.fetchCount(FetchDescriptor<StoredFood>())) ?? 0 == 0
            && (try? ctx.fetchCount(FetchDescriptor<StoredMeal>())) ?? 0 == 0
            && (try? ctx.fetchCount(FetchDescriptor<StoredEntry>())) ?? 0 == 0
            && (try? ctx.fetchCount(FetchDescriptor<StoredTargets>())) ?? 0 == 0
        // Never reseed once the user has chosen an empty start (Settings → Delete all data).
        if isEmpty && !defaults.bool(forKey: Self.emptyStartKey) { seed(ctx) }
        if versionChanged { defaults.set(Self.seedVersion, forKey: Self.seedVersionKey) }

        foods = fetchFoods(ctx)
        customMeals = fetchMeals(ctx)
        todayEntries = fetchEntries(ctx)
        if let t = fetchTargets(ctx) { targets = t }
    }

    /// Write the whole seed set once. Entry order is preserved via monotonic `loggedAt`.
    private func seed(_ ctx: ModelContext) {
        for (i, food) in SampleData.foods.enumerated() {
            if let json = try? Self.encoder.encode(food) {
                ctx.insert(StoredFood(foodID: food.id, json: json, sortIndex: i))
            }
        }
        for (i, meal) in SampleData.customMeals().enumerated() {
            if let json = try? Self.encoder.encode(meal) {
                ctx.insert(StoredMeal(mealID: meal.id, json: json, sortIndex: i))
            }
        }
        let base = SampleData.referenceDate
        for (i, entry) in SampleData.todayEntries().enumerated() {
            if let json = try? Self.encoder.encode(entry.food) {
                ctx.insert(StoredEntry(entryID: entry.id, foodJSON: json,
                                       slotRaw: entry.slot.rawValue, servings: entry.servings,
                                       time: entry.time, loggedAt: base.addingTimeInterval(Double(i))))
            }
        }
        let t = SampleData.targets
        ctx.insert(StoredTargets(calories: t.calories, carbs: t.carbs, protein: t.protein,
                                 fibre: t.fibre, fat: t.fat))
        try? ctx.save()
    }

    private func wipe(_ ctx: ModelContext) {
        try? ctx.delete(model: StoredFood.self)
        try? ctx.delete(model: StoredMeal.self)
        try? ctx.delete(model: StoredEntry.self)
        try? ctx.delete(model: StoredTargets.self)
        try? ctx.save()
    }

    // MARK: Fetch

    private func fetchFoods(_ ctx: ModelContext) -> [Food] {
        let rows = (try? ctx.fetch(FetchDescriptor<StoredFood>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        return rows.compactMap { try? Self.decoder.decode(Food.self, from: $0.json) }
    }

    private func fetchMeals(_ ctx: ModelContext) -> [Food] {
        let rows = (try? ctx.fetch(FetchDescriptor<StoredMeal>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        return rows.compactMap { try? Self.decoder.decode(Food.self, from: $0.json) }
    }

    private func fetchEntries(_ ctx: ModelContext) -> [MealEntry] {
        let rows = (try? ctx.fetch(FetchDescriptor<StoredEntry>(sortBy: [SortDescriptor(\.loggedAt)]))) ?? []
        return rows.compactMap { row in
            guard let food = try? Self.decoder.decode(Food.self, from: row.foodJSON),
                  let slot = MealSlot(rawValue: row.slotRaw) else { return nil }
            return MealEntry(id: row.entryID, food: food, slot: slot,
                             servings: row.servings, time: row.time)
        }
    }

    private func fetchTargets(_ ctx: ModelContext) -> MacroTargets? {
        guard let row = (try? ctx.fetch(FetchDescriptor<StoredTargets>()))?.first else { return nil }
        return MacroTargets(calories: row.calories, carbs: row.carbs, protein: row.protein,
                            fibre: row.fibre, fat: row.fat)
    }

    // MARK: Write-through
    //
    // `foods` and `customMeals` are small and bounded, so each mutation rewrites the
    // whole collection — the load order (`sortIndex`) then always matches the array,
    // with no min/max bookkeeping. Entries can grow unboundedly, so they're written
    // incrementally (insert on log, delete on remove).

    private func persistFoods() {
        guard let ctx = persistence?.context else { return }
        try? ctx.delete(model: StoredFood.self)
        for (i, food) in foods.enumerated() where (try? Self.encoder.encode(food)) != nil {
            ctx.insert(StoredFood(foodID: food.id, json: try! Self.encoder.encode(food), sortIndex: i))
        }
        try? ctx.save()
    }

    private func persistMeals() {
        guard let ctx = persistence?.context else { return }
        try? ctx.delete(model: StoredMeal.self)
        for (i, meal) in customMeals.enumerated() where (try? Self.encoder.encode(meal)) != nil {
            ctx.insert(StoredMeal(mealID: meal.id, json: try! Self.encoder.encode(meal), sortIndex: i))
        }
        try? ctx.save()
    }

    private func persistInsertEntry(_ entry: MealEntry) {
        guard let ctx = persistence?.context,
              let json = try? Self.encoder.encode(entry.food) else { return }
        ctx.insert(StoredEntry(entryID: entry.id, foodJSON: json, slotRaw: entry.slot.rawValue,
                               servings: entry.servings, time: entry.time, loggedAt: Date()))
        try? ctx.save()
    }

    private func persistDeleteEntry(_ id: UUID) {
        guard let ctx = persistence?.context else { return }
        try? ctx.delete(model: StoredEntry.self, where: #Predicate { $0.entryID == id })
        try? ctx.save()
    }
}
