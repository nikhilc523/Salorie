import SwiftUI

// MARK: - Palette

/// A single ring's exact colors. Base = the solid stroke; tipLight = the light
/// tone that a wrapped lap fades toward at its tip. Never red/orange/warning.
struct RingStyle: Hashable, Sendable {
    let base: UInt          // solid base stroke
    let tipLight: UInt      // light tone for wrapped-lap tips

    static let calories = RingStyle(base: 0xE3D9C6, tipLight: 0xF7F2E9) // oatmeal
    static let protein  = RingStyle(base: 0xD1A67A, tipLight: 0xEACBA6) // caramel
    static let carbs    = RingStyle(base: 0xB3664C, tipLight: 0xD98E72) // terracotta
}

private enum SunTone {
    static let horizon = Color(hex: 0x3A2E25) // horizon line
    static let pillDark = Color(hex: 0x17110D) // near-black text on solid pills
}

/// Linear blend of two packed hex colors in sRGB.
private func mix(_ a: UInt, _ b: UInt, _ t: Double) -> Color {
    func ch(_ v: UInt, _ s: UInt) -> Double { Double((v >> s) & 0xFF) }
    let r  = ch(a, 16) + (ch(b, 16) - ch(a, 16)) * t
    let g  = ch(a, 8)  + (ch(b, 8)  - ch(a, 8))  * t
    let bl = ch(a, 0)  + (ch(b, 0)  - ch(a, 0))  * t
    return Color(.sRGB, red: r / 255, green: g / 255, blue: bl / 255, opacity: 1)
}

// MARK: - Geometry

/// Shared geometry for the "rising sun" rings so every layer lines up exactly.
/// Ring center is pinned so the artwork is identical whether or not the tall
/// below-horizon pill area is reserved.
private struct SunGeometry {
    let s: CGFloat
    let center: CGPoint
    let R: CGFloat
    let W: CGFloat
    let radii: [CGFloat]

    /// Design box is 320×196 for the rings; only when a pill actually needs to
    /// drop below the horizon do we extend the box downward so it isn't clipped.
    /// Under goal the box stays tight so the stats sit right beneath the sun.
    static let designWidth: CGFloat = 320
    /// `compact` hugs the box to the arcs (used when the horizon line is dropped
    /// and the milestone track supplies the base below), trimming the dead space
    /// under the sun so the track can sit a comfortable — not huge — gap below.
    static func designHeight(reserveDock: Bool, compact: Bool = false) -> CGFloat {
        if reserveDock { return 260 }
        return compact ? 170 : 196
    }

    init(size: CGSize, reserveDock: Bool, compact: Bool = false) {
        let h = SunGeometry.designHeight(reserveDock: reserveDock, compact: compact)
        s = min(size.width / SunGeometry.designWidth, size.height / h)
        center = CGPoint(x: size.width / 2, y: (size.height - h * s) / 2 + 158 * s)
        R = 114 * s
        W = 22 * s
        radii = [R, R * 0.754, R * 0.509]
    }

    /// Tip of lap 1 (the leading edge of the filled arc) at fraction `f` (0…1).
    func tip(ringIndex: Int, f: Double) -> CGPoint {
        let r = radii[ringIndex]
        let theta = Angle.degrees(180 + 180 * min(max(f, 0), 1)).radians
        return CGPoint(x: center.x + r * cos(theta), y: center.y + r * sin(theta))
    }

    /// Resting spot under the horizon for the solid pill (staircase, inner→outer).
    func dockPoint(ringIndex: Int) -> CGPoint {
        let r = radii[ringIndex]
        let drop: CGFloat = ringIndex == 2 ? 1.73 : ringIndex == 1 ? 2.82 : 3.91
        return CGPoint(x: center.x + r + 4 * s, y: center.y + W * drop)
    }
}

private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

// MARK: - Horizon backdrop

