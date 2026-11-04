import Testing
import Foundation
import SwiftData
@testable import Blockey

// Round-2 QA gaps for the slug-carry change: the hop restore -> task/row -> token url,
// and slugs whose characters are special inside a query string.

@Suite("Slug carry, QA round 2")
@MainActor
struct CategorySlugCarryQA2Tests {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TaskItem.self, DayTemplate.self, TemplateRow.self, TemplateAssignment.self, ActivityDay.self, CategoryDefinition.self,
            configurations: config)
        return ModelContext(container)
    }

    @Test("An empty slug restored from a file is stored as empty, reads as the fallback, and yields a token with no c")
    func emptyRestoredSlug() throws {
        let context = try makeContext()
        var backup = BlockeyBackup()
        backup.tasks = [.init(title: "a", estimatedMinutes: 30, category: "", sortIndex: 0)]
        try backup.restore(into: context)
        let task = try #require(try context.fetch(FetchDescriptor<TaskItem>()).first)
        #expect(task.categoryRaw == "")
        #expect(task.category == .fallback)
        let url = try #require(BlockToken(categorySlug: task.categoryRaw).url)
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == nil)
        #expect(BlockToken(url: url)?.categorySlug == nil)
    }

    @Test("Slugs containing query-special characters survive token regeneration verbatim",
          arguments: ["a&b", "a=b", "a+b", "a#b", "100%", "a b", "a?b", "🙂", "x/y"])
    func specialCharacterSlugs(slug: String) throws {
        let token = BlockToken(categorySlug: slug)
        let url = try #require(token.url)
        let parsed = try #require(BlockToken(url: url))
        #expect(parsed.categorySlug == slug.precomposedStringWithCanonicalMapping)
        #expect(parsed.id == token.id)
    }

    @Test("A slug with a trailing space is kept as typed, not trimmed")
    func paddedSlugKept() {
        #expect(BlockToken(categorySlug: " foo").categorySlug == " foo")
    }

    @Test("An unknown row slug flows through categorySlug(forRowID:) into a token unchanged")
    func rowSlugToToken() throws {
        let template = DayTemplate(name: "x")
        let row = TemplateRow(title: "r", startMinuteOfDay: 540, durationMinutes: 30, categoryRaw: "งานบ้าน")
        row.template = template
        template.rows.append(row)
        let url = try #require(BlockToken(categorySlug: template.categorySlug(forRowID: row.id)).url)
        #expect(BlockToken(url: url)?.categorySlug == "งานบ้าน")
    }

    @Test("A block returned to the inbox and placed again keeps its unknown slug")
    func inboxRoundTrip() throws {
        let original = BlockToken(categorySlug: "telepathy", sourceTaskID: UUID())
        let url = try #require(original.url)
        let block = try #require(BlockToken(url: url))
        // Mirrors TodayView.returnToInbox then place.
        let task = TaskItem(title: "t", categoryRaw: block.categorySlug ?? BlockCategory.fallback.rawValue)
        let again = BlockToken(categorySlug: task.categoryRaw, sourceTaskID: task.id)
        #expect(again.categorySlug == "telepathy")
    }

    @Test("The enum init and the slug init of TaskItem agree for every known category", arguments: BlockCategory.allCases)
    func initsAgree(category: BlockCategory) {
        #expect(TaskItem(title: "t", category: category).categoryRaw
                == TaskItem(title: "t", categoryRaw: category.rawValue).categoryRaw)
    }
}
