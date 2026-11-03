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
                return "That block no longer exists. It may have been deleted in Calendar."
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
            // Neither a cancelled event nor one you declined is a commitment,
            // so neither may eat a gap.
            if event.status == .canceled { continue }
            if event.isDeclinedByUser { continue }
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
        try createBlock(title: title, range: range, categorySlug: category.rawValue,
                        sourceTaskID: sourceTaskID, alarmMinutesBefore: alarmMinutesBefore)
    }

    /// The slug form, for work that already carries one (inbox tasks, template rows). Going
    /// through `BlockCategory` would turn a slug this build doesn't know into the fallback.
    @discardableResult
    func createBlock(title: String,
                     range: TimeRange,
                     categorySlug: String?,
                     sourceTaskID: UUID? = nil,
                     alarmMinutesBefore: Int? = nil) throws -> Block {
        try createBlock(title: title,
                        range: range,
                        token: BlockToken(categorySlug: categorySlug, sourceTaskID: sourceTaskID),
                        notes: nil,
                        alarmOffsets: alarmMinutesBefore.map { [TimeInterval(-$0 * 60)] } ?? [])
    }

    /// The one place a block is written. The token goes in verbatim, so Undo can give a block
    /// back its original id, slug, source task and any query items this build does not know.
    @discardableResult
    func createBlock(title: String,
                     range: TimeRange,
                     token: BlockToken?,
                     notes: String?,
                     alarmOffsets: [TimeInterval]) throws -> Block {
        guard access.isGranted else { throw Failure.notPermitted }
        let calendar = try ensureBlockeyCalendar()

        let event = makeEvent(in: calendar, title: title, range: range, token: token,
                              notes: notes, alarmOffsets: alarmOffsets)
        try store.save(event, span: .thisEvent, commit: true)
        revision &+= 1
        return Block(event: event, blockeyCalendarID: calendar.calendarIdentifier)
    }

    /// Which of `ids` have a block in the Blockey calendar within `days` days of `day`, by token.
    /// See `BlockWriting.existingTokenIDs` for why a failure reads as "none".
    func existingTokenIDs(_ ids: Set<UUID>, around day: Date, days: Int,
                          calendar: Calendar = .current) -> Set<UUID> {
        guard access.isGranted, !ids.isEmpty, let ours = blockeyCalendar() else { return [] }
        let dayStart = calendar.startOfDay(for: day)
        guard let from = calendar.date(byAdding: .day, value: -days, to: dayStart),
              let to = calendar.date(byAdding: .day, value: days + 1, to: dayStart) else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: [ours])
        let found = store.events(matching: predicate).compactMap { BlockToken(url: $0.url)?.id }
        return ids.intersection(found)
    }

    /// Builds an unsaved block event. Shared by `createBlock` and `applyUndo` so both write
    /// the same fields.
    private func makeEvent(in calendar: EKCalendar,
                           title: String,
                           range: TimeRange,
                           token: BlockToken?,
                           notes: String?,
                           alarmOffsets: [TimeInterval]) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = range.start
        event.endDate = range.end
        // A nil token writes no url: a block that never had one stays tokenless.
        if let token {
            if let url = token.url {
                event.url = url
            } else {
                // Unreachable by construction (fixed scheme, host and UUID path). Loud in debug
                // builds so it can't hide; harmless in release, where the block is just tokenless.
                assertionFailure("BlockToken produced no url for a new block")
            }
        }
        event.notes = notes
        for offset in alarmOffsets {
            event.addAlarm(EKAlarm(relativeOffset: offset))
        }
        return event
    }

    /// Undo as one operation: delete the blocks an action created, found by token over the
    /// recorded day, and write back the blocks it removed.
    ///
    /// Blocks are never looked up by `eventIdentifier` here (ADR 001): it does not survive every
    /// edit, and a stale one could point at a block that is not ours to delete. A token that
    /// finds nothing, deleted or stripped, lands in neither `removed` nor `leftAlone`, and nothing is
    /// removed for it; the planner derives the missing count from that.
    ///
    /// Everything is staged with `commit: false` and committed once. On any throw the staged
    /// work is discarded with `reset()`, for the reason `deleteAllBlocks` gives: it would
    /// otherwise be flushed by the next unrelated save.
    func applyUndo(_ batch: UndoBatch, calendar: Calendar = .current) throws -> UndoApplied {
        guard access.isGranted else { throw Failure.notPermitted }

        let dayStart = calendar.startOfDay(for: batch.day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return UndoApplied(removed: [], leftAlone: [], created: [])
        }

        // Nothing to write means no reason to create the calendar just to find it empty.
        let ours: EKCalendar
        if batch.create.isEmpty {
            guard let existing = blockeyCalendar() else {
                return UndoApplied(removed: [], leftAlone: [], created: [])
            }
            ours = existing
        } else {
            ours = try ensureBlockeyCalendar()
        }

        var byToken: [UUID: EKEvent] = [:]
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: [ours])
        // Sorted so that if a token is on two events (a block duplicated in Calendar.app keeps
        // its url), the same one is chosen every time: the earliest. Only one is removed; the
        // other is the user's own copy.
        for event in store.events(matching: predicate).sorted(by: { $0.startDate < $1.startDate }) {
            guard let id = BlockToken(url: event.url)?.id, byToken[id] == nil else { continue }
            byToken[id] = event
        }

        var removed: [UUID] = []
        var leftAlone: [UUID] = []
        var seen = Set<UUID>()
        var written: [EKEvent] = []
        do {
            for id in batch.removeTokenIDs where seen.insert(id).inserted {
                guard let event = byToken[id] else { continue }
                // Same refusal as `delete`: recurring, all-day and multi-day events are not
                // ours to rewrite, and Clear leaves them too.
                guard Block(event: event, blockeyCalendarID: ours.calendarIdentifier).isEditable else {
                    leftAlone.append(id)
                    continue
                }
                try store.remove(event, span: .thisEvent, commit: false)
                removed.append(id)
            }
            for draft in batch.create {
                let event = makeEvent(in: ours, title: draft.title, range: draft.range,
                                      token: draft.token, notes: draft.notes,
                                      alarmOffsets: draft.alarmOffsets)
                try store.save(event, span: .thisEvent, commit: false)
                written.append(event)
            }
            try store.commit()
        } catch {
            store.reset()
            throw error
        }

        revision &+= 1
        return UndoApplied(removed: removed,
                           leftAlone: leftAlone,
                           created: written.map { Block(event: $0, blockeyCalendarID: ours.calendarIdentifier) })
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
            if let url = token.url {
                event.url = url
            } else {
                // Same unreachable case as in createBlock. Here the old token stays, so the
                // save would succeed without the category change: say so in debug builds.
                assertionFailure("BlockToken produced no url; category change not written")
            }
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
        // All-day events in this calendar are not blocks — nothing else in the
        // app treats them as one, they consume no time, and the signing reminder
        // is one of them. Clearing the day leaves them alone.
        //
        // Events Blockey cannot edit (recurring, multi-day) are left alone too: `delete`
        // refuses them, and Undo could not restore a recurrence rule. Judged by `Block`'s
        // own `isEditable` so the rule lives in one place.
        let ourID = blockeyCalendar.calendarIdentifier
        let doomed = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map { (event: $0, block: Block(event: $0, blockeyCalendarID: ourID)) }
            .filter { $0.block.isEditable }
        let events = doomed.map(\.event)
        let removed = doomed.map(\.block)

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

    // MARK: - Keeping the app alive

    /// Puts a reminder in the calendar that this build is about to stop
    /// launching, and keeps exactly one of them pending.
    ///
    /// Deliberately a calendar event and not a local notification: the reminder
    /// has to arrive *after* the app can no longer be opened, and a notification
    /// scheduled by the app dies with the app's sandbox. An `EKAlarm` lives in
    /// the calendar store, so it reaches the Lock Screen and the Watch with the
    /// app uninstallable — and it needs no notification permission, which is a
    /// second prompt the user would otherwise have to be asked for.
    ///
    /// All-day, so it cannot consume a gap the user could have planned into.
    ///
    /// - Returns: whether a reminder was written.
    @discardableResult
    func ensureSigningReminder(expiring expiry: Date,
                               now: Date = .now,
                               calendar: Calendar = .current) throws -> Bool {
        guard access.isGranted else { return false }
        guard let searchEnd = calendar.date(byAdding: .day, value: 60, to: now) else { return false }

        let wanted = SigningReminder.day(expiring: expiry, now: now, calendar: calendar)

        // Create the calendar when there is a reminder to put in it — a new
        // install should be warned even if the user has not made a block yet —
        // but only look when there is not, so a build that never expires does
        // not bring a calendar into existence just to find that out.
        let found = wanted == nil ? blockeyCalendar() : try ensureBlockeyCalendar()
        guard let blockeyCalendar = found else { return false }

        // One reminder outstanding at a time. Re-signing moves the date, and
        // moving to a paid account removes the need altogether — in both cases
        // the reminder already in the calendar is now a lie and has to go.
        let pending = store.events(matching: store.predicateForEvents(withStart: calendar.startOfDay(for: now),
                                                                      end: searchEnd,
                                                                      calendars: [blockeyCalendar]))
            // Never by title alone: a timed block the user named the same would be
            // deleted. See `SigningReminder.isReminder`.
            .filter { SigningReminder.isReminder(title: $0.title, isAllDay: $0.isAllDay, url: $0.url) }

        if let wanted, pending.count == 1,
           let only = pending.first, calendar.isDate(only.startDate, inSameDayAs: wanted),
           // A legacy reminder on the right day is still replaced once, so it
           // gains the marker rather than waiting for the next re-sign.
           SigningReminder.isMarked(url: only.url) {
            return false
        }

        for stale in pending {
            try? store.remove(stale, span: .thisEvent, commit: false)
        }

        guard let day = wanted else {
            // Nothing to schedule — this build does not expire out from under
            // the user. Flush the cleanup and stop.
            if !pending.isEmpty {
                try store.commit()
                revision &+= 1
            }
            return false
        }

        let event = EKEvent(eventStore: store)
        event.calendar = blockeyCalendar
        event.title = SigningReminder.title
        event.isAllDay = true
        event.url = SigningReminder.markerURL
        event.startDate = day
        event.endDate = day
        event.notes = SigningReminder.notes(expiry: expiry)
        event.addAlarm(EKAlarm(absoluteDate: SigningReminder.alarmDate(on: day,
                                                                      now: now,
                                                                      calendar: calendar)))

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            // Staged removals survive a throw and would otherwise be flushed by
            // the next unrelated save, taking a reminder with them.
            store.reset()
            throw error
        }
        revision &+= 1
        return true
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

private extension EKEvent {
    /// Whether *you* declined this invitation.
    ///
    /// Not the same question as `status == .canceled`, which is the organiser
    /// calling the meeting off — the two were conflated here once, and the
    /// result was that declined meetings still consumed free time. A decline is
    /// recorded on your own attendee record, and an event with no attendees at
    /// all (anything you created yourself) is never declined.
    var isDeclinedByUser: Bool {
        attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }
}
