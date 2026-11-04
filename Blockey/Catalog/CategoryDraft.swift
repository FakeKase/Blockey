import Foundation

/// Which of the editor's four modes is open (UI spec section 3).
enum CategoryEditorMode: Hashable, Sendable {
    case add
    case edit(slug: String)
    case archived(slug: String)
    /// A stand-in being saved as a real category. The slug is fixed to the stand-in's.
    case adopt(slug: String)

    var slug: String? {
        switch self {
        case .add: return nil
        case .edit(let s), .archived(let s), .adopt(let s): return s
        }
    }

    var title: String {
        switch self {
        case .add: return "New category"
        case .edit, .archived: return "Edit category"
        case .adopt: return "Add category"
        }
    }

    /// Edit and Archived change a stored category, so Save needs something to have changed.
    var isEditing: Bool {
        switch self {
        case .edit, .archived: return true
        case .add, .adopt: return false
        }
    }
}

/// Everything the editor decides, over plain values, so the view only draws it. The draft is a
/// `CategoryDefinitionValue` plus the value it started from.
struct CategoryDraft: Equatable {
    let mode: CategoryEditorMode
    /// Where the editor started. Dirty means the draft differs from this.
    let initial: CategoryDefinitionValue
    var value: CategoryDefinitionValue
    /// Set for a built-in being edited: what "Reset to default" loads.
    let builtInDefault: CategoryDefinitionValue?

    /// Nil when an edit/archived/adopt mode names a slug the catalog cannot start from (a
    /// stand-in in Edit mode, say): the caller should open Adopt instead.
    init?(mode: CategoryEditorMode, catalog: CategoryCatalog) {
        self.mode = mode
        switch mode {
        case .add:
            initial = CategoryDefinitionValue(slug: "", name: "", emoji: "", symbolName: EmojiSuggestions.fallbackSymbol,
                                              paletteIndex: catalog.defaultPaletteIndexForNewCategory,
                                              customColorHex: nil, sortIndex: catalog.nextSortIndex,
                                              archivedAt: nil)
            builtInDefault = nil
        case .edit(let slug), .archived(let slug):
            guard let stored = catalog.value(for: slug) else { return nil }
            initial = stored
            builtInDefault = CategoryCatalog.builtInDefault(slug: slug)
        case .adopt(let slug):
            guard catalog.resolve(slug).origin == .standIn else { return nil }
            initial = catalog.definitionAdopting(standIn: slug, sortIndex: catalog.nextSortIndex)
            builtInDefault = nil
        }
        value = initial
    }

    // MARK: Fields

    mutating func setName(_ text: String) { value.name = CategoryNameField.clamped(text) }

    /// The emoji and its fallback symbol travel together. An emoji the draft started with (or a
    /// built-in's own) keeps its stored symbol.
    mutating func chooseEmoji(_ emoji: String) {
        value.emoji = emoji
        var stored = [(emoji: initial.emoji, symbolName: initial.symbolName)]
        if let d = builtInDefault { stored.append((d.emoji, d.symbolName)) }
        value.symbolName = EmojiSuggestions.symbol(for: emoji, keeping: stored)
    }

    mutating func choosePalette(_ index: Int) { value.choosePalette(index) }

    /// False, changing nothing, for anything but `#RRGGBB`.
    @discardableResult
    mutating func chooseCustom(hex: String) -> Bool { value.chooseCustom(hex: hex) }

    // MARK: State

    var hasEmoji: Bool { CategoryCatalog.isAcceptableEmoji(value.emoji) }
    var usesCustomColor: Bool { value.customColorHex.flatMap(CategoryCatalog.canonicalHex) != nil }

    /// The swatch ring: the palette index in use, or nil while Other... is selected.
    var selectedPaletteIndex: Int? {
        usesCustomColor ? nil : CategoryPalette.wrapped(value.paletteIndex)
    }

    var colorChoice: ColorChoice {
        if let hex = value.customColorHex.flatMap(CategoryCatalog.canonicalHex) { return .custom(hex) }
        return .palette(CategoryPalette.wrapped(value.paletteIndex))
    }

    var colors: CategoryColors { CategoryPalette.colors(for: colorChoice) }

    /// Compared with names trimmed, so trailing spaces alone are not a change.
    var isDirty: Bool {
        var a = value, b = initial
        a.name = CategoryCatalog.cleanedName(a.name)
        b.name = CategoryCatalog.cleanedName(b.name)
        return a != b
    }

