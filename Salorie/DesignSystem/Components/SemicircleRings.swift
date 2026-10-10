import SwiftUI

// MARK: - Semicircle arc shape

/// A half-circle arc from the left end (180°) over the top to the right end (0°),
/// concentric with siblings at a shared centre. `.trim(from: 0, to: p)` fills from
/// the LEFT end, matching the Today "rising sun" language. Use with round caps.
struct SemicircleArc: Shape {
    var radius: CGFloat
    var centerY: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: centerY),
                 radius: radius,
                 startAngle: .degrees(180), endAngle: .degrees(360),
                 clockwise: false)
        return p
    }
}

// MARK: - SemicircleRings

/// Three concentric semicircle rings (Calories · Protein · Carbs, outer → inner)
/// in the app's ring palette. Parameterised by `width` and the stroke/gap ratios so
/// the same component scales from the small stack card to larger detail views.
///
/// - Progress is clamped 0…1; exactly 0 draws no arc and no cap dot (track only).
/// - `isSharing == false` shows faint tracks only, at 55% opacity.
/// - When `animateLoad`, each ring sweeps up from 0 (1.4 s, staggered 90 ms,
///   outer first). The animation lives entirely inside this view (driven by an
///   `onAppear`-set `@State`) so it plays once per appearance and never replays
///   while the parent stack is dragged or settling.
struct SemicircleRings: View {
    var caloriesPct: Double
    var proteinPct: Double
    var carbsPct: Double
    var isSharing: Bool = true
    var animateLoad: Bool = true
    var loadDelay: Double = 0          // stagger the whole sweep (detail entrance)
    var width: CGFloat = 192
    var strokeRatio: CGFloat = 0.085
    var gapRatio: CGFloat = 0.024

    @State private var drawn: [Double] = [0, 0, 0]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let colors: [RingColor] = [.calories, .protein, .carb]
    /// Opaque dark tint of each ring's own colour — a coloured groove, not a black
    /// gap (same intent as `MiniSunRings`, tuned for the near-black card).
    private let trackHex: [UInt] = [0x33302A, 0x2C241E, 0x281712]

    private var sw: CGFloat { width * strokeRatio }
    private var gap: CGFloat { width * gapRatio }
    private var outerR: CGFloat { width / 2 - sw / 2 }
    private var centerY: CGFloat { width / 2 }
    private var ringsHeight: CGFloat { width / 2 + sw / 2 }
    private func radius(_ i: Int) -> CGFloat { outerR - CGFloat(i) * (sw + gap) }
    private var targets: [Double] { [caloriesPct, proteinPct, carbsPct].map { min(max($0, 0), 1) } }

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                SemicircleArc(radius: radius(i), centerY: centerY)
                    .stroke(Color(hex: trackHex[i]),
                            style: StrokeStyle(lineWidth: sw, lineCap: .round))
                    .opacity(isSharing ? 1 : 0.55)

                if isSharing {
                    SemicircleArc(radius: radius(i), centerY: centerY)
                        .trim(from: 0, to: drawn[i])
                        .stroke(colors[i].tint,
                                style: StrokeStyle(lineWidth: sw, lineCap: .round))
                }
            }
        }
        .frame(width: width, height: ringsHeight)
        .onAppear(perform: load)
        .accessibilityHidden(true)
    }

    private func load() {
        guard isSharing else { drawn = [0, 0, 0]; return }
        guard animateLoad, !reduceMotion else { drawn = targets; return }
        for i in 0..<3 {
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 1.4).delay(loadDelay + Double(i) * 0.09)) {
                drawn[i] = targets[i]
            }
        }
    }
}

// MARK: - Geometry helpers (avatar placement)

extension SemicircleRings {
    /// Total drawn height for a given `width` (leaves room for the bottom round caps).
    static func height(width: CGFloat, strokeRatio: CGFloat = 0.085) -> CGFloat {
        width / 2 + (width * strokeRatio) / 2
    }
    /// The arcs' centre line (their common centre y == the dome floor / baseline).
    static func baselineY(width: CGFloat) -> CGFloat { width / 2 }
    /// The inner ring's inner-edge radius — the room available for an avatar.
    static func innerEdgeRadius(width: CGFloat, strokeRatio: CGFloat = 0.085, gapRatio: CGFloat = 0.024) -> CGFloat {
        let sw = width * strokeRatio, gap = width * gapRatio
        let R = width / 2 - sw / 2
        return R - 2 * (sw + gap) - sw / 2
    }
    /// Avatar diameter that fits inside the inner ring, touching nothing.
    static func avatarDiameter(width: CGFloat, strokeRatio: CGFloat = 0.085, gapRatio: CGFloat = 0.024) -> CGFloat {
        (innerEdgeRadius(width: width, strokeRatio: strokeRatio, gapRatio: gapRatio) - 6).rounded()
    }
}

#Preview("SemicircleRings") {
    ZStack {
        Theme.bg.ignoresSafeArea()
        HStack(spacing: 24) {
            SemicircleRings(caloriesPct: 0.86, proteinPct: 1.02, carbsPct: 0.74, width: 150)
            SemicircleRings(caloriesPct: 0, proteinPct: 0, carbsPct: 0, width: 150)          // 0%
            SemicircleRings(caloriesPct: 0.5, proteinPct: 0.4, carbsPct: 0.6,
                            isSharing: false, width: 150)                                     // not sharing
        }
    }
    .preferredColorScheme(.dark)
}
