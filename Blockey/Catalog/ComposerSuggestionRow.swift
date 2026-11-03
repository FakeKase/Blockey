import Foundation

/// The inbox composer's draft, and what a tapped suggestion does to it. Pure so the rules are
/// tested: no SwiftUI, no EventKit, no SwiftData.
struct ComposerDraft: Equatable {
    static let presetDurations = [15, 30, 45, 60, 90, 120]

    var title = ""
    var minutes = 30
    var category: BlockCategory = .deepWork
    /// A remembered duration that is not a preset (say 50), shown as one more chip so the
    /// selection is visible. Cleared by `reset()`.
    var extraMinutes: Int?

    /// Presets plus the extra one, in order, so the extra chip sits where it belongs.
    var durations: [Int] {
        guard let extraMinutes, !Self.presetDurations.contains(extraMinutes) else { return Self.presetDurations }
        return (Self.presetDurations + [extraMinutes]).sorted()
    }

    /// Fills title, duration and category. Never submits. A nil or unknown slug leaves the
    /// category as it is.
    mutating func apply(_ suggestion: TitleSuggestion) {
        title = ComposerTitle.forSubmit(suggestion.title)
        minutes = suggestion.minutes
        extraMinutes = Self.presetDurations.contains(suggestion.minutes) ? nil : suggestion.minutes
        if let slug = suggestion.categorySlug, let known = BlockCategory(rawValue: slug) {
            category = known
        }
    }

    /// After a task is added: the title clears, the duration and category stay (the user is
    /// usually adding several alike), and a one-off extra duration chip goes away unless it is
    /// still the selected one.
    /// A duration chip tap. A one-off extra chip goes away once something else is selected.
    mutating func select(minutes newMinutes: Int) {
        minutes = newMinutes
        if extraMinutes != newMinutes { extraMinutes = nil }
    }

    mutating func resetTitle() {
        title = ""
        if extraMinutes != minutes { extraMinutes = nil }
    }
}

/// Which suggestion chips the composer shows. The fetch happens once, when the tray opens; this
/// only ranks what was fetched. Debouncing is the view's job (`debounce`), because it is a
/// timer; deciding what to show is here.
struct ComposerSuggestionRow {
    /// Update about this long after typing stops. See ADR 006.
    static let debounce: Duration = .milliseconds(250)

    private var history: [TitleSample]
    private var templates: [TitleSample]
    private var knownSlugs: Set<String>
    private(set) var chips: [TitleSuggestion] = []
    /// The text a tap just put in the field. While the field still holds exactly this, no chips.
    private var suppressedText: String?

    init(history: [TitleSample] = [], templates: [TitleSample] = [],
         knownSlugs: Set<String> = Set(BlockCategory.allCases.map(\.rawValue))) {
        self.history = history
        self.templates = templates
        self.knownSlugs = knownSlugs
    }

    /// Chips to draw for the field's current text. Hidden at once when the field is empty or
    /// only whitespace, without waiting for the debounce, and hidden after a tap until typing.
    func visibleChips(for text: String) -> [TitleSuggestion] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, text != suppressedText else { return [] }
        // Between a keystroke and the debounce, chips were ranked for older text. Keep only
        // those that still contain what is in the field now, so "gym" then "gymx" hides at once
        // and a chip never stays up for text it does not match. Compared by scalars on
        // normalised keys, so a partial Thai cluster and case or width variants behave.
        let needle = Array(TitleKey.normalize(trimmed).unicodeScalars)
        return chips.filter { Self.contains(Array(TitleKey.normalize($0.title).unicodeScalars), needle) }
    }

    private static func contains(_ hay: [Unicode.Scalar], _ needle: [Unicode.Scalar]) -> Bool {
        guard let first = needle.first else { return true }
        guard needle.count <= hay.count else { return false }
        for i in 0...(hay.count - needle.count) where hay[i] == first {
            if hay[i..<(i + needle.count)].elementsEqual(needle) { return true }
        }
        return false
    }

    /// Drops everything at once, for when the field is cleared by a submit.
    mutating func clear() {
        chips = []
        suppressedText = nil
    }

    /// Recomputes after the debounce. While an IME is composing (`isComposing`) the current chips
    /// are kept, so they do not flicker on every marked-text change.
    mutating func refresh(query: String, isComposing: Bool = false, now: Date) {
        if isComposing { return }
        if query != suppressedText { suppressedText = nil }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            chips = []
            return
        }
        chips = TitleSuggestions.suggest(query: query, history: history, templates: templates,
                                         knownSlugs: knownSlugs, now: now)
    }

    /// Call when a chip is tapped, with the text it put into the field.
    mutating func suppress(forText text: String) {
        suppressedText = text
        chips = []
    }
}

/// Words on a chip. Pure so the label, the truncation-friendly layout and the spoken form are
/// tested without a view.
enum SuggestionChipText {

    /// `45m`, `1h`, `1.5h`. The format the duration chips already use.
    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let hours = Double(minutes) / 60
        return hours == hours.rounded() ? "\(Int(hours))h" : String(format: "%.1fh", hours)
    }

    /// `Title · 45m`. The emoji is drawn separately (it may be a symbol where emoji cannot render).
    /// The duration is last so middle truncation keeps it.
    static func visible(_ s: TitleSuggestion) -> String { "\(s.title) \u{00B7} \(duration(s.minutes))" }

    /// Full title, duration and category name, never truncated.
    static func accessibilityLabel(_ s: TitleSuggestion) -> String {
        let spoken = s.minutes == 1 ? "1 minute" : "\(s.minutes) minutes"
        var parts = [s.title, spoken]
        if let slug = s.categorySlug, let category = BlockCategory(rawValue: slug) {
            parts.append(category.title)
        }
        return parts.joined(separator: ", ")
    }
}
