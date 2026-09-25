import SwiftUI

/// Root native tab bar (Liquid Glass, automatic). Today · Add · Sharing.
/// Add is the single hub for logging — search, scan, quick-add, and your
/// history / meals / favorites / foods all live there.
struct RootView: View {
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
    }
}

#Preview {
    RootView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
