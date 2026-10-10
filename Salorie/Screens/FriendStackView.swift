import SwiftUI

/// The "follow the finger" two-sided friend stack (like the iMessage photo stack).
/// Seen friends pile left, upcoming wait right; the front card tracks the finger and
/// every other card interpolates toward where it would land. It does not loop —
/// dragging past either end rubber-bands. Tapping the front card opens that friend.
struct FriendStackView: View {
    let friends: [SharedFriend]
    var onOpen: (SharedFriend) -> Void
    /// Screenshot/testing hook: start the stack on a given card (see `SALORIE_SHARE_INDEX`).
    var initialIndex: Int = 0

    @State private var currentIndex = 0
    @State private var drag: CGSize? = nil        // nil = not dragging
    @State private var isSettling = false          // ignore new drags mid-settle
    @State private var bounceTrigger = 0
    @State private var bounceDir = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Rotation/scale pivot below the card → the fanned-hand look.
    private let anchor = UnitPoint(x: 0.5, y: 1.4)
    private let stackHeight: CGFloat = 420
    private let cardTop: CGFloat = 34

    private var count: Int { friends.count }
    private var atFirst: Bool { currentIndex == 0 }
    private var atLast: Bool { currentIndex >= count - 1 }
    private var settleAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.55)
    }

    /// Only build cards near the front (≤ 11 regardless of roster size).
    private var visibleIndices: [Int] {
        guard count > 0 else { return [] }
        let lo = max(0, currentIndex - 5)
        let hi = min(count - 1, currentIndex + 5)
        return Array(lo...hi)
    }

    var body: some View {
        VStack(spacing: 10) {
            stack
            controls
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(currentIndex + 1) of \(count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: goNext()
            case .decrement: goPrevious()
            @unknown default: break
            }
        }
        .accessibilityAction { if count > 0 { onOpen(friends[currentIndex]) } }
        .onAppear {
            if count > 0 { currentIndex = min(max(initialIndex, 0), count - 1) }
        }
    }

    // MARK: Stack

    private var stack: some View {
        ZStack(alignment: .top) {
            Color.clear
            ForEach(visibleIndices, id: \.self) { index in
                cardView(index: index)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: stackHeight)
        .contentShape(Rectangle())
    }

    private func cardView(index: Int) -> some View {
        let layout = self.layout(for: index)
        let isFront = index == currentIndex
        return FriendStackCard(friend: friends[index], animateLoad: !reduceMotion)
            .overlay(
                RoundedRectangle(cornerRadius: FriendStackCard.cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(layout.dim))
            )
            .modifier(BounceModifier(active: isFront && !reduceMotion,
                                     trigger: bounceTrigger, dir: bounceDir, anchor: anchor))
            .scaleEffect(layout.pose.scale, anchor: anchor)
            .rotationEffect(.degrees(layout.pose.rotation), anchor: anchor)
            .offset(x: layout.pose.x, y: cardTop)
            .opacity(layout.opacity)
            .zIndex(layout.z)
            .allowsHitTesting(isFront && !isSettling)
            .gesture(dragGesture)
    }

    // MARK: Per-card layout (pure function of currentIndex + drag)

    private struct Layout { var pose: CardPose; var dim: Double; var z: Double; var opacity: Double }

    private func layout(for index: Int) -> Layout {
        let o = Double(index - currentIndex)

        guard let drag else {
            return Layout(pose: StackGeometry.pose(o), dim: StackGeometry.dim(o),
                          z: StackGeometry.zIndex(o), opacity: StackGeometry.opacity(o))
        }

        let dx = drag.width
        let edge = StackGeometry.isEdge(dx: dx, atFirst: atFirst, atLast: atLast)

        // Front card tracks the finger (damped at an edge) and stays on top.
        if index == currentIndex {
            let x = StackGeometry.frontDragX(dx: dx, atFirst: atFirst, atLast: atLast)
            let pose = CardPose(x: x, rotation: Double(x / StackGeometry.frontRotationDivisor), scale: 1)
            return Layout(pose: pose, dim: 0, z: StackGeometry.baseZ, opacity: 1)
        }

        // At an edge only the front card moves.
        if edge {
            return Layout(pose: StackGeometry.pose(o), dim: StackGeometry.dim(o),
                          z: StackGeometry.zIndex(o), opacity: StackGeometry.opacity(o))
        }

        // Every other card blends toward where it would land, in proportion to the drag.
        let t = StackGeometry.progress(dx: dx)
        let dir = t >= 0 ? 1.0 : -1.0
        let k = CGFloat(abs(t))
        let from = StackGeometry.pose(o)
        let to = StackGeometry.pose(o - dir)
        let pose = StackGeometry.blend(from, to, k)
        let dim = lerp(StackGeometry.dim(o), StackGeometry.dim(o - dir), Double(k))
        let opacity = lerp(StackGeometry.opacity(o), StackGeometry.opacity(o - dir), Double(k))
        return Layout(pose: pose, dim: dim, z: StackGeometry.zIndex(o), opacity: opacity)
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    // MARK: Drag gesture ("follow the finger")

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isSettling else { return }
                let tr = value.translation
                // Let a clearly-vertical pan fall through (e.g. to a scroll view).
                if drag == nil,
                   abs(tr.height) > abs(tr.width),
                   hypot(tr.width, tr.height) > StackGeometry.tapSlop {
                    return
                }
                drag = tr
            }
            .onEnded { value in
                guard !isSettling else { return }
                handleRelease(value)
            }
    }

    private func handleRelease(_ value: DragGesture.Value) {
        let moved = hypot(value.translation.width, value.translation.height)

        // A tap (barely moved) opens the friend's detail.
        if drag == nil || moved < StackGeometry.tapSlop {
            drag = nil
            HapticManager.shared.trigger(.light)
            onOpen(friends[currentIndex])
            return
        }

        let decision = StackGeometry.commitDecision(
            dx: value.translation.width,
            predicted: value.predictedEndTranslation.width,
            atFirst: atFirst, atLast: atLast)

        switch decision {
        case .next: commit(+1)
        case .prev: commit(-1)
        case .stay:
            if StackGeometry.isEdge(dx: value.translation.width, atFirst: atFirst, atLast: atLast) {
                HapticManager.shared.trigger(.rigid)
            }
            settle { drag = nil }
        }
    }

    // MARK: Commit / settle

    private func commit(_ direction: Int) {
        HapticManager.shared.trigger(.light)
        settle {
            currentIndex += direction
            drag = nil
        }
    }

    /// Run `changes` under the settle curve and hold `isSettling` until it finishes,
    /// so a new drag can't interrupt the animation (no DispatchQueue timers).
    private func settle(_ changes: @escaping () -> Void) {
        isSettling = true
        withAnimation(settleAnimation, completionCriteria: .logicallyComplete) {
            changes()
        } completion: {
            isSettling = false
        }
    }

    // MARK: Buttons

    private func goNext() {
        guard !isSettling else { return }
        if atLast { edgeBounce(dir: 1) } else { commit(+1) }
    }

    private func goPrevious() {
        guard !isSettling else { return }
        if atFirst { edgeBounce(dir: -1) } else { commit(-1) }
    }

    private func edgeBounce(dir: Int) {
        HapticManager.shared.trigger(.rigid)
        guard !reduceMotion else { return }
        bounceDir = dir
        bounceTrigger += 1
    }

    // MARK: Controls (buttons + dots + counter)

    private var controls: some View {
        HStack(spacing: 14) {
            navButton(system: "chevron.left", disabled: atFirst, action: goPrevious)
            VStack(spacing: 8) {
                dots
                Text("\(currentIndex + 1) of \(count)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x8E857B))
                    .monospacedDigit()
            }
            navButton(system: "chevron.right", disabled: atLast, action: goNext)
        }
        .padding(.top, 10)
    }

    private func navButton(system: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(disabled ? 0.35 : 1))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color(hex: 0x1F1D1B)))
                .overlay(Circle().strokeBorder(Color(hex: 0x2E2B28), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == currentIndex ? Color(hex: 0xDDD5C4) : Color(hex: 0x3A3531))
                    .frame(width: i == currentIndex ? 16 : 6, height: 6)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentIndex)
    }

    // MARK: Accessibility

    private var accessibilityLabel: String {
        guard count > 0 else { return "Friends" }
        let f = friends[currentIndex]
        let name = f.isMe ? "You" : f.name
        if f.hasShared, let today = f.today {
            return "Friends, \(name), \(today.overallPercentInt) percent of calorie goal"
        }
        return "Friends, \(name), not sharing today"
    }
}

