import Testing
import Foundation
@testable import Salorie

/// P6: hosted-catalog delivery — the pure install/verify/version logic that decides
/// which SQLite the app opens and safely swaps in a downloaded build (plan §10).
@Suite struct CatalogInstallerTests {

    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func makeInstaller(_ dir: URL, suite: String) -> CatalogInstaller {
        CatalogInstaller(manifestURL: nil, supportDirectory: dir, defaultsSuiteName: suite)
    }

    private func freshSuite() -> String { "test.catalog.\(UUID().uuidString)" }

    @Test func manifestDecodesFromJSON() throws {
        let json = #"{"version":3,"url":"https://cdn.example.com/foods_v3.sqlite","sha256":"ABC123","bytes":100}"#
        let m = try JSONDecoder().decode(CatalogManifest.self, from: Data(json.utf8))
        #expect(m.version == 3)
        #expect(m.url.absoluteString == "https://cdn.example.com/foods_v3.sqlite")
        #expect(m.sha256 == "ABC123")
        #expect(m.bytes == 100)
    }

    @Test func sha256MatchesKnownVector() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("abc.bin")
        try Data("abc".utf8).write(to: f)
        // NIST vector: SHA-256("abc")
        #expect(CatalogInstaller.sha256(ofFileAt: f)
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func shouldDownloadOnlyWhenNewer() {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let suite = freshSuite()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let inst = makeInstaller(dir, suite: suite)
        let m = CatalogManifest(version: 1, url: URL(string: "https://e/x")!, sha256: "y", bytes: nil)
        #expect(inst.installedVersion == 0)
        #expect(inst.shouldDownload(m) == true)
    }

    @Test func verifyAndInstallSucceedsBumpsVersionAndBecomesPreferred() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let suite = freshSuite()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let inst = makeInstaller(dir, suite: suite)

        let src = tempDir().appendingPathComponent("dl.sqlite")
        let payload = Data("SQLITE-DB-CONTENT".utf8)
        try payload.write(to: src)
        let sha = try #require(CatalogInstaller.sha256(ofFileAt: src))
        let m = CatalogManifest(version: 5, url: URL(string: "https://e/x")!,
                                sha256: sha, bytes: Int64(payload.count))

        #expect(try inst.verifyAndInstall(downloadedFile: src, manifest: m))
        #expect(FileManager.default.fileExists(atPath: inst.downloadedURL.path))
        #expect(inst.installedVersion == 5)
        // A newly installed download is the preferred candidate over the bundled seed.
        #expect(inst.candidateDatabaseURLs().first == inst.downloadedURL)
        // Same build is no longer worth downloading.
        #expect(inst.shouldDownload(m) == false)
    }

    @Test func verifyRejectsBadChecksumAndLeavesStateUntouched() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let suite = freshSuite()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let inst = makeInstaller(dir, suite: suite)

        let src = tempDir().appendingPathComponent("dl.sqlite")
        try Data("corrupt".utf8).write(to: src)
        let m = CatalogManifest(version: 2, url: URL(string: "https://e/x")!,
                                sha256: "deadbeef", bytes: nil)   // wrong checksum

        #expect(throws: CatalogInstallError.self) {
            try inst.verifyAndInstall(downloadedFile: src, manifest: m)
        }
        #expect(inst.installedVersion == 0)                                   // not bumped
        #expect(!FileManager.default.fileExists(atPath: inst.downloadedURL.path))  // not installed
    }

    @Test func verifyRejectsSizeMismatch() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let suite = freshSuite()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let inst = makeInstaller(dir, suite: suite)

        let src = tempDir().appendingPathComponent("dl.sqlite")
        let payload = Data("12345".utf8)
        try payload.write(to: src)
        let sha = try #require(CatalogInstaller.sha256(ofFileAt: src))
        let m = CatalogManifest(version: 2, url: URL(string: "https://e/x")!,
                                sha256: sha, bytes: 999)   // wrong size

        #expect(throws: CatalogInstallError.self) {
            try inst.verifyAndInstall(downloadedFile: src, manifest: m)
        }
        #expect(inst.installedVersion == 0)
    }
}
