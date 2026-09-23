import SwiftUI
import UIKit

/// Central haptic manager. Law: every touch fires a haptic.
@MainActor
final class HapticManager {
    static let shared = HapticManager()
    private init() {}

    enum Kind {
        case light, medium, heavy, rigid, soft
        case selection
        case success, warning, error
    }

    func trigger(_ kind: Kind) {
        switch kind {
        case .light:  UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:  UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .rigid:  UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .soft:   UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:   UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

extension View {
    /// Fire a haptic when the view is tapped, then run `action`.
    func hapticTap(_ kind: HapticManager.Kind = .light, perform action: @escaping () -> Void = {}) -> some View {
        onTapGesture {
            HapticManager.shared.trigger(kind)
            action()
        }
    }
}
