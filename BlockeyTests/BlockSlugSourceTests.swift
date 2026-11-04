import Testing
import Foundation
@testable import Blockey

// Task 3.6: the slug is the source of truth on Block and on every write path. These pin that a
// slug this build does not know survives reading a Block, preparing an update, and the detail
// sheet's save decision, none of which may go through the closed BlockCategory enum.
@Suite("Block carries the slug, not the enum")
struct BlockSlugSourceTests {

    private func block(slug: String?) -> Block {
        let range = TimeRange(start: TestDates.ordinaryDay(), duration: 1800)
        let token = slug.map { BlockToken(categorySlug: $0) } ?? BlockToken(categorySlug: nil)
        return Block(title: "b", range: range, kind: .block(token))
    }

    @Test("categorySlug returns an unknown slug verbatim while category derives the fallback")
    func unknownSlugVerbatim() {
        let b = block(slug: "u-งานบ้าน")
        #expect(b.categorySlug == "u-งานบ้าน")
        #expect(b.category == .fallback)
    }

    @Test("categorySlug is nil for a tokenless block and for a fixed event")
    func nilSlugCases() {
        let range = TimeRange(start: TestDates.ordinaryDay(), duration: 1800)
        #expect(Block(title: "x", range: range, kind: .block(nil)).categorySlug == nil)
        #expect(Block(title: "x", range: range, kind: .fixed).categorySlug == nil)
        #expect(block(slug: nil).categorySlug == nil)
    }

    @Test("Known slugs agree with the derived enum", arguments: BlockCategory.allCases)
    func knownSlugsAgree(category: BlockCategory) {
        let b = block(slug: category.rawValue)
        #expect(b.categorySlug == category.rawValue)
        #expect(b.category == category)
    }

    @Test("Updating the slug keeps id, source task and unknown query items")
    func updatedTokenKeepsIdentity() throws {
        let id = UUID(), task = UUID()
        let url = try #require(URL(string: "blockey://block/\(id.uuidString)?c=u-old&t=\(task.uuidString)&future=1"))
        let original = try #require(BlockToken(url: url))
        let updated = original.replacingCategorySlug("u-new")
        #expect(updated.categorySlug == "u-new")
        #expect(updated.id == id && updated.sourceTaskID == task)
        let reparsed = try #require(BlockToken(url: try #require(updated.url)))
        #expect(reparsed == updated)
        #expect(updated.url?.absoluteString.contains("future=1") == true)
    }

    @Test("The detail sheet saves a slug only when the pick changed")
    func sheetSaveDecision() {
        #expect(BlockDetailSheet.slugToSave(initial: .deepWork, current: .deepWork) == nil)
        #expect(BlockDetailSheet.slugToSave(initial: .deepWork, current: .rest) == BlockCategory.rest.rawValue)
    }

    @Test("A replaced Thai or delimiter-bearing slug survives url write and re-parse",
          arguments: ["u-งานบ้าน", "u-a&b=c", "u-a+b", "u-100%", "u-x#y"])
    func replacedSlugRoundTrips(slug: String) throws {
        let id = UUID(), task = UUID()
        let url = try #require(URL(string: "blockey://block/\(id.uuidString)?c=work&t=\(task.uuidString)&future=1"))
        let updated = try #require(BlockToken(url: url)).replacingCategorySlug(slug)
        let reparsed = try #require(BlockToken(url: try #require(updated.url)))
        #expect(reparsed.categorySlug == slug.precomposedStringWithCanonicalMapping)
        #expect(reparsed.id == id && reparsed.sourceTaskID == task)
        #expect(reparsed.unknownQueryItems == updated.unknownQueryItems)
    }

    @Test("Saving a block with an unknown slug and no category pick passes no slug")
    func untouchedUnknownSlugPassesNil() {
        let b = block(slug: "u-งานบ้าน")
        #expect(BlockDetailSheet.slugToSave(initial: b.category, current: b.category) == nil)
    }
}
