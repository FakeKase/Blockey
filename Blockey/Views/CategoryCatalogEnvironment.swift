import SwiftUI
import SwiftData

/// The catalog every view asks (UI spec 0.1). Built from the stored definitions, so a built-in
/// with no row still resolves and an empty store behaves exactly as before this feature.
private struct CategoryCatalogKey: EnvironmentKey {
    static let defaultValue = CategoryCatalog(definitions: [])
}

extension EnvironmentValues {
    var categoryCatalog: CategoryCatalog {
        get { self[CategoryCatalogKey.self] }
        set { self[CategoryCatalogKey.self] = newValue }
    }
}

/// Puts a live `CategoryCatalog` into the environment. A `@Query` re-evaluates this body when a
/// definition is inserted, edited or archived, so every tint and glyph follows without anyone
/// refreshing anything. Sheets inherit the environment from their presenter.
struct CategoryCatalogProvider<Content: View>: View {
    @Query private var definitions: [CategoryDefinition]
    @ViewBuilder var content: Content

    var body: some View {
        content.environment(\.categoryCatalog, CategoryCatalog(definitions: definitions.map(\.value)))
    }
}

extension CategoryCatalog {
    /// Views draw through this: one call, one `CategoryStyle` (UI spec 0.1).
    func style(_ slug: String?) -> CategoryStyle { CategoryStyle(resolve(slug)) }
}
