import Foundation

/// The two surfaces a chip is judged against in one appearance.
struct ModeSurfaces: Hashable, Sendable {
    var canvas: SRGB
    var meetingFill: SRGB
}

struct ColorSurfaces: Hashable, Sendable {
    var light: ModeSurfaces
    var dark: ModeSurfaces

    /// PENDING STORY 1 (#11). These are the designer's assumed values from
    /// `docs/category-palette.md` section 1, not published ones: Story 1 has not chosen the canvas
    /// yet. When it does, change this one declaration and every floor test reruns against the real
    /// surfaces. Nothing else in `Catalog/` may hard-code a canvas or meeting colour.
    ///
    /// Meeting fill is `Color.primary` at 5 percent (light) and 6 percent (dark) over the canvas
    /// (`TimelineCanvas.swift:462`), composited in sRGB and rounded to bytes.
    static let assumedPendingStory1 = ColorSurfaces(
        light: ModeSurfaces(canvas: SRGB(rgb: 0xFAF8F5), meetingFill: SRGB(rgb: 0xEEECE9)),
        dark: ModeSurfaces(canvas: SRGB(rgb: 0x1C1C1E), meetingFill: SRGB(rgb: 0x2A2A2C)))

    func mode(isDark: Bool) -> ModeSurfaces { isDark ? dark : light }
}

/// The floors from ADR 005 (assessment table) and the redesign plan section 2. One place, so the
/// assessment and its tests cannot drift apart.
enum ColorFloors {
    static let spineOnCanvas = 3.0
    static let borderOnCanvas = 3.0
    static let onFillOnFill = 4.5
    static let fillOnCanvasRatio = 1.3
    static let fillFromCanvasDeltaE = 8.0
    static let fillFromMeetingDeltaE = 15.0
    static let fillFromOtherCategoryDeltaE = 10.0
}
