import SwiftUI

/// Root native tab bar (Liquid Glass, automatic). Today · Add · Foods · My Items · History.
struct RootView: View {
    @State private var selection: AppTab = RootView.initialTab

    enum AppTab: Hashable { case today, add, foods, items, history }

    /// Screenshot/testing hook: `SALORIE_TAB=foods` etc. selects the launch tab.
    static var initialTab: AppTab {
        switch ProcessInfo.processInfo.environment["SALORIE_TAB"] {
        case "add": return .add
        case "foods": return .foods
        case "items": return .items
        case "history": return .history
        default: return .today
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "flame.fill", value: AppTab.today) {
                TodayView()
            }
            Tab("Add", systemImage: "plus.circle.fill", value: AppTab.add) {
                AddView()
            }
            Tab("Foods", systemImage: "fork.knife", value: AppTab.foods) {
                FoodDatabaseView()
            }
            Tab("My Items", systemImage: "square.stack.3d.up.fill", value: AppTab.items) {
                MyItemsView()
            }
            Tab("History", systemImage: "clock.fill", value: AppTab.history) {
                HistoryView()
            }
        }
    }
}

#Preview {
    RootView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
