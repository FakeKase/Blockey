import SwiftUI

/// The kind of work a block represents.
///
/// Deliberately a fixed enum rather than a user-editable SwiftData model.
/// Categories are identified by their raw slug, which is what travels inside a
/// block's token, so colours survive anything that happens to local storage —
/// there is no colour table to lose. Six buckets is enough to read a day at a
/// glance; more would just be a settings screen nobody opens.
enum BlockCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case deepWork = "deep"
    case meeting
    case admin
    case personal
    case health
    case rest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepWork: return "Deep work"
        case .meeting:  return "Meeting"
        case .admin:    return "Admin"
        case .personal: return "Personal"
        case .health:   return "Health"
        case .rest:     return "Rest"
        }
    }

    /// The category's face throughout the app.
    ///
    /// An emoji rather than an SF Symbol, for two reasons. Six categories
    /// cannot be told apart by hue alone — under deuteranopia the closest pair
    /// stays below the threshold of noticing however the palette is tuned — and
    /// an emoji brings its own colour and silhouette, so it distinguishes a
    /// block where a monochrome tinted glyph only repeats the tint. It also
    /// reads as friendlier, which is the point of a day you plan every morning.
    var emoji: String {
        switch self {
        case .deepWork: return "\u{1F9E0}"       // brain
        case .meeting:  return "\u{1F465}"       // busts in silhouette
        case .admin:    return "\u{1F5C2}\u{FE0F}" // card index dividers
        case .personal: return "\u{1F3E1}"       // house with garden
        case .health:   return "\u{1F3C3}"       // runner
        case .rest:     return "\u{2615}"        // hot beverage
        }
    }

    /// What to draw where emoji are unavailable. See `Emoji.isSupported`.
    var symbolName: String {
        switch self {
        case .deepWork: return "brain.head.profile"
        case .meeting:  return "person.2.fill"
        case .admin:    return "tray.full.fill"
        case .personal: return "house.fill"
        case .health:   return "figure.run"
        case .rest:     return "cup.and.saucer.fill"
        }
    }

    /// Title with its emoji, for pickers and list rows.
    var labelled: String { Emoji.prefixed(emoji, title) }

    /// Light and dark variants. The dark values are lifted rather than reused:
    /// the same tint that reads well on white sits at barely 1.2:1 on black, at
    /// which point a block is a rumour rather than a rectangle.
    private var components: (light: (Double, Double, Double), dark: (Double, Double, Double)) {
        switch self {
        case .deepWork: return ((0.29, 0.40, 0.87), (0.52, 0.62, 1.00))
        case .meeting:  return ((0.85, 0.42, 0.24), (1.00, 0.62, 0.42))
        case .admin:    return ((0.40, 0.44, 0.54), (0.66, 0.71, 0.82))
        case .personal: return ((0.24, 0.60, 0.36), (0.44, 0.83, 0.56))
        case .health:   return ((0.83, 0.33, 0.51), (1.00, 0.55, 0.71))
        case .rest:     return ((0.52, 0.44, 0.72), (0.74, 0.66, 0.95))
        }
    }

    var tint: Color {
        let (light, dark) = components
        return Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    static let fallback: BlockCategory = .deepWork
}
