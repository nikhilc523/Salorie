import SwiftUI

// MARK: - Cell model

enum TableCell {
    case text(String)
    case number(String)
    case tags([Tag])
    case source(FoodSource)
    case macro(RingColor, String)
    case button(title: String, color: TagColor, action: () -> Void)
    case empty
}

// MARK: - Column & row

struct NotionColumn: Identifiable {
    let id = UUID()
    var title: String
    var icon: String? = nil          // SF Symbol drawn before the header title
    var width: CGFloat = 96
    var alignment: Alignment = .leading
}

struct NotionRow: Identifiable {
    let id = UUID()
    var icon: String              // SF Symbol leading glyph
    var tint: TagColor = .gray
    var name: String
    var ghost: String? = nil         // e.g. "OPEN"
    var cells: [TableCell] = []
    var isChecked: Bool = false
    var onTap: (() -> Void)? = nil
}

// MARK: - NotionTable

/// The core list component. Non-name columns scroll horizontally; the name column is pinned.
/// Hairline dividers, "+ New page" ghost footer, optional leading checkbox and COUNT footer.
struct NotionTable: View {
    var columns: [NotionColumn]
    var rows: [NotionRow]
    var leadingCheckbox: Bool = false
    var showCount: Bool = true
    var showNewRow: Bool = true
    var newRowTitle: String = "New page"
    var onNewRow: (() -> Void)? = nil
    var onToggleCheck: ((NotionRow) -> Void)? = nil

    private let rowHeight = Metrics.rowHeight

    var body: some View {
        HStack(spacing: 0) {
            pinnedColumn
                .background(Theme.bg)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Theme.divider).frame(width: Metrics.hairline)
                }
                .zIndex(1)

            ScrollView(.horizontal, showsIndicators: false) {
                scrollingColumns
            }
        }
    }

    // MARK: Pinned name column

    private var pinnedColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "textformat")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text("Name")
                    .font(.columnHeader)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(height: rowHeight, alignment: .leading)
            .padding(.horizontal, Metrics.cellPadding)

            Divider().overlay(Theme.divider)

            ForEach(rows) { row in
                nameCell(row)
                Divider().overlay(Theme.divider)
            }

            if showNewRow { newRow }
            if showCount { countFooter }
        }
        .frame(width: leadingCheckbox ? Metrics.pinnedColumnWidth + 28 : Metrics.pinnedColumnWidth,
               alignment: .leading)
    }

    private func nameCell(_ row: NotionRow) -> some View {
        HStack(spacing: 8) {
            if leadingCheckbox {
                Button {
                    HapticManager.shared.trigger(.selection)
                    onToggleCheck?(row)
                } label: {
                    Image(systemName: row.isChecked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 17))
                        .foregroundStyle(row.isChecked ? Theme.accent : Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            Image(systemName: row.icon)
                .font(.system(size: 15))
                .foregroundStyle(row.tint.fg)
                .frame(width: 20)
            Text(row.name)
                .font(.rowName)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if let ghost = row.ghost {
                GhostBadge(ghost)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.cellPadding)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.trigger(.light)
            row.onTap?()
        }
    }

    // MARK: Scrolling value columns

    private var scrollingColumns: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 0) {
                ForEach(columns) { col in
                    HStack(spacing: 5) {
                        if let icon = col.icon {
                            Image(systemName: icon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text(col.title)
                            .font(.columnHeader)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(width: col.width, alignment: .leading)
                    .padding(.horizontal, Metrics.cellPadding)
                }
            }
            .frame(height: rowHeight)

            Divider().overlay(Theme.divider)

            ForEach(rows) { row in
                HStack(spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.element.id) { idx, col in
                        cellView(cell(row, idx))
                            .frame(width: col.width, alignment: col.alignment)
                            .padding(.horizontal, Metrics.cellPadding)
                    }
                }
                .frame(height: rowHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    HapticManager.shared.trigger(.light)
                    row.onTap?()
                }
                Divider().overlay(Theme.divider)
            }

            if showNewRow {
                Color.clear.frame(height: rowHeight)
            }
            if showCount {
                Color.clear.frame(height: 36)
            }
        }
    }

    private func cell(_ row: NotionRow, _ idx: Int) -> TableCell {
        idx < row.cells.count ? row.cells[idx] : .empty
    }

    @ViewBuilder
    private func cellView(_ cell: TableCell) -> some View {
        switch cell {
        case .text(let s):
            Text(s).font(.cellValue).foregroundStyle(Theme.textPrimary).lineLimit(1)
        case .number(let s):
            Text(s).font(.cellValue).monospacedDigit().foregroundStyle(Theme.textPrimary).lineLimit(1)
        case .tags(let tags):
            HStack(spacing: 5) {
                ForEach(tags) { TagPill($0) }
            }
        case .source(let src):
            SourceBadge(source: src)
        case .macro(let ring, let value):
            HStack(spacing: 6) {
                Circle().fill(ring.gradient).frame(width: 8, height: 8)
                Text(value).font(.cellValue).monospacedDigit().foregroundStyle(Theme.textPrimary)
            }
        case .button(let title, let color, let action):
            Button {
                HapticManager.shared.trigger(.medium)
                action()
            } label: {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color.fg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(color.bg))
            }
            .buttonStyle(.plain)
        case .empty:
            Color.clear
        }
    }

    // MARK: Footers

    private var newRow: some View {
        Button {
            HapticManager.shared.trigger(.light)
            onNewRow?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text(newRowTitle)
                Spacer(minLength: 0)
            }
            .font(.system(size: 15))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, Metrics.cellPadding)
            .frame(height: rowHeight)
        }
        .buttonStyle(.plain)
    }

    private var countFooter: some View {
        HStack(spacing: 6) {
            Text("COUNT")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text("\(rows.count)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.cellPadding)
        .frame(height: 36)
    }
}
