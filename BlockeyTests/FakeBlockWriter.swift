import Foundation
@testable import Blockey

/// An in-memory `BlockWriting`: blocks live in an array, fixed events are set by the test, and
/// failures can be injected per call. It is the stand-in for a real event store that Undo
/// tests will need as well.
@MainActor
final class FakeBlockWriter: BlockWriting {
    struct Failure: Error, LocalizedError {
        var errorDescription: String? { "injected failure" }
    }

    var blocks: [Block] = []
    var fixed: [Block] = []

    /// Zero-based indexes of `createBlock` calls that throw.
    var failCreateAtCalls: Set<Int> = []
    var failAllDeletes = false
    var failDeleteAll = false

    private(set) var createCalls = 0
    private(set) var created: [(title: String, range: TimeRange, slug: String?, source: UUID?, alarm: Int?)] = []

    func addFixed(_ title: String, _ range: TimeRange) {
        fixed.append(Block(title: title, range: range, kind: .fixed))
    }

    /// A block as the calendar would hold it, token included unless `tokenless`.
    @discardableResult
    func seedBlock(_ title: String, _ range: TimeRange, slug: String? = "deep",
                   source: UUID? = nil, tokenless: Bool = false) -> Block {
        let token = tokenless ? nil : BlockToken(categorySlug: slug, sourceTaskID: source)
        let block = Block(title: title, range: range, kind: .block(token))
        blocks.append(block)
        return block
    }

    func createBlock(title: String, range: TimeRange, categorySlug: String?,
                     sourceTaskID: UUID?, alarmMinutesBefore: Int?) throws -> Block {
        defer { createCalls += 1 }
        if failCreateAtCalls.contains(createCalls) { throw Failure() }
        created.append((title, range, categorySlug, sourceTaskID, alarmMinutesBefore))
        let block = Block(title: title, range: range,
                          kind: .block(BlockToken(categorySlug: categorySlug, sourceTaskID: sourceTaskID)))
        blocks.append(block)
        return block
    }

    func delete(_ block: Block) throws {
        if failAllDeletes { throw Failure() }
        blocks.removeAll { $0.id == block.id }
    }

    func deleteAllBlocks(on date: Date, calendar: Calendar) throws -> [Block] {
        if failDeleteAll { throw Failure() }
        let day = calendar.startOfDay(for: date)
        let removed = blocks.filter { calendar.isDate($0.range.start, inSameDayAs: day) }
        blocks.removeAll { block in removed.contains { $0.id == block.id } }
        return removed
    }

    func contents(for date: Date, ignoring hiddenCalendarIDs: Set<String>, calendar: Calendar) -> DayContents {
        DayContents(blocks: blocks.sorted { $0.range.start < $1.range.start },
                    fixed: fixed.sorted { $0.range.start < $1.range.start })
    }
}
