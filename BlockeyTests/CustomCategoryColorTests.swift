import Testing
import Foundation
@testable import Blockey

/// Plan Appendix A.4b, derive and assess (tasks 3.3b, 3.4b).
@Suite("CustomCategoryColor")
struct CustomCategoryColorTests {
    private typealias M = CategoryColorMath
    private let surfaces = ColorSurfaces.assumedPendingStory1
    private let targets = DerivationTargets.measured

    private func pick(h: Double, c: Double, l: Double = 0.6) -> SRGB { M.srgb(OKLCH(l: l, c: c, h: h)) }

    // MARK: derive

    @Test func deriveIsDeterministic() {
        let p = SRGB(rgb: 0x3A7BD5)
        #expect(CustomCategoryColor.derive(from: p) == CustomCategoryColor.derive(from: p))
    }

    @Test func deriveKeepsTheModesInkForOnFill() {
        let c = CustomCategoryColor.derive(from: SRGB(rgb: 0x3A7BD5))
        #expect(c.light.onFill == .black && c.dark.onFill == .white)
    }

    @Test func deriveIgnoresThePicksLightness() {
        // Same hue and chroma, very different lightness: the same result, because lightness comes
        // from the targets. This is the whole point of the amendment (M10).
        let dark = CustomCategoryColor.derive(from: pick(h: 250, c: 0.12, l: 0.35))
        let light = CustomCategoryColor.derive(from: pick(h: 250, c: 0.12, l: 0.85))
        for isDark in [false, true] {
            let a = M.oklch(dark.record(isDark: isDark).fill), b = M.oklch(light.record(isDark: isDark).fill)
            #expect(abs(a.l - b.l) < 0.01 && abs(a.h - b.h) < 3)
        }
    }

