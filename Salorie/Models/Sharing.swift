import SwiftUI

// MARK: - Ring progress (a friend's daily activity, mock now / CloudKit later)

/// One day's ring completion for a person. Percentages are 0…∞ fractions of that
/// person's own goals (rings overshoot & wrap past 1, like `Ring`). `consumedCal`
/// / `goalCal` back the "277/300 CAL" line on each Sharing row.
struct RingProgress: Hashable, Sendable {
    var caloriesPct: Double
    var proteinPct: Double
    var carbsPct: Double
    var consumedCal: Int
    var goalCal: Int

    /// The single headline percent shown big on a row — the calories (outer) ring.
    var overallPct: Double { caloriesPct }
    var overallPercentInt: Int { Int((overallPct * 100).rounded()) }

    /// `[Ring]` built exactly like TodayView's hero (Calories · Protein · Carbs),
    /// so `ActivityRings` / `MiniDayRing` reuse works unchanged.
    var rings: [Ring] {
        [
            Ring(progress: caloriesPct, color: .calories, label: "Calories",
                 valueText: "\(consumedCal)/\(goalCal)", unit: "CAL"),
            Ring(progress: proteinPct, color: .protein, label: "Protein",
                 valueText: "\(Int((proteinPct * 100).rounded()))%", unit: ""),
            Ring(progress: carbsPct, color: .carb, label: "Carbs",
                 valueText: "\(Int((carbsPct * 100).rounded()))%", unit: ""),
        ]
    }
}

extension RingProgress {
    /// Faint, empty rings for a person who hasn't shared yet (just the tracks).
    static var empty: [Ring] {
        [
            Ring(progress: 0, color: .calories, label: "Calories", valueText: "--/--", unit: "CAL"),
            Ring(progress: 0, color: .protein, label: "Protein", valueText: "--", unit: ""),
            Ring(progress: 0, color: .carb, label: "Carbs", valueText: "--", unit: ""),
        ]
    }
}

// MARK: - Friend day / friend

/// One day in a friend's Last-7-Days strip. `progress == nil` ⇒ no data shared.
struct FriendDay: Identifiable, Hashable, Sendable {
    let id = UUID()
    var date: Date
    var weekdayLetter: String
    var progress: RingProgress?
}

/// A person in the Sharing tab. `isMe` marks the current user's own row; when
/// `hasShared == false` the row/detail render em-dashes and faint empty rings.
struct SharedFriend: Identifiable, Hashable, Sendable {
    let id = UUID()
    var name: String
    var avatar: String       // emoji (e.g. "🐶") or an SF Symbol name
    var avatarTint: TagColor = .gray   // tinted circle behind an SF-Symbol avatar
    var appleID: String
    var isMe: Bool = false
    var hasShared: Bool = true
    var today: RingProgress?
    var last7: [FriendDay] = []

    /// True when `avatar` is an emoji glyph (render as Text) vs. an SF Symbol
    /// name (ASCII, render as Image). SF Symbol names are always ASCII.
    var isEmojiAvatar: Bool {
        !(avatar.unicodeScalars.first?.isASCII ?? true)
    }

    /// Rings for the compact row / hero — real progress, or faint empties.
    var displayRings: [Ring] {
        (hasShared ? today?.rings : nil) ?? RingProgress.empty
    }
}

