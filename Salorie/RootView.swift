import SwiftUI

/// Root native tab bar (Liquid Glass, automatic). Today · Add · Sharing.
/// Add is the single hub for logging — search, scan, quick-add, and your
/// history / meals / favorites / foods all live there.
struct RootView: View {
    @Environment(IslandController.self) private var island
    @Environment(MockStore.self) private var store
    @State private var selection: AppTab = RootView.initialTab

    enum AppTab: Hashable { case today, add, sharing }

    /// Screenshot/testing hook: `SALORIE_TAB=add` etc. selects the launch tab.
    /// Legacy `items` maps to Add, where saved items now live.
    static var initialTab: AppTab {
        switch ProcessInfo.processInfo.environment["SALORIE_TAB"] {
        case "add", "items": return .add
        case "sharing": return .sharing
        default: return .today
        }
    }

    var body: some View {
      GeometryReader { proxy in
        ZStack(alignment: .top) {
            TabView(selection: $selection) {
                Tab("Today", systemImage: "house.fill", value: AppTab.today) {
                    TodayView()
                }
                Tab("Add", systemImage: "plus.circle.fill", value: AppTab.add) {
                    AddView()
                }
                Tab("Sharing", systemImage: "person.2.fill", value: AppTab.sharing) {
                    SharingView()
                }
            }

            // The Dynamic-Island overlay lives in its own passthrough window (see
            // IslandWindowInstaller) so it floats ABOVE sheets — otherwise the
            // ingredient-picker sheet clips the meal-building card. Installed here
            // with the shared island + store instances.
            IslandWindowInstaller(island: island, store: store)
                .frame(width: 0, height: 0)
        }
        // Row tiles report frames here so flights line up with the island window
        // (both are full-screen, so screen coordinates match).
        .coordinateSpace(.named("screen"))
        // Feed the real top safe-area inset to the island (a UIKit window read
        // races the first layout; this GeometryReader value is reactive & correct).
        // Only feed the inset while idle, so hiding the status bar (which can shift
        // the inset) never repositions an open card mid-animation.
        .onAppear { island.topInset = proxy.safeAreaInsets.top }
        .onChange(of: proxy.safeAreaInsets.top) { _, new in
            if island.mode == .idle { island.topInset = new }
        }
        // NB: the status bar is hidden by IslandOverlay itself (it lives in the top
        // window, which is what iOS consults for the status bar). Requesting it here
        // too would be a second, lower-priority authority — the island window wins —
        // so we leave it to the overlay to avoid two windows fighting over the bar.
        .onAppear {
            let demo = ProcessInfo.processInfo.environment["SALORIE_ISLAND_DEMO"]
            let tile = CGRect(x: proxy.size.width / 2 - 17, y: proxy.size.height * 0.62,
                              width: 34, height: 34)
            if demo == "real" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    island.log(store.foods[0], slot: .breakfast, servings: 1, from: tile, store: store)
                }
            } else if demo == "tray" {
                // Fire six tray adds so the 4-slot cap + overflow badge can be verified.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.2))
                    for f in store.foods.prefix(6) {
                        island.addToTray(f, from: tile)
                        try? await Task.sleep(for: .milliseconds(750))
                    }
                }
            } else if demo == "meal" {
                // Build a tray then create the meal, to verify the meal card.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.2))
                    let foods = Array(store.foods.prefix(4))
                    for f in foods {
                        island.addToTray(f, from: tile)
                        try? await Task.sleep(for: .milliseconds(550))
                    }
                    try? await Task.sleep(for: .milliseconds(700))
                    let kcal = foods.reduce(0) { $0 + $1.calories }
                    let protein = Int(foods.reduce(0.0) { $0 + $1.protein }.rounded())
                    island.createMeal(name: "Power Oat Bowl", symbol: "cup.and.saucer.fill",
                                      tint: .green, items: foods, kcal: kcal, protein: protein)
                }
            }
        }
      }
    }
}

#Preview {
    RootView()
        .environment(MockStore())
        .environment(IslandController())
        .preferredColorScheme(.dark)
}
