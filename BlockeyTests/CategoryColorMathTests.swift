import Testing
import Foundation
@testable import Blockey

@Suite("CategoryColorMath")
struct CategoryColorMathTests {
    private typealias M = CategoryColorMath

    @Test func contrastRatioMatchesWcagReferencePairs() {
        #expect(abs(M.contrastRatio(.black, .white) - 21) < 1e-9)
        #expect(abs(M.contrastRatio(.white, .white) - 1) < 1e-9)
        // Symmetric.
        let a = SRGB(rgb: 0x4664DC), b = SRGB(rgb: 0xFAF8F5)
        #expect(M.contrastRatio(a, b) == M.contrastRatio(b, a))
        // The palette document's Blue spine on the light canvas: 4.81.
        #expect(abs(M.contrastRatio(a, b) - 4.81) < 0.02)
        // #777777 on white is the classic 4.48:1 just-fails-AA pair.
        #expect(abs(M.contrastRatio(SRGB(rgb: 0x777777), .white) - 4.48) < 0.01)
    }

    @Test func labMatchesReferenceValues() {
        let white = M.lab(.white), black = M.lab(.black)
        #expect(abs(white.l - 100) < 0.01 && abs(white.a) < 0.05 && abs(white.b) < 0.05)
        #expect(abs(black.l) < 0.01)
        // sRGB red in CIELAB D65: (53.24, 80.09, 67.20).
        let red = M.lab(SRGB(rgb: 0xFF0000))
        #expect(abs(red.l - 53.24) < 0.1 && abs(red.a - 80.09) < 0.2 && abs(red.b - 67.20) < 0.2)
        // Worked example in docs/category-palette.md 3.1: Orange fill #FAC8A0.
        let orange = M.lab(SRGB(rgb: 0xFAC8A0))
        #expect(abs(orange.l - 84.06) < 0.1 && abs(orange.a - 12.43) < 0.2 && abs(orange.b - 26.76) < 0.2)
    }

    @Test func deltaE76MatchesPinnedReferenceValue() {
        #expect(abs(M.deltaE76(.black, .white) - 100) < 0.01)
        #expect(M.deltaE76(.white, .white) == 0)
        // Teal and Sky light fills: the palette's weakest pair, 11.6 in the document.
        #expect(abs(M.deltaE76(SRGB(rgb: 0xA0DCE6), SRGB(rgb: 0xAADCFA)) - 11.6) < 0.5)
        let a = SRGB(rgb: 0x123456), b = SRGB(rgb: 0xFEDCBA)
        #expect(M.deltaE76(a, b) == M.deltaE76(b, a))
    }

    @Test func oklchMatchesReferenceValues() {
        let white = M.oklch(.white)
        #expect(abs(white.l - 1) < 1e-4 && white.c < 1e-4)
        // Ottosson's reference for sRGB red: L 0.6280, C 0.2577, h 29.23.
        let red = M.oklch(SRGB(rgb: 0xFF0000))
        #expect(abs(red.l - 0.6280) < 1e-3 && abs(red.c - 0.2577) < 1e-3 && abs(red.h - 29.23) < 0.05)
    }

