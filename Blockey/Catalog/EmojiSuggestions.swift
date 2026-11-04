import Foundation

/// The emoji grid of the category editor (UI spec 3.2.1) and the symbol each one falls back to
/// where emoji cannot be drawn (the simulator, and screenshots). Foundation only.
enum EmojiSuggestions {

    struct Suggestion: Hashable, Sendable {
        let emoji: String
        let symbolName: String
        /// The VoiceOver name.
        let label: String
    }

    /// Used when an emoji is not in the table and no stored symbol applies. Not `tag`, which is
    /// the stand-in's glyph and means "not recognised".
    static let fallbackSymbol = "star.fill"

    // Written as scalars so an editor cannot strip a variation selector from the source.
    static let all: [Suggestion] = [
        Suggestion(emoji: "\u{1F4DA}", symbolName: "books.vertical.fill", label: "Books"),
        Suggestion(emoji: "\u{1F4BC}", symbolName: "briefcase.fill", label: "Work"),
        Suggestion(emoji: "\u{1F4BB}", symbolName: "laptopcomputer", label: "Computer"),
        Suggestion(emoji: "\u{2709}\u{FE0F}", symbolName: "envelope.fill", label: "Mail"),
        Suggestion(emoji: "\u{1F4DE}", symbolName: "phone.fill", label: "Calls"),
        Suggestion(emoji: "\u{1F6D2}", symbolName: "cart.fill", label: "Shopping"),
        Suggestion(emoji: "\u{1F9F9}", symbolName: "sparkles", label: "Cleaning"),
        Suggestion(emoji: "\u{1F37D}\u{FE0F}", symbolName: "fork.knife", label: "Meals"),
        Suggestion(emoji: "\u{1F697}", symbolName: "car.fill", label: "Travel"),
        Suggestion(emoji: "\u{2708}\u{FE0F}", symbolName: "airplane", label: "Flights"),
        Suggestion(emoji: "\u{1F3A8}", symbolName: "paintpalette.fill", label: "Art"),
        Suggestion(emoji: "\u{1F3B5}", symbolName: "music.note", label: "Music"),
        Suggestion(emoji: "\u{1F3AE}", symbolName: "gamecontroller.fill", label: "Games"),
        Suggestion(emoji: "\u{1F4D6}", symbolName: "book.fill", label: "Reading"),
        Suggestion(emoji: "\u{1F3CB}\u{FE0F}", symbolName: "dumbbell.fill", label: "Workout"),
        Suggestion(emoji: "\u{1F9D8}", symbolName: "figure.mind.and.body", label: "Mindfulness"),
        Suggestion(emoji: "\u{1F634}", symbolName: "bed.double.fill", label: "Sleep"),
        Suggestion(emoji: "\u{1F436}", symbolName: "pawprint.fill", label: "Pets"),
        Suggestion(emoji: "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", symbolName: "figure.2.and.child.holdinghands", label: "Family"),
        Suggestion(emoji: "\u{2764}\u{FE0F}", symbolName: "heart.fill", label: "Relationships"),
        Suggestion(emoji: "\u{1F4B0}", symbolName: "banknote.fill", label: "Money"),
        Suggestion(emoji: "\u{1F9FE}", symbolName: "doc.text.fill", label: "Bills"),
        Suggestion(emoji: "\u{1F6E0}\u{FE0F}", symbolName: "wrench.and.screwdriver.fill", label: "Repairs"),
        Suggestion(emoji: "\u{1F331}", symbolName: "leaf.fill", label: "Garden"),
        Suggestion(emoji: "\u{1F4A1}", symbolName: "lightbulb.fill", label: "Ideas"),
        Suggestion(emoji: "\u{270D}\u{FE0F}", symbolName: "pencil", label: "Writing"),
        Suggestion(emoji: "\u{1F393}", symbolName: "graduationcap.fill", label: "Study"),
        Suggestion(emoji: "\u{1F48A}", symbolName: "pills.fill", label: "Medicine"),
        Suggestion(emoji: "\u{1F389}", symbolName: "party.popper.fill", label: "Social"),
        Suggestion(emoji: "\u{1F4C5}", symbolName: "calendar", label: "Planning")
    ]

    /// Emoji compare equal across the optional text/emoji variation selector, so `\u{2708}` typed
    /// on a keyboard that drops it still finds the airplane.
    static func comparisonKey(_ emoji: String) -> String {
        String(String.UnicodeScalarView(emoji.unicodeScalars.filter { $0 != "\u{FE0F}" }))
    }

    static func suggestion(for emoji: String) -> Suggestion? {
        let key = comparisonKey(emoji)
        return all.first { comparisonKey($0.emoji) == key }
    }

    /// The symbol to store with `emoji` (spec 3.2). In order: a suggestion's symbol; a stored
    /// pair the emoji is unchanged from (`keeping`, tried in order, so an edited category keeps its
    /// own symbol and a reset built-in gets its own back); else `star.fill`.
    static func symbol(for emoji: String, keeping stored: [(emoji: String, symbolName: String)] = []) -> String {
        if let hit = suggestion(for: emoji) { return hit.symbolName }
        let key = comparisonKey(emoji)
        if let kept = stored.first(where: { comparisonKey($0.emoji) == key }) { return kept.symbolName }
        return fallbackSymbol
    }

    /// The spoken name of an emoji, for the header tile: the suggestion's label, else nothing
    /// specific (the glyph itself is read).
    static func label(for emoji: String) -> String? { suggestion(for: emoji)?.label }
}

/// The 24-character cap of a category name, counted by `Character` (grapheme cluster) so a Thai
/// tone mark is never cut off its consonant (UI spec 3.1, Q2).
enum CategoryNameField {
    static let maxLength = 24

    static func clamped(_ text: String) -> String {
        text.count > maxLength ? String(text.prefix(maxLength)) : text
    }

    static func isAtCap(_ text: String) -> Bool { text.count >= maxLength }

    static let capFooter = "Names can be up to 24 characters."
}

/// Keeps one emoji from the free-entry field: the last `Character` typed, so a new emoji replaces
/// the old one (spec 3.2).
enum EmojiEntry {
    static func lastCharacter(of text: String) -> String {
        text.last.map(String.init) ?? ""
    }
}
