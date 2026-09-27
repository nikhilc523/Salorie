import CoreGraphics

// MARK: - Two-sided card-stack geometry (pure, testable, no SwiftUI)

/// Where one card sits: horizontal offset, rotation (degrees) and scale. The
/// rotation/scale pivot is a point *below* the card (`UnitPoint(x: 0.5, y: 1.4)`,
/// applied in the view layer) which produces the fanned-hand look.
struct CardPose: Equatable {
    var x: CGFloat
    var rotation: Double   // degrees
    var scale: CGFloat
}

/// The result of releasing a drag (or tapping a nav button).
enum CommitResult: Equatable { case next, prev, stay }

/// The maths behind the "follow the finger" stack, kept free of SwiftUI so it can
/// be unit-tested and reasoned about in isolation. Every tunable in the spec lives
/// here as a named constant.
enum StackGeometry {

    // Spec tunables ---------------------------------------------------------
    static let maxVisibleSide: Double = 4      // up to 4 cards fan out on each side
    static let buildCutoff: Double = 5         // only build views for |o| <= 5
    static let xPerStep: CGFloat = 7           // px of horizontal fan per step
    static let rotationPerStep: Double = 4.4   // degrees of tilt per step
    static let scalePerStep: CGFloat = 0.02    // shrink per step
    static let dimPerStep: Double = 0.10       // black overlay per step
    static let baseZ: Double = 100             // front card z-index

    static let dragDivisor: CGFloat = 220      // dx -> progress t
    static let frontRotationDivisor: CGFloat = 18
    static let rubberBandFactor: CGFloat = 0.25
    static let tapSlop: CGFloat = 6            // < this total movement == a tap
    static let commitDx: CGFloat = 60          // a deliberate drag past this commits
    static let commitPredicted: CGFloat = 140  // ...or a flick projected past this

    // Poses -----------------------------------------------------------------

    /// Resting pose for a card at signed offset `o` (0 = front, negative = left/
    /// seen pile, positive = right/upcoming pile). Only ever call with integers —
    /// fractional positions come from `blend`, never `pose(fraction)`.
    static func pose(_ o: Double) -> CardPose {
        guard o != 0 else { return CardPose(x: 0, rotation: 0, scale: 1) }
        let side: CGFloat = o < 0 ? -1 : 1
        let m = min(abs(o), maxVisibleSide)
        return CardPose(
            x: side * CGFloat(m) * xPerStep,
            rotation: Double(side) * m * rotationPerStep,
            scale: 1 - CGFloat(m) * scalePerStep
        )
    }

    /// Linear blend of two poses by `t` in 0…1 (t=0 → a, t=1 → b).
    static func blend(_ a: CardPose, _ b: CardPose, _ t: CGFloat) -> CardPose {
        let k = min(max(t, 0), 1)
        return CardPose(
            x: a.x + (b.x - a.x) * k,
            rotation: a.rotation + (b.rotation - a.rotation) * Double(k),
            scale: a.scale + (b.scale - a.scale) * k
        )
    }

    /// Black-overlay opacity for a card at offset `o` (front 0, 4th-back 0.4).
    static func dim(_ o: Double) -> Double { min(abs(o), maxVisibleSide) * dimPerStep }

    /// Front on top; nearer pile cards above farther ones.
    static func zIndex(_ o: Double) -> Double { baseZ - abs(o) * 2 }

    /// Cards past the visible fan fade out (they still sit at the m=4 pose).
    static func opacity(_ o: Double) -> Double { abs(o) > maxVisibleSide ? 0 : 1 }

    /// Drag progress toward the next card: positive heads to `next`, clamped ±1.
    static func progress(dx: CGFloat) -> CGFloat { min(max(-dx / dragDivisor, -1), 1) }

    /// Is this drag pushing past an end (no card to reveal)? Such drags rubber-band.
    static func isEdge(dx: CGFloat, atFirst: Bool, atLast: Bool) -> Bool {
        let t = progress(dx: dx)
        return (t > 0 && atLast) || (t < 0 && atFirst)
    }

    /// Where the front card sits mid-drag — full 1:1 tracking, or damped at an edge.
    static func frontDragX(dx: CGFloat, atFirst: Bool, atLast: Bool) -> CGFloat {
        isEdge(dx: dx, atFirst: atFirst, atLast: atLast) ? dx * rubberBandFactor : dx
    }

    // Commit decision -------------------------------------------------------

    /// Decide what a released drag does. Edges never commit (they rubber-band back).
    /// A deliberate drag past `commitDx`, or a flick whose projected end passes
    /// `commitPredicted`, commits in that direction.
    static func commitDecision(dx: CGFloat, predicted: CGFloat,
                               atFirst: Bool, atLast: Bool) -> CommitResult {
        if dx < -commitDx || predicted < -commitPredicted {
            return atLast ? .stay : .next
        }
        if dx > commitDx || predicted > commitPredicted {
            return atFirst ? .stay : .prev
        }
        return .stay
    }
}