// MARK: - Sharing service (mock now, CloudKit CKShare later)
//
// ── Real-sharing architecture (CloudKit `CKShare`, wire up in the data phase) ──
//
// Each user publishes ONE lightweight "RingShare" root record (today's
// RingProgress + last7) into a custom zone in their **private** database, then
// wraps it in a `CKShare`. Saving the record + share together yields a
// `share.url` — a normal https link that can be sent over iMessage, WhatsApp, or
// any channel. A recipient taps it → the system calls
// `userDidAcceptCloudKitShare(metadata:)` → we `container.accept([metadata])` and
// afterwards read their record from `container.sharedCloudDatabase`. We keep our
// own record fresh (daily, or via `BGTaskScheduler`) so friends see today's rings.
//
// Why this and NOT Apple **Family Sharing**: Family Sharing is an account/
// purchase-and-subscription relationship managed by Apple (payment, storage,
// Screen Time) — it is NOT a per-record data-sharing API and can't scope "share
// my rings with this one friend." `CKShare` is record-level collaboration: any
// Apple ID with the app installed can accept, family or not.
//
// Hard limits & cost:
//   • iOS/Apple-only — Android cannot accept a CKShare (no CloudKit client).
//   • 100 participants per share; plenty for a friends list.
//   • Cost: $0 beyond the $99/yr Apple Developer Program. CloudKit's free quota
//     scales with the app's user count and ring data is tiny (a few numbers/day).
//
// Entitlement/setup notes (scaffold, don't require a live iCloud account to run UI):
//   • Signing & Capabilities → iCloud → CloudKit; container e.g.
//     `iCloud.com.salorie.app`.
//   • Info.plist: `CKSharingSupported = YES` so the OS can launch us from a share URL.
//   • Handle the accept in the scene delegate / `.onOpenURL` bridge and route
//     into `SharingService.acceptShare(_:)`.

/// Abstracts friend sharing so the UI is backend-agnostic. `MockSharingService`
/// drives the current UI; `CloudKitSharingService` is stubbed for the data phase.
@MainActor
protocol SharingService {
    /// Present/produce a share invite (returns a share URL string when real).
    func invite() async throws -> URL?
    /// Accept an incoming share (opaque token/URL now; `CKShare.Metadata` later).
    func acceptShare(_ token: String) async throws
    /// The people I can see rings for (me first, then friends).
    func fetchFriends() async throws -> [SharedFriend]
    /// Publish my own rings so friends see today's progress.
    func publishMyRings(_ progress: RingProgress) async throws
}

/// In-memory sharing used by the UI phase. Reads seeded friends from the store.
@MainActor
final class MockSharingService: SharingService {
    private let store: MockStore
    init(store: MockStore) { self.store = store }

    func invite() async throws -> URL? {
        // Mock: a fake share URL of the shape CloudKit would return.
        URL(string: "https://www.icloud.com/share/salorie-rings-mock")
    }
    func acceptShare(_ token: String) async throws {
        // Mock: append a pending, not-yet-shared friend.
        store.friends.append(
            SharedFriend(name: "Pending Invite", avatar: "person.crop.circle.badge.plus",
                         appleID: "pending@privaterelay.appleid.com",
                         hasShared: false, today: nil, last7: SampleData.emptyLast7())
        )
    }
    func fetchFriends() async throws -> [SharedFriend] { store.friends }
    func publishMyRings(_ progress: RingProgress) async throws { /* no-op in mock */ }
}

/// CloudKit `CKShare`-backed implementation — filled in during the data phase.
/// See the architecture note above. Kept as a compiling stub so the UI ships now
/// and the wiring drops in without touching views.
@MainActor
final class CloudKitSharingService: SharingService {
    // let container = CKContainer(identifier: "iCloud.com.salorie.app")

    func invite() async throws -> URL? {
        // TODO: build the RingShare root record + CKShare, save both, return share.url.
        throw SharingError.notImplemented
    }
    func acceptShare(_ token: String) async throws {
        // TODO: container.accept([metadata]); then read from sharedCloudDatabase.
        throw SharingError.notImplemented
    }
    func fetchFriends() async throws -> [SharedFriend] {
        // TODO: query my private RingShare + each accepted share in the shared DB.
        throw SharingError.notImplemented
    }
    func publishMyRings(_ progress: RingProgress) async throws {
        // TODO: upsert my RingShare record in the private DB custom zone.
        throw SharingError.notImplemented
    }

    enum SharingError: Error { case notImplemented }
}
