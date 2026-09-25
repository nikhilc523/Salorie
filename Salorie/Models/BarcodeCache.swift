import Foundation

/// Persistent cache of foods resolved via the live API, keyed by GTIN-14 barcode,
/// so a barcode fetched once resolves instantly (and offline) forever after.
/// Stored as JSON in Documents (`Food` is `Codable`). Small by nature — only the
/// handful of items not already in the bundled 466k catalog.
@MainActor
final class BarcodeCache {
    private var map: [String: Food]
    private let url: URL

    init(filename: String = "barcode_cache.json") {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.url = dir.appendingPathComponent(filename)
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: Food].self, from: data) {
            self.map = decoded
        } else {
            self.map = [:]
        }
    }

    /// In-memory only (for tests / previews).
    init(inMemory foods: [Food]) {
        self.url = URL(fileURLWithPath: "/dev/null")
        self.map = Dictionary(uniqueKeysWithValues: foods.compactMap { f in f.barcode.map { ($0, f) } })
    }

    func food(for barcode: String) -> Food? { map[barcode] }

    func insert(_ food: Food) {
        guard let code = food.barcode else { return }
        map[code] = food
        save()
    }

    var count: Int { map.count }

    private func save() {
        guard url.path != "/dev/null" else { return }
        if let data = try? JSONEncoder().encode(map) { try? data.write(to: url, options: .atomic) }
    }
}
