import Foundation

/// The twelve measured swatches, exactly as `docs/category-palette.md` section 2 records them.
///
/// Slots 0 to 5 are the six built-ins in `BlockCategory` order, so a stored `paletteIndex` for a
/// built-in never changes meaning; 6 to 11 are new. This is not hue order: the picker shows
/// `pickerOrder`, a display permutation that does not change what an index means.
enum CategoryPalette {

    struct Swatch: Sendable {
        let name: String
        let colors: CategoryColors
    }

    // onFill is the mode's ink, identical for all twelve.
    private static func swatch(_ name: String,
                               light: (UInt32, UInt32, UInt32),
                               dark: (UInt32, UInt32, UInt32)) -> Swatch {
        Swatch(name: name, colors: CategoryColors(
            light: CategoryColorRecord(spine: SRGB(rgb: light.0), fill: SRGB(rgb: light.1),
                                       border: SRGB(rgb: light.2), onFill: .black),
            dark: CategoryColorRecord(spine: SRGB(rgb: dark.0), fill: SRGB(rgb: dark.1),
                                      border: SRGB(rgb: dark.2), onFill: .white)))
    }

    static let swatches: [Swatch] = [
        swatch("Blue",   light: (0x4664DC, 0xC8D2FA, 0x5A78E6), dark: (0x82A0FA, 0x284682, 0x506EBE)),
        swatch("Orange", light: (0xD26428, 0xFAC8A0, 0xD26E32), dark: (0xFAA06E, 0x6E3C1E, 0xB46E46)),
        swatch("Teal",   light: (0x1E8C96, 0xA0DCE6, 0x3296A0), dark: (0x5AC8D2, 0x145064, 0x328CA0)),
        swatch("Green",  light: (0x3C965A, 0xAADCAA, 0x469664), dark: (0x6ED28C, 0x1E5A32, 0x46965A)),
        swatch("Pink",   light: (0xD25082, 0xFABED2, 0xDC648C), dark: (0xFA8CB4, 0x82325A, 0xBE5A82)),
        swatch("Violet", light: (0x826EB4, 0xDCBEF0, 0x9682BE), dark: (0xBEAAFA, 0x5A3C82, 0x8C6EBE)),
        swatch("Red",    light: (0xD2463C, 0xFAC8BE, 0xDC5A50), dark: (0xFA786E, 0x783232, 0xBE5A50)),
        swatch("Gold",   light: (0xA07800, 0xE6D278, 0xAA8214), dark: (0xE6BE3C, 0x5A5014, 0xA08228)),
        swatch("Lime",   light: (0x648C1E, 0xC8DC82, 0x6E9628), dark: (0xAAD246, 0x46501E, 0x789632)),
        swatch("Mint",   light: (0x149678, 0xA0E6C8, 0x1E9678), dark: (0x50D2B4, 0x145046, 0x328C78)),
        swatch("Sky",    light: (0x1E82C8, 0xAADCFA, 0x288CD2), dark: (0x64B4FA, 0x145078, 0x3C82BE)),
        swatch("Plum",   light: (0xB446AA, 0xFAB4F0, 0xBE5AB4), dark: (0xE68CE6, 0x783278, 0xAA5AAA))
    ]

    static let count = swatches.count

    /// Hue order for the picker, as indices into `swatches`: Red, Orange, Gold, Lime, Green, Mint,
    /// Teal, Sky, Blue, Violet, Plum, Pink.
    static let pickerOrder: [Int] = [6, 1, 7, 8, 3, 9, 2, 10, 0, 5, 11, 4]

    /// Any integer is a valid index: it wraps (positive modulo), so a backup from a build with a
    /// larger palette, or a negative value, lands on a swatch instead of trapping.
    static func wrapped(_ index: Int) -> Int {
        ((index % count) + count) % count
    }

    static func colors(at index: Int) -> CategoryColors { swatches[wrapped(index)].colors }

    /// The colours a resolved choice draws with. A custom hex that somehow fails to parse (the
    /// catalog canonicalises, so this is a second line of defence) falls back to swatch 0.
    static func colors(for choice: ColorChoice) -> CategoryColors {
        switch choice {
        case .palette(let index):
            return colors(at: index)
        case .custom(let hex):
            guard let picked = SRGB(hex: hex) else { return colors(at: 0) }
            return CustomCategoryColor.derive(from: picked)
        }
    }

    /// The swatch a new category starts on (UI spec 3.4): the first in `pickerOrder` that no
    /// unarchived category uses, else `pickerOrder[unarchivedCount % 12]`. Returns a palette
    /// index, not a picker position.
    static func defaultIndex(avoiding used: Set<Int>, unarchivedCount: Int) -> Int {
        let normalised = Set(used.map(wrapped))
        if let free = pickerOrder.first(where: { !normalised.contains($0) }) { return free }
        return pickerOrder[((unarchivedCount % pickerOrder.count) + pickerOrder.count) % pickerOrder.count]
    }
}
