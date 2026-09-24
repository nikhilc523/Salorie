import SwiftUI

/// Root native tab bar (Liquid Glass, automatic). Today · Add · My Items · Sharing.
struct RootView: View {
    @State private var selection: AppTab = RootView.initialTab

    enum AppTab: Hashable { case today, add, items, sharing }

    /// Screenshot/testing hook: `SALORIE_TAB=add` etc. selects the launch tab.
    static var initialTab: AppTab {
        switch ProcessInfo.processInfo.environment["SALORIE_TAB"] {
        case "add": return .add
        case "items": return .items
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
            Tab("My Items", systemImage: "bookmark.fill", value: AppTab.items) {
                MyItemsView()
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
