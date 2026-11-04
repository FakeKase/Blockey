import Foundation

/// The plain-data shape of a category definition. `CategoryDefinition` (the @Model) converts to
/// this, so every rule in `Catalog/` is testable without SwiftData. See ADR 005, "Contract".
struct CategoryDefinitionValue: Hashable, Sendable {
    var slug: String
    var name: String
    var emoji: String
    var symbolName: String
    var paletteIndex: Int
    /// A valid `#RRGGBB` wins over `paletteIndex` (ADR 005 amendment, 2026-11-04).
    var customColorHex: String?
    var sortIndex: Int
    var archivedAt: Date?

    /// Choosing a swatch sets the index and clears the custom colour.
    mutating func choosePalette(_ index: Int) {
        paletteIndex = index
        customColorHex = nil
    }

    /// Choosing Other... stores the colour and leaves `paletteIndex` alone, so a bad hex later
    /// still lands on the swatch the category had before. Returns false, changing nothing, for
    /// anything that is not `#RRGGBB`.
    @discardableResult
    mutating func chooseCustom(hex: String) -> Bool {
        guard let canonical = CategoryCatalog.canonicalHex(hex) else { return false }
        customColorHex = canonical
        return true
    }
}

/// Which colour a category resolved to, before light/dark derivation.
enum ColorChoice: Hashable, Sendable {
    case palette(Int)
    /// Canonical uppercase `#RRGGBB`.
    case custom(String)
}

struct ResolvedCategory: Hashable, Sendable {
    enum Origin: Hashable, Sendable { case builtIn, custom, standIn }

    /// Nil is reserved for the ADR's "absent slug" case, but resolution always lands on a real
    /// one today: an absent slug resolves to `deep`, so views can key on it.
    let slug: String?
    let name: String
    let emoji: String
    let symbolName: String
    let colorChoice: ColorChoice
    /// Light and dark records, already derived for a custom colour (ADR 005 contract). Views read
    /// this and never look up the palette themselves.
    let colors: CategoryColors
    /// Archived means "not offered", never "not rendered".
    let isArchived: Bool
    let origin: Origin
}

enum NameProblem: Hashable, Sendable {
    case empty
    /// Matches the current display name of this unarchived category.
    case duplicate(ofSlug: String)
}

/// Turns slugs into something drawable. Pure: no EventKit, no SwiftUI, no SwiftData.
///
/// This is the one seam views ask (ADR 005, "Escape hatch"). `resolve` never fails, because a
/// block whose category is unknown still has to render something honest.
struct CategoryCatalog: Sendable {

    /// Built-in defaults as plain data, in the enum's order, which is also their default sort
    /// order. Copied from `BlockCategory` because that file imports SwiftUI; a test pins the two
    /// together until the enum is deleted (ADR 005, last bullet of "What this supersedes").
    struct BuiltIn: Hashable, Sendable {
        let slug: String, name: String, emoji: String, symbolName: String
    }

    static let builtIns: [BuiltIn] = [
        BuiltIn(slug: "deep", name: "Deep work", emoji: "\u{1F9E0}", symbolName: "brain.head.profile"),
        BuiltIn(slug: "meeting", name: "Meeting", emoji: "\u{1F465}", symbolName: "person.2.fill"),
        BuiltIn(slug: "admin", name: "Admin", emoji: "\u{1F5C2}\u{FE0F}", symbolName: "tray.full.fill"),
        BuiltIn(slug: "personal", name: "Personal", emoji: "\u{1F3E1}", symbolName: "house.fill"),
        BuiltIn(slug: "health", name: "Health", emoji: "\u{1F3C3}", symbolName: "figure.run"),
        BuiltIn(slug: "rest", name: "Rest", emoji: "\u{2615}", symbolName: "cup.and.saucer.fill")
    ]
    static let builtInSlugs: Set<String> = Set(builtIns.map(\.slug))
    static let fallbackSlug = "deep"