/// The single horizon line, drawn once beneath every ring layer.
private struct SunBackdrop: View {
    let reserveDock: Bool
    /// The milestone track carries its own line below the rings, so when it's on
    /// we drop the sun's horizon line and let the arcs float above it (like the
    /// mockup) — no double line.
    var showHorizon: Bool = true
    var body: some View {
        Canvas { ctx, size in
            guard showHorizon else { return }
            let g = SunGeometry(size: size, reserveDock: reserveDock)
            var h = Path()
            h.move(to: CGPoint(x: g.center.x - (g.R + g.W), y: g.center.y + g.W))
            h.addLine(to: CGPoint(x: g.center.x + (g.R + g.W), y: g.center.y + g.W))
            ctx.stroke(h, with: .color(SunTone.horizon),
                       style: .init(lineWidth: g.W * 0.23, lineCap: .round))
        }
    }
}

// MARK: - One ring layer

/// A single semicircle ring — track, laps, soft tip shadow, and its percentage
/// pill — drawn in one Canvas. It's `Animatable` on `frac` (real progress) and
/// `dock` (0 = riding the tip, 1 = docked under the horizon) so the pill follows
/// the arc per-frame and slides smoothly to its resting spot.
private struct SunRingLayer: View, Animatable {
    var frac: Double            // real progress, unclamped (1.0 = 100%)
    var dock: Double            // 0…1 dock amount
    let ringIndex: Int          // 0 = outer/calories, 1 = protein, 2 = inner/carbs
    let style: RingStyle
    let showPills: Bool
    let showShadow: Bool
    let reserveDock: Bool
    var compact: Bool = false

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { .init(frac, dock) }
        set { frac = newValue.first; dock = newValue.second }
    }

    var body: some View {
        Canvas { ctx, size in
            let g = SunGeometry(size: size, reserveDock: reserveDock, compact: compact)
            let r = g.radii[ringIndex]
            let c = g.center
            let W = g.W, s = g.s
            let stroke = StrokeStyle(lineWidth: W, lineCap: .round)
            let p = min(max(frac, 0), 3)

            // 1. Track — a dark tint of THIS ring's colour (not a neutral groove), so a
            // no-data day still reads as a faint coloured ring, Apple-Activity style.
            ctx.stroke(arc(c, r, to: 1), with: .color(mix(style.base, 0x000000, 0.75)), style: stroke)
            // 2. Lap 1
            ctx.stroke(arc(c, r, to: min(p, 1)), with: .color(Color(hex: style.base)), style: stroke)

            // 3–4. Wrapped laps (only the topmost lap casts a shadow).
            let topLap = p > 2 + 0.004 ? 2 : (p > 1 + 0.004 ? 1 : 0)
            if topLap > 0 {
                for k in 1...2 where p > Double(k) + 0.004 {
                    let f = min(p - Double(k), 1)
                    let theta = Angle.degrees(180 + 180 * f).radians
                    let tip = CGPoint(x: c.x + r * cos(theta), y: c.y + r * sin(theta))
                    let dir = CGPoint(x: -sin(theta), y: cos(theta)) // direction of travel

                    // Ease the lap treatment in with its size so a just-over-goal
                    // stub (e.g. 106%) blends into the base instead of reading as a
                    // light nub with a shadow — keeps every ring consistent.
                    let ramp = min(f / 0.28, 1)

                    if showShadow && k == topLap && ramp > 0.15 {
                        ctx.drawLayer { layer in
                            layer.addFilter(.blur(radius: 2.6 * s))
                            let sc = CGPoint(x: tip.x + dir.x * 3.5 * s, y: tip.y + dir.y * 3.5 * s)
                            layer.fill(Path(ellipseIn: CGRect(x: sc.x - W / 2, y: sc.y - W / 2, width: W, height: W)),
                                       with: .color(.black.opacity(0.6 * ramp)))
                        }
                    }

                    let tipColor = mix(style.base, style.tipLight, (k == 1 ? 0.55 : 0.85) * ramp)
                    let sweep = 180 * f / 360
                    let gradient = Gradient(stops: [
                        .init(color: Color(hex: style.base), location: 0),
                        .init(color: tipColor, location: sweep),
                        .init(color: tipColor, location: 1),
                    ])
                    ctx.stroke(arc(c, r, to: f),
                               with: .conicGradient(gradient, center: c, angle: .degrees(180)),
                               style: stroke)
                }
            }

            if showPills { drawPill(&ctx, g) }
        }
    }

    private func arc(_ c: CGPoint, _ r: CGFloat, to fraction: Double) -> Path {
        var p = Path()
        p.addArc(center: c, radius: r, startAngle: .degrees(180),
                 endAngle: .degrees(180 + 180 * max(fraction, 0.002)), clockwise: false)
        return p
    }

    private func drawPill(_ ctx: inout GraphicsContext, _ g: SunGeometry) {
        let W = g.W, s = g.s
        let pct = Int(frac * 100)
        let font = Font.system(size: W * 0.48, weight: .bold, design: .rounded).monospacedDigit()

        // Position: ride lap-1 tip, then slide down to the dock as `dock` → 1.
        let tip = g.tip(ringIndex: ringIndex, f: min(max(frac, 0), 1))
        let pos = lerp(tip, g.dockPoint(ringIndex: ringIndex), CGFloat(min(max(dock, 0), 1)))

        // Capsule size from measured text.
        let probe = ctx.resolve(Text("\(pct)%").font(font))
        let tSize = probe.measure(in: CGSize(width: 400, height: 100))
        let h = W * 0.82
        let width = max(tSize.width + W * 0.55, W * 1.7)
        let rect = CGRect(x: pos.x - width / 2, y: pos.y - h / 2, width: width, height: h)
        let capsule = Path(roundedRect: rect, cornerRadius: h / 2)

        let d = min(max(dock, 0), 1)
        // Outline style (under goal) fades out as the solid style fades in.
        if d < 0.999 {
            ctx.fill(capsule, with: .color(Color(hex: 0x000000).opacity(1 - d)))
            ctx.stroke(capsule, with: .color(Color(hex: style.base).opacity(1 - d)),
                       style: .init(lineWidth: 1.5 * s))
            ctx.draw(Text("\(pct)%").font(font).foregroundColor(Color(hex: style.base).opacity(1 - d)),
                     at: pos, anchor: .center)
        }
        if d > 0.001 {
            ctx.fill(capsule, with: .color(Color(hex: style.base).opacity(d)))
            ctx.draw(Text("\(pct)%").font(font).foregroundColor(SunTone.pillDark.opacity(d)),
                     at: pos, anchor: .center)
        }
    }
}

