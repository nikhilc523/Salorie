import Foundation
import SwiftData

// MARK: - Stored models (denormalized JSON snapshots)
//
// P5 keeps the whole UI speaking in value types (`Food` / `MealEntry` / …). Rather
// than re-modelling every nested type (ExtendedNutrients, Tag, TagColor, meal
// components) as SwiftData relationships, each row stores the **Codable snapshot**
// of the value it persists. This is the same "denormalized snapshot" principle the
// backend plan uses for logged history: the row is a frozen copy, so a food logged
// today never changes if its catalog entry later does.
//
// Only genuinely mutable *user* data lives here — logged entries, custom meals,
// saved/custom foods (which also carry the favorite flag), and macro targets. The
// read-only demo (7-day history, 120-day trend log, friends) is rebuilt from
// `SampleData` each launch and never persisted.

/// A saved single food (sample catalog seed + hand-entered custom foods). Carries
/// the favorite flag inside its JSON, so toggling a star survives relaunch.
@Model
final class StoredFood {
    #Unique<StoredFood>([\.foodID])
    var foodID: UUID
    var json: Data          // encoded `Food`
    var sortIndex: Int

    init(foodID: UUID, json: Data, sortIndex: Int) {
        self.foodID = foodID
        self.json = json
        self.sortIndex = sortIndex
    }
}

/// A user-built composite meal (`Food` with `kind == .custom`).
@Model
final class StoredMeal {
    #Unique<StoredMeal>([\.mealID])
    var mealID: UUID
    var json: Data          // encoded custom `Food`
    var sortIndex: Int

    init(mealID: UUID, json: Data, sortIndex: Int) {
        self.mealID = mealID
        self.json = json
        self.sortIndex = sortIndex
    }
}

/// One logged `MealEntry`. The food is stored as a frozen JSON snapshot; slot,
/// servings, and display time are plain columns. `loggedAt` gives a stable order.
@Model
final class StoredEntry {
    #Unique<StoredEntry>([\.entryID])
    var entryID: UUID
    var foodJSON: Data      // encoded `Food` snapshot
    var slotRaw: String
    var servings: Double
    var time: String
    var loggedAt: Date

    init(entryID: UUID, foodJSON: Data, slotRaw: String, servings: Double, time: String, loggedAt: Date) {
        self.entryID = entryID
        self.foodJSON = foodJSON
        self.slotRaw = slotRaw
        self.servings = servings
        self.time = time
        self.loggedAt = loggedAt
    }
}

/// The user's macro goals (single row).
@Model
final class StoredTargets {
    var calories: Int
    var carbs: Double
    var protein: Double
    var fibre: Double
    var fat: Double

    init(calories: Int, carbs: Double, protein: Double, fibre: Double, fat: Double) {
        self.calories = calories
        self.carbs = carbs
        self.protein = protein
        self.fibre = fibre
        self.fat = fat
    }
}

// MARK: - Controller

/// Owns the on-device `ModelContainer` for user data. `MockStore` reads and writes
/// through `context` on the main actor — no view touches SwiftData directly, so the
/// whole app keeps its `@Environment(MockStore.self)` surface unchanged.
@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    /// The schema for every user-data model. Kept in one place so tests can spin up
    /// an in-memory container with the exact same shape.
    static let schema = Schema([
        StoredFood.self, StoredMeal.self, StoredEntry.self, StoredTargets.self,
    ])

    init(inMemory: Bool = false) {
        let config = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: Self.schema, configurations: [config])
        } catch {
            // Never crash the app over a persistence failure (e.g. an incompatible
            // store during development): fall back to an ephemeral in-memory store.
            let fallback = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: Self.schema, configurations: [fallback])
        }
    }
}
