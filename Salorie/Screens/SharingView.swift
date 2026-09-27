import SwiftUI

/// Sharing — family/friends' daily activity rings (Apple Fitness "Sharing" clone,
/// minus Highlights/Awards/Competitions). Rows drill into a person's detail.
struct SharingView: View {
    @Environment(MockStore.self) private var store

    enum Sort: String, CaseIterable, Identifiable {
        case name = "Name", rings = "Rings"
        var id: String { rawValue }
    }
    @State private var sort: Sort = .name
    @State private var path = NavigationPath()

    /// Me is always pinned first; the rest sort by the chosen key.
    private var orderedFriends: [SharedFriend] {
        let me = store.friends.filter(\.isMe)
        let others = store.friends.filter { !$0.isMe }
        let sorted: [SharedFriend]
        switch sort {
        case .name:  sorted = others.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .rings: sorted = others.sorted { ($0.today?.overallPct ?? -1) > ($1.today?.overallPct ?? -1) }
        }
        return me + sorted
    }

    /// Mock invite link — a CloudKit share URL shape (see SharingService note).
    private var inviteURL: URL { URL(string: "https://www.icloud.com/share/salorie-rings-mock")! }

    /// Screenshot hook: `SALORIE_SHARE_INDEX=1` starts the friend stack on that card.
    private static var launchIndex: Int {
        Int(ProcessInfo.processInfo.environment["SALORIE_SHARE_INDEX"] ?? "") ?? 0
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader
                    FriendStackView(friends: orderedFriends, onOpen: { friend in
                        HapticManager.shared.trigger(.light)
                        path.append(friend)
                    }, initialIndex: Self.launchIndex)
                    .id(sort)   // reset to the first card when the sort order changes
                    .padding(.top, 6)
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle("Sharing")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: SharedFriend.self) { FriendDetailView(friend: $0) }
            .onAppear {
                // Screenshot hook: SALORIE_FRIEND=1 auto-pushes a friend detail
                // (Niharika, the pending "--" person, mirroring IMG_5019).
                if ProcessInfo.processInfo.environment["SALORIE_FRIEND"] == "1",
                   path.isEmpty,
                   let friend = store.friends.first(where: { $0.name == (ProcessInfo.processInfo.environment["SALORIE_FRIEND_NAME"] ?? "Niharika") }) ?? store.friends.first(where: { !$0.isMe }) {
                    path.append(friend)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: inviteURL,
                              subject: Text("Follow my Salorie rings"),
                              message: Text("Tap to see my daily nutrition rings on Salorie.")) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
        }
    }

    // MARK: Section header — "Activity Rings" + date + sort

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Activity Rings")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Today, \(store.today.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            sortMenu
        }
        .padding(.top, 2)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(Sort.allCases) { option in
                Button {
                    HapticManager.shared.trigger(.selection)
                    withAnimation(.snappy) { sort = option }
                } label: {
                    if sort == option { Label(option.rawValue, systemImage: "checkmark") }
                    else { Text(option.rawValue) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(sort.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(RingColor.protein.tint)
        }
    }
}

// MARK: - Avatar (emoji or SF Symbol) + status dot

struct FriendAvatar: View {
    let friend: SharedFriend
    var size: CGFloat = 32
    var showStatusDot: Bool = true

    private var statusColor: Color {
        friend.hasShared ? TagColor.green.fg : Theme.textTertiary
    }

    var body: some View {
        ZStack {
            Circle().fill(friend.isEmojiAvatar ? Theme.surfaceRaised : friend.avatarTint.bg)
            if friend.isEmojiAvatar {
                Text(friend.avatar).font(.system(size: size * 0.58))
            } else {
                Image(systemName: friend.avatar)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(friend.avatarTint.fg)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if showStatusDot {
                Circle()
                    .fill(statusColor)
                    .frame(width: size * 0.28, height: size * 0.28)
                    .overlay(Circle().stroke(Theme.bg, lineWidth: 2))
            }
        }
    }
}

#Preview {
    SharingView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