    func nameProblem(in catalog: CategoryCatalog) -> NameProblem? {
        catalog.validate(name: value.name, editing: mode.slug)
    }

    /// Save: no name problem, an emoji, and for the editing modes something changed.
    func canSave(in catalog: CategoryCatalog) -> Bool {
        guard nameProblem(in: catalog) == nil, hasEmoji else { return false }
        return mode.isEditing ? isDirty : true
    }

    /// Restore saves the draft and un-archives, so it needs no change, only a valid draft.
    func canRestore(in catalog: CategoryCatalog) -> Bool {
        guard case .archived = mode else { return false }
        return nameProblem(in: catalog) == nil && hasEmoji
    }

    /// Shown only for a built-in whose name, emoji, symbol or colour differs from the factory
    /// values (spec 3.6).
    var canReset: Bool {
        guard case .edit = mode, let d = builtInDefault else { return false }
        return value.name != d.name || value.emoji != d.emoji || value.symbolName != d.symbolName
            || value.paletteIndex != d.paletteIndex || value.customColorHex != d.customColorHex
    }

    /// Loads the factory values into the draft. Position and archive state stay (Q3).
    mutating func resetToDefault() {
        guard let d = builtInDefault else { return }
        value.name = d.name
        value.emoji = d.emoji
        value.symbolName = d.symbolName
        value.paletteIndex = d.paletteIndex
        value.customColorHex = nil
    }

    // MARK: Colour assessment

    /// Every other unarchived category with its colours: what `assess` compares against. The one
    /// being edited is left out, and so are archived ones.
    func others(in catalog: CategoryCatalog) -> [(slug: String, colors: CategoryColors)] {
        catalog.activeInOrder().compactMap { r in
            guard let slug = r.slug, slug != mode.slug else { return nil }
            return (slug, r.colors)
        }
    }

    var isGreyPick: Bool {
        guard case .custom(let hex) = colorChoice, let picked = SRGB(hex: hex) else { return false }
        return CustomCategoryColor.isGrey(picked)
    }

    func concerns(in catalog: CategoryCatalog,
                  surfaces: ColorSurfaces = .assumedPendingStory1) -> [ColorConcern] {
        CustomCategoryColor.assess(colors, surfaces: surfaces, others: others(in: catalog))
    }

    /// The single warning line, or nil when `assess` finds nothing.
    func warningLine(in catalog: CategoryCatalog,
                     surfaces: ColorSurfaces = .assumedPendingStory1) -> String? {
        ColorConcernCopy.line(for: concerns(in: catalog, surfaces: surfaces), isGrey: isGreyPick) {
            catalog.resolve($0).name
        }
    }

    /// The saved name: trimmed, nothing else altered.
    var cleanedName: String { CategoryCatalog.cleanedName(value.name) }
}

/// Copy that belongs to the editor and is not a concern line.
enum CategoryEditorCopy {
    static let emptyName = "Give this category a name."
    static func duplicateName(of other: String) -> String {
        "Another category is already called \u{201C}\(other)\u{201D}. Choose a different name."
    }
    static let emojiRequired = "Choose an emoji. It keeps this category recognisable without its colour."
    static func emojiFooter(canTypeOwn: Bool) -> String {
        let base = "Emoji help you tell categories apart without relying on colour."
        return canTypeOwn ? base + " To type your own, switch to the emoji keyboard." : base
    }
    static let pastBlocksFooter = "Changes apply to every block, task and template row that uses this category, including past ones. Nothing in your calendar is rewritten."
    static let adoptBanner = "Blocks already use this category. Saving it gives them this name, emoji and colour."
    static let archivedBanner = "This category is archived. Blocks that use it still show it, but it isn\u{2019}t offered for new work."
    static let saveFailure = "Couldn\u{2019}t save this category. Nothing was changed. Try again."
    static let discardTitle = "Discard your changes?"

    static func nameMessage(_ problem: NameProblem, catalog: CategoryCatalog) -> String {
        switch problem {
        case .empty: return emptyName
        case .duplicate(let slug): return duplicateName(of: catalog.resolve(slug).name)
        }
    }

    static func swatchLabel(name: String, position: Int, total: Int) -> String {
        "\(name), colour \(position) of \(total)"
    }
}
