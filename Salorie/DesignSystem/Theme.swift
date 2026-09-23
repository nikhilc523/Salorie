import SwiftUI

/// Salorie color tokens — Notion dark palette (v1 is dark-only).
/// All values pulled from the reference screenshots in `/UI`.
enum Theme {

    // MARK: Surfaces — pure black + neutral elevated panels (sampled from SiriAI/ references)
    static let bg            = Color(hex: 0x000000) // page background — pure black (non-negotiable)
    static let surface       = Color(hex: 0x1E1E1E) // cards, board columns, metric cards
    static let surfaceRaised = Color(hex: 0x262626) // selected/hover row, popovers
    static let divider       = Color(hex: 0x2C2C2C) // table lines, column separators

    // MARK: Text — neutral off-white
    static let textPrimary   = Color(hex: 0xEDEDED) // names, big numbers, titles
    static let textSecondary = Color(hex: 0x9B9B9B) // column headers, property labels
    static let textTertiary  = Color(hex: 0x6A6A6A) // placeholders, "+ New page", empty

    // MARK: Accent
    static let accent        = Color(hex: 0x2383E2) // New / + button, active tab (Notion blue)
    static let accentPressed = Color(hex: 0x1B6FC4)

    // MARK: Calm dashboard
    /// Raised card, subtly elevated above pure black (SiriAI panel tone).
    static let cardRaised    = Color(hex: 0x161616)
    static let cardStroke    = Color.white.opacity(0.055)

    /// Oatmeal tone (invismile --oatmeal) for the Fat macro — no rogue values in views.
    static let macroFatStops: [Color] = [Color(hex: 0xE3D9C6), Color(hex: 0xE3D9C6)]
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

// MARK: - Ring colors
// EXACT ring colors from the invismile-website source (styles.css CSS variables), which drive
// the reference rings in UI/Required. Three distinct solid strokes, outer→inner:
//   --oatmeal #E3D9C6 (Wear)  --caramel #D1A67A (Streak)  --terracotta #B3664C (Life)
// Mapped Calories = oatmeal, Protein = caramel, Carbs = terracotta.

enum RingColor: String, CaseIterable, Hashable {
    case calories, protein, carb, fibre

    var gradient: LinearGradient {
        LinearGradient(colors: stops, startPoint: .top, endPoint: .bottom)
    }

    /// Solid exact hex (website uses flat strokes). Duplicated so gradient == solid color.
    var stops: [Color] {
        switch self {
        case .calories: return [Color(hex: 0xE3D9C6), Color(hex: 0xE3D9C6)] // oatmeal
        case .protein:  return [Color(hex: 0xD1A67A), Color(hex: 0xD1A67A)] // caramel
        case .carb:     return [Color(hex: 0xB3664C), Color(hex: 0xB3664C)] // terracotta
        case .fibre:    return [Color(hex: 0xD1A67A), Color(hex: 0xD1A67A)] // caramel
        }
    }

    var base: Color { stops.first ?? .white }

    /// Solid tone used for legend dots / progress bars — matches the ring, no clash.
    var tint: Color { stops.last ?? base }

    var label: String {
        switch self {
        case .calories: return "Calories"
        case .protein:  return "Protein"
        case .carb:     return "Carbs"
        case .fibre:    return "Fibre"
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
