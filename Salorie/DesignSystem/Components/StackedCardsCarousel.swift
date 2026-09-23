import SwiftUI

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
            .frame(width: cardWidth + CGFloat(maxVisible) * 15 + 24,
                   height: cardHeight + CGFloat(maxVisible) * 7 + 30)

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
            // fanned deck geometry (iMessage photo-stack) — animated only on topIndex,
            // so the deck springs forward smoothly when a card is thrown.
            .scaleEffect(1 - CGFloat(shown) * 0.02, anchor: .center)
            .rotationEffect(.degrees(Double(shown) * 3.5), anchor: .center)
            .offset(x: CGFloat(shown) * 15, y: CGFloat(shown) * 7)
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

// MARK: - BigStatCard (portrait)

/// Marketing-style portrait stat card: tag, a huge gradient number that counts up when
/// this card is at the front, a progress bar, and a caption — over a photo-like panel.
struct BigStatCard: View {
    var tag: String
    var value: Double
    var format: (Double) -> String
    var unit: String
    var percent: Int
    var caption: String
    var colors: [Color]
    var animate: Bool

    @State private var progress: Double = 0

    private var grad: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(tag)
                    .font(.system(size: 13, weight: .bold)).tracking(1.4)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(Int((Double(percent) * progress).rounded()))%")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(grad).monospacedDigit()
            }

            Spacer(minLength: 0)

            // Huge hero number, centered in the portrait body
            VStack(alignment: .leading, spacing: -4) {
                Text(format(value * progress))
                    .font(.system(size: 74, weight: .heavy, design: .rounded))
                    .foregroundStyle(grad)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(unit)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 0)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill((colors.first ?? .white).opacity(0.16))
                    Capsule().fill(grad)
                        .frame(width: max(6, geo.size.width * min(Double(percent) / 100, 1) * progress))
                }
            }
            .frame(height: 8)

            HStack(spacing: 6) {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.surface)
                .overlay {
                    RadialGradient(colors: [(colors.first ?? .clear).opacity(0.22), .clear],
                                   center: .topTrailing, startRadius: 0, endRadius: 320)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
        .onAppear { runCount() }
        .onChange(of: animate) { _, _ in runCount() }
    }

    private func runCount() {
        if animate {
            progress = 0
            withAnimation(.easeOut(duration: 0.9)) { progress = 1 }
        } else {
            progress = 1
        }
    }
}
