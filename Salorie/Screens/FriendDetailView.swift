import SwiftUI

/// A person's Sharing detail, laid out like the Today screen: a big semicircle
/// "rising sun" of rings on a baseline, three stat columns, a 7-day strip, and the
/// Avg Cal / Streak cards. Opens from the friend card stack; the back button pops
/// to the same card. Data loading and the more-menu actions are unchanged — only
/// the layout and visuals are redesigned.
struct FriendDetailView: View {
    let friend: SharedFriend
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    // Palette (app tokens, matching the card stack).
    private let calColor = RingColor.calories.tint     // oatmeal
    private let proColor = RingColor.protein.tint      // caramel
    private let carbColor = RingColor.carb.tint        // terracotta
    private let labelColor = Color(hex: 0x8E857B)
    private let subLabelColor = Color(hex: 0xB9B1A8)
    private let baselineColor = Color(hex: 0x3C2C24)

    private var isSharing: Bool { friend.hasShared && friend.today != nil }
    private var today: RingProgress? { isSharing ? friend.today : nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                topBar
                header.padding(.top, 4)
                todayRings.padding(.top, 24)
                statColumns.padding(.top, 20)
                lastSevenHeading.padding(.top, 24)
                weekStrip.padding(.top, 12)
                statCards.padding(.top, 18)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .background(Theme.bg)
        .scrollContentBackground(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { appeared = true }
    }

    // MARK: Top bar (back + more)

    private var topBar: some View {
        HStack {
            circleButton("chevron.left", color: .white) { dismiss() }
            Spacer()
            Menu {
                Button { HapticManager.shared.trigger(.light) } label: {
                    Label("Hide my Activity", systemImage: "eye.slash")
                }
                Button(role: .destructive) { HapticManager.shared.trigger(.warning) } label: {
                    Label("Remove Friend", systemImage: "person.badge.minus")
                }
            } label: {
                circleLabel(Image(systemName: "ellipsis").foregroundStyle(Theme.accent))
            }
        }
        .frame(height: 60)
    }

    private func circleButton(_ system: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            circleLabel(Image(systemName: system).font(.system(size: 15, weight: .semibold)).foregroundStyle(color))
        }
        .buttonStyle(.plain)
    }

