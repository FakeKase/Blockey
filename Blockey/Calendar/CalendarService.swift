import Foundation
import EventKit
import Observation

/// Blockey's entire relationship with EventKit.
///
/// Nothing above this type ever sees an `EKEvent`: callers get `Block` value
/// snapshots and hand back `Block`s to mutate. That seam is what makes the
/// EventKit-as-source-of-truth decision reversible — swapping in a local store
/// would mean reimplementing this one class and nothing else.
@Observable
@MainActor
final class CalendarService {

    enum Access: Equatable {
        case undetermined, granted, denied, restricted

        var isGranted: Bool { self == .granted }
    }

    enum Failure: LocalizedError {
        case noCalendarAvailable
        case eventNotFound
        case notPermitted
        case notEditable

        var errorDescription: String? {
            switch self {
            case .noCalendarAvailable:
                return "Blockey could not create its calendar. Check that at least one calendar account is enabled in Settings."
            case .eventNotFound:
                return "That block no longer exists — it may have been deleted in Calendar."
            case .notPermitted:
                return "Blockey needs full access to your calendar to plan your day."
            case .notEditable:
                return "This block repeats or lasts all day, so it can only be changed in Calendar."
            }
        }
    }

    /// The name of the calendar Blockey writes to. Visible to the user in
    /// Calendar.app, which is the point: blocks are real events they can see.
    static let calendarTitle = "Blockey"

    private(set) var access: Access = .undetermined
    private(set) var lastError: String?

    /// Incremented whenever the calendar database changes, from any source —
    /// this app, Calendar.app, or an iCloud sync landing in the background.
    /// Views observe it to know their snapshot is stale.
    private(set) var revision: Int = 0

    private let store = EKEventStore()
    @ObservationIgnored private var changeObserver: _Concurrency.Task<Void, Never>?

    /// Persisted so the same calendar is reused across launches. Only ever a
    /// hint: if it is missing or stale, the calendar is found by title instead.
    @ObservationIgnored
    private var rememberedCalendarID: String? {
        get { UserDefaults.standard.string(forKey: "blockeyCalendarID") }
        set { UserDefaults.standard.set(newValue, forKey: "blockeyCalendarID") }
    }

