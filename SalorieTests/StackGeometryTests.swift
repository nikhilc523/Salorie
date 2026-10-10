import Testing
import CoreGraphics
@testable import Salorie

/// Pure-geometry tests for the two-sided "follow the finger" friend stack.
@Suite struct StackGeometryTests {

    private let eps = 0.0001

    // MARK: pose

    @Test func poseFrontIsIdentity() {
        let p = StackGeometry.pose(0)
        #expect(p == CardPose(x: 0, rotation: 0, scale: 1))
    }

    @Test func poseOnePerSideIsSymmetric() {
        let right = StackGeometry.pose(1)
        #expect(abs(right.x - 7) < eps)
        #expect(abs(right.rotation - 4.4) < eps)
        #expect(abs(right.scale - 0.98) < eps)

        let left = StackGeometry.pose(-1)
        #expect(abs(left.x - (-7)) < eps)
        #expect(abs(left.rotation - (-4.4)) < eps)
        #expect(abs(left.scale - 0.98) < eps)
    }

    @Test func poseAtFourthCard() {
        let p = StackGeometry.pose(4)
        #expect(abs(p.x - 28) < eps)
        #expect(abs(p.rotation - 17.6) < eps)
        #expect(abs(p.scale - 0.92) < eps)
    }

    @Test func poseClampsBeyondFour() {
        // o = 5 and 6 sit at the m = 4 pose (they only fade in/out in place).
        #expect(StackGeometry.pose(5) == StackGeometry.pose(4))
        #expect(StackGeometry.pose(6) == StackGeometry.pose(4))
        #expect(StackGeometry.pose(-6) == StackGeometry.pose(-4))
    }

    // MARK: blend

    @Test func blendMidpoint() {
        let mid = StackGeometry.blend(StackGeometry.pose(1), StackGeometry.pose(2), 0.5)
        #expect(abs(mid.x - 10.5) < eps)        // (7 + 14) / 2
        #expect(abs(mid.rotation - 6.6) < eps)  // (4.4 + 8.8) / 2
        #expect(abs(mid.scale - 0.97) < eps)    // (0.98 + 0.96) / 2
    }

    @Test func blendEndpointsAndIdempotent() {
        let a = StackGeometry.pose(0), b = StackGeometry.pose(1)
        #expect(StackGeometry.blend(a, b, 0) == a)
        #expect(StackGeometry.blend(a, b, 1) == b)
        #expect(StackGeometry.blend(a, a, 0.37) == a)
    }

    @Test func blendClampsT() {
        let a = StackGeometry.pose(0), b = StackGeometry.pose(1)
        #expect(StackGeometry.blend(a, b, -3) == a)
        #expect(StackGeometry.blend(a, b, 9) == b)
    }

    // MARK: dim / zIndex / opacity

    @Test func dimProgression() {
        #expect(abs(StackGeometry.dim(0) - 0) < eps)
        #expect(abs(StackGeometry.dim(-2) - 0.2) < eps)
        #expect(abs(StackGeometry.dim(4) - 0.4) < eps)
        #expect(abs(StackGeometry.dim(6) - 0.4) < eps)  // clamped
    }

    @Test func zIndexOrder() {
        #expect(StackGeometry.zIndex(0) == 100)
        #expect(StackGeometry.zIndex(1) == 98)
        #expect(StackGeometry.zIndex(-1) == 98)
        #expect(StackGeometry.zIndex(4) == 92)
    }

    @Test func opacityFadesBeyondFour() {
        #expect(StackGeometry.opacity(4) == 1)
        #expect(StackGeometry.opacity(-3) == 1)
        #expect(StackGeometry.opacity(5) == 0)
    }

    // MARK: commit thresholds

    @Test func commitsOnDeliberateDrag() {
        #expect(StackGeometry.commitDecision(dx: -70, predicted: -10, atFirst: false, atLast: false) == .next)
        #expect(StackGeometry.commitDecision(dx: 70, predicted: 10, atFirst: false, atLast: false) == .prev)
    }

    @Test func commitsOnFlick() {
        #expect(StackGeometry.commitDecision(dx: -30, predicted: -160, atFirst: false, atLast: false) == .next)
        #expect(StackGeometry.commitDecision(dx: 30, predicted: 160, atFirst: false, atLast: false) == .prev)
    }

    @Test func staysBelowThresholds() {
        #expect(StackGeometry.commitDecision(dx: -40, predicted: -50, atFirst: false, atLast: false) == .stay)
        #expect(StackGeometry.commitDecision(dx: 40, predicted: 50, atFirst: false, atLast: false) == .stay)
    }

    @Test func edgesNeverCommit() {
        #expect(StackGeometry.commitDecision(dx: -200, predicted: -300, atFirst: false, atLast: true) == .stay)
        #expect(StackGeometry.commitDecision(dx: 200, predicted: 300, atFirst: true, atLast: false) == .stay)
    }

    // MARK: edge rubber-band

    @Test func rubberBandDampsAtEdge() {
        // Dragging right on the first card is an edge → damped.
        #expect(StackGeometry.isEdge(dx: 100, atFirst: true, atLast: false))
        #expect(abs(StackGeometry.frontDragX(dx: 100, atFirst: true, atLast: false) - 25) < eps)
        // Dragging left on the first card is normal → 1:1.
        #expect(!StackGeometry.isEdge(dx: -100, atFirst: true, atLast: false))
        #expect(abs(StackGeometry.frontDragX(dx: -100, atFirst: true, atLast: false) - (-100)) < eps)
    }
}