    /// Every 5 degrees of hue, chroma from "barely coloured" to out of gamut, picks of mixed
    /// lightness. Result recorded in docs/category-palette.md: no pick with chroma above the grey
    /// threshold ever raised lowContrast, so DerivationTargets.measured needed no adjustment.
    @Test func derivedRecordsMeetContrastFloorsAcrossHueSweep() {
        var derived = 0
        for chromaStep in 0...40 {
            let chroma = 0.02 + Double(chromaStep) * 0.01
            for hueStep in 0..<72 {
                let p = pick(h: Double(hueStep) * 5, c: chroma, l: 0.3 + Double((chromaStep + hueStep) % 7) * 0.09)
                let colors = CustomCategoryColor.derive(from: p)
                derived += 1
                for isDark in [false, true] {
                    let r = colors.record(isDark: isDark), m = surfaces.mode(isDark: isDark)
                    let tag = "pick \(p.hex) \(isDark ? "dark" : "light")"
                    #expect(M.contrastRatio(r.spine, m.canvas) >= ColorFloors.spineOnCanvas, "spine \(tag)")
                    #expect(M.contrastRatio(r.border, m.canvas) >= ColorFloors.borderOnCanvas, "border \(tag)")
                    #expect(M.deltaE76(r.fill, m.canvas) >= ColorFloors.fillFromCanvasDeltaE, "fill dE \(tag)")
                    #expect(M.contrastRatio(r.fill, m.canvas) >= ColorFloors.fillOnCanvasRatio, "fill ratio \(tag)")
                    #expect(M.contrastRatio(r.onFill, r.fill) >= ColorFloors.onFillOnFill, "onFill \(tag)")
                }
                // The contract: flagged or fine, never silently low contrast.
                #expect(!CustomCategoryColor.assess(colors, surfaces: surfaces).contains { $0.kind == .lowContrast },
                        "\(p.hex)")
            }
        }
        #expect(derived == 41 * 72)
    }

    @Test func derivedColoursNeverLeaveTheByteRangeAndStayHexSafe() {
        for chroma in [0.0, 0.05, 0.2, 0.4, 1.0] {
            for h in stride(from: 0.0, to: 360, by: 15) {
                let colors = CustomCategoryColor.derive(from: pick(h: h, c: chroma))
                for isDark in [false, true] {
                    let r = colors.record(isDark: isDark)
                    for c in [r.spine, r.fill, r.border, r.onFill] {
                        for v in [c.r, c.g, c.b] { #expect(v >= 0 && v <= 1 && v.isFinite) }
                        #expect(SRGB(hex: c.hex) != nil)
                    }
                }
            }
        }
    }

    /// Tolerance (measured 2026-11-04 against all twelve records, deriving from each light spine):
    /// the light spine is the input, so it must come back within OKLCH hue 1 degree, lightness 0.07
    /// and CIE76 dE 8. Everything else was hand-authored in RGB and drifts: across all roles and
    /// modes the largest hue error was 21 degrees, lightness 0.075, chroma 0.059. The bounds below
    /// are those maxima with a little headroom. A derived colour is "near" its curated neighbour,
    /// not equal to it, which is what the editor's two-mode preview is for.
    @Test func deriveFromCuratedSpineLandsNearCuratedRecord() {
        for s in CategoryPalette.swatches {
            let d = CustomCategoryColor.derive(from: s.colors.light.spine)
            let lightSpine = M.oklch(d.light.spine), want = M.oklch(s.colors.light.spine)
            #expect(abs(lightSpine.h - want.h) < 1, "\(s.name) hue")
            #expect(abs(lightSpine.l - want.l) < 0.07, "\(s.name) L")
            #expect(M.deltaE76(d.light.spine, s.colors.light.spine) < 8, "\(s.name) light spine dE")
            for isDark in [false, true] {
                let got = d.record(isDark: isDark), rec = s.colors.record(isDark: isDark)
                for (role, a, b) in [("spine", got.spine, rec.spine), ("fill", got.fill, rec.fill),
                                     ("border", got.border, rec.border)] {
                    let p = M.oklch(a), q = M.oklch(b)
                    var dh = abs(p.h - q.h); if dh > 180 { dh = 360 - dh }
                    let tag = "\(s.name) \(isDark ? "dark" : "light") \(role)"
                    #expect(dh < 25, "hue \(tag)")
                    #expect(abs(p.l - q.l) < 0.09, "L \(tag)")
                    #expect(abs(p.c - q.c) < 0.07, "C \(tag)")
                }
            }
        }
    }

    @Test func greyPickDerivesToGreysWithoutCrashing() {
        for grey in [SRGB.black, SRGB.white, SRGB(rgb: 0x808080), SRGB(rgb: 0x777777), SRGB(rgb: 0x8A8B8A)] {
            #expect(CustomCategoryColor.isGrey(grey))
            let d = CustomCategoryColor.derive(from: grey)
            for isDark in [false, true] {
                let r = d.record(isDark: isDark)
                for c in [r.spine, r.fill, r.border] {
                    // Greys stay grey: no channel is more than a rounding step from the others.
                    #expect(abs(c.r - c.g) < 0.01 && abs(c.g - c.b) < 0.01, "\(grey.hex) -> \(c.hex)")
                }
            }
        }
        #expect(!CustomCategoryColor.isGrey(SRGB(rgb: 0x4664DC)))
    }

    @Test func outOfGamutPickIsMappedNotClipped() {
        // An extreme saturated colour at each hue: derived lightness and hue must hold even where
        // the target chroma would not fit sRGB (clipping would shift both).
        for h in stride(from: 0.0, to: 360, by: 15) {
            let extreme = M.srgb(OKLCH(l: 0.7, c: 5, h: h))   // as saturated as sRGB allows
            let d = CustomCategoryColor.derive(from: extreme)
            let p = M.oklch(extreme)
            for (t, c) in [(targets.light.spine, d.light.spine), (targets.dark.spine, d.dark.spine),
                           (targets.light.fill, d.light.fill), (targets.dark.fill, d.dark.fill)] {
                let k = M.oklch(c)
                #expect(abs(k.l - t.lightness) < 0.02, "L at hue \(h)")
                var dh = abs(k.h - p.h); if dh > 180 { dh = 360 - dh }
                #expect(dh < 6, "hue at hue \(h): \(dh)")
            }
        }
    }

    // MARK: assess

    @Test func greyPickWarnsLooksLikeMeeting() {
        let concerns = CustomCategoryColor.assess(CustomCategoryColor.derive(from: SRGB(rgb: 0x808080)),
                                                  surfaces: surfaces)
        #expect(concerns.contains(ColorConcern(kind: .looksLikeMeeting, isDark: false)))
        #expect(concerns.contains(ColorConcern(kind: .looksLikeMeeting, isDark: true)))
    }

    @Test func chromaGapFlagsPalePicksThatStillClearDeltaE() {
        // Pick chroma 0.07: the derived light fill (0.45 * 0.07 = 0.032) is under the 0.040 gap.
        let pale = DerivedFromHueChroma.derive(h: 250, c: 0.07)
        #expect(CustomCategoryColor.assess(pale, surfaces: surfaces).contains { $0.kind == .looksLikeMeeting })
        // Pick chroma 0.12 is comfortably past it.
        let vivid = DerivedFromHueChroma.derive(h: 250, c: 0.12)
        #expect(!CustomCategoryColor.assess(vivid, surfaces: surfaces).contains { $0.kind == .looksLikeMeeting })
        // And the flip happens near the documented 0.09 (0.45 * 0.09 = 0.040).
        var flipped: Double?
        for step in 0...40 {
            let c = 0.05 + Double(step) * 0.002
            let hit = CustomCategoryColor.assess(DerivedFromHueChroma.derive(h: 250, c: c), surfaces: surfaces)
                .contains { $0.kind == .looksLikeMeeting }
            if !hit { flipped = c; break }
        }
        #expect(flipped != nil && abs((flipped ?? 0) - 0.09) < 0.015)
    }

    @Test func pickNearActiveCategoryWarnsWithItsSlug() {
        let blue = CategoryPalette.colors(at: 0)
        let nearBlue = CustomCategoryColor.derive(from: blue.light.spine)
        let concerns = CustomCategoryColor.assess(
            nearBlue, surfaces: surfaces,
            others: [(slug: "deep", colors: blue), (slug: "meeting", colors: CategoryPalette.colors(at: 1))])
        #expect(concerns.contains { $0.kind == .closeTo(slug: "deep") })
        #expect(!concerns.contains { $0.kind == .closeTo(slug: "meeting") })
    }

    @Test func assessReportsEachModeSeparately() {
        // Light fill identical to Blue's, dark fill far from it: only light is close.
        let blue = CategoryPalette.colors(at: 0)
        var c = CategoryPalette.colors(at: 1)
        c.light.fill = blue.light.fill
        let concerns = CustomCategoryColor.assess(c, surfaces: surfaces, others: [(slug: "deep", colors: blue)])
        #expect(concerns.contains(ColorConcern(kind: .closeTo(slug: "deep"), isDark: false)))
        #expect(!concerns.contains(ColorConcern(kind: .closeTo(slug: "deep"), isDark: true)))
    }

    @Test func concernsAreOrderedWorstFirst() {
        // A colour that is low contrast, meeting-like and close to another at once.
        let blue = CategoryPalette.colors(at: 0)
        var c = blue
        c.light.fill = surfaces.light.meetingFill
        c.light.onFill = surfaces.light.meetingFill        // unreadable ink
        let kinds = CustomCategoryColor.assess(c, surfaces: surfaces, others: [(slug: "deep", colors: blue)])
            .map(\.kind)
        let lowIndex = kinds.firstIndex(of: .lowContrast)
        let meetingIndex = kinds.firstIndex(of: .looksLikeMeeting)
        let closeIndex = kinds.firstIndex(of: .closeTo(slug: "deep"))
        #expect(lowIndex != nil && meetingIndex != nil)
        #expect((lowIndex ?? .max) < (meetingIndex ?? .min))
        // Dark is untouched, so it is identical to Blue's: closeTo must be present, and last.
        #expect(closeIndex != nil)
        #expect((meetingIndex ?? .max) < (closeIndex ?? .min))
        // Within a kind, light comes before dark.
        let both = CustomCategoryColor.assess(CustomCategoryColor.derive(from: SRGB(rgb: 0x808080)), surfaces: surfaces)
            .filter { $0.kind == .looksLikeMeeting }.map(\.isDark)
        #expect(both == [false, true])
    }

    @Test func identicalColoursAreCloseInBothModesAndEachOtherIsReported() {
        let c = CategoryPalette.colors(at: 3)
        let concerns = CustomCategoryColor.assess(
            c, surfaces: surfaces,
            others: [(slug: "a", colors: c), (slug: "b", colors: CategoryPalette.colors(at: 0)), (slug: "c", colors: c)])
        // Others in the order given, light before dark within one; nothing for the far one.
        #expect(concerns == [ColorConcern(kind: .closeTo(slug: "a"), isDark: false),
                             ColorConcern(kind: .closeTo(slug: "a"), isDark: true),
                             ColorConcern(kind: .closeTo(slug: "c"), isDark: false),
                             ColorConcern(kind: .closeTo(slug: "c"), isDark: true)])
    }

    @Test func pureGreyPicksOfAnyLightnessDeriveAndWarnWithoutCrashing() {
        for rgb: UInt32 in [0x000000, 0x808080, 0xFFFFFF, 0x010101, 0xFEFEFE] {
            let colors = CustomCategoryColor.derive(from: SRGB(rgb: rgb))
            #expect(CustomCategoryColor.isGrey(SRGB(rgb: rgb)))
            let kinds = CustomCategoryColor.assess(colors, surfaces: surfaces).map(\.kind)
            #expect(kinds.contains(.looksLikeMeeting), "\(rgb)")
        }
    }

    @Test func assessTreatsWhoeverIsInOthersAsActive() {
        // assess cannot know about archiving or self: the caller filters. An empty list means no
        // closeTo, however similar the colour is to something else.
        let c = CategoryPalette.colors(at: 0)
        #expect(CustomCategoryColor.assess(c, surfaces: surfaces, others: []) == [])
    }
}

/// Builds a pick from hue and OKLCH chroma and derives it.
private enum DerivedFromHueChroma {
    static func derive(h: Double, c: Double) -> CategoryColors {
        CustomCategoryColor.derive(from: CategoryColorMath.srgb(OKLCH(l: 0.6, c: c, h: h)))
    }
}
