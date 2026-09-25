import Foundation

/// The read-only food catalog behind **search** and **barcode** lookup.
///
/// Today an in-memory sample; in P2 a GRDB / SQLite-FTS5 store implements this same
/// protocol so the real database drops in with **zero view changes**. It is the seam
/// between the app and the (eventually huge) food DB.
///
/// `Sendable` + `async` on purpose: the real catalog runs its queries off the main
/// actor, and results (`Food` is `Sendable`) cross back safely.
protocol FoodCatalog: Sendable {
    /// Ranked matches for a text query over name/brand. Empty query → `[]`.
    func search(_ query: String, limit: Int) async -> [Food]
    /// The exact food for a scanned/entered barcode, if the catalog holds it.
    func food(forBarcode code: String) async -> Food?
    /// Household measures for a food (by catalog id), for the serving picker.
    func portions(forID id: String) async -> [FoodPortion]
}

extension FoodCatalog {
    /// Convenience with a sensible default page size.
    func search(_ query: String) async -> [Food] { await search(query, limit: 50) }
    /// Default: no household measures (the sample catalog has none).
    func portions(forID id: String) async -> [FoodPortion] { [] }
}

/// One household measure option for a food (label + gram weight).
struct FoodPortion: Hashable, Sendable {
    let label: String
    let grams: Double
}

/// In-memory catalog over a fixed `[Food]` (the bundled sample data).
///
/// A value type, so it's automatically `Sendable`; under strict concurrency its
/// `async` methods run off the caller's actor — the same shape the GRDB store will
/// take, so swapping it in later is a one-line change in `MockStore.init`.
struct SampleFoodCatalog: FoodCatalog {
    let foods: [Food]

    func search(_ query: String, limit: Int) async -> [Food] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return foods
            .filter {
                $0.name.localizedCaseInsensitiveContains(q)
                    || ($0.brand?.localizedCaseInsensitiveContains(q) ?? false)
            }
            .prefix(limit)
            .map { $0 }
    }

    func food(forBarcode code: String) async -> Food? {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return nil }
        return foods.first { $0.barcode == c }
    }
}
