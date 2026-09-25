import Testing
import Foundation
import SwiftData
@testable import Salorie

/// P5: SwiftData-backed user data — seed on first launch, then persist every
/// mutation (log / favorite / custom meal / custom food) across store instances.
@MainActor
@Suite struct PersistenceTests {

    /// A store backed by a fresh in-memory SwiftData container + the sample catalog
    /// (so tests never load the 312 MB bundled DB or hit the network).
    private func store(_ p: PersistenceController) -> MockStore {
        MockStore(catalog: SampleFoodCatalog(foods: SampleData.foods),
                  cache: BarcodeCache(inMemory: []),
                  persistence: p)
    }

    @Test func firstLaunchSeedsFromSampleData() {
        let p = PersistenceController(inMemory: true)
        let s = store(p)
        #expect(!s.foods.isEmpty)
        #expect(s.customMeals.count == SampleData.customMeals().count)
        #expect(s.todayEntries.count == SampleData.todayEntries().count)
        #expect(s.targets == SampleData.targets)
    }

    @Test func loggedEntryPersistsAcrossReload() {
        let p = PersistenceController(inMemory: true)
        let first = store(p)
        let before = first.todayEntries.count
        first.addEntry(SampleData.foods[1], slot: .lunch, servings: 2, time: "1:00 PM")

        let reloaded = store(p)     // new instance, same container
        #expect(reloaded.todayEntries.count == before + 1)
        let logged = reloaded.todayEntries.last
        #expect(logged?.food.name == SampleData.foods[1].name)
        #expect(logged?.slot == .lunch)
        #expect(logged?.servings == 2)
    }

    @Test func removingEntryPersists() {
        let p = PersistenceController(inMemory: true)
        let first = store(p)
        first.addEntry(SampleData.foods[0], slot: .snacks)
        let target = first.todayEntries.last!
        first.removeEntry(target)

        let reloaded = store(p)
        #expect(!reloaded.todayEntries.contains { $0.id == target.id })
    }

    @Test func favoriteTogglePersists() {
        let p = PersistenceController(inMemory: true)
        let first = store(p)
        let food = first.foods[0]
        let wasFavorite = food.isFavorite
        first.toggleFavorite(food)

        let reloaded = store(p)
        let same = reloaded.foods.first { $0.id == food.id }
        #expect(same?.isFavorite == !wasFavorite)
    }

    @Test func customMealPersistsAndDeletes() {
        let p = PersistenceController(inMemory: true)
        let first = store(p)
        let meal = Food.customMeal(name: "Test Bowl",
                                   components: [MealComponent(food: SampleData.foods[2], servings: 1)])
        first.saveMeal(meal)
        #expect(store(p).customMeals.contains { $0.id == meal.id })

        first.deleteMeal(meal)
        #expect(!store(p).customMeals.contains { $0.id == meal.id })
    }

    @Test func customFoodJoinsMyItemsAndPersists() {
        let p = PersistenceController(inMemory: true)
        let first = store(p)
        let custom = Food(symbol: "fork.knife", tint: .gray, name: "Hand Entered",
                          source: .custom, servingDescription: "1 serving",
                          calories: 200, carbs: 20, protein: 10, fat: 8, fibre: 2)
        first.saveCustomFood(custom)
        #expect(first.foods.contains { $0.id == custom.id })

        let reloaded = store(p)
        let same = reloaded.foods.first { $0.id == custom.id }
        #expect(same?.name == "Hand Entered")
        #expect(same?.source == .custom)
    }

    @Test func extendedNutrientsSurviveRoundTrip() {
        let p = PersistenceController(inMemory: true)
        // Greek Yogurt carries extended nutrients + a Nutri-Score in SampleData.
        let seeded = store(p).foods.first { $0.name == "Greek Yogurt, Plain" }
        #expect(seeded?.extended.potassium == 240)
        #expect(seeded?.extended.nutriScore == "B")
        #expect(seeded?.isFavorite == true)
    }
}
