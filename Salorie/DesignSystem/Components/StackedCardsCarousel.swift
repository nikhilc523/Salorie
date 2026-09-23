import SwiftUI

// MARK: - StackedCardsCarousel

/// A stacked deck of cards (ref: AndreasVerhoeven/StackedItemsCarousel). The front card
/// is full-size; the ones behind peek out scaled-down. Drag the front card sideways and
/// it flings away, cycling to the back of the stack. Page dots track position.
struct StackedCardsCarousel<Item: Identifiable, Content: View>: View {
    let items: [Item]
    var cardHeight: CGFloat = 210
    @ViewBuilder var content: (Item) -> Content

    @State private var topIndex = 0
    @State private var drag: CGSize = .zero
    @State private var fling: CGFloat = 0

    private let maxVisible = 3

    private func depth(_ i: Int) -> Int { (i - topIndex + items.count) % items.count }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    let d = depth(i)
                    let isFront = d == 0
                    let shown = min(d, maxVisible)
                    content(item)
                        .frame(height: cardHeight)
                        .scaleEffect(1 - CGFloat(shown) * 0.05, anchor: .top)
                        .offset(y: CGFloat(shown) * 16)
                        .offset(x: isFront ? drag.width + fling : 0)
                        .rotationEffect(.degrees(isFront ? Double(drag.width) / 22 : 0))
                        .opacity(d < maxVisible ? 1 : 0)
                        .zIndex(isFront ? 100 : Double(maxVisible - d))
                        .allowsHitTesting(isFront)
                        .gesture(isFront && items.count > 1 ? dragGesture : nil)
                }
            }
            .frame(height: cardHeight + CGFloat(maxVisible) * 16, alignment: .top)
            .frame(maxWidth: .infinity)

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
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if abs(value.translation.width) > 90 {
                    HapticManager.shared.trigger(.light)
                    let dir: CGFloat = value.translation.width > 0 ? 1 : -1
                    withAnimation(.easeIn(duration: 0.22)) {
                        fling = dir * 720
                    } completion: {
                        drag = .zero
                        fling = 0
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                            topIndex = (topIndex + 1) % items.count
                        }
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { drag = .zero }
                }
            }
    }
}

// MARK: - BigStatCard

/// Marketing-style stat card: a huge gradient number + percent, progress bar, caption.
struct BigStatCard: View {
    var tag: String
    var value: String
    var unit: String
    var percent: Int
    var caption: String
    var colors: [Color]

    private var grad: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(tag)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(percent)%")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(grad)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 62, weight: .heavy, design: .rounded))
                    .foregroundStyle(grad)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill((colors.first ?? .white).opacity(0.14))
                    Capsule().fill(grad)
                        .frame(width: max(6, geo.size.width * min(Double(percent) / 100, 1)))
                }
            }
            .frame(height: 8)
            .padding(.top, 14)

            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 10)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surface)
                .overlay {
                    RadialGradient(colors: [(colors.first ?? .clear).opacity(0.18), .clear],
                                   center: .topTrailing, startRadius: 0, endRadius: 260)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
    }
}
