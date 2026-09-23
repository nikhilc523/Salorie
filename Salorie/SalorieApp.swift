import SwiftUI

@main
struct SalorieApp: App {
    @State private var store = MockStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
