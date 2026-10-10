import SwiftUI

/// The Dynamic-Island counterpart to `SalorieRings`: three concentric **upper-half**
/// semicircles (calories · protein · carbs) sized for the tiny island card. Values are
/// fractions (1.0 = 100%); each ring fills its own arc and animates smoothly when the
/// fraction changes. Flattened with `.drawingGroup()` so it composites as one layer
/// during the island's spring morph and stays at 120 fps on ProMotion.
///
/// Colours are the exact app ring tones — oatmeal / caramel / terracotta on the
/// `#1B1714` sun track — so the island reads as a shrunken copy of the hero rings.
struct MiniSemicircleRings: View {
    var calories: Double
    var protein: Double
    var carbs: Double

    /// Stroke width as a fraction of the view width.
    var lineWidthRatio: CGFloat = 0.15

    private static let styles: [RingStyle] = [.calories, .protein, .carbs]
    private static let track = Color(hex: 0x1B1714)

    var body: some View {
        // Drawn straight from the passed fractions so the arcs are always visible
        // (no internal @State / drawingGroup that could snapshot empty inside the
        // card's blur-replace transition). The `.animation` gives a smooth fill as
        // the fractions change when the card opens.
        Canvas { ctx, size in
            let w = size.width
            let lw = w * lineWidthRatio
            let c = CGPoint(x: w / 2, y: size.height - lw / 2)
            let R = (w - lw) / 2
            let radii = [R, R * 0.68, R * 0.36]
            let stroke = StrokeStyle(lineWidth: lw, lineCap: .round)
            let vals = [calories, protein, carbs]

            func arc(_ r: CGFloat, _ to: Double) -> Path {
                var p = Path()
                p.addArc(center: c, radius: r, startAngle: .degrees(180),
                         endAngle: .degrees(180 + 180 * max(min(to, 1), 0.001)),
                         clockwise: false)
                return p
            }

            for i in 0..<3 {
                ctx.stroke(arc(radii[i], 1), with: .color(Self.track), style: stroke)
                if vals[i] > 0.001 {
                    ctx.stroke(arc(radii[i], min(max(vals[i], 0.06), 1)),
                               with: .color(Color(hex: Self.styles[i].base)), style: stroke)
                }
            }
        }
        // A hair over 2:1 so the outer arc's round cap isn't clipped at the peak.
        .aspectRatio(1.9, contentMode: .fit)
        .animation(IslandMotion.ringFill, value: calories)
        .animation(IslandMotion.ringFill, value: protein)
        .animation(IslandMotion.ringFill, value: carbs)
        .accessibilityHidden(true)
    }
}

#Preview("MiniSemicircleRings") {
    struct Demo: View {
        @State private var full = false
        var body: some View {
            VStack(spacing: 24) {
                MiniSemicircleRings(calories: full ? 0.62 : 0,
                                    protein: full ? 0.51 : 0,
                                    carbs: full ? 0.63 : 0)
                    .frame(width: 56)
                    .padding(20)
                    .background(.black, in: RoundedRectangle(cornerRadius: 20))
                Button(full ? "Empty" : "Fill") { full.toggle() }
                    .foregroundStyle(Color(hex: 0xE3D9C6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: 0x101010))
        }
    }
    return Demo()
}
