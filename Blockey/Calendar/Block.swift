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
        /// A Blockey block: movable, resizable, ours.
        case block(BlockToken)
        /// A real event from another calendar. Planned around, never moved.
        case fixed
    }

    var id: String
    var title: String
    var range: TimeRange
    var kind: Kind
    var isAllDay: Bool
    var calendarTitle: String

    /// EventKit's identifier for the underlying event.
    ///
    /// Used only as a fast path for the very next write, within one fetch
    /// cycle. It is never persisted, and `CalendarService` falls back to
    /// searching by token when it goes stale.
    var eventIdentifier: String?

    var token: BlockToken? {
        if case .block(let token) = kind { return token }
        return nil
    }

    var isFixed: Bool { kind == .fixed }
    var category: BlockCategory { token?.category ?? .fallback }

    init(event: EKEvent, blockeyCalendarID: String?) {
        let token = BlockToken(url: event.url)
        let isOurs = event.calendar?.calendarIdentifier == blockeyCalendarID

        self.id = event.eventIdentifier ?? UUID().uuidString
        self.title = event.title ?? "(no title)"
        self.range = TimeRange(start: event.startDate, end: event.endDate)
        // A token on an event outside our calendar is ignored: if the user drags
        // a block into another calendar it becomes a fixed commitment, which is
        // the honest reading of that gesture.
        self.kind = (isOurs && token != nil) ? .block(token!) : (isOurs ? .block(BlockToken()) : .fixed)
        self.isAllDay = event.isAllDay
        self.calendarTitle = event.calendar?.title ?? ""
        self.eventIdentifier = event.eventIdentifier
    }

    /// Memberwise init for tests and previews.
    init(id: String = UUID().uuidString,
         title: String,
         range: TimeRange,
         kind: Kind,
         isAllDay: Bool = false,
         calendarTitle: String = "",
         eventIdentifier: String? = nil) {
        self.id = id
        self.title = title
        self.range = range
        self.kind = kind
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.eventIdentifier = eventIdentifier
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
