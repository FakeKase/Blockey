import Foundation

/// Turns `CustomCategoryColor.assess` output into the one warning line of the editor (UI spec
/// 3.3 d, copy from `docs/category-palette.md` 5.1). Worst problem only, never a list.
enum ColorConcernCopy {

    static let greyLine = "Too grey to tell apart from a meeting"
    static let derivedNote = "Blockey adjusts brightness for light and dark mode. Your pick sets the hue."

    /// - Parameters:
    ///   - concerns: in the order `assess` returns them, which is the precedence order.
    ///   - isGrey: pass `CustomCategoryColor.isGrey` for a custom pick, false for a swatch.
    ///   - nameFor: the other category's current display name for `closeTo`.
    static func line(for concerns: [ColorConcern], isGrey: Bool, nameFor: (String) -> String) -> String? {
        guard let worst = concerns.first else { return nil }
        // A grey pick always reads as a meeting, which is the less helpful sentence.
        if isGrey, worst.kind == .looksLikeMeeting { return greyLine }
        // Same kind (and same other category) in both modes folds into one phrase.
        let matching = concerns.filter { $0.kind == worst.kind }
        let modes = modePhrase(light: matching.contains { !$0.isDark }, dark: matching.contains { $0.isDark })
        switch worst.kind {
        case .lowContrast: return "Title may be hard to read in \(modes)"
        case .looksLikeMeeting: return "Looks like a meeting in \(modes)"
        case .closeTo(let slug): return "Close to \(nameFor(slug)) in \(modes)"
        }
    }

    static func modePhrase(light: Bool, dark: Bool) -> String {
        switch (light, dark) {
        case (true, true): return "light and dark mode"
        case (false, true): return "dark mode"
        default: return "light mode"
        }
    }

    /// VoiceOver label for the line.
    static func spoken(_ line: String) -> String { "Warning. \(line)" }
}
