import Foundation
import CryptoKit

// MARK: - Manifest

/// Describes a hosted catalog build. Published as a tiny JSON manifest next to the
/// SQLite on the host (Cloudflare R2 / Background Assets / any HTTPS origin).
/// Bumping `version` is what tells clients to pull the new `url`.
///
/// ```json
/// { "version": 3,
///   "url": "https://cdn.salorie.app/catalog/salorie_foods_v3.sqlite",
///   "sha256": "9f86d0…",           // lowercase hex of the sqlite file
///   "bytes": 312283136 }
/// ```
struct CatalogManifest: Codable, Equatable, Sendable {
    var version: Int
    var url: URL
    var sha256: String
    var bytes: Int64?
}

// MARK: - Installer

/// The pure, testable core of catalog delivery (plan §10): where the on-device DB
/// lives, which build is installed, and how a downloaded file is verified and swapped
/// into place. The actual transfer is driven by `CatalogDownloadManager` (a background
/// `URLSession`); this type has **no** download side-effects, so every branch is
/// unit-testable without the network.
///
/// Offline-first & non-destructive:
/// - Resolution order is **downloaded copy → bundled seed → none** (→ SampleFoodCatalog).
/// - `RemoteConfig.catalogManifestURL == nil` (the default) means nothing ever downloads,
///   so the app behaves exactly like the bundled-only build until a host is configured.
/// - A downloaded DB is verified (size + SHA-256) and installed atomically; it becomes
///   active on the **next launch** (the running catalog is never swapped mid-session).
struct CatalogInstaller: Sendable {
    static let shared = CatalogInstaller()

    /// UserDefaults key holding the installed build version (0 = only the bundle).
    static let versionDefaultsKey = "salorie.catalog.installedVersion"

    var manifestURL: URL?
    var bundledName = "salorie_foods"
    var bundledExt = "sqlite"
    /// Injectable seams so the file/version logic is unit-testable in isolation.
    var supportDirectory: URL
    var bundle: Bundle
    var session: URLSession
    /// `nil` ⇒ `.standard`. A suite name (not a `UserDefaults` instance) keeps the type
    /// `Sendable`; tests pass an isolated suite so version state doesn't leak.
    var defaultsSuiteName: String?

    /// The version store, resolved from `defaultsSuiteName`.
    var defaults: UserDefaults { defaultsSuiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard }

    init(manifestURL: URL? = RemoteConfig.catalogManifestURL,
         supportDirectory: URL? = nil,
         bundle: Bundle = .main,
         session: URLSession = .shared,
         defaultsSuiteName: String? = nil) {
        self.manifestURL = manifestURL
        self.bundle = bundle
        self.session = session
        self.defaultsSuiteName = defaultsSuiteName
        self.supportDirectory = supportDirectory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    // MARK: Paths

    /// Where a downloaded catalog lives once installed.
    var downloadedURL: URL { supportDirectory.appendingPathComponent("salorie_foods.sqlite") }

    var bundledURL: URL? { bundle.url(forResource: bundledName, withExtension: bundledExt) }

    /// The databases to try opening, best first: a verified download, then the seed.
    /// The store opens the first that opens cleanly (a corrupt download falls through).
    func candidateDatabaseURLs() -> [URL] {
        var out: [URL] = []
        if FileManager.default.fileExists(atPath: downloadedURL.path) { out.append(downloadedURL) }
        if let b = bundledURL { out.append(b) }
        return out
    }

    // MARK: Version

    var installedVersion: Int { defaults.integer(forKey: Self.versionDefaultsKey) }

    /// A manifest is worth downloading only when it advertises a newer build.
    func shouldDownload(_ manifest: CatalogManifest) -> Bool { manifest.version > installedVersion }

    // MARK: Manifest (small GET — safe to run foreground)

    func fetchManifest(from url: URL) async -> CatalogManifest? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let data = try? await session.data(for: req).0 else { return nil }
        return try? JSONDecoder().decode(CatalogManifest.self, from: data)
    }

    // MARK: Verify + atomic install (pure file ops — unit-tested)

    /// Verify a downloaded file against the manifest (byte count if given + SHA-256),
    /// then move it into place atomically and record the new version. Returns `true`
    /// on success. Throws `CatalogInstallError` on a bad file so the caller can ignore it
    /// and leave the current DB untouched.
    @discardableResult
    func verifyAndInstall(downloadedFile tmp: URL, manifest: CatalogManifest) throws -> Bool {
        if let expected = manifest.bytes {
            let actual = (try FileManager.default.attributesOfItem(atPath: tmp.path)[.size] as? Int64)
            if let actual, actual != expected {
                throw CatalogInstallError.sizeMismatch(expected: expected, actual: actual)
            }
        }
        guard let digest = Self.sha256(ofFileAt: tmp) else { throw CatalogInstallError.unreadable }
        guard digest.caseInsensitiveCompare(manifest.sha256) == .orderedSame else {
            throw CatalogInstallError.checksumMismatch(expected: manifest.sha256, actual: digest)
        }
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let dst = downloadedURL
        if FileManager.default.fileExists(atPath: dst.path) {
            _ = try FileManager.default.replaceItemAt(dst, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: dst)
        }
        defaults.set(manifest.version, forKey: Self.versionDefaultsKey)
        return true
    }

    /// Streaming SHA-256 (1 MB chunks) so a ~300 MB DB is never loaded into memory.
    static func sha256(ofFileAt url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = (try? handle.read(upToCount: 1 << 20)) ?? nil
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum CatalogInstallError: Error, Equatable {
    case unreadable
    case sizeMismatch(expected: Int64, actual: Int64)
    case checksumMismatch(expected: String, actual: String)
}
