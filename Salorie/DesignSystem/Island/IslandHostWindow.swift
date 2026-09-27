import SwiftUI
import UIKit

/// A borderless window that hosts the Dynamic-Island overlay ABOVE everything —
/// including `.sheet`s and `.fullScreenCover`s. The root ZStack can't do this: a
/// sheet presents above it and clips the island. A separate window at a high
/// window level floats over modals, so the island stays visible while you build a
/// meal in the ingredient-picker sheet. Touches pass straight through (the island
/// is non-interactive), so the app underneath stays fully usable.
private final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // The island never takes touches — let everything fall through to the app.
        nil
    }
}

/// Drop this in the main view hierarchy; it installs the island window once, wired
/// to the SAME `IslandController` / `MockStore` instances (both reference types, so
/// the floating overlay observes the same state the app mutates).
struct IslandWindowInstaller: UIViewRepresentable {
    let island: IslandController
    let store: MockStore

    func makeUIView(context: Context) -> UIView {
        let probe = UIView(frame: .zero)
        probe.isHidden = true
        probe.isUserInteractionEnabled = false
        // Wait a tick so `probe.window?.windowScene` is available.
        DispatchQueue.main.async {
            context.coordinator.install(from: probe, island: island, store: store)
        }
        return probe
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.install(from: uiView, island: island, store: store)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var window: PassthroughWindow?

        func install(from probe: UIView, island: IslandController, store: MockStore) {
            guard window == nil, let scene = probe.window?.windowScene else { return }
            let root = IslandOverlay()
                .environment(island)
                .environment(store)
            // A plain hosting controller (no status-bar overrides) so the island's
            // own `.statusBarHidden(...)` inside IslandOverlay drives the bar. Because
            // this window sits ABOVE the app, it's the one iOS consults for the status
            // bar — so hiding it here reliably clears the clock/wifi/battery while the
            // capsule is expanded (the whole "island swallowed the screen" illusion).
            let host = UIHostingController(rootView: root)
            host.view.backgroundColor = .clear

            let w = PassthroughWindow(windowScene: scene)
            w.rootViewController = host
            w.backgroundColor = .clear
            w.isUserInteractionEnabled = false
            // Above app content and sheets; below the system status bar so we don't
            // fight it.
            w.windowLevel = .normal + 3
            w.isHidden = false
            window = w
        }
    }
}
