import Testing
import Foundation
@testable import Blockey

/// ResolvedCategory.colors and the CategoryStyle seam (tasks 3.2 colour, 3.3, Story 2).
@Suite("Category colour resolution")
struct CategoryColorResolutionTests {

    private func def(_ slug: String, index: Int = 0, hex: String? = nil) -> CategoryDefinitionValue {
        CategoryDefinitionValue(slug: slug, name: slug, emoji: "x", symbolName: "tag",
                                paletteIndex: index, customColorHex: hex, sortIndex: 0, archivedAt: nil)
    }

    @Test func paletteChoiceResolvesToThatSwatch() {
        let r = CategoryCatalog(definitions: [def("u-a", index: 7)]).resolve("u-a")
        #expect(r.colors == CategoryPalette.colors(at: 7))
    }

    @Test func paletteIndexPastCountWrapsForColoursToo() {
        let r = CategoryCatalog(definitions: [def("u-a", index: 12 + 4)]).resolve("u-a")
        #expect(r.colorChoice == .palette(4))
        #expect(r.colors == CategoryPalette.colors(at: 4))
        #expect(CategoryCatalog(definitions: [def("u-b", index: -1)]).resolve("u-b").colors
                == CategoryPalette.colors(at: 11))
    }

    @Test func validCustomHexResolvesToDerivedColours() {
        let r = CategoryCatalog(definitions: [def("u-a", index: 2, hex: "#3a7bd5")]).resolve("u-a")
        #expect(r.colorChoice == .custom("#3A7BD5"))
        #expect(r.colors == CustomCategoryColor.derive(from: SRGB(rgb: 0x3A7BD5)))
    }

    @Test func invalidCustomHexFallsBackToThePaletteIndexColours() {
        let r = CategoryCatalog(definitions: [def("u-a", index: 5, hex: "blue")]).resolve("u-a")
        #expect(r.colors == CategoryPalette.colors(at: 5))
    }

    @Test func validHexBeatsAnyPaletteIndexIncludingOutOfRange() {
        for index in [0, 11, 12, 999, -5, Int.min, Int.max] {
            let r = CategoryCatalog(definitions: [def("u-a", index: index, hex: "#00AA88")]).resolve("u-a")
            #expect(r.colorChoice == .custom("#00AA88"), "\(index)")
            #expect(r.colors == CustomCategoryColor.derive(from: SRGB(rgb: 0x00AA88)))
        }
    }

    @Test func invalidHexVariantsAllFallBackToTheIndexWithoutTrapping() {
        for bad in ["", "#FFF", "00AA88", "#00AA8", "#00AA88FF", " #00AA88", "#GG0000", "#\u{FF10}\u{FF10}0000"] {
            let r = CategoryCatalog(definitions: [def("u-a", index: 3, hex: bad)]).resolve("u-a")
            #expect(r.colorChoice == .palette(3), "\(bad)")
            #expect(r.colors == CategoryPalette.colors(at: 3))
        }
        // Extreme index with no hex: still lands on a swatch.
        _ = CategoryCatalog(definitions: [def("u-b", index: Int.min)]).resolve("u-b").colors
    }

    @Test func standInUsesTheFnvSwatchAndNeverACustomColour() {
        let slug = "u-reading"
        let r = CategoryCatalog(definitions: []).resolve(slug)
        let index = CategorySlug.standInPaletteIndex(for: slug, paletteCount: CategoryPalette.count)
        #expect(r.origin == .standIn)
        #expect(r.colorChoice == .palette(index))
        #expect(r.colors == CategoryPalette.colors(at: index))
        // Pinned: the FNV value must not move (and so must not use per-process hashValue).
        #expect(index == 1)
    }

    @Test func absentSlugResolvesToDeepsColours() {
        #expect(CategoryCatalog(definitions: []).resolve(nil).colors == CategoryPalette.colors(at: 0))
    }

    @Test func categoryStyleCopiesTheResolvedValues() {
        let r = CategoryCatalog(definitions: []).resolve("health")
        let style = CategoryStyle(r)
        #expect(style.title == "Health" && style.emoji == r.emoji && style.symbolName == r.symbolName)
        #expect(style.colors == r.colors)
        #expect(style.record(isDark: true) == r.colors.dark)
        #expect(style.record(isDark: false) == r.colors.light)
    }

    @Test func categoryStyleHoldsAnyColoursNotJustBuiltIns() {
        let custom = CustomCategoryColor.derive(from: SRGB(rgb: 0x00AA88))
        let style = CategoryStyle(title: "Reading", emoji: "x", symbolName: "book", colors: custom)
        #expect(style.record(isDark: false).spine == custom.light.spine)
    }
}