    @Test func transferFunctionMatchesPublishedValues() {
        // IEC 61966-2-1: the toe ends at 0.04045 (linear 0.0031308), and mid-grey 0.5 is 0.21404.
        #expect(abs(M.linearize(0.5) - 0.214041) < 1e-5)
        #expect(abs(M.linearize(0.04045) - 0.0031308) < 1e-6)
        #expect(M.linearize(0) == 0 && abs(M.linearize(1) - 1) < 1e-12)
        #expect(abs(M.encode(0.214041) - 0.5) < 1e-5)
        for v in stride(from: 0.0, through: 1.0, by: 0.01) { #expect(abs(M.encode(M.linearize(v)) - v) < 1e-9) }
    }

    @Test func relativeLuminanceMatchesWcagPrimaries() {
        #expect(abs(M.relativeLuminance(SRGB(rgb: 0xFF0000)) - 0.2126) < 1e-9)
        #expect(abs(M.relativeLuminance(SRGB(rgb: 0x00FF00)) - 0.7152) < 1e-9)
        #expect(abs(M.relativeLuminance(SRGB(rgb: 0x0000FF)) - 0.0722) < 1e-9)
        #expect(M.relativeLuminance(.black) == 0 && abs(M.relativeLuminance(.white) - 1) < 1e-9)
    }

    @Test func labMatchesReferencePrimariesGreenAndBlue() {
        // Standard sRGB D65 values: green (87.73, -86.18, 83.18), blue (32.30, 79.19, -107.86).
        let g = M.lab(SRGB(rgb: 0x00FF00)), b = M.lab(SRGB(rgb: 0x0000FF))
        #expect(abs(g.l - 87.73) < 0.1 && abs(g.a + 86.18) < 0.4 && abs(g.b - 83.18) < 0.4)
        #expect(abs(b.l - 32.30) < 0.1 && abs(b.a - 79.19) < 0.4 && abs(b.b + 107.86) < 0.4)
    }

    @Test func oklabMatchesOttossonsPublishedPairs() {
        // From the OKLab post: white (1, 0, 0), red (0.628, 0.2249, 0.1258),
        // green (0.8664, -0.2339, 0.1795), blue (0.4520, -0.0325, -0.3115).
        func lab(_ k: OKLCH) -> (Double, Double, Double) {
            (k.l, k.c * cos(k.h * .pi / 180), k.c * sin(k.h * .pi / 180))
        }
        let want: [(UInt32, Double, Double, Double)] = [
            (0xFFFFFF, 1, 0, 0), (0xFF0000, 0.6280, 0.2249, 0.1258),
            (0x00FF00, 0.8664, -0.2339, 0.1795), (0x0000FF, 0.4520, -0.0325, -0.3115)]
        for (rgb, l, a, b) in want {
            let got = lab(M.oklch(SRGB(rgb: rgb)))
            #expect(abs(got.0 - l) < 5e-4 && abs(got.1 - a) < 5e-4 && abs(got.2 - b) < 5e-4, "\(rgb)")
        }
        // Black has no chroma and a defined hue (0), not NaN.
        let k = M.oklch(.black)
        #expect(k.l == 0 && k.c == 0 && k.h == 0)
    }

    @Test func oklchToLinearRGBInvertsTheReferencePairs() {
        // Forward direction from published OKLab red: linear (1, 0, 0).
        let red = M.linearRGB(OKLCH(l: 0.6280, c: (0.2249 * 0.2249 + 0.1258 * 0.1258).squareRoot(),
                                    h: atan2(0.1258, 0.2249) * 180 / .pi))
        #expect(abs(red.r - 1) < 2e-3 && abs(red.g) < 2e-3 && abs(red.b) < 2e-3)
        let white = M.linearRGB(OKLCH(l: 1, c: 0, h: 0))
        #expect(abs(white.r - 1) < 1e-4 && abs(white.g - 1) < 1e-4 && abs(white.b - 1) < 1e-4)
    }

    @Test func hostileInputsNeverTrapOrEscapeTheByteRange() {
        let bad: [OKLCH] = [
            OKLCH(l: .nan, c: 0.1, h: 10), OKLCH(l: 0.5, c: .nan, h: 10), OKLCH(l: 0.5, c: 0.1, h: .nan),
            OKLCH(l: .infinity, c: 0.1, h: 10), OKLCH(l: 0.5, c: .infinity, h: 10),
            OKLCH(l: -3, c: 0.1, h: 10), OKLCH(l: 7, c: 0.1, h: 10), OKLCH(l: 0.5, c: -0.4, h: 10),
            OKLCH(l: 0.5, c: 5, h: 1e9), OKLCH(l: 0.5, c: 0.1, h: -720)]
        for k in bad {
            let out = M.srgb(k)
            for v in [out.r, out.g, out.b] { #expect(v.isFinite && v >= 0 && v <= 1, "\(k)") }
            #expect(SRGB.byte(out.r) >= 0)
        }
        // NaN or negative channels into the measurements must not trap.
        _ = M.oklch(SRGB(r: .nan, g: -1, b: 2))
        _ = M.lab(SRGB(r: -1, g: -1, b: -1))
        #expect(M.gamutMapped(OKLCH(l: 0.5, c: -1, h: 0)).c == 0)
    }

    @Test func oklchRoundTripsInGamutColors() {
        var checked = 0
        for r in stride(from: 0, through: 255, by: 15) {
            for g in stride(from: 0, through: 255, by: 15) {
                for b in stride(from: 0, through: 255, by: 15) {
                    let c = SRGB(rgb: UInt32(r << 16 | g << 8 | b))
                    let back = M.srgb(M.oklch(c))
                    #expect(abs(back.r - c.r) < 2e-3 && abs(back.g - c.g) < 2e-3 && abs(back.b - c.b) < 2e-3,
                            "\(c.hex) came back \(back.hex)")
                    checked += 1
                }
            }
        }
        #expect(checked == 18 * 18 * 18)
    }

    @Test func gamutMappingKeepsLightnessAndHue() {
        // Far outside sRGB at every hue; only chroma may move.
        for h in stride(from: 0.0, to: 360, by: 10) {
            let wild = OKLCH(l: 0.6, c: 0.4, h: h)
            let mapped = M.gamutMapped(wild)
            #expect(M.isInGamut(mapped))
            #expect(mapped.l == wild.l && mapped.h == wild.h)
            #expect(mapped.c < wild.c && mapped.c > 0)
            // And it is the largest chroma that fits, to bisection precision.
            #expect(!M.isInGamut(OKLCH(l: wild.l, c: mapped.c + 1e-6, h: wild.h)) || mapped.c > 0.39)
        }
        // Already in gamut: untouched.
        let calm = OKLCH(l: 0.6, c: 0.05, h: 120)
        #expect(M.gamutMapped(calm) == calm)
    }

    @Test func srgbOutputNeverLeavesRange() {
        for l in stride(from: 0.0, through: 1.0, by: 0.05) {
            for h in stride(from: 0.0, to: 360, by: 30) {
                for c in [0.0, 0.1, 0.3, 0.6] {
                    let out = M.srgb(OKLCH(l: l, c: c, h: h))
                    for v in [out.r, out.g, out.b] { #expect(v >= 0 && v <= 1 && v.isFinite) }
                }
            }
        }
    }

    @Test func compositeMatchesTheDocumentedMeetingFills() {
        // Black 5 percent over #FAF8F5 and white 6 percent over #1C1C1E. The document rounded the
        // half-byte case (237.5) up; exact arithmetic gives 237. One byte of slack, no more.
        let s = ColorSurfaces.assumedPendingStory1
        for (fg, a, bg, want) in [(SRGB.black, 0.05, s.light.canvas, s.light.meetingFill),
                                  (SRGB.white, 0.06, s.dark.canvas, s.dark.meetingFill)] {
            let got = M.composite(fg, alpha: a, over: bg)
            #expect(abs(got.r - want.r) <= 1.0 / 255 + 1e-9 && abs(got.g - want.g) <= 1.0 / 255 + 1e-9
                    && abs(got.b - want.b) <= 1.0 / 255 + 1e-9, "\(got.hex) vs \(want.hex)")
        }
        #expect(M.composite(.white, alpha: 0, over: SRGB(rgb: 0x123456)).hex == "#123456")
        #expect(M.composite(.white, alpha: 1, over: SRGB(rgb: 0x123456)).hex == "#FFFFFF")
    }
}