    private func circleLabel<Content: View>(_ content: Content) -> some View {
        content
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color(hex: 0x1F1D1B)))
            .overlay(Circle().strokeBorder(Color(hex: 0x2E2B28), lineWidth: 1))
    }

    // MARK: Header — avatar + ring badge, name, email

    private var header: some View {
        VStack(spacing: 0) {
            FriendAvatar(friend: friend, size: 84, showStatusDot: false)
                .overlay(alignment: .bottomTrailing) { ringBadge.offset(x: 16, y: 2) }

            Text(friend.isMe ? "Me" : friend.name)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 10)
            Text(friend.appleID)
                .font(.system(size: 14))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
    }

    /// Small ring badge on the avatar's corner — a black uneven capsule with a mini sun.
    private var ringBadge: some View {
        SemicircleRings(
            caloriesPct: today?.caloriesPct ?? 0,
            proteinPct: today?.proteinPct ?? 0,
            carbsPct: today?.carbsPct ?? 0,
            isSharing: isSharing,
            animateLoad: !reduceMotion, loadDelay: 0.3,
            width: 35, strokeRatio: 3.8 / 35, gapRatio: 1.5 / 35
        )
        .padding(EdgeInsets(top: 4, leading: 4, bottom: 2, trailing: 4))
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 8,
                                   bottomTrailingRadius: 8, topTrailingRadius: 30)
                .fill(Color.black)
        )
    }

    // MARK: Today's rings + baseline

    private var todayRings: some View {
        VStack(spacing: 4) {
            SemicircleRings(
                caloriesPct: today?.caloriesPct ?? 0,
                proteinPct: today?.proteinPct ?? 0,
                carbsPct: today?.carbsPct ?? 0,
                isSharing: isSharing,
                animateLoad: !reduceMotion, loadDelay: 0.2,
                width: 290, strokeRatio: 25.0 / 290, gapRatio: 6.0 / 290
            )
            Capsule().fill(baselineColor).frame(width: 314, height: 6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Three stat columns

    private var statColumns: some View {
        HStack(alignment: .top, spacing: 0) {
            statColumn(label: "Calories", value: caloriesValue, unit: "kcal", zero: "0",
                       sub: isSharing ? "of \((friend.today?.goalCal ?? 0).formatted())" : nil, color: calColor)
            statColumn(label: "Protein", value: pctNumber(\.proteinPct), unit: "%", zero: "0",
                       sub: isSharing ? "of goal" : nil, color: proColor)
            statColumn(label: "Carbs", value: pctNumber(\.carbsPct), unit: "%", zero: "0",
                       sub: isSharing ? "of goal" : nil, color: carbColor)
        }
        .padding(.horizontal, 8)
    }

    /// Matches the Today screen's macro row: big heavy number + small unit + status,
    /// with a tight 4-pt rhythm (same fonts/colours — just larger and neater).
    private func statColumn(label: String, value: String, unit: String, zero: String, sub: String?, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(labelColor)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text((appeared || !isSharing) ? value : zero)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(isSharing ? color : Theme.textTertiary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeOut(duration: 1.3).delay(0.2), value: appeared)
                if isSharing {
                    Text(unit)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x636366))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            if let sub {
                Text(sub)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(subLabelColor)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var caloriesValue: String {
        guard let t = today else { return "—" }
        return t.consumedCal.formatted()
    }
    private func pctNumber(_ key: KeyPath<RingProgress, Double>) -> String {
        guard let t = today else { return "—" }
        return "\(Int((t[keyPath: key] * 100).rounded()))"
    }

    // MARK: Last 7 days

    private var lastSevenHeading: some View {
        HStack {
            Text("Last 7 Days")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(friend.last7.enumerated()), id: \.element.id) { i, day in
                let isToday = i == friend.last7.count - 1
                VStack(spacing: 8) {
                    Text(day.weekdayLetter)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isToday ? Theme.bg : labelColor)
                        .frame(width: 24, height: 24)
                        .background { if isToday { Circle().fill(calColor) } }
                    SemicircleRings(
                        caloriesPct: day.progress?.caloriesPct ?? 0,
                        proteinPct: day.progress?.proteinPct ?? 0,
                        carbsPct: day.progress?.carbsPct ?? 0,
                        isSharing: day.progress != nil,
                        animateLoad: !reduceMotion, loadDelay: 0.5 + Double(i) * 0.08,
                        width: 40, strokeRatio: 4.5 / 40, gapRatio: 1.35 / 40
                    )
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Avg Cal / Streak cards

    private var statCards: some View {
        HStack(spacing: 10) {
            metricCard(label: "Avg Cal", value: avgCalText, unit: avgCalText == "--" ? "" : "cal", delay: 0.60)
            metricCard(label: "Streak", value: streakText, unit: streakText == "--" ? "" : "days", delay: 0.68)
        }
    }

    private func metricCard(label: String, value: String, unit: String, delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(labelColor)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(appeared ? value : (value == "--" ? "--" : "0"))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(value == "--" ? Theme.textTertiary : Theme.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeOut(duration: 1.3).delay(0.2), value: appeared)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 15)).foregroundStyle(labelColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: 0x1C1B19)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color(hex: 0x2A2724), lineWidth: 1))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.6).delay(delay), value: appeared)
    }

    // MARK: Derived data (unchanged)

    private var sharedDays: [RingProgress] { friend.last7.compactMap(\.progress) }

    private var avgCalText: String {
        guard friend.hasShared else { return "--" }
        let present = sharedDays.filter { $0.consumedCal > 0 }
        guard !present.isEmpty else { return "0" }
        return (present.map(\.consumedCal).reduce(0, +) / present.count).formatted()
    }

    private var streakText: String {
        guard friend.hasShared else { return "--" }
        var streak = 0
        for day in friend.last7.reversed() {
            if let p = day.progress, p.consumedCal > 0 { streak += 1 } else { break }
        }
        return "\(streak)"
    }
}

#Preview("Detail — normal") {
    NavigationStack {
        FriendDetailView(friend: MockStore().friends.first { $0.hasShared && ($0.today?.consumedCal ?? 0) > 0 } ?? MockStore().friends[0])
            .environment(MockStore())
    }
    .preferredColorScheme(.dark)
}

#Preview("Detail — not sharing") {
    NavigationStack {
        FriendDetailView(friend: MockStore().friends.first { !$0.hasShared } ?? MockStore().friends[0])
            .environment(MockStore())
    }
    .preferredColorScheme(.dark)
}
