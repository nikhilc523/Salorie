import SwiftUI
import Observation

/// Single source of truth for the UI phase. `@Observable` so views update automatically.
/// Later this is replaced by the real (SwiftData/GRDB) store with identical surface.
@MainActor
@Observable
final class MockStore {
    var foods: [Food]
    var todayEntries: [MealEntry]
    var history: [DayLog]
    var targets: MacroTargets

    /// Fixed display date to match reference screens deterministically.
    let today: Date = SampleData.referenceDate

    init() {
        self.foods = SampleData.foods
        self.todayEntries = SampleData.todayEntries()
        self.history = SampleData.history()
        self.targets = SampleData.targets
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

    // MARK: Grouping

    func entries(for slot: MealSlot) -> [MealEntry] {
        todayEntries.filter { $0.slot == slot }
    }

    var favorites: [Food] { foods.filter(\.isFavorite) }

    // MARK: Mutation (UI-phase only)

    func addEntry(_ food: Food, slot: MealSlot, servings: Double = 1, time: String = "Now") {
        todayEntries.append(MealEntry(food: food, slot: slot, servings: servings, time: time))
    }

    func toggleFavorite(_ food: Food) {
        guard let idx = foods.firstIndex(of: food) else { return }
        foods[idx].isFavorite.toggle()
    }

    func removeEntry(_ entry: MealEntry) {
        todayEntries.removeAll { $0.id == entry.id }
    }
}