// MARK: - SalorieRings

/// Three concentric semicircle rings — a rising sun — with Apple-Fitness-style
/// wrapped laps, soft tip shadows, and percentage pills.
///
/// Values are real progress (1.0 = 100%); rings draw up to 3 laps but pills
/// always show the true percentage. Feed `consumed / goal` per metric.
struct SalorieRings: View {
    var calories: Double
    var protein: Double
    var carbs: Double
    var showPills: Bool = true
    var showShadow: Bool = true
    /// Drop the sun's horizon line when the milestone track below supplies its own.
    var showHorizon: Bool = true

    @State private var frac: [Double] = [0, 0, 0]
    @State private var dock: [Double] = [0, 0, 0]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let styles: [RingStyle] = [.calories, .protein, .carbs]

    private var targets: [Double] { [calories, protein, carbs] }

    /// Only reserve the tall below-horizon area when a pill will actually dock
    /// there — otherwise the stats can sit tight beneath the sun.
    private var reserveDock: Bool {
        showPills && (calories >= 1 || protein >= 1 || carbs >= 1)
    }

    private var compact: Bool { !showHorizon }

    var body: some View {
        ZStack {
            SunBackdrop(reserveDock: reserveDock, showHorizon: showHorizon)
            ForEach(0..<3, id: \.self) { i in
                SunRingLayer(frac: frac[i], dock: dock[i], ringIndex: i,
                             style: styles[i], showPills: showPills,
                             showShadow: showShadow, reserveDock: reserveDock,
                             compact: compact)
            }
        }
        .aspectRatio(SunGeometry.designWidth / SunGeometry.designHeight(reserveDock: reserveDock, compact: compact),
                     contentMode: .fit)
        .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8), value: reserveDock)
        .onAppear { apply(animated: !reduceMotion) }
        .onChange(of: calories) { _, _ in apply(animated: !reduceMotion) }
        .onChange(of: protein) { _, _ in apply(animated: !reduceMotion) }
        .onChange(of: carbs) { _, _ in apply(animated: !reduceMotion) }
        .accessibilityElement()
        .accessibilityLabel("Calories \(Int(calories * 100)) percent, protein \(Int(protein * 100)) percent, carbs \(Int(carbs * 100)) percent")
    }

    /// Stagger the rings — calories first, protein +70 ms, carbs +140 ms — and
    /// jump straight to the target values when Reduce Motion is on.
    private func apply(animated: Bool) {
        let t = targets
        for i in 0..<3 {
            let f = t[i]
            let d: Double = f >= 1 ? 1 : 0
            if animated {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(Double(i) * 0.07)) {
                    frac[i] = f
                    dock[i] = d
                }
            } else {
                frac[i] = f
                dock[i] = d
            }
        }
    }
}

