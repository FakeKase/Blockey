import Testing
import Foundation
import SwiftData
@testable import Blockey

/// Task 3.5. The catalog rules are tested over plain values; this only covers the @Model seam.
@Suite("CategoryDefinition model")
@MainActor
struct CategoryDefinitionModelTests {

    private func context() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self, DayTemplate.self, TemplateRow.self, TemplateAssignment.self,
            ActivityDay.self, CategoryDefinition.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @Test func roundTripsThroughTheValueType() throws {
        let ctx = try context()
        let value = CategoryDefinitionValue.fixture(slug: "u-gym", name: "Gym", emoji: "G", symbolName: "star",
                                                    paletteIndex: 3, customColorHex: "#112233", sortIndex: 7,
                                                    archivedAt: TestDates.today())
        ctx.insert(CategoryDefinition(value))
        try ctx.save()
        let fetched = try ctx.fetch(FetchDescriptor<CategoryDefinition>())
        #expect(fetched.map(\.value) == [value])
    }

    @Test func uniqueSlugUpsertsSoTheCatalogMustCheckFirst() throws {
        // Documents the landmine in ADR 005: a duplicate insert does not throw, it replaces.
        let ctx = try context()
        ctx.insert(CategoryDefinition(.fixture(slug: "u-a", name: "First")))
        try ctx.save()
        ctx.insert(CategoryDefinition(.fixture(slug: "u-a", name: "Second")))
        try ctx.save()
        let rows = try ctx.fetch(FetchDescriptor<CategoryDefinition>())
        #expect(rows.count == 1)
        let catalog = CategoryCatalog(definitions: rows.map(\.value))
        #expect(catalog.isSlugTaken("u-a"))
    }

    @Test func insertIfFreeRefusesATakenSlugAndKeepsTheOriginal() throws {
        let ctx = try context()
        #expect(try CategoryDefinition.insertIfFree(.fixture(slug: "u-a", name: "First"), in: ctx))
        try ctx.save()
        #expect(try CategoryDefinition.insertIfFree(.fixture(slug: "u-a", name: "Second"), in: ctx) == false)
        try ctx.save()
        let rows = try ctx.fetch(FetchDescriptor<CategoryDefinition>())
        #expect(rows.map(\.name) == ["First"])
    }

    @Test func slugAccessorsShareStorageWithCategoryRaw() {
        let task = TaskItem(title: "t", categoryRaw: "u-gym")
        #expect(task.categorySlug == "u-gym")
        task.categorySlug = "u-other"
        #expect(task.categoryRaw == "u-other")
        #expect(task.category == .fallback)   // the enum view stays lossy; the slug does not

        let row = TemplateRow(title: "r", startMinuteOfDay: 0, durationMinutes: 30, categoryRaw: "u-x")
        #expect(row.categorySlug == "u-x")
        row.categorySlug = "rest"
        #expect(row.category == .rest)
    }
}
