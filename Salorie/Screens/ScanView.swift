import SwiftUI

/// Camera/barcode scan placeholder (UI-only phase). Glass viewfinder over the dark canvas.
struct ScanView: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Theme.cardStroke, lineWidth: 1)
                    )

                // Reticle
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.accent, lineWidth: 3)
                    .frame(width: 220, height: 140)
                    .shadow(color: Theme.accent.opacity(0.5), radius: 12)

                // Scan line
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, Theme.accent, .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 220, height: 2)
                    .offset(y: pulse ? 66 : -66)

                VStack {
                    Spacer()
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.bottom, 28)
                }
            }
            .frame(height: 320)
            .padding(.horizontal, Metrics.pagePadding)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }

            VStack(spacing: 6) {
                Text("Point at a barcode or nutrition label")
                    .font(.sectionTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("We'll match it against USDA, Open Food Facts, and your custom items.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            HStack(spacing: 12) {
                Button {
                    HapticManager.shared.trigger(.medium)
                } label: {
                    Label("Scan Barcode", systemImage: "barcode")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)

                Button {
                    HapticManager.shared.trigger(.medium)
                } label: {
                    Label("Label", systemImage: "text.viewfinder")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal, Metrics.pagePadding)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}

#Preview {
    ScanView().preferredColorScheme(.dark)
}
