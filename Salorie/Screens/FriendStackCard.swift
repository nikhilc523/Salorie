import SwiftUI

/// One card in the friend stack — pure presentation, no gesture or index maths.
/// The parent applies all offset/scale/rotation/dim; this view just draws a single
/// resting card at the origin so SwiftUI only ever diffs transforms while dragging.
///
/// Visual language: an Apple-style hero card — a warm "sunrise" of rings crowning a
/// large avatar, with one big clean number below. Macro detail lives on the detail
/// screen, so the card stays calm and glanceable.
struct FriendStackCard: View {
    let friend: SharedFriend
    var animateLoad: Bool = true

    // Fixed card metrics (points).
    static let cardWidth: CGFloat = 232
    static let cardHeight: CGFloat = 330
    static let cornerRadius: CGFloat = 28

    private var rw: CGFloat { Self.cardWidth - 40 }                 // 192 rings width
    private var ri: CGFloat { SemicircleRings.innerEdgeRadius(width: rw) }
    private var baseline: CGFloat { SemicircleRings.baselineY(width: rw) }
    private var ringsHeight: CGFloat { SemicircleRings.height(width: rw) }

    /// Large hero avatar. Its top stays pinned just inside the inner arc (so it never
    /// touches the carbs ring) while it grows downward past the baseline.
    private var avatarD: CGFloat { (ri + 20).rounded() }            // ≈ 58
    private var avatarTopGap: CGFloat = 4
    private var avatarCenterY: CGFloat { (baseline - ri + avatarTopGap) + avatarD / 2 }
    private var ringsBlockHeight: CGFloat { max(ringsHeight, avatarCenterY + avatarD / 2 + 4) }

    private var isSharing: Bool { friend.hasShared && friend.today != nil }
    private var progress: RingProgress? { isSharing ? friend.today : nil }

    private let bloomColor = RingColor.calories.tint  // oatmeal glow
    private let captionColor = Color(hex: 0x9A9188)
    private let muted = Color(hex: 0x5A554E)
    private let sheen = LinearGradient(
        colors: [Color(hex: 0xF6F1E7), Color(hex: 0xDCD3C2)], startPoint: .top, endPoint: .bottom)

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 4)
            ringsWithAvatar
            textBlock.padding(.top, 14)
            Spacer(minLength: 4)
        }
        .padding(18)
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .background(cardBackground)
        .overlay(cardBorder)
        .shadow(color: .black.opacity(0.55), radius: 22, y: 18)
        .accessibilityHidden(true)   // the stack container is the a11y element
    }

    // MARK: Background — graded panel + soft sunrise bloom behind the rings

    private var cardBackground: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x24211F), Color(hex: 0x161513)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [bloomColor.opacity(isSharing ? 0.16 : 0.05), .clear],
                           center: UnitPoint(x: 0.5, y: 0.34), startRadius: 2, endRadius: 170)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [.white.opacity(0.10), Color(hex: 0x34312D).opacity(0.55)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
    }

    // MARK: Rings + hero avatar

    private var ringsWithAvatar: some View {
        ZStack(alignment: .top) {
            SemicircleRings(
                caloriesPct: progress?.caloriesPct ?? 0,
                proteinPct: progress?.proteinPct ?? 0,
                carbsPct: progress?.carbsPct ?? 0,
                isSharing: isSharing,
                animateLoad: animateLoad,
                width: rw
            )
            FriendAvatar(friend: friend, size: avatarD, showStatusDot: false)
                .overlay(Circle().strokeBorder(.white.opacity(0.09), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                .position(x: rw / 2, y: avatarCenterY)
        }
        .frame(width: rw, height: ringsBlockHeight)
    }

    // MARK: Name / hero number / caption

    private var textBlock: some View {
        VStack(spacing: 0) {
            Text(friend.isMe ? "Me" : friend.name)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            percentView
                .padding(.top, 4)

            Text(captionText)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(captionColor)
                .monospacedDigit()
                .padding(.top, 5)
        }
        .multilineTextAlignment(.center)
    }

    /// Apple-metric percentage: big digits with a smaller trailing "%".
    @ViewBuilder private var percentView: some View {
        if let p = progress {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(p.overallPercentInt)")
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .foregroundStyle(sheen)
                Text("%")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(sheen.opacity(0.85))
            }
            .monospacedDigit()
            .shadow(color: bloomColor.opacity(0.28), radius: 10)
        } else {
            Text("—")
                .font(.system(size: 58, weight: .bold, design: .rounded))
                .foregroundStyle(muted)
        }
    }

    private var captionText: String {
        guard let p = progress else { return "Not sharing" }
        return "\(p.consumedCal.formatted()) / \(p.goalCal.formatted()) CAL"
    }
}

#Preview("FriendStackCard") {
    ZStack {
        Theme.bg.ignoresSafeArea()
        HStack(spacing: 16) {
            FriendStackCard(friend: MockStore().friends.first { $0.hasShared && ($0.today?.consumedCal ?? 0) > 0 } ?? MockStore().friends[0])
            FriendStackCard(friend: MockStore().friends.first { !$0.hasShared } ?? MockStore().friends[0])
        }
    }
    .preferredColorScheme(.dark)
}
