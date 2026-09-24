import SwiftUI

/// A person's Sharing detail (Apple Fitness person screen, minus Competitions):
/// big avatar + name + Apple ID, a Last-7-Days ring strip, the day's triple rings
/// with a legend, and two nutrition metric cells.
struct FriendDetailView: View {
    let friend: SharedFriend
    @Environment(MockStore.self) private var store

    private var accent: Color { RingColor.calories.tint }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                identityHeader
                lastSevenDays
                todayRings
                metricCells
            }
            .padding(.horizontal, Metrics.pagePadding)
            .padding(.bottom, 34)
        }
        .background(Theme.bg)
        .scrollContentBackground(.hidden)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { HapticManager.shared.trigger(.light) } label: {
                        Label("Hide my Activity", systemImage: "eye.slash")
                    }
                    Button(role: .destructive) { HapticManager.shared.trigger(.warning) } label: {
                        Label("Remove Friend", systemImage: "person.badge.minus")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
    }

    // MARK: Identity — avatar + name + Apple ID

    private var identityHeader: some View {
        VStack(spacing: 12) {
            avatarWithBadge
            Text(friend.name)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(friend.appleID)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var avatarWithBadge: some View {
        ZStack {
            Circle().fill(friend.isEmojiAvatar ? Theme.surfaceRaised : friend.avatarTint.bg)
            if friend.isEmojiAvatar {
                Text(friend.avatar).font(.system(size: 56))
            } else {
                Image(systemName: friend.avatar)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(friend.avatarTint.fg)
            }
        }
        .frame(width: 104, height: 104)
        .overlay(alignment: .bottomTrailing) {
            MiniDayRing(rings: friend.displayRings, size: 40, lineWidth: 5)
                .padding(4)
                .background(Circle().fill(Theme.bg))
                .opacity(friend.hasShared ? 1 : 0.5)
                .offset(x: 6, y: 6)
        }
    }

    // MARK: Last 7 days

    private var lastSevenDays: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Activity Rings", subtitle: "Last 7 Days")
            HStack(spacing: 0) {
                ForEach(Array(friend.last7.enumerated()), id: \.element.id) { i, day in
                    let isToday = i == friend.last7.count - 1
                    VStack(spacing: 10) {
                        Text(day.weekdayLetter)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isToday ? Theme.bg : Theme.textTertiary)
                            .frame(width: 22, height: 22)
                            .background {
                                if isToday { Circle().fill(accent) }
                            }
                        MiniDayRing(rings: rings(for: day), size: 38, lineWidth: 4.5)
                            .opacity(day.progress == nil ? 0.4 : 1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func rings(for day: FriendDay) -> [Ring] {
        day.progress?.rings ?? RingProgress.empty
    }

    // MARK: Today's triple rings + legend

    private var todayRings: some View {
        HStack(alignment: .center, spacing: 22) {
            ActivityRings(rings: friend.displayRings, lineWidth: 16, spacing: 5)
                .frame(width: 150, height: 150)
                .opacity(friend.hasShared ? 1 : 0.5)
            RingLegend(items: legendRings)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    /// Legend rows: real values when shared, em-dashes otherwise.
    private var legendRings: [Ring] {
        (friend.hasShared ? friend.today?.rings : nil) ?? RingProgress.empty
    }

    // MARK: Two metric cells (nutrition adaptation of Apple's Steps/Distance)

    private var metricCells: some View {
        HStack(spacing: 12) {
            metricCell(title: "Avg Cal", value: avgCalText, unit: "cal")
            metricCell(title: "Streak", value: streakText, unit: streakText == "--" ? "" : "days")
        }
    }

    private func metricCell(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(value == "--" ? Theme.textTertiary : accent)
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
    }

    private var sharedDays: [RingProgress] { friend.last7.compactMap(\.progress) }

    private var avgCalText: String {
        guard friend.hasShared else { return "--" }
        let present = sharedDays.filter { $0.consumedCal > 0 }
        guard !present.isEmpty else { return "0" }
        return "\(present.map(\.consumedCal).reduce(0, +) / present.count)"
    }

    /// Consecutive most-recent days with logged calories.
    private var streakText: String {
        guard friend.hasShared else { return "--" }
        var streak = 0
        for day in friend.last7.reversed() {
            if let p = day.progress, p.consumedCal > 0 { streak += 1 } else { break }
        }
        return "\(streak)"
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

#Preview {
    NavigationStack {
        FriendDetailView(friend: MockStore().friends[0])
            .environment(MockStore())
    }
    .preferredColorScheme(.dark)
}
