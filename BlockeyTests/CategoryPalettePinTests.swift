import Testing
@testable import Blockey

/// Pins every palette value to `docs/category-palette.md`. The floor tests in
/// `CategoryPaletteTests` would still pass after a typo that happens to stay readable, and a
/// silently changed swatch recolours every past block that uses it, so the values themselves are
/// fixed here. Change this table only together with the doc.
@Suite("Category palette is pinned to the measured doc")
struct CategoryPalettePinTests {
    /// name, then light spine/fill/border, then dark spine/fill/border.
    static let expected: [(String, [String])] = [
        ("Blue", ["#4664DC", "#C8D2FA", "#5A78E6", "#82A0FA", "#284682", "#506EBE"]),
        ("Orange", ["#D26428", "#FAC8A0", "#D26E32", "#FAA06E", "#6E3C1E", "#B46E46"]),
        ("Teal", ["#1E8C96", "#A0DCE6", "#3296A0", "#5AC8D2", "#145064", "#328CA0"]),
        ("Green", ["#3C965A", "#AADCAA", "#469664", "#6ED28C", "#1E5A32", "#46965A"]),
        ("Pink", ["#D25082", "#FABED2", "#DC648C", "#FA8CB4", "#82325A", "#BE5A82"]),
        ("Violet", ["#826EB4", "#DCBEF0", "#9682BE", "#BEAAFA", "#5A3C82", "#8C6EBE"]),
        ("Red", ["#D2463C", "#FAC8BE", "#DC5A50", "#FA786E", "#783232", "#BE5A50"]),
        ("Gold", ["#A07800", "#E6D278", "#AA8214", "#E6BE3C", "#5A5014", "#A08228"]),
        ("Lime", ["#648C1E", "#C8DC82", "#6E9628", "#AAD246", "#46501E", "#789632"]),
        ("Mint", ["#149678", "#A0E6C8", "#1E9678", "#50D2B4", "#145046", "#328C78"]),
        ("Sky", ["#1E82C8", "#AADCFA", "#288CD2", "#64B4FA", "#145078", "#3C82BE"]),
        ("Plum", ["#B446AA", "#FAB4F0", "#BE5AB4", "#E68CE6", "#783278", "#AA5AAA"]),
    ]

    @Test("Twelve swatches, in slot order")
    func count() {
        #expect(CategoryPalette.count == Self.expected.count)
    }

    @Test("Every swatch matches the doc", arguments: Array(0..<12))
    func swatchMatches(index: Int) throws {
        try #require(index < CategoryPalette.swatches.count)
        let swatch = CategoryPalette.swatches[index]
        let (name, hexes) = Self.expected[index]
        let c = swatch.colors
        let actual = [c.light.spine, c.light.fill, c.light.border,
                      c.dark.spine, c.dark.fill, c.dark.border].map(\.hex)
        #expect(swatch.name.localizedCaseInsensitiveContains(name))
        #expect(actual == hexes)
    }
}
