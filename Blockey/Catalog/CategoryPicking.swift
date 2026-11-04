import Foundation

// The pure rules behind the category picker, the composer's category row and "Add as category"
// (UI spec issue #1, sections 1 and 4). Foundation only, so every decision is tested without a
// view. The views in `Views/CategoryPicker.swift` only draw what these return.

/// How the choice list is laid out: an optional `Current` section, then the offered categories.
struct CategoryChoiceLayout: Equatable {
    /// Set only when the current value is archived or unknown (a stand-in). It is shown first,
    /// because `choices` appends it at the end and a checked row at the bottom of a long list
    /// reads as an afterthought.
    let current: ResolvedCategory?
    /// Unarchived categories in the owner's order. Never contains `current`.
    let rows: [ResolvedCategory]
    /// The slug that carries the check mark. A nil or blank current resolves to the fallback.
    let selectedSlug: String?

    init(catalog: CategoryCatalog, current slug: String?) {
        let shown = catalog.resolve(slug)
        let all = catalog.choices(current: slug)
        selectedSlug = shown.slug
        if shown.isArchived || shown.origin == .standIn {
            current = shown
            rows = all.filter { $0.slug != shown.slug }
        } else {
            current = nil
            rows = all
        }
    }

    /// `choices` order with the off-list value last, which is what the composer chip row wants.
    var chipOrder: [ResolvedCategory] { rows + (current.map { [$0] } ?? []) }
}

/// What state a category is in, as far as the picker's words go.
enum CategoryStatus: Equatable {
    case active, archived, standIn

    init(_ resolved: ResolvedCategory) {
        if resolved.origin == .standIn { self = .standIn }
        else if resolved.isArchived { self = .archived }
        else { self = .active }
    }
}

/// Every string the picker shows that depends on a name or a status. Curly quotes throughout
/// (spec 0.6). Names are never transformed (spec 0.7).
enum CategoryPickerCopy {
    static func footer(for resolved: ResolvedCategory) -> String? {
        switch CategoryStatus(resolved) {
        case .active: return nil
        case .archived:
            return "\u{201C}\(resolved.name)\u{201D} is archived. It still shows here, but it won\u{2019}t be offered for new work."
        case .standIn:
            return "\u{201C}\(resolved.name)\u{201D} isn\u{2019}t saved as a category on this phone."
        }
    }

    static func subtitle(for resolved: ResolvedCategory) -> String? {
        switch CategoryStatus(resolved) {
        case .active: return nil
        case .archived: return "Archived"
        case .standIn: return "Not saved as a category"
        }
    }

    /// The Form row's spoken label: `Category, Deep work`, with the status appended.
    static func rowAccessibilityLabel(for resolved: ResolvedCategory) -> String {
        "Category, \(resolved.name)" + statusSuffix(resolved)
    }

    /// A list row's spoken label: the name, with `, archived` or `, not saved as a category`.
    static func listAccessibilityLabel(for resolved: ResolvedCategory) -> String {
        resolved.name + statusSuffix(resolved)
    }

    private static func statusSuffix(_ resolved: ResolvedCategory) -> String {
        switch CategoryStatus(resolved) {
        case .active: return ""
        case .archived: return ", archived"
        case .standIn: return ", not saved as a category"
        }
    }

    static func adopted(name: String) -> String {
        "Added \u{201C}\(name)\u{201D}. Change its emoji and colour in Settings."
    }

    static let adoptFailure = "Couldn\u{2019}t add this category. Nothing was changed. Try again."
}

/// What "Add as category" should do for a slug, decided before anything is written.
enum AdoptionPlan: Equatable {
    /// One tap: insert this definition. It keeps the stand-in's colour and tag glyph, so nothing
    /// on screen changes (spec 4.2).
    case add(CategoryDefinitionValue)
    /// The recovered name equals an unarchived category's name (or is empty), so a one-tap add
    /// would create two identical names. Spec 4.2 sends this to the editor in Adopt mode.
    case needsRename(CategoryDefinitionValue)
    /// The slug is a built-in or already has a definition: there is nothing to adopt.
    case notAStandIn
}

extension CategoryCatalog {
    func planAdoption(of slug: String?) -> AdoptionPlan {
        guard let slug, resolve(slug).origin == .standIn else { return .notAStandIn }
        let value = definitionAdopting(standIn: slug, sortIndex: nextSortIndex)
        return validate(name: value.name, editing: nil) == nil ? .add(value) : .needsRename(value)
    }
}

/// The composer's category row (spec 1.4).
enum ComposerCategoryRow {
    /// More than this many unarchived categories collapse the chip row into one chip.
    static let maxInlineChips = 8

    /// Collapse when there are too many to scan, or at an accessibility text size, where a row of
    /// giant chips would only scroll sideways.
    static func isCollapsed(unarchivedCount: Int, isAccessibilitySize: Bool) -> Bool {
        unarchivedCount > maxInlineChips || isAccessibilitySize
    }
}

/// The "untouched means nil" rule of the block sheet (spec 0.3), over slugs.
enum CategorySelection {
    /// Nil when the picker ends on the category it began on, so a Save that changes nothing never
    /// rewrites the slug and picking away and back does not either. Nil and blank both mean the
    /// fallback, because that is what they resolve to. Unlike the enum version, an explicit pick
    /// of the fallback on a block with an unknown slug is honoured: it differs.
    static func slugToSave(initial: String?, current: String?) -> String? {
        normalized(current) == normalized(initial) ? nil : current
    }

    static func normalized(_ slug: String?) -> String {
        guard let slug, CategorySlug.hasContent(slug) else { return CategoryCatalog.fallbackSlug }
        return slug
    }
}
