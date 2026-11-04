import Testing
import Foundation
import SwiftData
@testable import Blockey

/// QA pass on tasks 3.8 and 3.8b: the write-level guards that the editor's disabled buttons
/// normally make unreachable, and the reorder invariants that need a real store.
@Suite("Category store, QA")
@MainActor
struct CategoryStoreQATests {

    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self, DayTemplate.self, TemplateRow.self, TemplateAssignment.self,
            ActivityDay.self, CategoryDefinition.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func catalog(_ ctx: ModelContext) throws -> CategoryCatalog {
        CategoryCatalog(definitions: try ctx.fetch(FetchDescriptor<CategoryDefinition>()).map(\.value))
    }

    private func rows(_ ctx: ModelContext) throws -> [CategoryDefinition] {
        try ctx.fetch(FetchDescriptor<CategoryDefinition>())
    }

    // MARK: move targets

    @Test func movingOntoAnArchivedCategoryIsRefusedAndMovesNothing() throws {
        let ctx = try context()
        ctx.insert(TaskItem(title: "A", categoryRaw: "admin"))
        ctx.insert(CategoryDefinition(.fixture(slug: "rest", name: "Rest", sortIndex: 5, archivedAt: .now)))
        try ctx.save()
        let c = try catalog(ctx)
        #expect(throws: CategoryStore.StoreError.invalidMoveTarget) {
            try CategoryStore(context: ctx).archive("admin", moveTo: "rest", catalog: c)
        }
        #expect(try ctx.fetch(FetchDescriptor<TaskItem>()).first?.categoryRaw == "admin")
        #expect(try rows(ctx).count == 1)
    }

    @Test func movingOntoAnUnknownSlugIsRefused() throws {
        let ctx = try context()
        ctx.insert(TaskItem(title: "A", categoryRaw: "admin"))
        try ctx.save()
        #expect(throws: CategoryStore.StoreError.invalidMoveTarget) {
            try CategoryStore(context: ctx).archive("admin", moveTo: "u-nowhere", catalog: try catalog(ctx))
        }
        #expect(try ctx.fetch(FetchDescriptor<TaskItem>()).first?.categoryRaw == "admin")
    }

    @Test func archiveFromTheEditorRefusesAnArchivedTargetToo() throws {
        let ctx = try context()
        ctx.insert(TaskItem(title: "A", categoryRaw: "admin"))
        ctx.insert(CategoryDefinition(.fixture(slug: "rest", name: "Rest", sortIndex: 5, archivedAt: .now)))
        try ctx.save()
        let c = try catalog(ctx)
        let draft = try #require(CategoryDraft(mode: .edit(slug: "admin"), catalog: c))
        #expect(throws: CategoryStore.StoreError.invalidMoveTarget) {
            try CategoryStore(context: ctx).saveAndArchive(draft, moveTo: "rest", catalog: c)
        }
        #expect(try rows(ctx).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<TaskItem>()).first?.categoryRaw == "admin")
    }

    // MARK: at least one active

    @Test func saveAndArchiveRefusesTheLastUnarchivedCategory() throws {
        let ctx = try context()
        for slug in CategoryCatalog.builtIns.map(\.slug).dropLast() {
            try CategoryStore(context: ctx).archive(slug, catalog: try catalog(ctx))
        }
        let c = try catalog(ctx)
        var draft = try #require(CategoryDraft(mode: .edit(slug: "rest"), catalog: c))
        draft.setName("Downtime")
        try CategoryStore(context: ctx).saveAndArchive(draft, catalog: c)
        let after = try catalog(ctx)
        #expect(after.activeInOrder().compactMap(\.slug) == ["rest"])
        #expect(after.resolve("rest").name == "Rest")          // refused whole: the rename did not land either
    }

    // MARK: duplicate names at the write

    @Test func restoringAnArchivedCategoryWhoseNameIsNowTakenIsRefused() throws {
        let ctx = try context()
        ctx.insert(CategoryDefinition(.fixture(slug: "u-old", name: "Errands", sortIndex: 9, archivedAt: .now)))
        ctx.insert(CategoryDefinition(.fixture(slug: "u-new", name: "errands", sortIndex: 7)))
        try ctx.save()
        let c = try catalog(ctx)
        let draft = try #require(CategoryDraft(mode: .archived(slug: "u-old"), catalog: c))
        #expect(throws: CategoryStore.StoreError.duplicateName) {
            try CategoryStore(context: ctx).save(draft, catalog: c, restoring: true)
        }
        #expect(try catalog(ctx).resolve("u-old").isArchived)
    }

    @Test func savingAnArchivedCategoryWithoutRestoringMayKeepATakenName() throws {
        let ctx = try context()
        ctx.insert(CategoryDefinition(.fixture(slug: "u-old", name: "Errands", sortIndex: 9, archivedAt: .now)))
        ctx.insert(CategoryDefinition(.fixture(slug: "u-new", name: "Errands", sortIndex: 7)))
        try ctx.save()
        let c = try catalog(ctx)
        var draft = try #require(CategoryDraft(mode: .archived(slug: "u-old"), catalog: c))
        draft.choosePalette(4)
        try CategoryStore(context: ctx).save(draft, catalog: c, restoring: false)
        #expect(try catalog(ctx).resolve("u-old").isArchived)
    }

    @Test func adoptingUnderANameAlreadyInUseIsRefusedAndInsertsNothing() throws {
        let ctx = try context()
        let c = try catalog(ctx)
        var draft = try #require(CategoryDraft(mode: .adopt(slug: "u-meeting"), catalog: c))
        draft.chooseEmoji("\u{1F4DE}")
        #expect(draft.value.name == "meeting")                 // recovered from the slug
        #expect(throws: CategoryStore.StoreError.duplicateName) {
            try CategoryStore(context: ctx).save(draft, catalog: c)
        }
        #expect(try rows(ctx).isEmpty)
    }

    @Test func editingABuiltInOntoAnotherCategorysNameCreatesNoRow() throws {
        let ctx = try context()
        let c = try catalog(ctx)
        var draft = try #require(CategoryDraft(mode: .edit(slug: "admin"), catalog: c))
        draft.setName("  health ")
        #expect(throws: CategoryStore.StoreError.duplicateName) {
            try CategoryStore(context: ctx).save(draft, catalog: c)
        }
        #expect(try rows(ctx).isEmpty)
    }

    @Test func addRefusesAWhitespaceOnlyNameAtTheWrite() throws {
        let ctx = try context()
        let c = try catalog(ctx)
        var draft = try #require(CategoryDraft(mode: .add, catalog: c))
        draft.setName(" \u{00A0}\u{200B}\n")
        draft.chooseEmoji("\u{1F6D2}")
        #expect(throws: CategoryStore.StoreError.nameHasNoContent) {
            try CategoryStore(context: ctx).save(draft, catalog: c)
        }
        #expect(try rows(ctx).isEmpty)
    }

    // MARK: names

    @Test func theNameCapCountsGraphemesSoThaiMarksSurvive() {
        let thai = String(repeating: "\u{0E01}\u{0E33}", count: 24)       // 24 clusters, 48 scalars
        #expect(thai.unicodeScalars.count == 48)
        #expect(CategoryNameField.clamped(thai) == thai)
        #expect(CategoryNameField.clamped(thai + "\u{0E01}\u{0E33}").count == 24)
        #expect(CategoryNameField.clamped(thai + "\u{0E01}\u{0E33}").unicodeScalars.count == 48)
    }

    // MARK: reorder

    @Test func reorderingBuiltInsWithNoRowsGivesEveryActiveCategoryItsOwnPosition() throws {
        let ctx = try context()
        let c = try catalog(ctx)
        let order = ["rest", "deep", "health", "meeting", "personal", "admin"]
        try CategoryStore(context: ctx).apply(CategoryOrdering.plan(newOrder: order, catalog: c))
        let after = try catalog(ctx)
        #expect(after.activeInOrder().compactMap(\.slug) == order)
        let positions = order.compactMap { after.value(for: $0)?.sortIndex }
        #expect(positions == Array(0..<order.count))           // no collision
    }

    @Test func reorderingAfterAnArchiveKeepsTheArchivedOneOutOfTheListAndOrderStable() throws {
        let ctx = try context()
        try CategoryStore(context: ctx).archive("meeting", catalog: try catalog(ctx))
        let c = try catalog(ctx)
        let order = ["rest", "health", "personal", "admin", "deep"]
        try CategoryStore(context: ctx).apply(CategoryOrdering.plan(newOrder: order, catalog: c))
        let after = try catalog(ctx)
        #expect(after.activeInOrder().compactMap(\.slug) == order)
        #expect(after.archived().compactMap(\.slug) == ["meeting"])
        #expect(after.resolve("meeting").isArchived)
    }

    @Test func aNewCategoryAfterAReorderLandsLast() throws {
        let ctx = try context()
        let c = try catalog(ctx)
        try CategoryStore(context: ctx).apply(
            CategoryOrdering.plan(newOrder: ["rest", "health", "personal", "admin", "meeting", "deep"], catalog: c))
        let c2 = try catalog(ctx)
        var draft = try #require(CategoryDraft(mode: .add, catalog: c2))
        draft.setName("Errands")
        draft.chooseEmoji("\u{1F6D2}")
        let slug = try CategoryStore(context: ctx).save(draft, catalog: c2)
        #expect(try catalog(ctx).activeInOrder().compactMap(\.slug).last == slug)
    }

    // MARK: defaults

    @Test func newWorkStartsOnTheFirstOfferedCategoryOnceDeepIsArchived() throws {
        let ctx = try context()
        try CategoryStore(context: ctx).archive("deep", catalog: try catalog(ctx))
        #expect(try catalog(ctx).defaultSlugForNewWork == "meeting")
    }
}