// MARK: - Edge bounce (front card only)

/// A quick edge bounce played when the user tries to go past the first/last card.
/// Applied to every card but only the front (`active`) has a non-zero amplitude, so
/// identity stays stable and the pile never jiggles.
private struct BounceModifier: ViewModifier {
    let active: Bool
    let trigger: Int
    let dir: Int
    let anchor: UnitPoint

    struct Values { var x: CGFloat = 0; var rot: Double = 0 }

    func body(content: Content) -> some View {
        let amp: CGFloat = active ? 26 : 0
        let rotAmp: Double = active ? 2 : 0
        return content.keyframeAnimator(initialValue: Values(), trigger: trigger) { view, v in
            view.offset(x: v.x).rotationEffect(.degrees(v.rot), anchor: anchor)
        } keyframes: { _ in
            KeyframeTrack(\.x) {
                CubicKeyframe(-CGFloat(dir) * amp, duration: 0.19)
                CubicKeyframe(0, duration: 0.19)
            }
            KeyframeTrack(\.rot) {
                CubicKeyframe(-Double(dir) * rotAmp, duration: 0.19)
                CubicKeyframe(0, duration: 0.19)
            }
        }
    }
}

#Preview("FriendStackView") {
    ZStack {
        Theme.bg.ignoresSafeArea()
        FriendStackView(friends: MockStore().friends) { friend in
            print("open \(friend.name)")
        }
        .padding(.horizontal, Metrics.pagePadding)
    }
    .preferredColorScheme(.dark)
}
