import SwiftUI

// MARK: - Flight model

/// What a landed token should do when it reaches the island (or a row).
enum FlightKind: Equatable {
    case log(slot: MealSlot, servings: Double)  // fly food → island, then log it
    case tray                                    // fly food → island tray (meal building)
    case remove                                  // fly island chip → row (removing an item)
}

/// One in-flight token: a copy of a food tile travelling along a Bézier curve
/// between a row tile and the island (or back). Removes itself on landing.
struct Flight: Identifiable, Equatable {
    let id = UUID()
    let food: Food
    let from: CGRect       // source tile, in the "screen" coordinate space
    let to: CGRect         // target tile / island center, in "screen"
    let reverse: Bool      // true = island → row (grows), false = row → island (shrinks)
    let kind: FlightKind

    static func == (a: Flight, b: Flight) -> Bool { a.id == b.id }
}

// MARK: - Bézier flight modifier

/// Positions a token along a quadratic Bézier curve as `t` animates 0 → 1, while
/// interpolating scale, rotation, corner radius and opacity. `Animatable` on `t`
/// so the whole flight is one interruptible spring/curve — no timers, no snapping.
struct BezierFlight: ViewModifier, Animatable {
    var t: Double
    let p0: CGPoint          // start center
    let p1: CGPoint          // end center
    let control: CGPoint     // Bézier control point
    let reverse: Bool

    nonisolated var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    func body(content: Content) -> some View {
        let tt = min(max(t, 0), 1)
        let pos = point(at: tt)

        // Shrink flying in (row → island); grow flying back (island → row).
        let eased = pow(tt, 1.4)
        let scale = reverse ? (0.3 + 0.7 * tt) : (1 - 0.7 * eased)
        let rotation = reverse ? Angle.degrees(-25 * (1 - tt)) : Angle.degrees(-25 * tt)
        let corner = reverse ? (21 - 9 * tt) : (12 + 9 * tt)

        // Forward: fade out in the last 8%. Reverse: fade in over the first 8%.
        let opacity: Double = reverse
            ? min(tt / 0.08, 1)
            : (tt > 0.92 ? max(1 - (tt - 0.92) / 0.08, 0) : 1)

        content
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .scaleEffect(scale)
            .rotationEffect(rotation)
            .opacity(opacity)
            .position(pos)
    }

