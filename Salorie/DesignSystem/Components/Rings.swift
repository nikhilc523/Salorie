import SwiftUI

// MARK: - Ring model

struct Ring: Identifiable, Hashable {
    let id = UUID()
    var progress: Double   // 0…∞ (rings overshoot & wrap past 1)
    var color: RingColor
    var label: String
    var valueText: String  // e.g. "120 g"
}

// MARK: - Single ring arc

/// One concentric ring: gradient arc, rounded caps, fills clockwise from 12 o'clock,
/// with a wrapped overshoot segment and a soft glow.
private struct SingleRing: View {
    let progress: Double        // animated target
    let color: RingColor
    let lineWidth: CGFloat

    private var clamped: Double { min(progress, 1) }
    private var overshoot: Double { max(0, min(progress - 1, 1)) }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(color.base.opacity(0.16), style: .init(lineWidth: lineWidth, lineCap: .round))

            // Main arc
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(color.gradient, style: .init(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.base.opacity(0.35), radius: 6)

            // Overshoot arc (wraps on top when > 100%)
            if overshoot > 0 {
                Circle()
                    .trim(from: 0, to: overshoot)
                    .stroke(color.gradient, style: .init(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
            }
        }
    }
}

// MARK: - ActivityRings

/// Apple-Fitness-style stack of concentric rings (outer → inner).
struct ActivityRings: View {
    let rings: [Ring]           // outer first
    var lineWidth: CGFloat = 16
    var spacing: CGFloat = 6
    var centerText: String? = nil
    var centerSubtitle: String? = nil

    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                let inset = CGFloat(index) * (lineWidth + spacing)
                SingleRing(
                    progress: animate ? ring.progress : 0,
                    color: ring.color,
                    lineWidth: lineWidth
                )
                .padding(inset)
                .animation(
                    reduceMotion ? nil : .smooth(duration: 0.9).delay(Double(index) * 0.06),
                    value: animate
                )
            }

            if let centerText {
                VStack(spacing: 2) {
                    Text(centerText)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    if let centerSubtitle {
                        Text(centerSubtitle)
                            .font(.system(size: 11, weight: .medium))
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .onAppear {
            if reduceMotion { animate = true }
            else { withAnimation { animate = true } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private var accessibilitySummary: String {
        rings.map { "\($0.label) \(Int($0.progress * 100)) percent" }.joined(separator: ", ")
    }
}

// MARK: - RingLegend

/// Colored-dot legend beside/under the rings.
struct RingLegend: View {
    let items: [Ring]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items) { ring in
                HStack(spacing: 8) {
                    Circle()
                        .fill(ring.color.gradient)
                        .frame(width: 9, height: 9)
                    Text(ring.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    Text(ring.valueText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
            }
        }
    }
}

// MARK: - RingChart (single donut)

/// Single donut with a center number + subtitle + optional target line.
/// Used for secondary stats (calorie total, weight goal).
struct RingChart: View {
    let progress: Double
    let centerText: String
    var subtitle: String? = nil
    var targetText: String? = nil
    var color: Color = Theme.accent

    var lineWidth: CGFloat = 14

    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.16), style: .init(lineWidth: lineWidth, lineCap: .round))
                Circle()
                    .trim(from: 0, to: animate ? min(progress, 1) : 0)
                    .stroke(color, style: .init(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.4), radius: 6)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.9), value: animate)

                VStack(spacing: 2) {
                    Text(centerText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            if let targetText {
                Text(targetText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .onAppear { animate = true }
    }
}

// MARK: - Mini day ring (for history / streak rows)

struct MiniDayRing: View {
    let rings: [Ring]      // outer first
    var size: CGFloat = 34
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                Circle()
                    .stroke(ring.color.base.opacity(0.16), lineWidth: lineWidth)
                    .padding(CGFloat(index) * (lineWidth + 1.5))
                Circle()
                    .trim(from: 0, to: min(ring.progress, 1))
                    .stroke(ring.color.gradient, style: .init(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(CGFloat(index) * (lineWidth + 1.5))
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview("Rings") {
    ZStack {
        Theme.bg.ignoresSafeArea()
        let rings = [
            Ring(progress: 0.72, color: .carb, label: "Carb", valueText: "180 g"),
            Ring(progress: 1.15, color: .protein, label: "Protein", valueText: "161 g"),
            Ring(progress: 0.5, color: .fibre, label: "Fibre", valueText: "15 g"),
        ]
        VStack(spacing: 28) {
            HStack(spacing: 24) {
                ActivityRings(rings: rings, centerText: "87%", centerSubtitle: "Goal")
                    .frame(width: 150, height: 150)
                RingLegend(items: rings)
            }
            HStack(spacing: 12) {
                ForEach(0..<7, id: \.self) { _ in
                    MiniDayRing(rings: rings)
                }
            }
        }
        .padding()
    }
}
