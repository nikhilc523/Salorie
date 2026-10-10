import Foundation
import SwiftData

// MARK: - Stored models (denormalized JSON snapshots)
//
// P5 keeps the whole UI speaking in value types (`Food` / `MealEntry` / …). Rather
// than re-modelling every nested type (ExtendedNutrients, Tag, TagColor, meal
// components) as SwiftData relationships, each row stores the **Codable snapshot**
// of the value it persists — the same "denormalized snapshot" principle the backend
// plan uses for logged history: the row is a frozen copy, so a food logged today
// never changes if its catalog entry later does.
//
// P6 makes these models **CloudKit-compatible** (plan §10, optional sync): no unique
// constraints (CloudKit can't enforce them) and every stored attribute carries a
// default value (CloudKit must be able to populate one). That's harmless for the
// local-only default and lets `cloudKitDatabase: .private(...)` mirror the store to a
// user's private iCloud DB with no further model changes.
//
// Only genuinely mutable *user* data lives here — logged entries, custom meals,
// saved/custom foods (which also carry the favorite flag), and macro targets. The
// read-only demo (7-day history, 120-day trend log, friends) is rebuilt from
// `SampleData` each launch and never persisted.

/// A saved single food (sample catalog seed + hand-entered custom foods). Carries
/// the favorite flag inside its JSON, so toggling a star survives relaunch.
@Model
final class StoredFood {
    var foodID: UUID = UUID()
    var json: Data = Data()          // encoded `Food`
    var sortIndex: Int = 0

    init(foodID: UUID, json: Data, sortIndex: Int) {
        self.foodID = foodID
        self.json = json
        self.sortIndex = sortIndex
    }
}

/// A user-built composite meal (`Food` with `kind == .custom`).
@Model
final class StoredMeal {
    var mealID: UUID = UUID()
    var json: Data = Data()          // encoded custom `Food`
    var sortIndex: Int = 0

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
    var entryID: UUID = UUID()
    var foodJSON: Data = Data()      // encoded `Food` snapshot
    var slotRaw: String = ""
    var servings: Double = 0
    var time: String = ""
    var loggedAt: Date = Date.distantPast

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
    var calories: Int = 0
    var carbs: Double = 0
    var protein: Double = 0
    var fibre: Double = 0
    var fat: Double = 0

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
///
/// Container selection is a resilient 3-tier fallback (plan §10):
/// 1. **CloudKit** private DB — only when `RemoteConfig.cloudKitContainerID` is set
///    *and* the iCloud entitlement/account are available (init throws otherwise → next tier).
/// 2. **Local file** (`.none`) — the default; identical to the P5 store, same on-disk
///    URL, so existing data is preserved and later adopted by CloudKit if enabled.
/// 3. **In-memory** — last-resort so the app never crashes over persistence.
@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    /// True when the store is CloudKit-backed (surfaced for diagnostics / settings UI).
    let isCloudKitEnabled: Bool

    /// The schema for every user-data model. Kept in one place so tests can spin up an
    /// in-memory container with the exact same shape.
    static let schema = Schema([
        StoredFood.self, StoredMeal.self, StoredEntry.self, StoredTargets.self,
    ])

    init(inMemory: Bool = false, cloudKitContainerID: String? = RemoteConfig.cloudKitContainerID) {
        if inMemory {
            container = try! ModelContainer(
                for: Self.schema,
                configurations: [ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)])
            isCloudKitEnabled = false
            return
        }
        // Tier 1 — CloudKit private DB (same on-disk store URL so local data migrates up).
        if let ck = cloudKitContainerID,
           let c = try? ModelContainer(
               for: Self.schema,
               configurations: [ModelConfiguration(schema: Self.schema, cloudKitDatabase: .private(ck))]) {
            container = c
            isCloudKitEnabled = true
            return
        }
        // Tier 2 — local file, no sync (the P5 default; explicit `.none` so `.automatic`
        // never silently tries CloudKit via an unrelated entitlement).
        if let c = try? ModelContainer(
            for: Self.schema,
            configurations: [ModelConfiguration(schema: Self.schema, cloudKitDatabase: .none)]) {
            container = c
            isCloudKitEnabled = false
            return
        }
        // Tier 3 — ephemeral, so a persistence failure never crashes the app.
        container = try! ModelContainer(
            for: Self.schema,
            configurations: [ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)])
        isCloudKitEnabled = false
    }
}