    /// The generic glyph of a stand-in: a tag, so the user can see the category is not
    /// recognised rather than being told something false.
    static let standInEmoji = "\u{1F3F7}\u{FE0F}"
    static let standInSymbolName = "tag"

    private let overrides: [String: CategoryDefinitionValue]
    private let customs: [CategoryDefinitionValue]
    private let paletteCount: Int

    /// `definitions` may repeat a slug (a hand-edited backup, say); the first wins, matching
    /// Backup v2's first-wins rule.
    init(definitions: [CategoryDefinitionValue], paletteCount: Int = CategoryPalette.count) {
        var bySlug: [String: CategoryDefinitionValue] = [:]
        var custom: [CategoryDefinitionValue] = []
        for def in definitions where bySlug[def.slug] == nil {
            bySlug[def.slug] = def
            if !Self.builtInSlugs.contains(def.slug) { custom.append(def) }
        }
        self.overrides = bySlug
        self.customs = custom
        self.paletteCount = Swift.max(1, paletteCount)
    }

    // MARK: Resolution

    func resolve(_ slug: String?) -> ResolvedCategory {
        // An empty or whitespace slug counts as absent, as it does in the token.
        guard let slug, !slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return resolve(Self.fallbackSlug)
        }
        if let def = overrides[slug] {
            let isBuiltIn = Self.builtInSlugs.contains(slug)
            let choice = colorChoice(for: def)
            return ResolvedCategory(slug: slug, name: def.name, emoji: def.emoji, symbolName: def.symbolName,
                                    colorChoice: choice, colors: CategoryPalette.colors(for: choice),
                                    isArchived: def.archivedAt != nil,
                                    origin: isBuiltIn ? .builtIn : .custom)
        }
        if let index = Self.builtIns.firstIndex(where: { $0.slug == slug }) {
            let b = Self.builtIns[index]
            // Built-ins take palette slots 0...5 in order.
            return ResolvedCategory(slug: slug, name: b.name, emoji: b.emoji, symbolName: b.symbolName,
                                    colorChoice: .palette(index % paletteCount),
                                    colors: CategoryPalette.colors(at: index % paletteCount), isArchived: false,
                                    origin: .builtIn)
        }
        return standIn(for: slug)
    }

    /// Unarchived categories in picker order, plus `current` when it is archived or unknown, so
    /// opening something is never a silent change. A nil `current` shows what nil resolves to.
    func choices(current: String?) -> [ResolvedCategory] {
        var rows: [(sort: Int, order: Int, slug: String)] = []
        for (i, b) in Self.builtIns.enumerated() {
            let sort = overrides[b.slug]?.sortIndex ?? i
            rows.append((sort, i, b.slug))
        }
        for (i, def) in customs.enumerated() { rows.append((def.sortIndex, Self.builtIns.count + i, def.slug)) }
        rows.sort { ($0.sort, $0.order) < ($1.sort, $1.order) }

        var result = rows.map { resolve($0.slug) }.filter { !$0.isArchived }
        let shown = resolve(current)
        if !result.contains(where: { $0.slug == shown.slug }) { result.append(shown) }
        return result
    }

    /// The definition to insert for "Add as category" on a stand-in. Keeps the stand-in's FNV
    /// palette index and no custom colour, so adopting one never changes its colour on screen.
    func definitionAdopting(standIn slug: String, sortIndex: Int) -> CategoryDefinitionValue {
        CategoryDefinitionValue(slug: slug, name: CategorySlug.displayName(fromSlug: slug),
                                emoji: Self.standInEmoji, symbolName: Self.standInSymbolName,
                                paletteIndex: CategorySlug.standInPaletteIndex(for: slug, paletteCount: paletteCount),
                                customColorHex: nil, sortIndex: sortIndex, archivedAt: nil)
    }

    /// One past the largest `sortIndex` among unarchived categories, so a category added now
    /// lands last in the picker (UI spec 3.5). Built-ins without a row count at their default
    /// position. Never below the built-in count's end when nothing is customised.
    var nextSortIndex: Int {
        var highest = -1
        for (i, b) in Self.builtIns.enumerated() where !resolve(b.slug).isArchived {
            highest = Swift.max(highest, overrides[b.slug]?.sortIndex ?? i)
        }
        for def in customs where def.archivedAt == nil { highest = Swift.max(highest, def.sortIndex) }
        return highest + 1
    }

    // MARK: Rules

    /// Every slug in use: built-ins, rows, archived ones included. Feed this to
    /// `CategorySlug.mint`.
    var takenSlugs: Set<String> { Self.builtInSlugs.union(overrides.keys) }

    /// SwiftData's `.unique` upserts rather than failing, so this is checked before any insert.
    func isSlugTaken(_ slug: String) -> Bool { takenSlugs.contains(slug) }

    /// At least one category must stay unarchived (owner decision 3, ADR 005).
    func canArchive(_ slug: String) -> Bool {
        let active = Self.builtIns.map(\.slug).filter { resolve($0).isArchived == false }
            + customs.map(\.slug).filter { resolve($0).isArchived == false }
        return !(active.count == 1 && active.first == slug)
    }

    /// Names equal to any unarchived category's current display name are refused, built-ins
    /// included, compared through `TitleKey`. `editing` exempts the category being edited, so
    /// saving without changing the name is not a duplicate of itself.
    func validate(name: String, editing slug: String?) -> NameProblem? {
        guard CategorySlug.hasContent(name) else { return .empty }
        let key = TitleKey.normalize(Self.cleanedName(name))
        let active = Self.builtIns.map(\.slug) + customs.map(\.slug)
        for other in active where other != slug {
            let r = resolve(other)
            if !r.isArchived && TitleKey.normalize(r.name) == key { return .duplicate(ofSlug: other) }
        }
        return nil
    }

    /// The emoji is required (ADR 005): colour is never the only signal. Blank or invisible-only
    /// input is refused. Whether it is really an emoji is the keyboard's business.
    static func isAcceptableEmoji(_ emoji: String) -> Bool { CategorySlug.hasContent(emoji) }

    /// What gets saved: leading and trailing whitespace trimmed, nothing else touched.
    static func cleanedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `#RRGGBB` in either case, nothing else (no short form, no alpha, no whitespace), returned
    /// uppercase. Nil for anything that does not parse, so resolution can treat it as absent.
    static func canonicalHex(_ hex: String) -> String? {
        let scalars = Array(hex.unicodeScalars)
        guard scalars.count == 7, scalars[0] == "#",
              scalars.dropFirst().allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0)
                                               || ("A"..."F").contains($0) }) else { return nil }
        return hex.uppercased()
    }

    // MARK: Private

    private func colorChoice(for def: CategoryDefinitionValue) -> ColorChoice {
        if let hex = def.customColorHex, let canonical = Self.canonicalHex(hex) { return .custom(canonical) }
        // Positive modulo: a backup from a build with a larger palette (or a negative index) wraps
        // instead of crashing.
        return .palette(((def.paletteIndex % paletteCount) + paletteCount) % paletteCount)
    }

    /// Never produces `.custom`: the colour lived only in SwiftData and the backup, and the token
    /// carries just the slug, so a stand-in cannot know it.
    private func standIn(for slug: String) -> ResolvedCategory {
        let index = CategorySlug.standInPaletteIndex(for: slug, paletteCount: paletteCount)
        return ResolvedCategory(slug: slug, name: CategorySlug.displayName(fromSlug: slug),
                         emoji: Self.standInEmoji, symbolName: Self.standInSymbolName,
                         colorChoice: .palette(index), colors: CategoryPalette.colors(at: index),
                         isArchived: false, origin: .standIn)
    }
}
