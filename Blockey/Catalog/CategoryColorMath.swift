import Foundation

/// An OKLCH colour: lightness 0...1, chroma (about 0...0.4), hue in degrees 0..<360.
struct OKLCH: Hashable, Sendable {
    var l: Double
    var c: Double
    var h: Double
}

/// CIELAB, D65.
struct Lab: Hashable, Sendable {
    var l: Double
    var a: Double
    var b: Double
    var chroma: Double { (a * a + b * b).squareRoot() }
}

/// Colour measurement and conversion. Pure Foundation.
///
/// Contrast and ΔE76 follow `docs/design-review.md` (M9, M10) and `docs/category-palette.md`
/// section 3.1 formula for formula, so a number here is comparable with every number in the docs.
/// OKLCH is for derivation only (it holds hue steady while lightness moves); measurement stays in
/// CIELAB on purpose.
enum CategoryColorMath {

    // MARK: sRGB transfer

    static func linearize(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    static func encode(_ v: Double) -> Double {
        v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    // MARK: WCAG 2

    static func relativeLuminance(_ c: SRGB) -> Double {
        0.2126 * linearize(c.r) + 0.7152 * linearize(c.g) + 0.0722 * linearize(c.b)
    }

    /// `(Y_lighter + 0.05) / (Y_darker + 0.05)`; 1...21 and symmetric.
    static func contrastRatio(_ a: SRGB, _ b: SRGB) -> Double {
        let ya = relativeLuminance(a), yb = relativeLuminance(b)
        return (Swift.max(ya, yb) + 0.05) / (Swift.min(ya, yb) + 0.05)
    }

    // MARK: CIELAB, D65

    // The coefficients are the ones the palette document used, not the four-digit variants some
    // libraries carry, so the pinned numbers agree.
    private static let whiteX = 0.95047, whiteZ = 1.08883

    static func lab(_ c: SRGB) -> Lab {
        let r = linearize(c.r), g = linearize(c.g), b = linearize(c.b)
        let x = 0.4124 * r + 0.3576 * g + 0.1805 * b
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = 0.0193 * r + 0.1192 * g + 0.9505 * b
        func f(_ t: Double) -> Double {
            // Linear toe below the CIE threshold, so near-black never takes a cube root of ~0.
            t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116.0
        }
        let fx = f(x / whiteX), fy = f(y), fz = f(z / whiteZ)
        return Lab(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }

    static func deltaE76(_ a: SRGB, _ b: SRGB) -> Double {
        let p = lab(a), q = lab(b)
        let dl = p.l - q.l, da = p.a - q.a, db = p.b - q.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    // MARK: OKLab / OKLCH (Ottosson)

    static func oklch(_ c: SRGB) -> OKLCH {
        let r = linearize(c.r), g = linearize(c.g), b = linearize(c.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let bigL = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let chroma = (a * a + bb * bb).squareRoot()
        var hue = atan2(bb, a) * 180 / .pi
        if hue < 0 { hue += 360 }
        return OKLCH(l: bigL, c: chroma, h: chroma < 1e-9 ? 0 : hue)
    }

    /// Linear-light sRGB for an OKLCH colour. Not clamped: channels outside 0...1 mean the colour
    /// is outside the sRGB gamut, which is what `isInGamut` asks.
    static func linearRGB(_ k: OKLCH) -> (r: Double, g: Double, b: Double) {
        let hr = k.h * .pi / 180
        let a = k.c * cos(hr), b = k.c * sin(hr)
        let l = pow(k.l + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(k.l - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(k.l - 0.0894841775 * a - 1.2914855480 * b, 3)
        return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    private static let gamutSlack = 1e-6

    static func isInGamut(_ k: OKLCH) -> Bool {
        let c = linearRGB(k)
        return [c.r, c.g, c.b].allSatisfy { $0 >= -gamutSlack && $0 <= 1 + gamutSlack }
    }

    /// The colour with the same lightness and hue and the largest chroma that is at most `k.c` and
    /// inside sRGB. Chroma is the only thing reduced, so hue and lightness are not disturbed
    /// (clipping channels would shift both). Fixed-iteration bisection: deterministic.
    static func gamutMapped(_ k: OKLCH) -> OKLCH {
        var k = k
        k.c = Swift.max(0, k.c)
        if isInGamut(k) { return k }
        var lo = 0.0, hi = k.c
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if isInGamut(OKLCH(l: k.l, c: mid, h: k.h)) { lo = mid } else { hi = mid }
        }
        k.c = lo
        return k
    }

    /// Gamut-mapped, encoded, and clamped to the last rounding error, so every channel is 0...1.
    static func srgb(_ k: OKLCH) -> SRGB {
        let c = linearRGB(gamutMapped(k))
        func ch(_ v: Double) -> Double { Swift.min(1, Swift.max(0, encode(Swift.min(1, Swift.max(0, v))))) }
        return SRGB(r: ch(c.r), g: ch(c.g), b: ch(c.b))
    }

    // MARK: Compositing

    /// `fg` at `alpha` over an opaque `bg`, in gamma-encoded sRGB space (how the system blends a
    /// translucent view), not linear light.
    static func composite(_ fg: SRGB, alpha: Double, over bg: SRGB) -> SRGB {
        let a = Swift.min(1, Swift.max(0, alpha))
        return SRGB(r: fg.r * a + bg.r * (1 - a), g: fg.g * a + bg.g * (1 - a), b: fg.b * a + bg.b * (1 - a))
    }
}
