import SwiftUI

/// Salorie type scale — SF Pro, Notion weights.
extension Font {
    static let screenTitle  = Font.system(size: 30, weight: .bold)
    static let sectionTitle = Font.system(size: 17, weight: .semibold)
    /// 12pt semibold uppercase tracked (e.g. "INGREDIENTS", "REMOVAL BREAKDOWN").
    static let overline     = Font.system(size: 12, weight: .semibold)
    static let rowName      = Font.system(size: 16, weight: .semibold)
    static let cellValue    = Font.system(size: 15, weight: .regular)
    static let columnHeader = Font.system(size: 13, weight: .medium)
    static let metricNumber = Font.system(size: 34, weight: .bold, design: .rounded)
    static let metricLabel  = Font.system(size: 13, weight: .regular)
    static let pill         = Font.system(size: 13, weight: .medium)
}

/// Layout constants.
enum Metrics {
    static let pagePadding: CGFloat = 16
    static let rowHeight: CGFloat = 44
    static let cellPadding: CGFloat = 12
    static let pinnedColumnWidth: CGFloat = 184
    static let minColumnWidth: CGFloat = 72
    static let cardRadius: CGFloat = 10
    static let pillRadius: CGFloat = 4
    static let metricCardRadius: CGFloat = 12
    static let calmCardRadius: CGFloat = 20
    static let hairline: CGFloat = 0.5
}

extension Text {
    /// Uppercase gray overline label used across dashboard cards.
    func overlineStyle() -> some View {
        self.font(.overline)
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(Theme.textSecondary)
    }
}