    /// Quadratic Bézier: B(t) = (1−t)²·P0 + 2(1−t)t·C + t²·P1.
    private func point(at t: Double) -> CGPoint {
        let u = 1 - t
        let x = u * u * p0.x + 2 * u * t * control.x + t * t * p1.x
        let y = u * u * p0.y + 2 * u * t * control.y + t * t * p1.y
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Token tile

/// A 42-pt copy of a food row tile — the thing that flies.
private struct FoodFlightTile: View {
    let food: Food
    var body: some View {
        Image(systemName: food.symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(food.tint.fg)
            .frame(width: 42, height: 42)
            .background(food.tint.bg)
    }
}

/// A circular color icon that rides on top of the metaball goo and dissolves into
/// it — the "color → black" handoff (the Canvas can only draw monochrome blobs).
private struct FoodBlobIcon: View {
    let food: Food
    var body: some View {
        Image(systemName: food.symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(food.tint.fg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(food.tint.bg, in: Circle())
    }
}

// MARK: - Metaball swallow (log flight)

/// The "island swallows the food" fuse. Both the idle island capsule and the
/// flying food blob are drawn as solid-black symbols inside ONE `Canvas` under a
/// `blur` + `alphaThreshold` filter pair: the blur softens each shape's alpha into
/// a halo, and the 0.5 threshold snaps it back to hard black — so where the two
/// halos overlap as the blob nears the island, the gap fills and they melt into a
/// single gooey shape (the metaball trick). The real color icon rides on top and
/// fades to black as it merges, since the Canvas itself is monochrome.
///
/// `Animatable` on `progress` so the flight is one interruptible curve: SwiftUI
/// re-invokes `body` (re-drawing the Canvas) for every interpolated frame. This is
/// purely visual — the controller still lands the flight on a Task timer.
private struct MetaballFlight: View, Animatable {
    var progress: Double
    let flight: Flight

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private var p0: CGPoint { CGPoint(x: flight.from.midX, y: flight.from.midY) }
    private var p1: CGPoint { CGPoint(x: flight.to.midX, y: flight.to.midY) }

    /// Control point directly BELOW the island center, so the tail of the curve
    /// rises vertically into the middle of the pill (the food is "sucked up" into
    /// the center) — not swept in from the left end.
    private var control: CGPoint {
        CGPoint(x: p1.x, y: p1.y + 90)
    }

    private func point(at t: Double) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * p0.x + 2 * u * t * control.x + t * t * p1.x,
                       y: u * u * p0.y + 2 * u * t * control.y + t * t * p1.y)
    }

    var body: some View {
        let t = min(max(progress, 0), 1)
        let pos = point(at: t)
        let blob = IslandMotion.metaballBlobStart
            + (IslandMotion.metaballBlobEnd - IslandMotion.metaballBlobStart) * t
        // Color icon dissolves into the goo over the back half of the flight.
        let fade = t < IslandMotion.metaballFadeStart ? 0
            : (t - IslandMotion.metaballFadeStart) / (1 - IslandMotion.metaballFadeStart)

        Canvas { ctx, _ in
            // Order matters: threshold added first, blur second → blur is applied to
            // the raw shapes, then the threshold hardens the blurred field.
            ctx.addFilter(.alphaThreshold(min: IslandMotion.metaballThreshold, color: .black))
            ctx.addFilter(.blur(radius: IslandMotion.metaballBlur))
            ctx.drawLayer { layer in
                if let island = layer.resolveSymbol(id: "island") {
                    layer.draw(island, at: CGPoint(x: flight.to.midX, y: flight.to.midY))
                }
                if let ball = layer.resolveSymbol(id: "ball") {
                    layer.draw(ball, at: pos)
                }
            }
        } symbols: {
            RoundedRectangle(cornerRadius: IslandMotion.idleCorner, style: .continuous)
                .fill(.black)
                .frame(width: IslandMotion.idleSize.width, height: IslandMotion.idleSize.height)
                .tag("island")
            Circle()
                .fill(.black)
                .frame(width: blob, height: blob)
                .tag("ball")
        }
        .overlay {
            FoodBlobIcon(food: flight.food)
                .frame(width: blob, height: blob)
                .blur(radius: fade * 4)
                .opacity(1 - fade)
                .position(pos)
        }
        .allowsHitTesting(false)
    }
}

/// Drives a metaball flight's progress 0 → 1 on the flight curve. The land itself
/// is timer-driven in the controller, so the card opens even if this never fires.
private struct MetaballFlightView: View {
    let flight: Flight
    @State private var progress: Double = 0

    var body: some View {
        MetaballFlight(progress: progress, flight: flight)
            .onAppear { withAnimation(IslandMotion.flight) { progress = 1 } }
    }
}

// MARK: - One flying token (+ trailing dots)

private struct FlightTokenView: View {
    let flight: Flight

    @State private var t: Double = 0

    private var p0: CGPoint { CGPoint(x: flight.from.midX, y: flight.from.midY) }
    private var p1: CGPoint { CGPoint(x: flight.to.midX, y: flight.to.midY) }

    /// Control point: left of the midpoint and above the higher of the two ends.
    /// Mirrored to the right for the return (reverse) flight so the curve arcs the
    /// opposite way — the token clearly retraces a different path back.
    private var control: CGPoint {
        let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        let dx = abs(p1.x - p0.x)
        let side: CGFloat = flight.reverse ? 1 : -1
        return CGPoint(x: mid.x + side * (dx * 0.5 + 40),
                       y: min(p0.y, p1.y) - 70)
    }

    var body: some View {
        ZStack {
            // Trail dots — three, each lagging 7% behind, dimmer as they trail.
            ForEach(0..<3, id: \.self) { i in
                let lag = 0.07 * Double(i + 1)
                let opacities = [0.45, 0.33, 0.21]
                Circle()
                    .fill(flight.food.tint.fg)
                    .frame(width: 6, height: 6)
                    .modifier(BezierFlight(t: t - lag, p0: p0, p1: p1,
                                           control: control, reverse: flight.reverse))
                    .opacity(flight.reverse ? 0 : opacities[i])   // no trail on the calmer return
            }

            FoodFlightTile(food: flight.food)
                .modifier(BezierFlight(t: t, p0: p0, p1: p1,
                                       control: control, reverse: flight.reverse))
        }
        // Pure visual: the controller lands the flight on a timer (see
        // `scheduleLand`), so the card opens even if this completion never fires.
        .onAppear { withAnimation(IslandMotion.flight) { t = 1 } }
    }
}

// MARK: - FlightLayer

/// The ZStack overlay above everything that renders every active flight token.
/// Each token drives its own progress and, on landing, calls back into the
/// controller (gulp + open card, or land + bounce) and removes itself.
struct FlightLayer: View {
    @Environment(IslandController.self) private var island

    var body: some View {
        ZStack {
            ForEach(island.flights) { flight in
                // The quick-add (+) flight melts into the island as a metaball;
                // tray add / remove keep the plain Bézier token.
                if case .log = flight.kind {
                    MetaballFlightView(flight: flight)
                } else {
                    FlightTokenView(flight: flight)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
