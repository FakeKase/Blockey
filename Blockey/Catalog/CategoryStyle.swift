import Foundation

/// What a view needs to draw a category: words, glyph names and two colour records. A plain
/// struct of stored values, deliberately never a switch over `BlockCategory`, so a custom
/// category has somewhere to go (ADR 005, "Effect on the CategoryStyle seam"). The SwiftUI
/// `Color` bridge is in `Views/CategoryStyle+Color.swift`; this file stays Foundation only.
struct CategoryStyle: Hashable, Sendable {
    var title: String
    var emoji: String
    var symbolName: String
    var colors: CategoryColors

    init(title: String, emoji: String, symbolName: String, colors: CategoryColors) {
        self.title = title; self.emoji = emoji; self.symbolName = symbolName; self.colors = colors
    }

    init(_ resolved: ResolvedCategory) {
        self.init(title: resolved.name, emoji: resolved.emoji, symbolName: resolved.symbolName,
                  colors: resolved.colors)
    }

    func record(isDark: Bool) -> CategoryColorRecord { colors.record(isDark: isDark) }
}
