import SwiftUI

/// Floating "Ask AI"-style bar (ref: IMG_4953). Non-functional stub for now — a glass
/// capsule that hints at a future natural-language logging / assistant flow.
/// Mount it as a `.safeAreaInset(edge: .bottom)` or overlay above a scroll view.
struct AskAIBar: View {
    var placeholder: String = "Ask AI to log a meal…"
    var onTap: () -> Void = {}

    var body: some View {
        Button {
            HapticManager.shared.trigger(.light)
            onTap()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(placeholder)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 18)
            .frame(height: 50)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.bottom, 6)
    }
}

#Preview {
    ZStack {
        Theme.bg.ignoresSafeArea()
        VStack {
            Spacer()
            AskAIBar()
        }
    }
    .preferredColorScheme(.dark)
}
