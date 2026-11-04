import Foundation
import SwiftData

/// A user-defined category, or a built-in the user has customised (ADR 005). Keyed by slug.
///
/// Rows exist only for custom categories and overridden built-ins; deleting a built-in's row is
/// "Reset to default". Not in iCloud (ADR 003), so it travels in the backup (Backup v2, `BlockeyBackup.categories`).
///
/// `.unique` on `slug` upserts instead of failing, so callers must check
/// `CategoryCatalog.isSlugTaken` before inserting. Additive to the schema, so the existing store
/// should migrate lightly; that is unverified until an install-over check (ADR 005, "Not verified").
@Model
final class CategoryDefinition {
    @Attribute(.unique) var slug: String
    var name: String
    var emoji: String
    var symbolName: String
    var paletteIndex: Int
    var sortIndex: Int
    /// `#RRGGBB`; shipped in the model's first version so there is nothing to migrate later.
    var customColorHex: String?
    var archivedAt: Date?

    init(slug: String, name: String, emoji: String, symbolName: String,
         paletteIndex: Int, sortIndex: Int, customColorHex: String? = nil, archivedAt: Date? = nil) {
        self.slug = slug
        self.name = name
        self.emoji = emoji
        self.symbolName = symbolName
        self.paletteIndex = paletteIndex
        self.sortIndex = sortIndex
        self.customColorHex = customColorHex
        self.archivedAt = archivedAt
    }

    convenience init(_ value: CategoryDefinitionValue) {
        self.init(slug: value.slug, name: value.name, emoji: value.emoji, symbolName: value.symbolName,
                  paletteIndex: value.paletteIndex, sortIndex: value.sortIndex,
                  customColorHex: value.customColorHex, archivedAt: value.archivedAt)
    }

    var value: CategoryDefinitionValue {
        CategoryDefinitionValue(slug: slug, name: name, emoji: emoji, symbolName: symbolName,
                                paletteIndex: paletteIndex, customColorHex: customColorHex,
                                sortIndex: sortIndex, archivedAt: archivedAt)
    }
}

extension CategoryDefinition {
    /// Inserts only when no row has this slug. `.unique` would otherwise replace the existing
    /// definition silently, so every "add" path goes through here. Editing mutates the row in
    /// place and never inserts. Returns false, changing nothing, when the slug is taken.
    @discardableResult
    static func insertIfFree(_ value: CategoryDefinitionValue, in context: ModelContext) throws -> Bool {
        let slug = value.slug
        let existing = try context.fetchCount(FetchDescriptor<CategoryDefinition>(
            predicate: #Predicate { $0.slug == slug }))
        guard existing == 0 else { return false }
        context.insert(CategoryDefinition(value))
        return true
    }
}
