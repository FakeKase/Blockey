import Foundation
import SwiftData

/// The category writes that touch more than one thing: archive (and optionally move inbox tasks
/// and template rows), reorder, restore, and the editor's save. Foundation and SwiftData only, so
/// every one is tested against an in-memory store. EventKit is never involved: blocks carry only a
/// slug and resolve on read, so nothing in the calendar is rewritten (ADR 005, UI spec 3.8).
///
/// Each public function stages its changes, saves **once**, and on a failed save puts the objects
/// back as they were. `save` is injectable so the failure path can be tested; it defaults to
/// `context.save()`.
@MainActor
struct CategoryStore {
    let context: ModelContext
    private let commitSave: () throws -> Void

    init(context: ModelContext, save: (() throws -> Void)? = nil) {
        self.context = context
        self.commitSave = save ?? { try context.save() }
    }

    enum StoreError: Error, Equatable {
        case slugTaken
        case nameHasNoContent
        case notFound
        /// The move target is archived, unknown, or the category being archived.
        case invalidMoveTarget
        /// Saving would leave two unarchived categories with the same name.
        case duplicateName
    }

    /// Changes made to objects but not yet saved, with the way back.
    private typealias Undo = [() -> Void]

    private func commit(_ undo: Undo) throws {
        do { try commitSave() } catch {
            undo.reversed().forEach { $0() }
            throw error
        }
    }

    // MARK: Usage

    struct Usage: Equatable {
        var tasks: Int
        var rows: Int
        var total: Int { tasks + rows }
    }

    /// How many inbox tasks and template rows carry this slug. A blank slug counts as the fallback
    /// because that is what it resolves to. Blocks already on the calendar are not counted: they
    /// keep the slug and keep rendering.
    func usage(of slug: String) throws -> Usage {
        Usage(tasks: try tasks(using: slug).count, rows: try rows(using: slug).count)
    }

