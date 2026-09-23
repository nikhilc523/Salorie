import SwiftUI

// MARK: - CalmCard

/// The premium raised card used across the dashboard (UI/Required aesthetic):
/// large radius, subtle stroke, generous padding.
struct CalmCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: Metrics.calmCardRadius, style: .continuous))
            .overlay( // iOS-26 glossy top sheen
                RoundedRectangle(cornerRadius: Metrics.calmCardRadius, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.05), .clear],
                                         startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.calmCardRadius, style: .continuous)
                    .stroke(Theme.cardStroke, lineWidth: 1)
            )
    }
}

// MARK: - MacroProgressCard

/// Compact macro glance: colored dot + label, big grams number, target, and a thin
/// gradient progress bar. Used for the Protein / Carbs / Fat strip on Today.
struct MacroProgressCard: View {
    var label: String
    var consumed: Double
    var target: Double
    var unit: String = "g"
    var colors: [Color]

    private var pct: Double { target > 0 ? min(consumed / target, 1) : 0 }
    private var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Circle().fill(gradient).frame(width: 7, height: 7)
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(consumed.rounded()))")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            Text("of \(Int(target.rounded()))\(unit)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill((colors.first ?? .white).opacity(0.16))
                    Capsule().fill(gradient).frame(width: max(4, geo.size.width * pct))
                }
            }
            .frame(height: 5)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.metricCardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.metricCardRadius, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }
}

// MARK: - MetricCard

/// Dashboard stat card: big number over small uppercase gray label, optional icon/trend.
struct MetricCard: View {
    var label: String
    var value: String
    var icon: String? = nil
    var accent: Color = Theme.textPrimary
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).overlineStyle()
                Spacer()
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Text(value)
                .font(.metricNumber)
                .foregroundStyle(accent)
                .contentTransition(.numericText())
            if let footnote {
                Text(footnote)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.metricCardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.metricCardRadius, style: .continuous)
                .stroke(Theme.cardStroke, lineWidth: 1)
        )
    }
}

// MARK: - PropertyRow

/// Detail-page row: leading icon + label, trailing value content.
struct PropertyRow<Value: View>: View {
    var icon: String
    var label: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 150, alignment: .leading)

            value
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 40)
    }
}

// MARK: - QuickActionButton

/// `+ Add …` ghost button with a green plus.
struct QuickActionButton: View {
    var title: String
    var systemImage: String = "plus"
    var action: () -> Void = {}

    var body: some View {
        Button {
            HapticManager.shared.trigger(.medium)
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TagColor.green.fg)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .frame(maxWidth: .infinity)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .stroke(Theme.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Board (kanban)

struct BoardCard: View {
    var food: Food
    var onTap: () -> Void = {}

    var body: some View {
        Button {
            HapticManager.shared.trigger(.light)
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: food.symbol)
                        .font(.system(size: 15))
                        .foregroundStyle(food.tint.fg)
                        .frame(width: 22)
                    Text(food.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 5) {
                    ForEach(food.tags.prefix(2)) { TagPill($0) }
                }
                HStack {
                    SourceBadge(source: food.source)
                    Spacer()
                    Text("\(food.calories) cal")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(12)
            .frame(width: 220, alignment: .leading)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .stroke(Theme.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct BoardColumn<Content: View>: View {
    var title: String
    var symbol: String
    var count: Int
    var tint: TagColor
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(tint.fg)
                TagPill(text: title, color: tint)
                Text("\(count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
            content
        }
        .frame(width: 244, alignment: .leading)
    }
}
