import SwiftUI
import Charts

// MARK: - StackedCardsCarousel (portrait photo-deck)

/// A neat deck of portrait cards (ref: AndreasVerhoeven/StackedItemsCarousel). The front
/// card is full-size and centered; the cards behind peek out at the bottom, scaled down —
/// like a stack of photos. Flick the front card in any direction and it springs away while
/// the deck smoothly advances. The content builder receives `isFront` (drives count-up).
struct StackedCardsCarousel<Item: Identifiable, Content: View>: View {
    let items: [Item]
    var cardWidth: CGFloat = 250
    var cardHeight: CGFloat = 360
    @ViewBuilder var content: (Item, Bool) -> Content

    @State private var topIndex = 0
    @State private var drag: CGSize = .zero
    // The card being thrown away renders as a transient flyaway, decoupled from the deck,
    // so the deck can advance in one continuous spring (no two-phase stall).
    @State private var flyingID: Item.ID?
    @State private var flyOffset: CGSize = .zero
    @State private var flyRotation: Double = 0

    private let maxVisible = 4
    private let deckSpring: Animation = .spring(response: 0.5, dampingFraction: 0.86)
    private func depth(_ i: Int) -> Int { (i - topIndex + items.count) % items.count }

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    if item.id == flyingID {
                        content(item, false)
                            .frame(width: cardWidth, height: cardHeight)
                            .rotationEffect(.degrees(flyRotation), anchor: .center)
                            .offset(flyOffset)
                            .zIndex(2000)
                            .allowsHitTesting(false)
                    } else {
                        deckCard(i, item)
                    }
                }
            }
            .frame(width: cardWidth + 24,
                   height: cardHeight + CGFloat(maxVisible) * 12 + 26)

            if items.count > 1 {
                HStack(spacing: 6) {
                    ForEach(items.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == topIndex ? Theme.textPrimary : Theme.textTertiary.opacity(0.4))
                            .frame(width: i == topIndex ? 18 : 6, height: 6)
                            .animation(.snappy, value: topIndex)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func deckCard(_ i: Int, _ item: Item) -> some View {
        let d = depth(i)
        let isFront = d == 0
        let shown = min(d, maxVisible)
        content(item, isFront)
            .frame(width: cardWidth, height: cardHeight)
            // Centered photo-stack: cards peek straight down (no rightward drift),
            // animated only on topIndex so the deck springs forward smoothly.
            .scaleEffect(1 - CGFloat(shown) * 0.03, anchor: .top)
            .offset(y: CGFloat(shown) * 12)
            .animation(deckSpring, value: topIndex)
            // live drag on the front card — 1:1 with the finger (no implicit animation)
            .rotationEffect(.degrees(isFront ? Double(drag.width) / 22 : 0), anchor: .bottom)
            .offset(isFront ? drag : .zero)
            .opacity(d <= maxVisible ? 1 : 0)
            .zIndex(isFront ? 1000 : Double(maxVisible - d))
            .allowsHitTesting(isFront)
            .gesture(isFront && items.count > 1 ? dragGesture : nil)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { drag = $0.translation }
            .onEnded { value in
                // Use the velocity-aware predicted end so a fast flick commits + throws far.
                let predicted = value.predictedEndTranslation
                let dist = hypot(value.translation.width, value.translation.height)
                let predDist = hypot(predicted.width, predicted.height)

                guard dist > 80 || predDist > 200 else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { drag = .zero }
                    return
                }

                HapticManager.shared.trigger(.light)
                let n = items.count
                // Hand the current card off to the flyaway layer at its live position…
                flyingID = items[topIndex].id
                flyOffset = drag
                flyRotation = Double(drag.width) / 22
                drag = .zero

                // …advance the deck in one spring…
                withAnimation(deckSpring) { topIndex = (topIndex + 1) % n }

                // …and let the thrown card continue off in the flick direction (velocity).
                let mag = max(1, predDist)
                let target = CGSize(width: predicted.width / mag * 760,
                                    height: predicted.height / mag * 760)
                withAnimation(.easeOut(duration: 0.4)) {
                    flyOffset = target
                    flyRotation += predicted.width >= 0 ? 16 : -16
                } completion: {
                    flyingID = nil
                    flyOffset = .zero
                    flyRotation = 0
                }
            }
    }
}

// MARK: - One bar of the stat card chart

struct StatBar: Identifiable {
    let id = UUID()
    let index: Int
    let label: String
    let value: Double
}

// MARK: - BigStatCard (Apple Health card)

/// Apple-Health-style stat card: bold title + a circular chevron (tap → detail),
/// a small period subtitle, a big colored number with a unit suffix, and a clear
/// per-period bar chart with faint gridlines and a date axis at the bottom.
struct BigStatCard: View {
    var title: String
    var subtitle: String
    var value: Double
    var grouped: Bool
    var unit: String
    var bars: [StatBar]
    var goal: Double
    var colors: [Color]
    var animate: Bool

    @State private var shownValue: Double = 0
    @State private var grow: Double = 0

    private var grad: LinearGradient {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
    private var maxY: Double { max(goal, bars.map(\.value).max() ?? 1) * 1.12 }
    private func fmt(_ v: Double) -> String { grouped ? Int(v).formatted() : "\(Int(v.rounded()))" }
    private var barWidth: CGFloat { bars.count <= 7 ? 16 : (bars.count <= 31 ? 5 : 9) }

    /// Up to four evenly-spaced x labels (Apple shows 12AM·6AM·12PM·6PM).
    private var tickIndices: [Int] {
        let n = bars.count
        guard n > 4 else { return Array(0..<n) }
        let step = max(1, (n - 1) / 3)
        return stride(from: 0, through: n - 1, by: step).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title + circular chevron
            HStack(alignment: .center) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Theme.surfaceRaised, in: Circle())
            }

            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 8)

            // Big colored number + unit suffix
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(fmt(shownValue))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(grad)
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle((colors.first ?? .white).opacity(0.75))
            }
            .padding(.top, 2)

            Spacer(minLength: 12)

            // Per-period bar chart with faint gridlines + date axis
            Chart {
                ForEach(bars) { bar in
                    BarMark(
                        x: .value("i", bar.index),
                        y: .value("v", bar.value * grow),
                        width: .fixed(barWidth)
                    )
                    .foregroundStyle(grad)
                    .clipShape(Capsule())
                }
            }
            .chartXScale(domain: -0.7 ... (Double(bars.count) - 0.3))
            .chartYScale(domain: 0 ... maxY)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: tickIndices) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                        .foregroundStyle(Theme.divider.opacity(0.7))
                    AxisValueLabel {
                        if let i = value.as(Int.self), let b = bars.first(where: { $0.index == i }) {
                            Text(b.label).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 132)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.surface)
                .overlay {
                    RadialGradient(colors: [(colors.first ?? .clear).opacity(0.16), .clear],
                                   center: .topTrailing, startRadius: 0, endRadius: 300)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
        .compositingGroup()
        .shadow(color: .black.opacity(0.4), radius: 7, y: 5)
        .onAppear { runCount() }
        .onChange(of: animate) { _, _ in runCount() }
    }

    private func runCount() {
        if animate {
            shownValue = 0; grow = 0
            withAnimation(.snappy(duration: 0.6)) { shownValue = value; grow = 1 }
        } else {
            shownValue = value; grow = 1
        }
    }
}
