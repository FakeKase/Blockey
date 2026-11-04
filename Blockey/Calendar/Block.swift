import Foundation
import EventKit

/// A scheduled item as the rest of the app sees it.
///
/// A value type on purpose. Apple's own header says to *"consider all EKEvent
/// instances to be invalid as soon as you receive"* an
/// `EKEventStoreChangedNotification`, so no `EKEvent` is allowed to escape
/// `CalendarService`; views hold snapshots and the service re-reads on demand.
struct Block: Identifiable, Equatable, Sendable {

    /// What kind of commitment this is.
    enum Kind: Equatable, Sendable {
        /// A Blockey block: movable, resizable, ours. The token is `nil` when
        /// the event lives in our calendar but carries no readable token —
        /// deliberately not a freshly minted one, which would change the
        /// block's identity on every fetch.
        case block(BlockToken?)
        /// A real event from another calendar. Planned around, never moved.
        case fixed
    }

    var id: String
    var title: String
    var range: TimeRange
    var kind: Kind
    var isAllDay: Bool
    var calendarTitle: String

    /// Whether Blockey may safely rewrite this event.
    ///
    /// Recurring events are excluded because all occurrences share one
    /// `eventIdentifier` and `event(withIdentifier:)` returns the *first* of
    /// them — so dragging today's occurrence would silently rewrite one weeks
    /// in the past. All-day and multi-day events are excluded because they have
    /// no meaningful position on a single day's timeline.
    var isEditable: Bool

    /// EventKit's identifier for the underlying event.
    ///
    /// Used only as a fast path for the very next write, within one fetch
    /// cycle. It is never persisted, and `CalendarService` falls back to
    /// searching by token when it goes stale.
    var eventIdentifier: String?

    /// The event's notes, carried so Undo can put a cleared block back exactly (ADR 007).
    /// Only `Calendar/` reads this; `Planning/` passes it back untouched and views never touch it.
    var notes: String?

    /// Each time alarm as seconds relative to the event start (negative is before), sorted
    /// ascending because EventKit does not preserve insertion order. An absolute-date alarm is
    /// converted to its offset from the start, which is exact because Undo recreates the block
    /// at its original time.
    var alarmOffsets: [TimeInterval]

    var token: BlockToken? {
        if case .block(let token) = kind { return token }
        return nil
    }

    var isFixed: Bool { kind == .fixed }
    /// The slug as stored in the event's token, verbatim: the source of truth for a block's
    /// category. Nil for a fixed event, a tokenless block, or a token with no usable `c=`.
    var categorySlug: String? { token?.categorySlug }

    init(event: EKEvent, blockeyCalendarID: String?) {
        let token = BlockToken(url: event.url)
        let isOurs = event.calendar?.calendarIdentifier == blockeyCalendarID

        self.id = event.eventIdentifier ?? UUID().uuidString
        self.title = event.title ?? "(no title)"
        self.range = TimeRange(start: event.startDate, end: event.endDate)
        // A token on an event outside our calendar is ignored: if the user drags
        // a block into another calendar it becomes a fixed commitment, which is
        // the honest reading of that gesture.
        self.kind = isOurs ? .block(token) : .fixed
        self.isAllDay = event.isAllDay
        self.calendarTitle = event.calendar?.title ?? ""
        self.eventIdentifier = event.eventIdentifier
        self.notes = event.notes
        // Location-based alarms have no time to restore and would read as an offset of 0.
        self.alarmOffsets = (event.alarms ?? []).compactMap { alarm in
            if alarm.structuredLocation != nil { return nil }
            if let absolute = alarm.absoluteDate {
                return absolute.timeIntervalSince(event.startDate)
            }
            return alarm.relativeOffset
        }
        // EventKit does not keep the order alarms were added in (the simulator hands them back
        // reordered), so sort: equal sets of alarms must make equal blocks.
        .sorted()

        let spansWholeDay = event.endDate.timeIntervalSince(event.startDate) >= 86_400
        self.isEditable = isOurs
            && !event.hasRecurrenceRules
            && !event.isAllDay
            && !spansWholeDay
    }

    /// Memberwise init for tests and previews.
    init(id: String = UUID().uuidString,
         title: String,
         range: TimeRange,
         kind: Kind,
         isAllDay: Bool = false,
         calendarTitle: String = "",
         eventIdentifier: String? = nil,
         isEditable: Bool? = nil,
         notes: String? = nil,
         alarmOffsets: [TimeInterval] = []) {
        self.id = id
        self.title = title
        self.range = range
        self.kind = kind
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.eventIdentifier = eventIdentifier
        self.isEditable = isEditable ?? (kind != .fixed)
        self.notes = notes
        self.alarmOffsets = alarmOffsets
    }
}

/// Everything on screen for one day, already split into the two things the
/// timeline treats differently.
struct DayContents: Equatable, Sendable {
    var blocks: [Block] = []
    var fixed: [Block] = []

    /// All-day events are shown as a banner, never as busy time — otherwise a
    /// single "Holiday" entry would consume the entire day and leave no gaps.
    var allDay: [Block] = []

    /// What the gap finder must plan around.
    var busy: [TimeRange] { (blocks + fixed).map(\.range) }

    var isEmpty: Bool { blocks.isEmpty && fixed.isEmpty && allDay.isEmpty }
}
