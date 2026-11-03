import Foundation

/// The slice of the calendar the day-planning coordinator needs, and nothing else.
///
/// A protocol so `DayPlanner` can be tested against an in-memory fake instead of a real event
/// store, which is the only way Undo (issue #3, tasks 2.2 onwards) can be tested at all. It
/// deliberately names no EventKit type: `CalendarService` conforms in `Calendar/`, where
/// `EKEvent` is allowed to live, and everything here speaks `Block`, `TimeRange` and plain values.
@MainActor
protocol BlockWriting {
    @discardableResult
    func createBlock(title: String,
                     range: TimeRange,
                     categorySlug: String?,
                     sourceTaskID: UUID?,
                     alarmMinutesBefore: Int?) throws -> Block

    func delete(_ block: Block) throws

    /// Removes every block on `date`, returning what was removed.
    @discardableResult
    func deleteAllBlocks(on date: Date, calendar: Calendar) throws -> [Block]

    func contents(for date: Date,
                  ignoring hiddenCalendarIDs: Set<String>,
                  calendar: Calendar) -> DayContents
}
