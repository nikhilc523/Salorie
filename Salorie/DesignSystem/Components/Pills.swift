import SwiftUI

// MARK: - TagPill

/// Notion-style colored tag. Nearly-square corners. Soft (muted bg) or filled (solid) style.
struct TagPill: View {
    enum Style { case soft, filled }

    let text: String
    let color: TagColor
    var style: Style = .soft

    var body: some View {
        Text(text)
            .font(.pill)
            .lineLimit(1)
            .foregroundStyle(style == .soft ? color.fg : Color(hex: 0x1A1A1A))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Metrics.pillRadius, style: .continuous)
                    .fill(style == .soft ? color.bg : color.solid)
            )
    }
}

extension TagPill {
    init(_ tag: Tag) {
        self.text = tag.text
        self.color = tag.color
        self.style = tag.filled ? .filled : .soft
    }
}

// MARK: - GhostBadge

/// Outlined gray capsule, e.g. "OPEN".
struct GhostBadge: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.divider, lineWidth: 1)
            )
    }
}

// MARK: - SourceBadge

/// Maps a `FoodSource` to a colored TagPill. Shown on every food row.
struct SourceBadge: View {
    let source: FoodSource
    var body: some View {
        TagPill(text: source.short, color: source.tagColor, style: .soft)
    }
}

// MARK: - StatPill

/// Small solid mini-pill for compliance-style stats (e.g. "33%").
struct StatPill: View {
    let text: String
    let color: TagColor
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color.fg)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.bg))
    }
}

#Preview("Pills") {
    ZStack {
        Theme.bg.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TagPill(text: "Learning", color: .purple)
                TagPill(text: "Homemade", color: .blue, style: .filled)
                TagPill(text: "Overdue", color: .red)
            }
            HStack {
                GhostBadge("OPEN")
                SourceBadge(source: .usdaFoundation)
                SourceBadge(source: .openFoodFacts)
                SourceBadge(source: .custom)
            }
            HStack {
                StatPill(text: "33%", color: .green)
                StatPill(text: "87%", color: .blue)
            }
        }
        .padding()
    }
}