    private func tasks(using slug: String) throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>()).filter { CategorySelection.normalized($0.categoryRaw) == slug }
    }

    private func rows(using slug: String) throws -> [TemplateRow] {
        try context.fetch(FetchDescriptor<TemplateRow>()).filter { CategorySelection.normalized($0.categoryRaw) == slug }
    }

    // MARK: Archive and restore

    /// Archives `slug`. When `moveTo` is set, every inbox task and template row on `slug` moves
    /// to it in the same save; when nil, nothing moves and they keep the archived slug (spec 2.5).
    /// A move target is never chosen for the owner, which is why this takes it explicitly.
    /// Refuses silently (changing nothing) for the last unarchived category.
    func archive(_ slug: String, moveTo target: String? = nil, catalog: CategoryCatalog, now: Date = .now) throws {
        guard catalog.canArchive(slug) else { return }
        try requireOfferedTarget(target, besides: slug, catalog: catalog)
        var undo: Undo = []
        do {
            undo += try stageMove(from: slug, to: target)
            if let existing = try row(for: slug) {
                let old = existing.archivedAt
                existing.archivedAt = now
                undo.append { existing.archivedAt = old }
            } else if var created = CategoryCatalog.builtInDefault(slug: slug) {
                // An untouched built-in has no row; archive state needs one.
                created.sortIndex = catalog.value(for: slug)?.sortIndex ?? created.sortIndex
                created.archivedAt = now
                undo.append(insert(created))
            } else {
                throw StoreError.notFound
            }
        } catch {
            undo.reversed().forEach { $0() }
            throw error
        }
        try commit(undo)
    }

    /// The editor's `Archive category`: the draft is saved and the category archived in one write,
    /// moving what uses it first when `moveTo` is set (spec 3.6).
    func saveAndArchive(_ draft: CategoryDraft, moveTo target: String? = nil, catalog: CategoryCatalog,
                        now: Date = .now) throws {
        guard let slug = draft.mode.slug, catalog.canArchive(slug) else { return }
        try requireOfferedTarget(target, besides: slug, catalog: catalog)
        var undo: Undo = []
        do {
            undo += try stageMove(from: slug, to: target)
            var rng = SystemRandomNumberGenerator()   // edit paths never mint, so it goes unused
            undo += try stageDraft(draft, catalog: catalog, archiveAt: now, restoring: false, random: &rng).undo
        } catch {
            undo.reversed().forEach { $0() }
            throw error
        }
        try commit(undo)
    }

    /// Clears `archivedAt`. The name check is the caller's (`validate`); restoring a duplicate
    /// would put two identical names in one picker.
    func restore(_ slug: String) throws {
        guard let existing = try row(for: slug) else { throw StoreError.notFound }
        let old = existing.archivedAt
        existing.archivedAt = nil
        try commit([{ existing.archivedAt = old }])
    }

    /// Tasks must never be moved onto a category that is itself archived or unknown: that would
    /// strand them on something "not offered for new work". The sheet only lists offered
    /// categories; this holds the line for any other caller. Moving to the category's own slug is
    /// a no-op (`stageMove`), so it passes.
    private func requireOfferedTarget(_ target: String?, besides slug: String, catalog: CategoryCatalog) throws {
        guard let target, target != slug else { return }
        guard catalog.activeInOrder().contains(where: { $0.slug == target }) else {
            throw StoreError.invalidMoveTarget
        }
    }

    private func stageMove(from slug: String, to target: String?) throws -> Undo {
        guard let target, target != slug else { return [] }
        var undo: Undo = []
        for task in try tasks(using: slug) {
            let old = task.categoryRaw
            task.categoryRaw = target
            undo.append { task.categoryRaw = old }
        }
        for row in try rows(using: slug) {
            let old = row.categoryRaw
            row.categoryRaw = target
            undo.append { row.categoryRaw = old }
        }
        return undo
    }

    // MARK: Reorder

    /// Applies a `CategoryOrdering.Plan` in one save.
    func apply(_ plan: CategoryOrdering.Plan) throws {
        guard !plan.isEmpty else { return }
        var undo: Undo = []
        do {
            for (slug, index) in plan.updates {
                guard let existing = try row(for: slug) else { continue }
                let old = existing.sortIndex
                existing.sortIndex = index
                undo.append { existing.sortIndex = old }
            }
            for value in plan.creations {
                if try row(for: value.slug) != nil { continue }
                undo.append(insert(value))
            }
        } catch {
            undo.reversed().forEach { $0() }
            throw error
        }
        try commit(undo)
    }

    // MARK: Editor save

    /// Writes an editor draft and returns the slug it saved under.
    /// - Add: mints the slug, inserts through `insertIfFree`, never overwrites.
    /// - Adopt: inserts the stand-in's own slug through `insertIfFree`.
    /// - Edit/Archived: mutates the stored row in place; an untouched built-in gets its row now.
    /// `restoring` also clears `archivedAt` in the same save.
    @discardableResult
    func save(_ draft: CategoryDraft, catalog: CategoryCatalog, restoring: Bool = false,
              random: inout some RandomNumberGenerator) throws -> String {
        let staged = try stageDraft(draft, catalog: catalog, archiveAt: nil, restoring: restoring, random: &random)
        try commit(staged.undo)
        return staged.slug
    }

    @discardableResult
    func save(_ draft: CategoryDraft, catalog: CategoryCatalog, restoring: Bool = false) throws -> String {
        var rng = SystemRandomNumberGenerator()
        return try save(draft, catalog: catalog, restoring: restoring, random: &rng)
    }

    private struct Staged { var slug: String; var undo: Undo }

    private func stageDraft(_ draft: CategoryDraft, catalog: CategoryCatalog, archiveAt: Date?,
                            restoring: Bool, random: inout some RandomNumberGenerator) throws -> Staged {
        var value = draft.value
        value.name = draft.cleanedName
        guard CategoryCatalog.isAcceptableEmoji(value.emoji), CategorySlug.hasContent(value.name) else {
            throw StoreError.nameHasNoContent
        }
        // The editor already disables Save for a duplicate; this is the same rule at the write, so
        // a restore or an adopt can never leave two identical names in one picker. A result that
        // stays archived is not offered, so it cannot collide.
        let staysArchived: Bool
        if archiveAt != nil { staysArchived = true }
        else if case .archived = draft.mode { staysArchived = !restoring }
        else { staysArchived = false }
        if !staysArchived, catalog.validate(name: value.name, editing: draft.mode.slug) != nil {
            throw StoreError.duplicateName
        }

        switch draft.mode {
        case .add:
            guard let slug = CategorySlug.mint(name: value.name, taken: catalog.takenSlugs, random: &random) else {
                throw StoreError.nameHasNoContent
            }
            value.slug = slug
            value.archivedAt = archiveAt
            return Staged(slug: slug, undo: [try insertFree(value)])
        case .adopt(let slug):
            value.slug = slug
            value.archivedAt = archiveAt
            return Staged(slug: slug, undo: [try insertFree(value)])
        case .edit(let slug), .archived(let slug):
            if let existing = try row(for: slug) {
                let old = existing.value
                existing.name = value.name
                existing.emoji = value.emoji
                existing.symbolName = value.symbolName
                existing.paletteIndex = value.paletteIndex
                existing.customColorHex = value.customColorHex
                if restoring { existing.archivedAt = nil }
                if let archiveAt { existing.archivedAt = archiveAt }
                return Staged(slug: slug, undo: [{
                    existing.name = old.name; existing.emoji = old.emoji; existing.symbolName = old.symbolName
                    existing.paletteIndex = old.paletteIndex; existing.customColorHex = old.customColorHex
                    existing.archivedAt = old.archivedAt
                }])
            }
            // An untouched built-in: its row appears on first edit, copying the position it has.
            value.slug = slug
            value.archivedAt = archiveAt
            return Staged(slug: slug, undo: [try insertFree(value)])
        }
    }

    // MARK: Rows

    /// Inserts a row unconditionally (the caller has checked) and returns the way back. Deleting
    /// only this row, not rolling back, leaves unrelated unsaved edits in the context alone.
    private func insert(_ value: CategoryDefinitionValue) -> () -> Void {
        let inserted = CategoryDefinition(value)
        context.insert(inserted)
        return { [context] in context.delete(inserted) }
    }

    private func insertFree(_ value: CategoryDefinitionValue) throws -> () -> Void {
        guard try CategoryDefinition.insertIfFree(value, in: context) else { throw StoreError.slugTaken }
        let target = value.slug
        return { [context] in
            if let stray = try? context.fetch(FetchDescriptor<CategoryDefinition>(
                predicate: #Predicate { $0.slug == target })).first {
                context.delete(stray)
            }
        }
    }

    private func row(for slug: String) throws -> CategoryDefinition? {
        try context.fetch(FetchDescriptor<CategoryDefinition>(predicate: #Predicate { $0.slug == slug })).first
    }
}
