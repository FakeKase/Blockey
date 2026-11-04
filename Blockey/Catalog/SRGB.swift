import Foundation

/// An sRGB colour, channels 0...1 (gamma-encoded, as in a hex string). Pure data: no SwiftUI, so
/// the derivation and the floors can be tested without a view. See ADR 005, "Amendment: palette +
/// custom colour".
struct SRGB: Hashable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    /// From a packed `0xRRGGBB` literal. Used for the palette data so it needs no parse that could
    /// fail (and so no force unwrap).
    init(rgb: UInt32) {
        self.r = Double((rgb >> 16) & 0xFF) / 255
        self.g = Double((rgb >> 8) & 0xFF) / 255
        self.b = Double(rgb & 0xFF) / 255
    }

    /// Exactly `#` plus six hex digits, either case. No short form, no alpha, no missing `#`, no
    /// whitespace: the same grammar as `CategoryCatalog.canonicalHex`, because a stored value must
    /// mean the same thing to both (the backup format depends on it).
    init?(hex: String) {
        let scalars = Array(hex.unicodeScalars)
        guard scalars.count == 7, scalars[0] == "#" else { return nil }
        var value: UInt32 = 0
        for s in scalars.dropFirst() {
            guard s.isASCII, let digit = Character(s).hexDigitValue else { return nil }
            value = value << 4 | UInt32(digit)
        }
        self.init(rgb: value)
    }

    /// Canonical `#RRGGBB`, always uppercase. Channels are clamped and rounded to 8 bits, which is
    /// what the stored format can hold.
    var hex: String {
        String(format: "#%02X%02X%02X", Self.byte(r), Self.byte(g), Self.byte(b))
    }

    static func byte(_ v: Double) -> Int {
        guard v.isFinite else { return 0 }
        // Clamp as a Double first: `Int(_:)` traps on a finite value too large for Int (1e300 * 255
        // is finite, 1e308 * 255 is infinite), so clamping the Int afterwards is too late.
        return Int((Swift.min(1, Swift.max(0, v)) * 255).rounded())
    }

    static let black = SRGB(r: 0, g: 0, b: 0)
    static let white = SRGB(r: 1, g: 1, b: 1)
}

/// What one category looks like in one appearance. All four are opaque (the old chips used alpha,
/// which let hour rules show through; design review M9).
struct CategoryColorRecord: Hashable, Sendable {
    /// The full category colour: the chip's leading bar, the glyph.
    var spine: SRGB
    /// The chip body.
    var fill: SRGB
    /// The chip outline.
    var border: SRGB
    /// Ink for text drawn on `fill`: black in light, white in dark.
    var onFill: SRGB
}

struct CategoryColors: Hashable, Sendable {
    var light: CategoryColorRecord
    var dark: CategoryColorRecord

    func record(isDark: Bool) -> CategoryColorRecord { isDark ? dark : light }
}
