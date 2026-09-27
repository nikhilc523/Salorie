import SwiftUI

// MARK: - TagPill

/// Notion-style colored tag. Nearly-square corners. Soft (muted bg) or filled (solid) style.
struct TagPill: View {
    enum Style { case soft, filled }

    let text: String
    let color: TagColor
    var style: Style = .soft

    var body: some View {
        Text(text)
            .font(.pill)
            .lineLimit(1)
            .foregroundStyle(style == .soft ? color.fg : Color(hex: 0x1A1A1A))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Metrics.pillRadius, style: .continuous)
                    .fill(style == .soft ? color.bg : color.solid)
            )
    }
}

extension TagPill {
    init(_ tag: Tag) {
        self.text = tag.text
        self.color = tag.color
        self.style = tag.filled ? .filled : .soft
    }
}

// MARK: - GhostBadge

/// Outlined gray capsule, e.g. "OPEN".
struct GhostBadge: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.divider, lineWidth: 1)
            )
    }
}

// MARK: - SourceBadge

/// Maps a `FoodSource` to a colored TagPill. Shown on every food row.
struct SourceBadge: View {
    let source: FoodSource
    var body: some View {
        TagPill(text: source.short, color: source.tagColor, style: .soft)
    }
}

// MARK: - StatPill

/// Small solid mini-pill for compliance-style stats (e.g. "33%").
struct StatPill: View {
    let text: String
    let color: TagColor
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color.fg)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.bg))
    }
}

// MARK: - Toast (glass pill)

/// One transient confirmation — e.g. "Added to Favorites". `token` lets an identical
/// message re-trigger the reveal + auto-dismiss timer when tapped again.
struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let symbol: String
    var tint: Color = RingColor.protein.tint   // caramel star, matches the favorite glyph
    var token: Int = 0
}

/// The floating glass capsule itself — liquid glass + hairline stroke, on the app's
/// terracotta/caramel palette, so it reads as part of the same surface family.
struct ToastPill: View {
    let message: ToastMessage
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: message.symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(message.tint)
                .symbolEffect(.bounce, value: message.token)
            Text(message.text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glassEffect(.regular.tint(message.tint.opacity(0.12)), in: Capsule())
        .overlay(Capsule().stroke(Theme.cardStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.text)
    }
}

extension View {
    /// Overlay a transient glass toast near the top. Auto-dismisses after `duration`.
    func salorieToast(_ message: Binding<ToastMessage?>, duration: Double = 1.7) -> some View {
        modifier(SalorieToastModifier(message: message, duration: duration))
    }
}

private struct SalorieToastModifier: ViewModifier {
    @Binding var message: ToastMessage?
    let duration: Double

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let m = message {
                    ToastPill(message: m)
                        .padding(.top, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        // Re-runs (restarting the timer) whenever a new message/token appears.
                        .task(id: m.token) {
                            try? await Task.sleep(for: .seconds(duration))
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                                message = nil
                            }
                        }
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: message)
    }
}

#Preview("Pills") {
    ZStack {
        Theme.bg.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TagPill(text: "Learning", color: .purple)
                TagPill(text: "Homemade", color: .blue, style: .filled)
                TagPill(text: "Overdue", color: .red)
            }
            HStack {
                GhostBadge("OPEN")
                SourceBadge(source: .usdaFoundation)
                SourceBadge(source: .openFoodFacts)
                SourceBadge(source: .custom)
            }
            HStack {
                StatPill(text: "33%", color: .green)
                StatPill(text: "87%", color: .blue)
            }
        }
        .padding()
    }
}