// MARK: - Stats row

/// One metric's real numbers for the stats row below the rings.
struct MacroDatum: Hashable {
    var consumed: Double
    var goal: Double

    var fraction: Double { goal > 0 ? consumed / goal : 0 }
    var pct: Int { Int((fraction * 100).rounded()) }
}

/// Apple-Health-style three-column stats row: label / big value+unit / status.
/// Numbers count with `.numericText()`; status stays neutral gray (never a
/// warning color) whether under, at, or over goal.
private struct MacroStatsRow: View {
    let calories: MacroDatum
    let protein: MacroDatum
    let carbs: MacroDatum

    private static let labelColor  = Color(hex: 0x8E8E93)
    private static let unitColor   = Color(hex: 0x636366)
    private static let statusColor = Color(hex: 0x8E8E93)

    var body: some View {
        // No divider rule under the rings — the stats sit directly beneath the sun.
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            column("Calories", calories, unit: "kcal", color: Color(hex: 0xE3D9C6))
            column("Protein", protein, unit: "g", color: Color(hex: 0xD1A67A))
            column("Carbs", carbs, unit: "g", color: Color(hex: 0xB3664C))
        }
        .padding(.top, 14)
        .padding(.horizontal, 8)
    }

    private func column(_ label: String, _ datum: MacroDatum, unit: String, color: Color) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Self.labelColor)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(datum.consumed, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Self.unitColor)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(statusText(datum))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Self.statusColor)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(Int(datum.consumed)) \(unit == "kcal" ? "kilocalories" : "grams"), \(accessibilityStatus(datum))")
    }

    private func statusText(_ d: MacroDatum) -> String {
        if d.pct > 100 { return "+\(d.pct - 100)% over" }
        if d.pct == 100 { return "Goal reached" }
        return "\(d.pct)% of goal"
    }

    private func accessibilityStatus(_ d: MacroDatum) -> String {
        if d.pct > 100 { return "\(d.pct - 100) percent over goal" }
        if d.pct == 100 { return "goal reached" }
        return "\(d.pct) percent of goal"
    }
}

// MARK: - SalorieMacroSummary

/// The full hero: rising-sun rings with pills, plus the stats row beneath.
/// Feed real consumed/goal per metric — display numbers come from these, not the
/// clamped ring value, so 240% still reads "+140% over".
struct SalorieMacroSummary: View {
    let calories: MacroDatum
    let protein: MacroDatum
    let carbs: MacroDatum
    /// Percentage pills are off on the Home hero — the stats row already shows the
    /// real numbers and "% of goal", so the pills were redundant clutter.
    var showPills: Bool = false
    /// Optional weight-milestone journey shown as its own line below the rings.
    var weight: WeightTrack? = nil

    var body: some View {
        VStack(spacing: 8) {
            SalorieRings(calories: calories.fraction,
                         protein: protein.fraction,
                         carbs: carbs.fraction,
                         showPills: showPills,
                         showHorizon: weight == nil)
            if let weight {
                WeightMilestoneTrack(track: weight)
                    .padding(.top, 6)
            }
            MacroStatsRow(calories: calories, protein: protein, carbs: carbs)
                .padding(.top, weight == nil ? 0 : 12)
        }
    }
}

// MARK: - Weight milestone track

/// The three weights that define the milestone journey.
struct WeightTrack: Equatable {
    var start: Double
    var current: Double
    var target: Double
}

/// Drops trailing ".0" so whole kilos read cleanly.
private func weightLabel(_ v: Double) -> String {
    v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)
}

/// The weight journey as its own element below the rings: a wide line with
/// milestone markers, large numbers tucked right under it, and a caption close
/// beneath. Sits with comfortable breathing room from the (horizon-less) rings.
struct WeightMilestoneTrack: View {
    let track: WeightTrack

