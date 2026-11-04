import Foundation

/// Reordering the unarchived categories (UI spec 2.4). Pure: it returns what to write and the
/// caller writes it in one save.
enum CategoryOrdering {

    /// `Array.move(fromOffsets:toOffset:)` without SwiftUI, so the rule is tested here. `toOffset`
    /// is an index in the original array, as `onMove` supplies it. Out-of-range offsets are ignored.
    static func moved<T>(_ items: [T], fromOffsets offsets: [Int], toOffset: Int) -> [T] {
        let valid = Set(offsets.filter { items.indices.contains($0) })
        guard !valid.isEmpty else { return items }
        let moving = valid.sorted().map { items[$0] }
        var rest: [T] = []
        for (i, item) in items.enumerated() where !valid.contains(i) { rest.append(item) }
        let clamped = Swift.max(0, Swift.min(items.count, toOffset))
        let insertAt = clamped - valid.filter { $0 < clamped }.count
        rest.insert(contentsOf: moving, at: insertAt)
        return rest
    }

    /// The order after moving `slug` one place up or down, or nil at the ends (where the custom
    /// action is absent) or for a slug that is not in the list.
    static func moved(_ order: [String], slug: String, by step: Int) -> [String]? {
        guard let index = order.firstIndex(of: slug) else { return nil }
        let target = index + step
        guard order.indices.contains(target) else { return nil }
        var result = order
        result.swapAt(index, target)
        return result
    }

    /// What one reorder writes.
    struct Plan: Equatable {
        /// Existing rows whose `sortIndex` must change: slug to new index.
        var updates: [String: Int]
        /// Built-ins with no row yet get one, copying their defaults, because the position is
        /// stored on the row (spec 2.4). Reset to default keeps the row, so the position survives.
        var creations: [CategoryDefinitionValue]

        var isEmpty: Bool { updates.isEmpty && creations.isEmpty }
    }

    /// `newOrder` is every unarchived category's slug, in the new order. Each gets `sortIndex`
    /// equal to its position (`0..<n`). Archived categories are not in the list and keep theirs.
    static func plan(newOrder: [String], catalog: CategoryCatalog) -> Plan {
        var updates: [String: Int] = [:]
        var creations: [CategoryDefinitionValue] = []
        for (position, slug) in newOrder.enumerated() {
            if catalog.hasRow(slug) {
                if catalog.value(for: slug)?.sortIndex != position { updates[slug] = position }
            } else if var created = CategoryCatalog.builtInDefault(slug: slug) {
                // Without a row a built-in sits at its default position, so only a built-in
                // that actually moved needs one.
                if created.sortIndex != position {
                    created.sortIndex = position
                    creations.append(created)
                }
            }
            // A slug with no row that is not a built-in is a stand-in: not orderable, skipped.
        }
        return Plan(updates: updates, creations: creations)
    }

    /// `Moved Errands to position 3 of 8` (spec 2.4).
    static func announcement(name: String, position: Int, total: Int) -> String {
        "Moved \(name) to position \(position) of \(total)"
    }
}