    init() {
        refreshAccessStatus()
        changeObserver = _Concurrency.Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                self?.revision &+= 1
            }
        }
    }

    deinit { changeObserver?.cancel() }

    // MARK: - Access

    func refreshAccessStatus() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:   access = .granted
        case .denied:       access = .denied
        case .restricted:   access = .restricted
        case .writeOnly:    access = .denied   // Blockey must read meetings to plan around them.
        default:            access = .undetermined
        }
    }

    func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            lastError = error.localizedDescription
        }
        refreshAccessStatus()
        revision &+= 1
    }

    // MARK: - The Blockey calendar

    /// The calendar Blockey owns, creating it on first use.
    @discardableResult
    func ensureBlockeyCalendar() throws -> EKCalendar {
        if let existing = blockeyCalendar() { return existing }

        // Try each candidate rather than trusting the first: an iCloud account
        // can exist with Calendars switched off, and saving to it fails. Giving
        // up there would mean no block could ever be written even though a
        // perfectly good local source is sitting right behind it.
        for source in candidateSources() {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = Self.calendarTitle
            calendar.source = source
            calendar.cgColor = CGColor(red: 0.29, green: 0.40, blue: 0.87, alpha: 1)

            if (try? store.saveCalendar(calendar, commit: true)) != nil {
                rememberedCalendarID = calendar.calendarIdentifier
                return calendar
            }
        }
        throw Failure.noCalendarAvailable
    }

    func blockeyCalendar() -> EKCalendar? {
        // Trust the identifier even if the title changed: renaming the calendar
        // in Calendar.app is a normal thing to do, and rejecting it here would
        // orphan every existing block (they would reclassify as immovable
        // fixed events) and quietly create a second "Blockey" calendar.
        if let id = rememberedCalendarID, let calendar = store.calendar(withIdentifier: id) {
            return calendar
        }
        // The remembered id can still go stale — the user may delete the
        // calendar, or a sync may re-create it under a new identifier. The
        // title is a discovery fallback only.
        if let found = store.calendars(for: .event).first(where: { $0.title == Self.calendarTitle }) {
            rememberedCalendarID = found.calendarIdentifier
            return found
        }
        return nil
    }

    var blockeyCalendarID: String? { blockeyCalendar()?.calendarIdentifier }

    /// Sources that could host the Blockey calendar, best first.
    ///
    /// iCloud leads so blocks reach the user's other devices; a local calendar
    /// is a fine fallback and still survives an app reinstall, because the
    /// calendar database lives outside the app sandbox.
    private func candidateSources() -> [EKSource] {
        let usable = store.sources.filter { $0.sourceType != .birthdays && $0.sourceType != .subscribed }
        var ordered: [EKSource] = []

        func add(_ source: EKSource?) {
            guard let source, !ordered.contains(where: { $0.sourceIdentifier == source.sourceIdentifier }) else { return }
            ordered.append(source)
        }

        add(usable.first { $0.sourceType == .calDAV && $0.title.caseInsensitiveCompare("iCloud") == .orderedSame })
        add(store.defaultCalendarForNewEvents?.source)
        add(usable.first { $0.sourceType == .local })
        usable.forEach(add)
        return ordered
    }

    /// Calendars the user can choose to ignore when planning.
    func selectableCalendars() -> [EKCalendar] {
        let ours = blockeyCalendarID
        return store.calendars(for: .event)
            .filter { $0.calendarIdentifier != ours }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Reading

    /// Everything scheduled on `date`, split into Blockey blocks, fixed
    /// commitments, and all-day banners.
    func contents(for date: Date,
                  ignoring hiddenCalendarIDs: Set<String> = [],
                  calendar: Calendar = .current) -> DayContents {
        guard access.isGranted else { return DayContents() }

        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return DayContents() }

        let ourID = blockeyCalendarID
        let visible = store.calendars(for: .event).filter {
            $0.calendarIdentifier == ourID || !hiddenCalendarIDs.contains($0.calendarIdentifier)
        }
        guard !visible.isEmpty else { return DayContents() }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: visible)
        var contents = DayContents()

        for event in store.events(matching: predicate) {
            // A declined invitation is not a commitment and must not eat a gap.
            if event.status == .canceled { continue }
            let block = Block(event: event, blockeyCalendarID: ourID)

            if block.isAllDay {
                contents.allDay.append(block)
            } else if block.isFixed {
                contents.fixed.append(block)
            } else {
                contents.blocks.append(block)
            }
        }

        contents.blocks.sort { $0.range.start < $1.range.start }
        contents.fixed.sort { $0.range.start < $1.range.start }
        return contents
    }

    // MARK: - Writing

    @discardableResult
    func createBlock(title: String,
                     range: TimeRange,
                     category: BlockCategory,
                     sourceTaskID: UUID? = nil,
                     alarmMinutesBefore: Int? = nil) throws -> Block {
        guard access.isGranted else { throw Failure.notPermitted }
        let calendar = try ensureBlockeyCalendar()

        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = range.start
        event.endDate = range.end
        event.url = BlockToken(category: category, sourceTaskID: sourceTaskID).url
        if let alarmMinutesBefore {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-alarmMinutesBefore * 60)))
        }

        try store.save(event, span: .thisEvent, commit: true)
        revision &+= 1
        return Block(event: event, blockeyCalendarID: calendar.calendarIdentifier)
    }

    func update(_ block: Block,
                title: String? = nil,
                range: TimeRange? = nil,
                category: BlockCategory? = nil) throws {
        guard access.isGranted else { throw Failure.notPermitted }
        guard block.isEditable else { throw Failure.notEditable }
        guard let event = event(for: block) else { throw Failure.eventNotFound }

        if let title { event.title = title }
        if let range {
            event.startDate = range.start
            event.endDate = range.end
        }
        if let category {
            var token = block.token ?? BlockToken()
            token.category = category
            event.url = token.url
        }

        try store.save(event, span: .thisEvent, commit: true)
        revision &+= 1
    }

    func delete(_ block: Block) throws {
        guard access.isGranted else { throw Failure.notPermitted }
        guard block.isEditable else { throw Failure.notEditable }
        guard let event = event(for: block) else { throw Failure.eventNotFound }
        try store.remove(event, span: .thisEvent, commit: true)
        revision &+= 1
    }

    /// Removes every Blockey block on `date`, returning what was removed so the
    /// caller can put any source tasks back in the inbox.
    @discardableResult
    func deleteAllBlocks(on date: Date, calendar: Calendar = .current) throws -> [Block] {
        guard access.isGranted else { throw Failure.notPermitted }
        guard let blockeyCalendar = blockeyCalendar() else { return [] }

        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [blockeyCalendar])
        let events = store.events(matching: predicate)
        let removed = events.map { Block(event: $0, blockeyCalendarID: blockeyCalendar.calendarIdentifier) }

        do {
            for event in events {
                try store.remove(event, span: .thisEvent, commit: false)
            }
            try store.commit()
        } catch {
            // Removals staged with `commit: false` survive a thrown error and
            // would be flushed by the next unrelated save — blocks vanishing at
            // a moment with no connection to this action. Discard them.
            store.reset()
            throw error
        }

        revision &+= 1
        return removed
    }

    /// Locates the event behind a block.
    ///
    /// Tries EventKit's identifier first because it is cheap, then falls back to
    /// searching the surrounding days for a matching token. The fallback is what
    /// makes edits survive a sync that re-created the event under a new id.
    private func event(for block: Block) -> EKEvent? {
        if let id = block.eventIdentifier, let event = store.event(withIdentifier: id) {
            return event
        }
        guard let token = block.token, let calendar = blockeyCalendar() else { return nil }

        let start = block.range.start.addingTimeInterval(-86_400)
        let end = block.range.end.addingTimeInterval(86_400)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        return store.events(matching: predicate).first { BlockToken(url: $0.url)?.id == token.id }
    }

    // MARK: - Demo data (simulator only)

    #if DEBUG
    /// Seeds a plausible day of meetings so gap-finding and template collisions
    /// can be exercised.
    ///
    /// Compiled only for the simulator. It must never be possible to run this
    /// against a real person's calendar, so the guard is at compile time rather
    /// than behind a runtime flag.
    #if targetEnvironment(simulator)
    func seedDemoMeetings(on date: Date = .now, calendar: Calendar = .current) {
        guard access.isGranted else { return }
        let midnight = calendar.startOfDay(for: date)
        guard let target = store.defaultCalendarForNewEvents ?? store.calendars(for: .event).first(where: { $0.allowsContentModifications && $0.title != Self.calendarTitle })
        else { return }

        // Simulator calendar events outlive the app, so seeding twice would
        // stack duplicates. Clear anything this method created before.
        clearDemoMeetings(on: date, calendar: calendar)

        let demo: [(String, Int, Int)] = [
            ("Standup", 9 * 60 + 30, 15),
            ("Design review", 11 * 60, 60),
            ("1:1 with Sam", 14 * 60, 30),
            ("Sprint planning", 16 * 60, 45)
        ]

        for (title, startMinute, minutes) in demo {
            let event = EKEvent(eventStore: store)
            event.calendar = target
            event.title = title
            event.startDate = midnight.addingTimeInterval(TimeInterval(startMinute * 60))
            event.endDate = event.startDate.addingTimeInterval(TimeInterval(minutes * 60))
            event.url = Self.demoMarker
            try? store.save(event, span: .thisEvent, commit: false)
        }
        try? store.commit()
        revision &+= 1
    }

    private static let demoMarker = URL(string: "blockey://demo")!

    /// Clears the day's non-Blockey events so seeding is idempotent.
    ///
    /// Deliberately broader than "events I marked": earlier demo runs left
    /// unmarked events behind, and this is simulator-only code, so wiping the
    /// day's scratch meetings is safe and keeps repeated runs comparable.
    func clearDemoMeetings(on date: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        let ours = blockeyCalendarID
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        for event in store.events(matching: predicate) where event.calendar?.calendarIdentifier != ours {
            try? store.remove(event, span: .thisEvent, commit: false)
        }
        try? store.commit()
    }
    #endif
    #endif
}