    @State private var anim: Double = 0   // animated fill/knob position (0…1)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let reached  = Color(hex: 0xE3D9C6) // oatmeal — progress + checks
    private let flagTint = Color(hex: 0xB3664C) // terracotta — goal + "next"
    private let rail     = Color(hex: 0x3A2E25) // empty line (the old horizon tone)
    private let upcoming = Color(hex: 0x4A3B30) // not-yet dots

    private let lineY: CGFloat = 20             // headroom above for flag + knob
    private let numberGap: CGFloat = 25         // numbers hug the line
    private let inset: CGFloat = 13             // so end markers/flag aren't clipped

    private var milestones: [Double] { WeightPrefs.milestones(start: track.start, target: track.target) }
    private var realProgress: Double { WeightPrefs.progress(start: track.start, current: track.current, target: track.target) }

    private func frac(_ v: Double) -> Double {
        guard track.start != track.target else { return 0 }
        return min(max((v - track.start) / (track.target - track.start), 0), 1)
    }
    private func isReached(_ v: Double) -> Bool { anim >= frac(v) - 0.0001 }
    private var nextIndex: Int? { milestones.dropLast().firstIndex { !isReached($0) } }

    private var reachedCount: Int {
        milestones.dropLast().filter { realProgress >= frac($0) - 0.0001 }.count
    }
    private var nextTarget: (value: Double, away: Double)? {
        guard let v = milestones.first(where: { realProgress < frac($0) - 0.0001 }) else { return nil }
        return (v, abs(track.current - v))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in lineAndMarkers(width: geo.size.width) }
                .frame(height: lineY + numberGap + 12)
            caption
        }
        .onAppear { animate() }
        .onChange(of: track) { _, _ in animate() }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private func lineAndMarkers(width w: CGFloat) -> some View {
        let usable = max(w - inset * 2, 1)
        func x(_ f: Double) -> CGFloat { inset + usable * CGFloat(f) }
        let lineH: CGFloat = 5

        return ZStack(alignment: .topLeading) {
            // Empty rail + bright reached portion up to the present weight.
            Capsule().fill(rail).frame(width: usable, height: lineH)
                .position(x: w / 2, y: lineY)
            Capsule().fill(reached)
                .frame(width: max(usable * CGFloat(anim), 0.001), height: lineH)
                .position(x: inset + usable * CGFloat(anim) / 2, y: lineY)

            ForEach(Array(milestones.enumerated()), id: \.offset) { i, v in
                let isGoal = i == milestones.count - 1
                marker(v, isGoal: isGoal, isNext: i == nextIndex)
                    .position(x: x(frac(v)), y: lineY)
                Text(weightLabel(v))
                    .font(.system(size: 15, weight: labelWeight(v, isGoal: isGoal), design: .rounded))
                    .monospacedDigit()
                    .fixedSize()
                    .foregroundStyle(labelColor(v, isGoal: isGoal, isNext: i == nextIndex))
                    .position(x: x(frac(v)), y: lineY + numberGap)
            }

            // Goal flag flies just above the final marker.
            Image(systemName: "flag.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(flagTint)
                .position(x: x(1), y: lineY - 16)

            // Present-weight knob rides the head of the filled line.
            Circle().fill(reached).frame(width: 13, height: 13)
                .overlay(Circle().stroke(Theme.bg, lineWidth: 3))
                .shadow(color: reached.opacity(0.5), radius: 4)
                .position(x: x(anim), y: lineY)
        }
    }

    @ViewBuilder
    private func marker(_ v: Double, isGoal: Bool, isNext: Bool) -> some View {
        if isGoal {
            Circle().fill(isReached(v) ? flagTint : Color(hex: 0x2A2420)).frame(width: 19, height: 19)
                .overlay(Circle().stroke(flagTint, lineWidth: isReached(v) ? 0 : 2))
        } else if isReached(v) {
            Circle().fill(reached).frame(width: 21, height: 21)
                .overlay(Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Color(hex: 0x17110D)))
        } else if isNext {
            Circle().fill(Theme.bg).frame(width: 19, height: 19)
                .overlay(Circle().stroke(flagTint, lineWidth: 2))
        } else {
            Circle().fill(upcoming).frame(width: 9, height: 9)
        }
    }

    private var caption: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(reachedCount) ").fontWeight(.bold).foregroundStyle(reached)
            + Text(reachedCount == 1 ? "milestone reached" : "milestones reached")
                .foregroundStyle(Theme.textSecondary)

            Spacer(minLength: 8)

            if let next = nextTarget {
                Text("Next: ").foregroundStyle(Theme.textSecondary)
                + Text("\(weightLabel(next.value)) kg").fontWeight(.semibold).foregroundStyle(Theme.textPrimary)
                + Text(", \(weightLabel(next.away)) kg away").foregroundStyle(Theme.textSecondary)
            } else {
                Text("Goal reached").fontWeight(.semibold).foregroundStyle(flagTint)
            }
        }
        .font(.system(size: 12))
    }

    private func labelWeight(_ v: Double, isGoal: Bool) -> Font.Weight {
        isGoal || isReached(v) ? .semibold : .regular
    }
    private func labelColor(_ v: Double, isGoal: Bool, isNext: Bool) -> Color {
        if isGoal || isNext { return flagTint }
        if isReached(v) { return Theme.textSecondary }
        return Theme.textTertiary
    }
    private func animate() {
        if reduceMotion { anim = realProgress }
        else { withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) { anim = realProgress } }
    }
    private var accessibilityText: String {
        if let next = nextTarget {
            return "Weight goal: \(reachedCount) milestones reached. Next milestone \(weightLabel(next.value)) kilograms, \(weightLabel(next.away)) away. Target \(weightLabel(track.target)) kilograms."
        }
        return "Weight goal reached: \(weightLabel(track.target)) kilograms."
    }
}

