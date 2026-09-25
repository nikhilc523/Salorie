import Foundation

/// Drives the out-of-band catalog transfer (plan §10) using a **background
/// `URLSession`**, so a ~300 MB DB download survives app suspension and even
/// termination — the system finishes it and relaunches us to install.
///
/// Flow: `check()` fetches the manifest, and if it advertises a newer build than the
/// one installed, enqueues a background download of the SQLite. When the transfer
/// finishes, the delegate moves the temp file into staging (synchronously, as the API
/// requires) and hands it to `CatalogInstaller.verifyAndInstall` (SHA-256 + atomic
/// swap). The new DB becomes active on the next launch.
///
/// Entirely dormant unless `RemoteConfig.catalogManifestURL` is set — no session is
/// even created, so the default build makes zero network calls.
final class CatalogDownloadManager: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = CatalogDownloadManager()

    static let sessionIdentifier = "com.salorie.app.catalog-download"
    private static let pendingManifestKey = "salorie.catalog.pendingManifest"

    private let installer = CatalogInstaller.shared
    private let lock = NSLock()
    private var backgroundCompletionHandler: (() -> Void)?

    /// The background session — created lazily so the default (no-host) build never
    /// spins one up. `sessionSendsLaunchEvents` relaunches us to finish/install.
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = true
        config.allowsCellularAccess = false        // a 300 MB DB should wait for Wi-Fi
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private var pendingManifest: CatalogManifest? {
        get {
            guard let data = installer.defaults.data(forKey: Self.pendingManifestKey) else { return nil }
            return try? JSONDecoder().decode(CatalogManifest.self, from: data)
        }
        set {
            if let m = newValue, let data = try? JSONEncoder().encode(m) {
                installer.defaults.set(data, forKey: Self.pendingManifestKey)
            } else {
                installer.defaults.removeObject(forKey: Self.pendingManifestKey)
            }
        }
    }

    private var stagingURL: URL {
        installer.supportDirectory.appendingPathComponent("salorie_foods.download.sqlite")
    }

    // MARK: Public API

    /// Check the host and enqueue a background download if a newer build exists.
    /// Safe to call on launch and from the background-refresh task; no-ops when no
    /// manifest host is configured or the current build is already latest.
    func check() async {
        guard let manifestURL = installer.manifestURL else { return }
        guard let manifest = await installer.fetchManifest(from: manifestURL),
              installer.shouldDownload(manifest) else { return }
        // Skip if a download for this exact build is already pending/in-flight.
        if pendingManifest == manifest { return }
        pendingManifest = manifest
        let task = session.downloadTask(with: manifest.url)
        task.resume()
    }

    /// Stash the system-provided completion handler when we're relaunched to finish a
    /// background transfer (called from the app delegate shim). Invoked once the
    /// session reports all events delivered.
    func setBackgroundCompletionHandler(_ handler: @escaping () -> Void, forSessionIdentifier id: String) {
        guard id == Self.sessionIdentifier else { return }
        _ = session   // ensure the session exists to receive the relaunch events
        lock.withLock { backgroundCompletionHandler = handler }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temp file is deleted the moment this method returns — move it out now.
        let staged = stagingURL
        let fm = FileManager.default
        try? fm.createDirectory(at: installer.supportDirectory, withIntermediateDirectories: true)
        try? fm.removeItem(at: staged)
        let moved = (try? fm.moveItem(at: location, to: staged)) != nil
        guard moved, let manifest = pendingManifest else { return }
        // Verify (SHA-256 over ~300 MB) + install off the delegate thread.
        Task.detached(priority: .utility) { [installer, staging = staged] in
            defer { try? FileManager.default.removeItem(at: staging) }
            do {
                try installer.verifyAndInstall(downloadedFile: staging, manifest: manifest)
                self.pendingManifest = nil
            } catch {
                // Bad checksum/size → discard; the current DB stays active, retry later.
                self.pendingManifest = nil
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // A failed transfer clears the pending marker so a later check() can retry.
        if error != nil { pendingManifest = nil }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = lock.withLock { () -> (() -> Void)? in
            let h = backgroundCompletionHandler
            backgroundCompletionHandler = nil
            return h
        }
        // Per the API contract, the stored handler must be called on the main thread.
        // The UIKit-provided closure isn't `Sendable`; box it to cross the hop.
        guard let handler else { return }
        let box = UncheckedSendableBox(handler)
        DispatchQueue.main.async { box.value() }
    }
}

/// Ferries a non-`Sendable` value across a concurrency boundary we've reasoned about
/// by hand (here: the system background-session completion handler → main thread).
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
