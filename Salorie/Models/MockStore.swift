import SwiftUI
import Observation

/// Single source of truth for the UI phase. `@Observable` so views update automatically.
/// Later this is replaced by the real (SwiftData/GRDB) store with identical surface.
@MainActor
@Observable
final class MockStore {
    var foods: [Food]
    var customMeals: [Food]        // user-built composite meals (kind == .custom)
    var todayEntries: [MealEntry]
    var history: [DayLog]          // curated last 7 days (Today / DayDetail week strips)
    var dailyLog: [DayLog]         // long run for History trends (Week / Month / Year)
    var targets: MacroTargets
    var friends: [SharedFriend]    // Sharing tab: me + family/friends' rings

    /// Fixed display date to match reference screens deterministically.
    let today: Date = SampleData.referenceDate

    init() {
        self.foods = SampleData.foods
        self.customMeals = SampleData.customMeals()
        self.todayEntries = SampleData.todayEntries()
        self.history = SampleData.history()
        self.dailyLog = SampleData.extendedHistory()
        self.targets = SampleData.targets
        self.friends = []
        // Me is built from this store's own day/history; friends are seeded.
        self.friends = [meFriend] + SampleData.otherFriends()
    }

    // MARK: Derived — today's totals

    var caloriesToday: Int { todayEntries.reduce(0) { $0 + $1.calories } }
    var carbsToday: Double { todayEntries.reduce(0) { $0 + $1.carbs } }
    var proteinToday: Double { todayEntries.reduce(0) { $0 + $1.protein } }
    var fibreToday: Double { todayEntries.reduce(0) { $0 + $1.fibre } }
    var fatToday: Double { todayEntries.reduce(0) { $0 + $1.fat } }

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

    /// Single foods + custom meals, the full set the search picker draws from.
    var searchableFoods: [Food] { customMeals + foods }

    /// Food matching a scanned barcode payload, if any.
    func food(forBarcode code: String) -> Food? {
        searchableFoods.first { $0.barcode == code }
    }

    var favorites: [Food] { searchableFoods.filter(\.isFavorite) }

    // MARK: Recent & frequent (for quick re-log — derived from what you've logged)

    /// Every entry logged today + across history, newest first.
    private var loggedEntries: [MealEntry] {
        todayEntries.reversed() + history.reversed().flatMap { $0.entries.reversed() }
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

    // MARK: Mutation (UI-phase only)

    func addEntry(_ food: Food, slot: MealSlot, servings: Double = 1, time: String = "Now") {
        todayEntries.append(MealEntry(food: food, slot: slot, servings: servings, time: time))
    }

    func toggleFavorite(_ food: Food) {
        if let idx = customMeals.firstIndex(where: { $0.id == food.id }) {
            customMeals[idx].isFavorite.toggle()
        } else if let idx = foods.firstIndex(where: { $0.id == food.id }) {
            foods[idx].isFavorite.toggle()
        }
    }

    func removeEntry(_ entry: MealEntry) {
        todayEntries.removeAll { $0.id == entry.id }
    }

    // MARK: Custom meals

    /// Add every ingredient of a custom meal to a slot as its own entry —
    /// used when the user wants the components broken out instead of one row.
    func logMealExpanded(_ meal: Food, slot: MealSlot, time: String = "Now") {
        for component in meal.components {
            addEntry(component.food, slot: slot, servings: component.servings, time: time)
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
    }

    func deleteMeal(_ meal: Food) {
        customMeals.removeAll { $0.id == meal.id }
    }
}
