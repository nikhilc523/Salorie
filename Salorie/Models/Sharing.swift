import SwiftUI
import CloudKit

// MARK: - Ring progress (a friend's daily activity, synced via CloudKit CKShare)

/// One day's ring completion for a person. Percentages are 0…∞ fractions of that
/// person's own goals (rings overshoot & wrap past 1, like `Ring`). `consumedCal`
/// / `goalCal` back the "277/300 CAL" line on each Sharing row.
struct RingProgress: Hashable, Sendable, Codable {
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
/// `id` is the calendar day itself so the strip keeps stable SwiftUI identity across
/// refreshes (a fresh `UUID()` per rebuild re-ran the ring load animation every time).
struct FriendDay: Identifiable, Hashable, Sendable {
    var id: Date { date }
    var date: Date
    var weekdayLetter: String
    var progress: RingProgress?
}

/// A person in the Sharing tab. `isMe` marks the current user's own row; when
/// `hasShared == false` the row/detail render em-dashes and faint empty rings.
struct SharedFriend: Identifiable, Hashable, Sendable {
    /// Stable identity: "me" for the current user, else the Apple ID (unique per
    /// person). Computed — NOT a stored `UUID()` — so rebuilding the roster on every
    /// `refreshFriends()` doesn't hand the same person a new id and churn navigation,
    /// `ForEach` identity, and ring animations. Equality/Hashing fold over content.
    var id: String { isMe ? "me" : appleID }
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

// MARK: - Wire format (the payload stored in a CloudKit CKShare root record)

/// The Codable snapshot of a person's rings that travels over CloudKit. It is JSON
/// stored in one `CKRecord` field so the schema is a single blob (no per-field
/// CloudKit indexing) and the on-device model can evolve without a schema change.
/// `id`/`isMe` are intentionally omitted — identity is the record, and "me" is a
/// local notion, never a shared attribute.
struct SharePayload: Codable, Sendable {
    var version: Int = 1
    var name: String
    var avatar: String
    var avatarTint: String        // TagColor rawValue
    var appleID: String
    var today: RingProgress?
    var last7: [Day]

    struct Day: Codable, Sendable {
        var date: Date
        var weekdayLetter: String
        var progress: RingProgress?
    }

    init(friend: SharedFriend) {
        name = friend.name
        avatar = friend.avatar
        avatarTint = friend.avatarTint.rawValue
        appleID = friend.appleID
        today = friend.today
        last7 = friend.last7.map { Day(date: $0.date, weekdayLetter: $0.weekdayLetter, progress: $0.progress) }
    }
}

extension SharedFriend {
    /// Rebuild a (non-me) friend from a decoded CloudKit payload. `hasShared` is
    /// derived from whether the sharer actually had ring data today.
    init(payload: SharePayload) {
        self.init(
            name: payload.name,
            avatar: payload.avatar,
            avatarTint: TagColor(rawValue: payload.avatarTint) ?? .gray,
            appleID: payload.appleID,
            isMe: false,
            hasShared: payload.today != nil,
            today: payload.today,
            last7: payload.last7.map { FriendDay(date: $0.date, weekdayLetter: $0.weekdayLetter, progress: $0.progress) }
        )
    }
}

// MARK: - Sharing service (CloudKit CKShare)
//
// ── Real-sharing architecture (CloudKit `CKShare`) ──
//
// Each user publishes ONE "RingShare" root record (today's RingProgress + last7,
// JSON-encoded into a single `payload` field) into a custom zone in their
// **private** database, then wraps it in a `CKShare`. Saving the record + share
// together yields a `share.url` — a normal https link that can be sent over
// iMessage, WhatsApp, or any channel. A recipient taps it → the system launches
// us with `application(_:userDidAcceptCloudKitShareWith:)` → we accept the share
// and afterwards read the sharer's record from `container.sharedCloudDatabase`.
// We keep our own record fresh (on each publish) so friends see today's rings.
//
// Why this and NOT Apple **Family Sharing**: Family Sharing is an account/
// purchase-and-subscription relationship — NOT a per-record data-sharing API.
// `CKShare` is record-level collaboration: any Apple ID with the app installed
// can accept, family or not.
//
// Setup (see project.yml + Salorie.entitlements + Info.plist):
//   • iCloud → CloudKit capability, container `iCloud.com.salorie.app`
//     (CODE_SIGN_ENTITLEMENTS wired in project.yml, needs a real DEVELOPMENT_TEAM).
//   • Info.plist: `CKSharingSupported = YES` so the OS can launch us from a URL.
//   • `RemoteConfig.cloudKitContainerID` non-nil selects CloudKit over the mock.

/// Abstracts friend sharing so the UI is backend-agnostic. `CloudKitSharingService`
/// is the real backend; `MockSharingService` drives previews/tests offline.
@MainActor
protocol SharingService {
    /// Publish my latest rings and return a shareable https URL for the invite sheet.
    func makeShareURL(for me: SharedFriend) async throws -> URL?
    /// Push my latest rings so friends who already accepted see today's progress.
    func publish(_ me: SharedFriend) async throws
    /// Every friend whose share I've accepted (does NOT include me).
    func fetchFriends() async throws -> [SharedFriend]
}

/// Offline stand-in for previews and unit tests. Never touches the network.
@MainActor
final class MockSharingService: SharingService {
    func makeShareURL(for me: SharedFriend) async throws -> URL? {
        URL(string: "https://www.icloud.com/share/salorie-rings-mock")
    }
    func publish(_ me: SharedFriend) async throws { /* no-op */ }
    func fetchFriends() async throws -> [SharedFriend] { [] }
}

/// CloudKit `CKShare`-backed implementation. See the architecture note above.
@MainActor
final class CloudKitSharingService: SharingService {
    static let recordType = "RingShare"
    static let payloadKey = "payload"

