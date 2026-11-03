import Testing
import Foundation
import SwiftData
@testable import Blockey

// A slug this build doesn't know must survive every hop that used to go through the
// BlockCategory enum (and so collapse to Deep work): inbox tasks, template rows, restore.

@Suite("Unknown category slugs are carried verbatim")
@MainActor
struct CategorySlugCarryTests {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TaskItem.self, DayTemplate.self, TemplateRow.self, TemplateAssignment.self, ActivityDay.self,
            configurations: config)
        return ModelContext(container)
    }

    @Test("TaskItem built from a raw slug keeps it, while category reads as the fallback")
    func taskItemRawSlugInit() {
        let task = TaskItem(title: "t", categoryRaw: "งานบ้าน")
        #expect(task.categoryRaw == "งานบ้าน")
        #expect(task.category == .fallback)
        // The enum init is unchanged.
        #expect(TaskItem(title: "t", category: .rest).categoryRaw == BlockCategory.rest.rawValue)
    }

    @Test("TemplateRow built from a raw slug keeps it, and the template reports it by row id")
    func templateRowRawSlug() {
        let template = DayTemplate(name: "x")
        let row = TemplateRow(title: "r", startMinuteOfDay: 540, durationMinutes: 30, categoryRaw: "telepathy")
        row.template = template
        template.rows.append(row)
        #expect(template.categorySlug(forRowID: row.id) == "telepathy")
        #expect(template.category(forRowID: row.id) == .fallback)
        #expect(template.categorySlug(forRowID: UUID()) == BlockCategory.fallback.rawValue)
    }

    @Test("Restore keeps unknown slugs verbatim on tasks and template rows")
    func restoreKeepsUnknownSlugsVerbatim() throws {
        let context = try makeContext()
        var backup = BlockeyBackup()
        backup.tasks = [.init(title: "a", estimatedMinutes: 30, category: "telepathy", sortIndex: 0),
                        .init(title: "b", estimatedMinutes: 30, category: "rest", sortIndex: 1)]
        backup.templates = [.init(id: UUID(), name: "T", rows: [
            .init(title: "r", startMinuteOfDay: 540, durationMinutes: 30, category: "งานบ้าน")])]

        try backup.restore(into: context)

        let tasks = try context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.sortIndex)]))
        #expect(tasks.map(\.categoryRaw) == ["telepathy", "rest"])
        let rows = try context.fetch(FetchDescriptor<TemplateRow>())
        #expect(rows.map(\.categoryRaw) == ["งานบ้าน"])
    }
}
