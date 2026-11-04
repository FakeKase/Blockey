import Foundation

/// How one role (spine, fill or border) in one mode is derived from a picked colour: the pick's
/// hue, this lightness, and `min(cap, factor * pickedChroma)` for chroma.
struct RoleTarget: Hashable, Sendable {
    var lightness: Double
    var chromaFactor: Double
    var chromaCap: Double
}

struct ModeTargets: Hashable, Sendable {
    var spine: RoleTarget
    var fill: RoleTarget
    var border: RoleTarget
}

/// `docs/category-palette.md` section 4. A first fit to the twelve curated records, then checked
/// (and where needed adjusted) by the hue sweep in `CustomCategoryColorTests`.
struct DerivationTargets: Hashable, Sendable {
    var light: ModeTargets
    var dark: ModeTargets
    /// Picks under this OKLCH chroma have no usable hue (ADR 005, Greys).
    var greyChroma: Double
    /// Minimum OKLCH chroma of a derived fill, per mode. Below it the fill reads as the grey
    /// meeting chip. Sits 0.016 under the palest curated fill (Blue light, 0.057).
    var chromaGap: Double

    static let measured = DerivationTargets(
        light: ModeTargets(spine: RoleTarget(lightness: 0.57, chromaFactor: 1.00, chromaCap: 0.19),
                           fill: RoleTarget(lightness: 0.86, chromaFactor: 0.45, chromaCap: 0.12),
                           border: RoleTarget(lightness: 0.60, chromaFactor: 0.90, chromaCap: 0.17)),
        dark: ModeTargets(spine: RoleTarget(lightness: 0.74, chromaFactor: 0.90, chromaCap: 0.16),
                          fill: RoleTarget(lightness: 0.41, chromaFactor: 0.60, chromaCap: 0.11),
                          border: RoleTarget(lightness: 0.58, chromaFactor: 0.80, chromaCap: 0.14)),
        greyChroma: 0.02,
        chromaGap: 0.040)
}

/// What is wrong with a colour, in which appearance. Warn only: nothing here blocks saving.
struct ColorConcern: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case lowContrast
        case looksLikeMeeting
        case closeTo(slug: String)
    }
    var kind: Kind
    var isDark: Bool
}

enum CustomCategoryColor {

    /// True when the pick has no usable hue.
    static func isGrey(_ picked: SRGB, targets: DerivationTargets = .measured) -> Bool {
        CategoryColorMath.oklch(picked).c < targets.greyChroma
    }

    /// One picked colour becomes eight: the pick supplies hue and chroma, the targets supply
    /// lightness, per mode. Gamut mapping lowers chroma only. `onFill` is the mode's ink.
    static func derive(from picked: SRGB, targets: DerivationTargets = .measured) -> CategoryColors {
        let p = CategoryColorMath.oklch(picked)
        let grey = p.c < targets.greyChroma
        func role(_ t: RoleTarget) -> SRGB {
            // A grey has no hue worth keeping; chroma 0 keeps it grey rather than tinting it by
            // whatever rounding noise left in the hue.
            let chroma = grey ? 0 : Swift.min(t.chromaCap, t.chromaFactor * p.c)
            return CategoryColorMath.srgb(OKLCH(l: t.lightness, c: chroma, h: p.h))
        }
        func record(_ m: ModeTargets, ink: SRGB) -> CategoryColorRecord {
            CategoryColorRecord(spine: role(m.spine), fill: role(m.fill), border: role(m.border), onFill: ink)
        }
        return CategoryColors(light: record(targets.light, ink: .black), dark: record(targets.dark, ink: .white))
    }

    /// Every concern, worst first: low contrast, then looks-like-a-meeting, then close-to (in
    /// `others` order); within a kind, light before dark. Callers show `.first`.
    ///
    /// `others` must already be the *other, unarchived* categories: this function cannot know
    /// which one is being edited or which are archived.
    static func assess(_ colors: CategoryColors,
                       surfaces: ColorSurfaces = .assumedPendingStory1,
                       others: [(slug: String, colors: CategoryColors)] = [],
                       targets: DerivationTargets = .measured) -> [ColorConcern] {
        var result: [ColorConcern] = []
        for isDark in [false, true] {
            let r = colors.record(isDark: isDark)
            let s = surfaces.mode(isDark: isDark)
            let math = CategoryColorMath.self
            if math.contrastRatio(r.onFill, r.fill) < ColorFloors.onFillOnFill
                || math.contrastRatio(r.spine, s.canvas) < ColorFloors.spineOnCanvas
                || math.contrastRatio(r.border, s.canvas) < ColorFloors.borderOnCanvas
                || math.deltaE76(r.fill, s.canvas) < ColorFloors.fillFromCanvasDeltaE
                || math.contrastRatio(r.fill, s.canvas) < ColorFloors.fillOnCanvasRatio {
                result.append(ColorConcern(kind: .lowContrast, isDark: isDark))
            }
        }
        for isDark in [false, true] {
            let r = colors.record(isDark: isDark)
            let s = surfaces.mode(isDark: isDark)
            if CategoryColorMath.deltaE76(r.fill, s.meetingFill) < ColorFloors.fillFromMeetingDeltaE
                || CategoryColorMath.oklch(r.fill).c < targets.chromaGap {
                result.append(ColorConcern(kind: .looksLikeMeeting, isDark: isDark))
            }
        }
        for other in others {
            for isDark in [false, true]
            where CategoryColorMath.deltaE76(colors.record(isDark: isDark).fill,
                                             other.colors.record(isDark: isDark).fill)
                < ColorFloors.fillFromOtherCategoryDeltaE {
                result.append(ColorConcern(kind: .closeTo(slug: other.slug), isDark: isDark))
            }
        }
        return result
    }
}
