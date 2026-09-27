import SwiftUI

// MARK: - Meal palette

/// Warm tone per meal slot, following the day's arc: sunrise-light → midday
/// caramel → evening terracotta → a soft neutral for snacks. Keeps the meal
/// cards in the same family as the hero rings.
extension MealSlot {
    var sunColor: Color {
        switch self {
        case .breakfast: return Color(hex: 0xE3D9C6) // oatmeal — sunrise
        case .lunch:     return Color(hex: 0xD1A67A) // caramel — midday
        case .dinner:    return Color(hex: 0xB3664C) // terracotta — dusk
        case .snacks:    return Color(hex: 0xC8A882) // soft gold
        }
    }

    /// Short label that fits four-across without truncation.
    var shortName: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch:     return "Lunch"
        case .dinner:    return "Dinner"
        case .snacks:    return "Snacks"
        }
    }
}

// MARK: - Mini sun arc

/// A single small semicircle — a mini rising sun — filled to `fraction`, with the
/// meal's glyph tucked under the dome.
private struct MealArc: View {
    var fraction: Double
    var color: Color
    var symbol: String
    var active: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            Canvas { ctx, size in
                let lw: CGFloat = 5.5
                // Constrain the radius by BOTH width and height so the round-capped
                // peak isn't sliced flat by the frame top (the "black line cutoff").
                let r = min((size.width - lw) / 2, size.height - lw)
                let c = CGPoint(x: size.width / 2, y: size.height - lw / 2)
                func arc(_ to: Double) -> Path {
                    var p = Path()
                    p.addArc(center: c, radius: r, startAngle: .degrees(180),
                             endAngle: .degrees(180 + 180 * max(min(to, 1), 0.001)), clockwise: false)
                    return p
                }
                ctx.stroke(arc(1), with: .color(Color(hex: 0x1B1714)),
                           style: .init(lineWidth: lw, lineCap: .round))
                if fraction > 0 {
                    ctx.stroke(arc(fraction), with: .color(color),
                               style: .init(lineWidth: lw, lineCap: .round))
                }
            }
            .aspectRatio(2, contentMode: .fit)

            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(active ? color : color.opacity(0.55))
                .padding(.bottom, 3)
        }
    }
}

// MARK: - Meal card

/// One tappable meal card: a mini sun arc + glyph, the meal name, and its
/// calorie total. Selected cards lift onto a raised surface.
struct MealCard: View {
    let slot: MealSlot
    let calories: Int
    let itemCount: Int
    let goalCalories: Int
    let isSelected: Bool
    let onTap: () -> Void

    private var fraction: Double {
        goalCalories > 0 ? Double(calories) / Double(goalCalories) : 0
    }
    private var isEmpty: Bool { itemCount == 0 }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                MealArc(fraction: fraction, color: slot.sunColor, symbol: slot.symbol, active: !isEmpty)
                    .frame(height: 30)
                    .padding(.horizontal, 6)

                VStack(spacing: 1) {
                    Text(slot.shortName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isEmpty ? Theme.textTertiary : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(calories)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(isEmpty ? Theme.textTertiary : Theme.textPrimary)
                            .contentTransition(.numericText())
                        Text("cal")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Theme.surfaceRaised : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? slot.sunColor.opacity(0.4) : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
