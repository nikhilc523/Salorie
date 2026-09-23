import SwiftUI

// MARK: - NewButton

/// Blue split button: `+ ⌄` (accent), as seen on Notion mobile database views.
struct NewButton: View {
    var action: () -> Void = {}
    var menuAction: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            Button {
                HapticManager.shared.trigger(.medium)
                action()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 46, height: 34)
            }
            Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 20)
            Button {
                HapticManager.shared.trigger(.light)
                menuAction()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 34)
            }
        }
        .foregroundStyle(.white)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - NotionToolbar

/// Trailing icon cluster used at the top-right of every table: search, filter, sort,
/// and the blue New button. Icons are grouped in a glass container.
struct NotionToolbar: View {
    var onSearch: () -> Void = {}
    var onFilter: () -> Void = {}
    var onSort: () -> Void = {}
    var onNew: () -> Void = {}

    var body: some View {
        HStack(spacing: 14) {
            toolbarIcon("magnifyingglass", action: onSearch)
            toolbarIcon("line.3.horizontal.decrease", action: onFilter)
            toolbarIcon("slider.horizontal.3", action: onSort)
            NewButton(action: onNew)
        }
    }

    private func toolbarIcon(_ name: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.trigger(.light)
            action()
        } label: {
            Image(systemName: name)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 30, height: 34)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FilterChip

/// The left-side "All events ⌄" style pill with a leading glyph.
struct FilterChip: View {
    var systemImage: String = "asterisk"
    var title: String
    var action: () -> Void = {}

    var body: some View {
        Button {
            HapticManager.shared.trigger(.light)
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - NotionPageHeader

/// Big emoji + screen title, as on every Notion database page.
struct NotionPageHeader: View {
    var symbol: String
    var tint: TagColor = .gray
    var title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(tint.fg)
                .frame(width: 52, height: 52)
                .background(tint.bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(title)
                .font(.screenTitle)
                .foregroundStyle(Theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - SegmentedTabs

/// Notion database-tab strip ("Exercises · Workouts · Splits" / "Search · Scan").
struct SegmentedTabs: View {
    let items: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 20) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, title in
                Button {
                    HapticManager.shared.trigger(.selection)
                    selection = idx
                } label: {
                    VStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 15, weight: selection == idx ? .semibold : .regular))
                            .foregroundStyle(selection == idx ? Theme.textPrimary : Theme.textSecondary)
                        Rectangle()
                            .fill(selection == idx ? Theme.textPrimary : .clear)
                            .frame(height: 2)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.divider).frame(height: Metrics.hairline)
        }
    }
}
