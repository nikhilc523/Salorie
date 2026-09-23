import SwiftUI

// MARK: - StackedCardsCarousel (vertical)

/// A vertical stacked deck (ref: AndreasVerhoeven/StackedItemsCarousel). The front card
/// is full-size; cards behind peek out below, scaled down. Drag the front card up (or down)
/// and it slides gently to the back of the stack, revealing the next. Page dots track position.
/// The content builder receives `isFront` so the front card can animate (e.g. count up).
struct StackedCardsCarousel<Item: Identifiable, Content: View>: View {
    let items: [Item]
    var cardHeight: CGFloat = 210
    @ViewBuilder var content: (Item, Bool) -> Content

    @State private var topIndex = 0
    @State private var dragY: CGFloat = 0
    @State private var slide: CGFloat = 0

    private let maxVisible = 3
    private func depth(_ i: Int) -> Int { (i - topIndex + items.count) % items.count }

    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .top) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    let d = depth(i)
                    let isFront = d == 0
                    let shown = min(d, maxVisible)
                    content(item, isFront)
                        .frame(height: cardHeight)
                        .scaleEffect(1 - CGFloat(shown) * 0.05, anchor: .top)
                        .offset(y: isFront ? dragY + slide : CGFloat(shown) * 14)
                        .opacity(d < maxVisible ? 1 : 0)
                        .zIndex(isFront ? 100 : Double(maxVisible - d))
                        .allowsHitTesting(isFront)
                        .gesture(isFront && items.count > 1 ? dragGesture : nil)
                }
            }
            .frame(height: cardHeight + CGFloat(maxVisible) * 14, alignment: .top)
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
        DragGesture(minimumDistance: 8)
            .onChanged { dragY = $0.translation.height }
            .onEnded { value in
                let threshold: CGFloat = 70
                if abs(value.translation.height) > threshold {
                    HapticManager.shared.trigger(.light)
                    let dir: CGFloat = value.translation.height < 0 ? -1 : 1   // up = next
                    // Gentle slide (spring, not a hard fling), then cycle & settle.
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                        slide = dir * (cardHeight + 50)
                    } completion: {
                        dragY = 0
                        slide = 0
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                            topIndex = dir < 0
                                ? (topIndex + 1) % items.count
                                : (topIndex - 1 + items.count) % items.count
                        }
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { dragY = 0 }
                }
            }
    }
}

// MARK: - BigStatCard

/// Marketing-style stat card: a huge gradient number + percent, progress bar, caption.
/// When `animate` is true (front card) the number counts up and the bar fills.
struct BigStatCard: View {
    var tag: String
    var value: Double
    var format: (Double) -> String
    var unit: String
    var percent: Int
    var caption: String
    var colors: [Color]
    var animate: Bool

    @State private var progress: Double = 0   // 0…1 drives the count-up + bar fill

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
                Text("\(Int((Double(percent) * progress).rounded()))%")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(grad)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(format(value * progress))
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
                        .frame(width: max(6, geo.size.width * min(Double(percent) / 100, 1) * progress))
                }
            }
            .frame(height: 8)
            .padding(.top, 14)

            HStack(spacing: 6) {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if animate {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary.opacity(0.7))
                }
            }
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
        .onAppear { runCount() }
        .onChange(of: animate) { _, _ in runCount() }
    }

    private func runCount() {
        if animate {
            progress = 0
            withAnimation(.easeOut(duration: 0.85)) { progress = 1 }
        } else {
            progress = 1
        }
    }
}
