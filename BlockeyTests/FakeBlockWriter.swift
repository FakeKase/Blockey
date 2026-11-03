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

    /// Which calendar each fixed event lives in, by block id. Only set when a test names one;
    /// the real service hides fixed events whose calendar is in `hiddenCalendarIDs`, and ours
    /// is never hidden.
    private var calendarIDs: [String: String] = [:]

    @discardableResult
    func addFixed(_ title: String, _ range: TimeRange, allDay: Bool = false,
                  calendarID: String? = nil) -> Block {
        let block = Block(title: title, range: range, kind: .fixed, isAllDay: allDay)
        if let calendarID { calendarIDs[block.id] = calendarID }
        fixed.append(block)
        return block
    }

    /// A block as the calendar would hold it, token included unless `tokenless`.
    @discardableResult
    func seedBlock(_ title: String, _ range: TimeRange, slug: String? = "deep",
                   source: UUID? = nil, tokenless: Bool = false,
                   allDay: Bool = false, isEditable: Bool? = nil) -> Block {
        let token = tokenless ? nil : BlockToken(categorySlug: slug, sourceTaskID: source)
        let block = Block(title: title, range: range, kind: .block(token), isAllDay: allDay,
                          eventIdentifier: UUID().uuidString, isEditable: isEditable)
        blocks.append(block)
        return block
    }

    func createBlock(title: String, range: TimeRange, categorySlug: String?,
                     sourceTaskID: UUID?, alarmMinutesBefore: Int?) throws -> Block {
        defer { createCalls += 1 }
        if failCreateAtCalls.contains(createCalls) { throw Failure() }
        created.append((title, range, categorySlug, sourceTaskID, alarmMinutesBefore))
        let block = Block(title: title, range: range,
                          kind: .block(BlockToken(categorySlug: categorySlug, sourceTaskID: sourceTaskID)),
                          eventIdentifier: UUID().uuidString)
        blocks.append(block)
        return block
    }

    /// Like the real service, refuses anything it may not rewrite (recurring, all-day, or
    /// spanning a whole day).
    func delete(_ block: Block) throws {
        if failAllDeletes { throw Failure() }
        guard block.isEditable else { throw Failure() }
        blocks.removeAll { $0.id == block.id }
    }

    /// Mirrors `CalendarService.deleteAllBlocks`: anything in our calendar that overlaps the
    /// day (so a block spanning midnight counts from either side), except all-day events
    /// (not blocks; the signing reminder is one) and anything not editable (recurring,
    /// multi-day), which the real service leaves alone.
    func deleteAllBlocks(on date: Date, calendar: Calendar) throws -> [Block] {
        if failDeleteAll { throw Failure() }
        let day = Self.dayRange(of: date, calendar)
        let removed = blocks.filter { !$0.isAllDay && $0.isEditable && $0.range.overlaps(day) }
        blocks.removeAll { block in removed.contains { $0.id == block.id } }
        return removed
    }

    /// Mirrors `CalendarService.contents`: EventKit's predicate matches by overlap with the
    /// day, all-day events become banners, and fixed events from hidden calendars are skipped.
    func contents(for date: Date, ignoring hiddenCalendarIDs: Set<String>, calendar: Calendar) -> DayContents {
        let day = Self.dayRange(of: date, calendar)
        func onDay(_ b: Block) -> Bool { b.range.overlaps(day) }
        let visibleFixed = fixed.filter { block in
            guard let id = calendarIDs[block.id] else { return true }
            return !hiddenCalendarIDs.contains(id)
        }
        let all = (blocks + visibleFixed).filter(onDay)
        func sorted(_ list: [Block]) -> [Block] { list.sorted { $0.range.start < $1.range.start } }
        return DayContents(blocks: sorted(all.filter { !$0.isAllDay && !$0.isFixed }),
                           fixed: sorted(all.filter { !$0.isAllDay && $0.isFixed }),
                           allDay: sorted(all.filter(\.isAllDay)))
    }

    private static func dayRange(of date: Date, _ calendar: Calendar) -> TimeRange {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return TimeRange(start: start, end: end)
    }
}
