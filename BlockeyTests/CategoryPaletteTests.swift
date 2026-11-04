import Testing
import Foundation
@testable import Blockey

/// Plan Appendix A.4, CategoryPalette (task 3.3). Floors are recomputed here from the hex values
/// with `CategoryColorMath`; the document's tables are never copied in, so a drifting formula or a
/// mistyped hex fails loudly. Surfaces are the assumed ones, pending Story 1 (#11).
@Suite("CategoryPalette")
struct CategoryPaletteTests {
    private typealias M = CategoryColorMath
    private let surfaces = ColorSurfaces.assumedPendingStory1
    private let modes = [false, true]

    @Test func hasTwelveSwatchesAndTheCountIsDerivedFromThem() {
        #expect(CategoryPalette.count == 12)
        #expect(CategoryPalette.swatches.count == CategoryPalette.count)
    }

    @Test func builtInsTakeSlotsZeroToFiveInEnumOrder() {
        let names = CategoryPalette.swatches.prefix(6).map(\.name)
        #expect(names == ["Blue", "Orange", "Teal", "Green", "Pink", "Violet"])
        // Resolution agrees with the slot, for each built-in in BlockCategory order.
        let catalog = CategoryCatalog(definitions: [])
        for (i, cat) in BlockCategory.allCases.enumerated() {
            let r = catalog.resolve(cat.rawValue)
            #expect(r.colorChoice == .palette(i))
            #expect(r.colors == CategoryPalette.colors(at: i))
        }
    }

    @Test func pickerOrderIsAPermutationOfEverySlot() {
        #expect(CategoryPalette.pickerOrder.sorted() == Array(0..<CategoryPalette.count))
        let names = CategoryPalette.pickerOrder.map { CategoryPalette.swatches[$0].name }
        #expect(names == ["Red", "Orange", "Gold", "Lime", "Green", "Mint", "Teal", "Sky", "Blue", "Violet", "Plum", "Pink"])
    }

    @Test func onFillIsTheModesInkForEverySwatch() {
        for s in CategoryPalette.swatches {
            #expect(s.colors.light.onFill == .black, "\(s.name)")
            #expect(s.colors.dark.onFill == .white, "\(s.name)")
        }
    }

    @Test func paletteWrapsDeterministicallyPastCount() {
        let n = CategoryPalette.count
        #expect(CategoryPalette.wrapped(n) == 0)
        #expect(CategoryPalette.wrapped(n + 3) == 3)
        #expect(CategoryPalette.wrapped(-1) == n - 1)
        #expect(CategoryPalette.wrapped(Int.min) >= 0 && CategoryPalette.wrapped(Int.min) < n)
        #expect(CategoryPalette.colors(at: n + 3) == CategoryPalette.colors(at: 3))
    }

    // MARK: Floors (M9, M10), recomputed

    @Test func everySwatchPassesEveryFloorInBothModes() {
        for s in CategoryPalette.swatches {
            for isDark in modes {
                let r = s.colors.record(isDark: isDark), m = surfaces.mode(isDark: isDark)
                let tag = "\(s.name) \(isDark ? "dark" : "light")"
                #expect(M.contrastRatio(r.spine, m.canvas) >= 3.0, "spine \(tag)")
                #expect(M.contrastRatio(r.border, m.canvas) >= 3.0, "border \(tag)")
                #expect(M.deltaE76(r.fill, m.canvas) >= 8.0, "fill dE canvas \(tag)")
                #expect(M.contrastRatio(r.fill, m.canvas) >= 1.3, "fill ratio canvas \(tag)")
                #expect(M.contrastRatio(r.onFill, r.fill) >= 4.5, "onFill \(tag)")
                #expect(M.deltaE76(r.fill, m.meetingFill) >= 15.0, "fill vs meeting \(tag)")
                #expect(M.oklch(r.fill).c >= DerivationTargets.measured.chromaGap, "chroma gap \(tag)")
            }
        }
    }

    @Test func allSixtySixFillPairsAreDistinguishable() {
        let swatches = CategoryPalette.swatches
        var pairs = 0
        for i in swatches.indices {
            for j in swatches.indices where j > i {
                for isDark in modes {
                    let d = M.deltaE76(swatches[i].colors.record(isDark: isDark).fill,
                                       swatches[j].colors.record(isDark: isDark).fill)
                    #expect(d >= 10.0, "\(swatches[i].name)/\(swatches[j].name) \(isDark ? "dark" : "light") \(d)")
                }
                pairs += 1
            }
        }
        #expect(pairs == 66)
    }

    @Test func everyCuratedSwatchAssessesCleanAgainstTheOthers() {
        // The same function the editor uses, so the palette and the warning cannot disagree.
        for (i, s) in CategoryPalette.swatches.enumerated() {
            let others = CategoryPalette.swatches.enumerated().filter { $0.offset != i }
                .map { (slug: "swatch-\($0.offset)", colors: $0.element.colors) }
            #expect(CustomCategoryColor.assess(s.colors, surfaces: surfaces, others: others) == [], "\(s.name)")
        }
    }

    // MARK: Pins against the document

    @Test func weakestPairsMatchTheDocumentWithinItsStatedTolerance() {
        // Tolerance 0.5 as the document asks, so formula drift is caught.
        let sw = CategoryPalette.swatches
        func fillE(_ a: Int, _ b: Int, dark: Bool) -> Double {
            M.deltaE76(sw[a].colors.record(isDark: dark).fill, sw[b].colors.record(isDark: dark).fill)
        }
        #expect(abs(fillE(2, 10, dark: false) - 11.6) < 0.5)   // Teal / Sky, light
        #expect(abs(fillE(7, 8, dark: true) - 11.8) < 0.5)     // Gold / Lime, dark
        #expect(abs(M.contrastRatio(sw[4].colors.light.border, surfaces.light.canvas) - 3.17) < 0.05)  // Pink
        #expect(abs(M.contrastRatio(sw[9].colors.light.fill, surfaces.light.canvas) - 1.35) < 0.05)    // Mint
    }

    @Test func assumedSurfacesArePendingAndMeetingFillIsGrey() {
        // If Story 1 publishes real surfaces, these two lines are what to revisit.
        for isDark in modes {
            let m = surfaces.mode(isDark: isDark)
            #expect(M.lab(m.meetingFill).chroma < 3)
        }
    }
}
