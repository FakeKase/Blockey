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
    /// Makes `applyUndo` throw before it touches anything.
    var failApplyUndo = false
    /// Zero-based indexes into `UndoBatch.create` that throw while the batch is being staged,
    /// i.e. after the removals have already been staged. The batch must then change nothing.
    var failUndoCreateAt: Set<Int> = []

    /// The last batch `applyUndo` was handed, so a test can check the day it searched.
    private(set) var lastUndoBatch: UndoBatch?

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
                   allDay: Bool = false, isEditable: Bool? = nil,
                   token explicitToken: BlockToken? = nil,
                   notes: String? = nil, alarmOffsets: [TimeInterval] = []) -> Block {
        let token = tokenless ? nil : (explicitToken ?? BlockToken(categorySlug: slug, sourceTaskID: source))
        let block = Block(title: title, range: range, kind: .block(token), isAllDay: allDay,
                          eventIdentifier: UUID().uuidString, isEditable: isEditable,
                          notes: notes, alarmOffsets: alarmOffsets.sorted())
        blocks.append(block)
        return block
    }

    // MARK: Things the user does in Calendar.app, for Undo tests

    /// Moves a block to a new time, as dragging it in Calendar.app would.
    func move(_ block: Block, to range: TimeRange) {
        guard let i = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        blocks[i].range = range
    }

    /// Strips the token, as a CalDAV round trip or clearing the URL field would. The event
    /// stays; it just can no longer be found by token.
    func stripToken(of block: Block) {
        guard let i = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        blocks[i].kind = .block(nil)
    }

    /// Makes a block something Blockey may not rewrite, as making it recurring in Calendar.app does.
    func makeRecurring(_ block: Block) {
        guard let i = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        blocks[i].isEditable = false
    }

    /// Deletes a block, as the user would in Calendar.app.
    func userDeletes(_ block: Block) {
        blocks.removeAll { $0.id == block.id }
    }

    /// Gives every block a new identifier, as a sync that re-creates events would. Tokens
    /// survive; `eventIdentifier` does not.
    func reidentifyAll() {
        for i in blocks.indices {
            blocks[i].id = UUID().uuidString
            blocks[i].eventIdentifier = UUID().uuidString
        }
    }

    // MARK: BlockWriting

    /// Mirrors `CalendarService.createBlock(token:)`: the token is written verbatim, and nil
    /// writes no url at all.
    func createBlock(title: String, range: TimeRange, token: BlockToken?,
                     notes: String?, alarmOffsets: [TimeInterval]) throws -> Block {
        defer { createCalls += 1 }
        if failCreateAtCalls.contains(createCalls) { throw Failure() }
        let block = Block(title: title, range: range, kind: .block(token),
                          eventIdentifier: UUID().uuidString, notes: notes, alarmOffsets: alarmOffsets.sorted())
        blocks.append(block)
        return block
    }

    /// Mirrors `CalendarService.applyUndo`: blocks are found by token over the recorded day
    /// (never by identifier), a block that cannot be found is reported and not deleted, and
    /// the whole batch lands or none of it does. Staging happens on a copy that replaces
    /// `blocks` only at the end, which is what `commit: false` plus `store.reset()` gives
    /// the real service.
    func applyUndo(_ batch: UndoBatch, calendar: Calendar) throws -> UndoApplied {
        lastUndoBatch = batch
        if failApplyUndo { throw Failure() }
        let day = Self.dayRange(of: batch.day, calendar)
        var staged = blocks
        var removed: [UUID] = []
        var leftAlone: [UUID] = []
        var seen = Set<UUID>()
        for id in batch.removeTokenIDs where seen.insert(id).inserted {
            // The earliest match, as the real service picks, so a duplicated token is handled
            // the same way in both.
            let match = staged.indices
                .filter { staged[$0].token?.id == id && staged[$0].range.overlaps(day) }
                .min { staged[$0].range.start < staged[$1].range.start }
            if let i = match {
                // Same refusal as the real service: not editable means left alone.
                if staged[i].isEditable {
                    staged.remove(at: i)
                    removed.append(id)
                } else {
                    leftAlone.append(id)
                }
            }
        }
        var created: [Block] = []
        for (index, draft) in batch.create.enumerated() {
            if failUndoCreateAt.contains(index) { throw Failure() }
            let block = Block(title: draft.title, range: draft.range, kind: .block(draft.token),
                              eventIdentifier: UUID().uuidString,
                              notes: draft.notes, alarmOffsets: draft.alarmOffsets.sorted())
            staged.append(block)
            created.append(block)
        }
        blocks = staged
        return UndoApplied(removed: removed, leftAlone: leftAlone, created: created)
    }

    /// Mirrors `CalendarService.existingTokenIDs`: by token, within `days` days either side.
    func existingTokenIDs(_ ids: Set<UUID>, around day: Date, days: Int, calendar: Calendar) -> Set<UUID> {
        let start = calendar.startOfDay(for: day)
        guard let from = calendar.date(byAdding: .day, value: -days, to: start),
              let to = calendar.date(byAdding: .day, value: days + 1, to: start) else { return [] }
        let span = TimeRange(start: from, end: to)
        return ids.intersection(blocks.filter { $0.range.overlaps(span) }.compactMap { $0.token?.id })
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