// MARK: - MiniSunRings

/// A tiny three-ring rising sun (semicircle) — the compact counterpart to the
/// hero, for the day-detail week strip and other small spots. No pills/shadow.
struct MiniSunRings: View {
    var calories: Double
    var protein: Double
    var carbs: Double
    var lineWidthRatio: CGFloat = 0.11

    private let styles: [RingStyle] = [.calories, .protein, .carbs]

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let lw = w * lineWidthRatio
            let c = CGPoint(x: w / 2, y: size.height - lw / 2)
            let R = (w - lw) / 2
            let radii = [R, R * 0.68, R * 0.36]
            let vals = [calories, protein, carbs]

            func arc(_ r: CGFloat, _ to: Double) -> Path {
                var p = Path()
                p.addArc(center: c, radius: r, startAngle: .degrees(180),
                         endAngle: .degrees(180 + 180 * max(min(to, 1), 0.001)), clockwise: false)
                return p
            }

            let stroke = StrokeStyle(lineWidth: lw, lineCap: .round)
            for i in 0..<3 {
                // Empty track = a dark tint of the ring's own colour (Apple-Activity look),
                // so a no-data day still shows faint coloured rings, not a black groove.
                ctx.stroke(arc(radii[i], 1), with: .color(mix(styles[i].base, 0x000000, 0.75)), style: stroke)
                if vals[i] > 0 {
                    ctx.stroke(arc(radii[i], min(vals[i], 1)), with: .color(Color(hex: styles[i].base)), style: stroke)
                }
            }
        }
        // A hair taller than a pure semicircle (2:1) so the outer arc's stroke
        // isn't clipped at the peak.
        .aspectRatio(1.7, contentMode: .fit)
    }
}

// MARK: - Preview

#Preview("SalorieRings") {
    struct Demo: View {
        @State private var over = false
        private var cal: MacroDatum { over ? .init(consumed: 3300, goal: 2200) : .init(consumed: 1650, goal: 2200) }
        private var pro: MacroDatum { over ? .init(consumed: 210, goal: 140) : .init(consumed: 97, goal: 140) }
        private var carb: MacroDatum { over ? .init(consumed: 375, goal: 250) : .init(consumed: 198, goal: 250) }

        var body: some View {
            VStack(spacing: 28) {
                SalorieMacroSummary(calories: cal, protein: pro, carbs: carb)
                Button(over ? "Under goal" : "Lap it") {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { over.toggle() }
                }
                .foregroundStyle(Color(hex: 0xE3D9C6))
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
    }
    return Demo()
}
