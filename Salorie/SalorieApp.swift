import SwiftUI
import UIKit
import BackgroundTasks

@main
struct SalorieApp: App {
    /// Minimal delegate shim so a pure-SwiftUI app can receive background-URLSession
    /// relaunch events (there's no SwiftUI hook for `handleEventsForBackgroundURLSession`).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = MockStore(persistence: .shared)
    /// Drives the custom Dynamic-Island collect animations (a SwiftUI overlay,
    /// not ActivityKit — iOS hides our own Live Activity while in the foreground).
    @State private var island = IslandController()

    /// Background App Refresh identifier (declared in `BGTaskSchedulerPermittedIdentifiers`).
    static let catalogRefreshTaskID = "com.salorie.app.catalog-refresh"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(island)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task { island.bind(store: store) }
                .task {
                    // Opportunistic foreground check on launch. No-op unless a catalog
                    // host is configured; a newer DB installs for the next launch.
                    await CatalogDownloadManager.shared.check()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { Self.scheduleCatalogRefresh() }
                }
        }
        // Periodic background check to pull a fresh catalog build (plan §10). The system
        // decides timing; the closure kicks off a background download and reschedules.
        .backgroundTask(.appRefresh(Self.catalogRefreshTaskID)) {
            await CatalogDownloadManager.shared.check()
            Self.scheduleCatalogRefresh()
        }
    }

    /// Ask the system to run our refresh task again (no sooner than a day out). No-op
    /// when no catalog host is configured, so the default build schedules nothing.
    nonisolated static func scheduleCatalogRefresh() {
        guard RemoteConfig.catalogManifestURL != nil else { return }
        let request = BGAppRefreshTaskRequest(identifier: catalogRefreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// UIKit shim: forwards background-session completion events to the download manager.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        CatalogDownloadManager.shared.setBackgroundCompletionHandler(
            completionHandler, forSessionIdentifier: identifier)
    }
}
