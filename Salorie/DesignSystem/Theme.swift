import SwiftUI

/// Salorie color tokens — Notion dark palette (v1 is dark-only).
/// All values pulled from the reference screenshots in `/UI`.
enum Theme {

    // MARK: Surfaces
    static let bg            = Color(hex: 0x191919) // page background
    static let surface       = Color(hex: 0x202020) // cards, board columns, metric cards
    static let surfaceRaised = Color(hex: 0x252525) // selected/hover row, popovers
    static let divider       = Color(hex: 0x2E2E2E) // table lines, column separators (~white @ 9%)

    // MARK: Text
    static let textPrimary   = Color(hex: 0xEAEAEA) // names, big numbers, titles
    static let textSecondary = Color(hex: 0x9B9B9B) // column headers, property labels
    static let textTertiary  = Color(hex: 0x6E6E6E) // placeholders, "+ New page", empty

    // MARK: Accent
    static let accent        = Color(hex: 0x2383E2) // New / + button, active tab
    static let accentPressed = Color(hex: 0x1B6FC4)

    // MARK: Calm dashboard (UI/Required aesthetic)
    /// Slightly warmer raised card used on the dashboard for a premium, calm feel.
    static let cardRaised    = Color(hex: 0x232323)
    static let cardStroke    = Color.white.opacity(0.06)
}

// MARK: - Tag pill palette (Notion's 9 muted dark colors)

enum TagColor: String, CaseIterable, Hashable {
    case gray, brown, orange, yellow, green, blue, purple, pink, red

    /// Soft background used by the default pill style.
    var bg: Color {
        switch self {
        case .gray:   return Color(hex: 0x373737)
        case .brown:  return Color(hex: 0x4A3B2A)
        case .orange: return Color(hex: 0x4A3521)
        case .yellow: return Color(hex: 0x453F21)
        case .green:  return Color(hex: 0x2B3D2F)
        case .blue:   return Color(hex: 0x28374D)
        case .purple: return Color(hex: 0x3D2F4D)
        case .pink:   return Color(hex: 0x4A2F3D)
        case .red:    return Color(hex: 0x4D2F2F)
        }
    }

    /// Foreground text color for the soft style.
    var fg: Color {
        switch self {
        case .gray:   return Color(hex: 0xD4D4D4)
        case .brown:  return Color(hex: 0xC8A882)
        case .orange: return Color(hex: 0xD9A066)
        case .yellow: return Color(hex: 0xD6C158)
        case .green:  return Color(hex: 0x7DB38A)
        case .blue:   return Color(hex: 0x6E9FE0)
        case .purple: return Color(hex: 0xB090D0)
        case .pink:   return Color(hex: 0xC88AA8)
        case .red:    return Color(hex: 0xD08A8A)
        }
    }

    /// Vivid color used for the `.filled` (solid) style.
    var solid: Color { fg.opacity(0.9) }
}

// MARK: - Ring colors (Apple-Fitness-vivid, one place to reassign macros)

enum RingColor: String, CaseIterable, Hashable {
    case carb, protein, fibre

    var gradient: LinearGradient {
        LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
    }

    var stops: [Color] {
        switch self {
        case .carb:    return [Color(hex: 0xF0463A), Color(hex: 0xFF7A6B)]
        case .protein: return [Color(hex: 0xA6E22E), Color(hex: 0x7BD84A)]
        case .fibre:   return [Color(hex: 0x3AD1F0), Color(hex: 0x5AC8E0)]
        }
    }

    var base: Color { stops.first ?? .white }

    var label: String {
        switch self {
        case .carb: return "Carb"
        case .protein: return "Protein"
        case .fibre: return "Fibre"
        }
    }
}

// MARK: - Color hex helper

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
