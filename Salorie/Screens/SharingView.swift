import SwiftUI
import CloudKit

/// Posted after the app accepts an incoming CKShare link, so the Sharing tab can
/// refresh and show the newly-added friend.
extension Notification.Name {
    static let salorieDidAcceptShare = Notification.Name("salorie.didAcceptShare")
}

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

    // Invite flow (real CloudKit CKShare URL → system share sheet).
    @State private var isPreparingInvite = false
    @State private var inviteLink: InviteLink?      // non-nil ⇒ present the share sheet
    @State private var inviteError: String?
    @State private var showDataInfo = false         // "how sharing works" explainer

    /// Wraps the share URL so `.sheet(item:)` presents content atomically (no
    /// "sheet is up but URL is still nil" window) and auto-clears on dismiss.
    struct InviteLink: Identifiable { let id = UUID(); let url: URL }

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

    /// Screenshot hook: `SALORIE_SHARE_INDEX=1` starts the friend stack on that card.
    private static var launchIndex: Int {
        Int(ProcessInfo.processInfo.environment["SALORIE_SHARE_INDEX"] ?? "") ?? 0
    }

    /// True once at least one real (non-me) friend has been accepted.
    private var hasFriends: Bool { store.friends.contains { !$0.isMe } }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if hasFriends {
                    friendStack
                } else {
                    emptyState
                }
            }
            .background(Theme.bg)
            .task { await store.refreshFriends() }
            .onReceive(NotificationCenter.default.publisher(for: .salorieDidAcceptShare)) { _ in
                Task { await store.refreshFriends() }
            }
            .sheet(item: $inviteLink) { link in
                ActivityView(items: [link.url])
            }
            .alert("How sharing works", isPresented: $showDataInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Salorie shares only your daily nutrition rings, through your iCloud account. Friends see your progress after they accept your invite — and you can stop sharing at any time.")
            }
            .navigationTitle("Sharing")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: SharedFriend.self) { FriendDetailView(friend: $0) }
            .onAppear {
                // Screenshot hook: SALORIE_FRIEND=1 auto-pushes a friend detail (the
                // named friend, else the first non-me). No-ops safely when no real
                // friend has been added yet (roster is CloudKit-loaded, not seeded).
                if ProcessInfo.processInfo.environment["SALORIE_FRIEND"] == "1", path.isEmpty {
                    let name = ProcessInfo.processInfo.environment["SALORIE_FRIEND_NAME"]
                    if let friend = store.friends.first(where: { !$0.isMe && (name == nil || $0.name == name) }) {
                        path.append(friend)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await prepareInvite() }
                    } label: {
                        if isPreparingInvite {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .disabled(isPreparingInvite)
                    .accessibilityLabel("Invite a friend")
                }
            }
        }
    }

    // MARK: Friend stack (when there's at least one friend)

    private var friendStack: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader
                if let inviteError {
                    banner(inviteError)
                } else if let error = store.friendsError {
                    banner(error)
                }
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
        .scrollContentBackground(.hidden)
        .refreshable { await store.refreshFriends() }
    }

    // MARK: Empty state — no friends yet (Apple-Fitness "Share Activity", our palette,
    // centred, without the "Friend Suggestions" rail).

    private var emptyState: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 18) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)

                VStack(spacing: 10) {
                    Text("Share Activity")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Invite a friend to share daily nutrition rings. When they accept, their activity appears here.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await prepareInvite() }
                } label: {
                    Group {
                        if isPreparingInvite {
                            ProgressView().tint(.white)
                        } else {
                            Text("Invite a Friend")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .disabled(isPreparingInvite)
                .padding(.top, 4)

                Button { showDataInfo = true } label: {
                    Text("See how your data is managed…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)

                if let inviteError {
                    Text(inviteError)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 36)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Build (or reuse) my CKShare and hand its URL to the system share sheet.
    private func prepareInvite() async {
        isPreparingInvite = true
        inviteError = nil
        defer { isPreparingInvite = false }
        do {
            guard let url = try await store.sharingService.makeShareURL(for: store.meFriend) else {
                inviteError = "Couldn't create an invite link."
                return
            }
            inviteLink = InviteLink(url: url)
            HapticManager.shared.trigger(.light)
        } catch {
            inviteError = Self.inviteMessage(for: error)
            HapticManager.shared.trigger(.warning)
        }
    }

    private static func inviteMessage(for error: Error) -> String {
        switch (error as? CKError)?.code {
        case .notAuthenticated: return "Sign in to iCloud to share your rings."
        case .networkUnavailable, .networkFailure: return "You're offline — try again."
        default: return "Couldn't create an invite link. Try again."
        }
    }

    /// A dismissible inline error/status banner.
    private func banner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(text).font(.system(size: 13, weight: .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
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

// MARK: - System share sheet

/// Thin `UIActivityViewController` wrapper so we can present the CKShare URL from
/// SwiftUI (`ShareLink` needs its item up front; our URL is produced async).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview {
    SharingView()
        .environment(MockStore())
        .preferredColorScheme(.dark)
}