    private let container: CKContainer
    /// My rings live in a dedicated custom zone (a CKShare root record must sit in a
    /// custom zone — the default zone cannot be shared).
    private let zoneID = CKRecordZone.ID(zoneName: "SalorieShares", ownerName: CKCurrentUserDefaultName)
    /// One fixed root-record name per user, so publish() upserts rather than piles up.
    private let rootRecordName = "myRings"
    private var didCreateZone = false

    init(containerID: String) {
        container = CKContainer(identifier: containerID)
    }

    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }
    private var rootRecordID: CKRecord.ID { CKRecord.ID(recordName: rootRecordName, zoneID: zoneID) }

    // MARK: Publish / invite (private DB)

    /// Fail fast (and clearly) when there's no usable iCloud account, rather than
    /// letting a deep CloudKit call throw an opaque error.
    private func ensureAccountAvailable() async throws {
        let status = try await container.accountStatus()
        guard status == .available else { throw CKError(.notAuthenticated) }
    }

    /// Create the custom zone once per session (idempotent server-side).
    private func ensureZone() async throws {
        guard !didCreateZone else { return }
        _ = try await privateDB.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        didCreateZone = true
    }

    /// Fetch my existing root record or make a fresh one, then stamp it with `me`.
    /// Self-heals if the custom zone was deleted server-side (recreates + retries once).
    private func upsertRootRecord(_ me: SharedFriend) async throws -> CKRecord {
        try await ensureZone()
        let record: CKRecord
        do {
            record = try await privateDB.record(for: rootRecordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.recordType, recordID: rootRecordID)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            didCreateZone = false
            try await ensureZone()
            record = CKRecord(recordType: Self.recordType, recordID: rootRecordID)
        }
        let data = try JSONEncoder().encode(SharePayload(friend: me))
        record[Self.payloadKey] = data as CKRecordValue
        return record
    }

    func makeShareURL(for me: SharedFriend) async throws -> URL? {
        try await ensureAccountAvailable()
        let record = try await upsertRootRecord(me)

        // Reuse an existing share if this record is already shared. Only re-create on
        // a genuine miss (`.unknownItem`); a transient error must propagate, not fall
        // through to `CKShare(rootRecord:)` (which would throw `.alreadyShared`).
        if let shareRef = record.share {
            do {
                if let existing = try await privateDB.record(for: shareRef.recordID) as? CKShare {
                    // Push the freshest payload alongside (last-writer-wins on my own blob).
                    _ = try await privateDB.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
                    return existing.url
                }
            } catch let error as CKError where error.code != .unknownItem {
                throw error
            }
        }

        let share = CKShare(rootRecord: record)
        share[CKShare.SystemFieldKey.title] = "\(me.name)'s Salorie rings" as CKRecordValue
        // Anyone with the link may read (no per-participant invite needed).
        share.publicPermission = .readOnly

        // Save record + share atomically; read the URL off the server-returned share.
        let saved = try await privateDB.modifyRecords(saving: [record, share], deleting: [], savePolicy: .changedKeys)
        guard case .success(let obj)? = saved.saveResults[share.recordID],
              let savedShare = obj as? CKShare,
              let url = savedShare.url else {
            throw CKError(.internalError)
        }
        return url
    }

    func publish(_ me: SharedFriend) async throws {
        try await ensureAccountAvailable()
        let record = try await upsertRootRecord(me)
        // Last-writer-wins on my own record so a concurrent publish never conflicts.
        _ = try await privateDB.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
    }

    // Accepting an incoming share is handled in the app delegate
    // (`application(_:userDidAcceptCloudKitShareWith:)`); afterwards its zone shows
    // up in the shared database and `fetchFriends()` reads it.

    // MARK: Fetch friends (shared DB)

    /// Read every accepted friend's RingShare record from the shared database. We
    /// direct-`record(for:)` the fixed `myRings` root in each shared zone rather than
    /// running a `CKQuery` — a query on `recordType` needs a "queryable" `recordName`
    /// index the schema doesn't define, so it would throw and yield zero friends.
    func fetchFriends() async throws -> [SharedFriend] {
        let zones: [CKRecordZone]
        do {
            zones = try await sharedDB.allRecordZones()
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            return []
        }
        var friends: [SharedFriend] = []
        for zone in zones {
            let recordID = CKRecord.ID(recordName: rootRecordName, zoneID: zone.zoneID)
            do {
                let record = try await sharedDB.record(for: recordID)
                if let friend = Self.friend(from: record) { friends.append(friend) }
            } catch {
                continue   // a single unreadable/absent zone shouldn't sink the whole list
            }
        }
        return friends
    }

    /// Decode a `RingShare` record's payload blob into a friend (nil if malformed).
    private static func friend(from record: CKRecord) -> SharedFriend? {
        guard let data = record[payloadKey] as? Data,
              let payload = try? JSONDecoder().decode(SharePayload.self, from: data) else { return nil }
        return SharedFriend(payload: payload)
    }
}
