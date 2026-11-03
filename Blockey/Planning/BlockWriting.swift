import Foundation

/// A block for Undo to write: everything is given, nothing is minted. A nil token writes no url.
struct UndoDraft: Equatable, Sendable {
    var title: String
    var range: TimeRange
    var token: BlockToken?
    var notes: String?
    var alarmOffsets: [TimeInterval]
}

/// One undo, as a single all-or-nothing calendar operation.
struct UndoBatch: Equatable, Sendable {
    /// The recorded day, never the day the user is looking at now. Blocks are looked for on it.
    var day: Date
    /// Token ids of the blocks the action created. Looked up by token, never `eventIdentifier`.
    var removeTokenIDs: [UUID]
    /// Blocks to write back, after the removals.
    var create: [UndoDraft]
}

/// What an `UndoBatch` did. Only returned when the whole batch landed.
struct UndoApplied: Equatable, Sendable {
    /// Token ids whose block was found and deleted. Targets in neither list were not found on
    /// the day (deleted, moved off it, or token stripped); nothing was deleted for those, and
    /// the planner derives their count rather than carrying a second list.
    var removed: [UUID]
    /// Token ids whose block was found but not removed because Blockey cannot edit it, for
    /// instance one the user made recurring in Calendar.app. `delete` refuses such events and
    /// Clear leaves them, so Undo does too.
    var leftAlone: [UUID]
    /// The blocks written, in `UndoBatch.create` order.
    var created: [Block]
}

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

    /// Writes a block with exactly this token (id, slug, source task and unknown query items),
    /// notes and alarms. Used by Undo, which must give a block back its original identity.
    @discardableResult
    func createBlock(title: String,
                     range: TimeRange,
                     token: BlockToken?,
                     notes: String?,
                     alarmOffsets: [TimeInterval]) throws -> Block

    /// Removes blocks by token over `batch.day` and writes `batch.create`, as one operation.
    ///
    /// Throws having changed nothing: a failure part-way discards everything staged, so a retry
    /// cannot duplicate. A token that finds no block is not deleted.
    func applyUndo(_ batch: UndoBatch, calendar: Calendar) throws -> UndoApplied

    /// Which of `ids` still have a block, found by token, in the Blockey calendar within `days`
    /// days either side of `day`. Not throwing: a failed lookup returns an empty set, which
    /// makes Undo reinsert a task (a possible duplicate) rather than lose one.
    func existingTokenIDs(_ ids: Set<UUID>, around day: Date, days: Int, calendar: Calendar) -> Set<UUID>

    func delete(_ block: Block) throws

    /// Removes every block on `date`, returning what was removed.
    @discardableResult
    func deleteAllBlocks(on date: Date, calendar: Calendar) throws -> [Block]

    func contents(for date: Date,
                  ignoring hiddenCalendarIDs: Set<String>,
                  calendar: Calendar) -> DayContents
}
