import Testing
import Foundation
import SwiftData
@testable import Blockey

/// Tasks 3.8 and 3.8b, the multi-store parts: archive with an optional move, restore, reorder
/// and the editor's save, against an in-memory store. Includes the missing A.4 test
/// `archivingMovesTasksAndRowsOnlyWhenChosen`.
@Suite("Category store")
@MainActor
struct CategoryStoreTests {

    private struct SaveFailed: Error {}

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

    /// Two inbox tasks and one template row on `admin`, one task on `deep`.
    private func seed(_ ctx: ModelContext) throws {
        ctx.insert(TaskItem(title: "A", categoryRaw: "admin"))
        ctx.insert(TaskItem(title: "B", categoryRaw: "admin"))
        ctx.insert(TaskItem(title: "C", categoryRaw: "deep"))
        let template = DayTemplate(name: "Workday")
        ctx.insert(template)
        let row = TemplateRow(title: "Email", startMinuteOfDay: 540, durationMinutes: 30, categoryRaw: "admin")
        row.template = template
        ctx.insert(row)
        try ctx.save()
    }

    private func slugs(_ ctx: ModelContext) throws -> (tasks: [String], rows: [String]) {
        (try ctx.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.title)])).map(\.categoryRaw),
         try ctx.fetch(FetchDescriptor<TemplateRow>()).map(\.categoryRaw))
    }

    // MARK: usage

    @Test func usageCountsTasksAndRowsBySlug() throws {
        let ctx = try context()
        try seed(ctx)
        let store = CategoryStore(context: ctx)
        #expect(try store.usage(of: "admin") == .init(tasks: 2, rows: 1))
        #expect(try store.usage(of: "deep") == .init(tasks: 1, rows: 0))
        #expect(try store.usage(of: "rest").total == 0)
    }

    @Test func aBlankSlugCountsAsTheFallback() throws {
        let ctx = try context()
        ctx.insert(TaskItem(title: "A", categoryRaw: "  "))
        try ctx.save()
        #expect(try CategoryStore(context: ctx).usage(of: "deep").tasks == 1)
    }

    // MARK: archive (A.4)

    @Test func archivingMovesTasksAndRowsOnlyWhenChosen() throws {
        // Declined: archive without moving. Nothing that used it is touched.
        let declined = try context()
        try seed(declined)
        try CategoryStore(context: declined).archive("admin", moveTo: nil, catalog: try catalog(declined))
        #expect(try slugs(declined).tasks == ["admin", "admin", "deep"])
        #expect(try slugs(declined).rows == ["admin"])
        #expect(try catalog(declined).resolve("admin").isArchived)

        // Chosen: all of them move, in the same save as the archive.
        let chosen = try context()
        try seed(chosen)
        try CategoryStore(context: chosen).archive("admin", moveTo: "personal", catalog: try catalog(chosen))
        #expect(try slugs(chosen).tasks == ["personal", "personal", "deep"])
        #expect(try slugs(chosen).rows == ["personal"])
        #expect(try catalog(chosen).resolve("admin").isArchived)
    }

    @Test func archivingAnUntouchedBuiltInCreatesItsRowAtItsPosition() throws {
        let ctx = try context()
        try CategoryStore(context: ctx).archive("admin", catalog: try catalog(ctx))
        let rows = try ctx.fetch(FetchDescriptor<CategoryDefinition>())
        #expect(rows.map(\.slug) == ["admin"])
        #expect(rows.first?.sortIndex == 2)
        #expect(rows.first?.name == "Admin")
        #expect(rows.first?.archivedAt != nil)
    }

    @Test func archivingACustomSetsTheDateOnItsRow() throws {
        let ctx = try context()
        ctx.insert(CategoryDefinition(.fixture(slug: "u-a", name: "A", sortIndex: 6)))
        try ctx.save()
        let now = TestDates.today()
        try CategoryStore(context: ctx).archive("u-a", catalog: try catalog(ctx), now: now)
        #expect(try ctx.fetch(FetchDescriptor<CategoryDefinition>()).first?.archivedAt == now)
    }

    @Test func theLastUnarchivedCategoryCannotBeArchived() throws {
        let ctx = try context()
        let builtIns = CategoryCatalog.builtIns.map(\.slug)
        for slug in builtIns.dropLast() {
            try CategoryStore(context: ctx).archive(slug, catalog: try catalog(ctx))
        }
        let last = try #require(builtIns.last)
        #expect(!(try catalog(ctx)).canArchive(last))
        try CategoryStore(context: ctx).archive(last, catalog: try catalog(ctx))   // refused, silently
        #expect(try catalog(ctx).activeInOrder().count == 1)
    }

    @Test func aFailedSaveLeavesEverythingAsItWas() throws {
        let ctx = try context()
        try seed(ctx)
        let store = CategoryStore(context: ctx, save: { throw SaveFailed() })
        #expect(throws: SaveFailed.self) {
            try store.archive("admin", moveTo: "personal", catalog: try catalog(ctx))
        }
        #expect(try slugs(ctx).tasks == ["admin", "admin", "deep"])
        #expect(try slugs(ctx).rows == ["admin"])
        #expect(try catalog(ctx).resolve("admin").isArchived == false)
        #expect(try ctx.fetch(FetchDescriptor<CategoryDefinition>()).isEmpty)
    }

    @Test func movingToTheSameCategoryIsIgnored() throws {
        let ctx = try context()
        try seed(ctx)
        try CategoryStore(context: ctx).archive("admin", moveTo: "admin", catalog: try catalog(ctx))
        #expect(try slugs(ctx).tasks == ["admin", "admin", "deep"])
    }

    // MARK: restore

    @Test func restoreClearsTheDateAndKeepsThePosition() throws {
        let ctx = try context()
        try CategoryStore(context: ctx).archive("rest", catalog: try catalog(ctx))
        try CategoryStore(context: ctx).restore("rest")
        let row = try #require(try ctx.fetch(FetchDescriptor<CategoryDefinition>()).first)
        #expect(row.archivedAt == nil && row.sortIndex == 5)
        #expect(!(try catalog(ctx)).resolve("rest").isArchived)
    }

    @Test func restoreWithoutARowThrows() throws {
        let ctx = try context()
        #expect(throws: CategoryStore.StoreError.notFound) { try CategoryStore(context: ctx).restore("deep") }
    }

    @Test func aFailedRestoreStaysArchived() throws {
        let ctx = try context()
        ctx.insert(CategoryDefinition(.fixture(slug: "u-a", name: "A", sortIndex: 6, archivedAt: TestDates.today())))
        try ctx.save()
        let store = CategoryStore(context: ctx, save: { throw SaveFailed() })
        #expect(throws: SaveFailed.self) { try store.restore("u-a") }
        #expect(try ctx.fetch(FetchDescriptor<CategoryDefinition>()).first?.archivedAt != nil)
    }

    // MARK: reorder

    @Test func aMoveWritesAllChangesInOneSaveAndTheCatalogFollows() throws {
        let ctx = try context()
        ctx.insert(CategoryDefinition(.fixture(slug: "u-a", name: "Alpha", sortIndex: 6)))
        try ctx.save()
        let before = try catalog(ctx)
        let order = try #require(CategoryOrdering.moved(before.activeInOrder().compactMap(\.slug), slug: "u-a", by: -1))
        var saves = 0
        let store = CategoryStore(context: ctx, save: { saves += 1; try ctx.save() })
        try store.apply(CategoryOrdering.plan(newOrder: order, catalog: before))
        #expect(saves == 1)
        let after = try catalog(ctx)
        #expect(after.activeInOrder().compactMap(\.slug) == order)
        #expect(order.suffix(2) == ["u-a", "rest"])
    }

    @Test func aFailedReorderPutsIndexesBackAndInsertsNothing() throws {
        let ctx = try context()
        ctx.insert(CategoryDefinition(.fixture(slug: "u-a", name: "Alpha", sortIndex: 6)))
        try ctx.save()
        let before = try catalog(ctx)
        let order = try #require(CategoryOrdering.moved(before.activeInOrder().compactMap(\.slug), slug: "u-a", by: -1))
        let store = CategoryStore(context: ctx, save: { throw SaveFailed() })
        #expect(throws: SaveFailed.self) { try store.apply(CategoryOrdering.plan(newOrder: order, catalog: before)) }
        let rows = try ctx.fetch(FetchDescriptor<CategoryDefinition>())
        #expect(rows.map(\.slug) == ["u-a"] && rows.first?.sortIndex == 6)
    }

    // MARK: editor save

    @Test func addMintsASlugInsertsOnceAndSortsLast() throws {
        let ctx = try context()
        let c = try catalog(ctx)
        var draft = try #require(CategoryDraft(mode: .add, catalog: c))
        draft.setName("  Errands ")
        draft.chooseEmoji("\u{1F6D2}")
        let slug = try CategoryStore(context: ctx).save(draft, catalog: c)
        #expect(slug == "u-errands")
        let row = try #require(try ctx.fetch(FetchDescriptor<CategoryDefinition>()).first)
        #expect(row.name == "Errands" && row.sortIndex == 6 && row.symbolName == "cart.fill")
        #expect(try catalog(ctx).activeInOrder().last?.slug == "u-errands")
    }

    @Test func addNeverOverwritesATakenSlug() throws {
        let ctx = try context()
        ctx.insert(CategoryDefinition(.fixture(slug: "u-errands", name: "Original", sortIndex: 6)))
        try ctx.save()
        // A catalog that does not know the slug is taken, as a stale sheet would hold.
        let stale = CategoryCatalog(definitions: [])
        var draft = try #require(CategoryDraft(mode: .add, catalog: stale))
        draft.setName("Errands")
        draft.chooseEmoji("\u{1F6D2}")
        #expect(throws: CategoryStore.StoreError.slugTaken) { try CategoryStore(context: ctx).save(draft, catalog: stale) }
        #expect(try ctx.fetch(FetchDescriptor<CategoryDefinition>()).map(\.name) == ["Original"])
    }

    @Test func twoCategoriesWithTheSameFoldedNameGetDistinctSlugs() throws {
        let ctx = try context()
        var c = try catalog(ctx)
        var made: [String] = []
        for name in ["Gym", "GYM!"] {
            var draft = try #require(CategoryDraft(mode: .add, catalog: c))
            draft.setName(name)
            draft.chooseEmoji("\u{1F3CB}\u{FE0F}")
            made.append(try CategoryStore(context: ctx).save(draft, catalog: c))
            c = try catalog(ctx)
        }
        #expect(made == ["u-gym", "u-gym-2"])
    }

    @Test func editMutatesTheRowInPlaceAndKeepsPositionAndArchiveState() throws {
        let ctx = try context()
        ctx.insert(CategoryDefinition(.fixture(slug: "u-a", name: "Alpha", sortIndex: 9, archivedAt: TestDates.today())))
        try ctx.save()
        let c = try catalog(ctx)
        var draft = try #require(CategoryDraft(mode: .archived(slug: "u-a"), catalog: c))
        draft.setName("Beta")
        draft.choosePalette(4)
        try CategoryStore(context: ctx).save(draft, catalog: c)
        let rows = try ctx.fetch(FetchDescriptor<CategoryDefinition>())
        #expect(rows.count == 1)
        #expect(rows.first?.name == "Beta" && rows.first?.paletteIndex == 4)
        #expect(rows.first?.sortIndex == 9 && rows.first?.archivedAt != nil)
    }

    @Test func restoringSavesTheDraftAndClearsArchivedAtInOneWrite() throws {
        let ctx = try context()
        ctx.insert(CategoryDefinition(.fixture(slug: "u-a", name: "Alpha", sortIndex: 9, archivedAt: TestDates.today())))
        try ctx.save()
        let c = try catalog(ctx)
        var draft = try #require(CategoryDraft(mode: .archived(slug: "u-a"), catalog: c))
        draft.setName("Alpha two")
        try CategoryStore(context: ctx).save(draft, catalog: c, restoring: true)
        let row = try #require(try ctx.fetch(FetchDescriptor<CategoryDefinition>()).first)
        #expect(row.name == "Alpha two" && row.archivedAt == nil)
    }

    @Test func editingAnUntouchedBuiltInCreatesItsRowCopyingItsPosition() throws {
        let ctx = try context()
        let c = try catalog(ctx)
        var draft = try #require(CategoryDraft(mode: .edit(slug: "health"), catalog: c))
        draft.choosePalette(7)
        #expect(try CategoryStore(context: ctx).save(draft, catalog: c) == "health")
        let row = try #require(try ctx.fetch(FetchDescriptor<CategoryDefinition>()).first)
        #expect(row.slug == "health" && row.sortIndex == 4 && row.paletteIndex == 7 && row.name == "Health")
        #expect(try catalog(ctx).resolve("health").colorChoice == .palette(7))
    }

    @Test func resetKeepsTheRowAndWritesFactoryValues() throws {
        let ctx = try context()
        ctx.insert(CategoryDefinition(.fixture(slug: "admin", name: "Paperwork", emoji: "\u{1F4DA}",
                                               symbolName: "books.vertical.fill", paletteIndex: 7,
                                               customColorHex: "#112233", sortIndex: 0)))
        try ctx.save()
        let c = try catalog(ctx)
        var draft = try #require(CategoryDraft(mode: .edit(slug: "admin"), catalog: c))
        draft.resetToDefault()
        try CategoryStore(context: ctx).save(draft, catalog: c)
        let row = try #require(try ctx.fetch(FetchDescriptor<CategoryDefinition>()).first)
        #expect(row.name == "Admin" && row.paletteIndex == 2 && row.customColorHex == nil)
        #expect(row.sortIndex == 0)                  // position survives the reset (Q3)
    }

    @Test func adoptInsertsTheStandInsOwnSlugAndNothingElseChanges() throws {
        let ctx = try context()
        let c = try catalog(ctx)
        var draft = try #require(CategoryDraft(mode: .adopt(slug: "u-errands"), catalog: c))
        draft.setName("Errands")
        draft.chooseEmoji("\u{1F6D2}")
        #expect(try CategoryStore(context: ctx).save(draft, catalog: c) == "u-errands")
        let after = try catalog(ctx)
        #expect(after.resolve("u-errands").origin == .custom && after.resolve("u-errands").name == "Errands")
        #expect(after.resolve("u-errands").colorChoice == c.resolve("u-errands").colorChoice)
    }

    @Test func aFailedAddLeavesNoRowBehind() throws {
        let ctx = try context()
        let c = try catalog(ctx)
        var draft = try #require(CategoryDraft(mode: .add, catalog: c))
        draft.setName("Errands")
        draft.chooseEmoji("\u{1F6D2}")
        #expect(throws: SaveFailed.self) { try CategoryStore(context: ctx, save: { throw SaveFailed() }).save(draft, catalog: c) }
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<CategoryDefinition>()).isEmpty)
    }

    @Test func aFailedEditPutsTheFieldsBack() throws {
        let ctx = try context()
        ctx.insert(CategoryDefinition(.fixture(slug: "u-a", name: "Alpha", sortIndex: 6)))
        try ctx.save()
        let c = try catalog(ctx)
        var draft = try #require(CategoryDraft(mode: .edit(slug: "u-a"), catalog: c))
        draft.setName("Beta")
        #expect(throws: SaveFailed.self) { try CategoryStore(context: ctx, save: { throw SaveFailed() }).save(draft, catalog: c) }
        #expect(try ctx.fetch(FetchDescriptor<CategoryDefinition>()).first?.name == "Alpha")
    }

    // MARK: save and archive in one write

    @Test func archiveFromTheEditorSavesTheDraftAndArchivesInOneSave() throws {
        let ctx = try context()
        try seed(ctx)
        let c = try catalog(ctx)
        var draft = try #require(CategoryDraft(mode: .edit(slug: "admin"), catalog: c))
        draft.setName("Paperwork")
        var saves = 0
        let store = CategoryStore(context: ctx, save: { saves += 1; try ctx.save() })
        try store.saveAndArchive(draft, moveTo: "personal", catalog: c)
        #expect(saves == 1)
        let after = try catalog(ctx)
        #expect(after.resolve("admin").isArchived && after.resolve("admin").name == "Paperwork")
        #expect(try slugs(ctx).tasks == ["personal", "personal", "deep"])
        #expect(try ctx.fetch(FetchDescriptor<CategoryDefinition>()).count == 1)   // one row, not two
    }

    @Test func aFailedArchiveFromTheEditorChangesNothing() throws {
        let ctx = try context()
        try seed(ctx)
        let c = try catalog(ctx)
        var draft = try #require(CategoryDraft(mode: .edit(slug: "admin"), catalog: c))
        draft.setName("Paperwork")
        let store = CategoryStore(context: ctx, save: { throw SaveFailed() })
        #expect(throws: SaveFailed.self) { try store.saveAndArchive(draft, moveTo: "personal", catalog: c) }
        #expect(try slugs(ctx).tasks == ["admin", "admin", "deep"])
        #expect(try ctx.fetch(FetchDescriptor<CategoryDefinition>()).isEmpty)
    }
}
