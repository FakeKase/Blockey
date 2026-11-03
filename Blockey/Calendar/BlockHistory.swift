import Foundation

/// The facts about one calendar event that history cares about, as plain values. `EKEvent`
/// stays inside `CalendarService`; this is what crosses into the pure mapping below.
struct EventFacts: Sendable {
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let hasRecurrence: Bool
    let url: URL?
    /// Whether the event is in the Blockey calendar. History reads that calendar and nothing else.
    let isInBlockeyCalendar: Bool
    /// An edited occurrence of a recurring series: `hasRecurrence` is false for it, but it is one.
    var isDetached: Bool = false
}

/// Which events count as title history, and what they become. Pure, so it is tested without an
/// event store. See ADR 006, "What counts as history".
enum BlockHistory {

    /// Midnight `days` calendar days before today. Calendar-day arithmetic, not
    /// `days * 86_400` seconds, so a DST change cannot move the boundary by an hour.
    static func windowStart(endingAt now: Date, days: Int, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))
    }

    /// At most `limit` samples, newest first. Everything not listed here is kept on purpose:
    /// tokenless events (no category), the current title as edited in Calendar.app, and the
    /// actual duration after any resize.
    static func samples(from events: [EventFacts], windowStart: Date, now: Date, limit: Int) -> [TitleSample] {
        guard limit > 0 else { return [] }
        let mapped = events.compactMap { sample(from: $0, windowStart: windowStart, now: now) }
        // Start alone is not a total order (two blocks can share it), and `prefix(limit)` would
        // then keep an arbitrary one at the cap. Title and end make it deterministic.
        let sorted = mapped.sorted { a, b in
            let da = a.date ?? .distantPast, db = b.date ?? .distantPast
            if da != db { return da > db }
            if a.title != b.title { return a.title < b.title }
            return a.minutes > b.minutes
        }
        return Array(sorted.prefix(limit))
    }

    static func sample(from e: EventFacts, windowStart: Date, now: Date) -> TitleSample? {
        guard e.isInBlockeyCalendar, !e.isAllDay, !e.hasRecurrence, !e.isDetached else { return nil }
        // Marker first, with the pre-marker all-day title as a fallback; never by title alone.
        guard !SigningReminder.isReminder(title: e.title, isAllDay: e.isAllDay, url: e.url),
              !SigningReminder.isMarked(url: e.url) else { return nil }

        let length = e.end.timeIntervalSince(e.start)
        // 24 hours or longer is `Block.isEditable`'s "not a real block", kept as one definition.
        guard length < 86_400 else { return nil }
        // Rounded to whole minutes; anything that rounds to zero (or runs backwards) teaches nothing.
        let minutes = Int((length / 60).rounded())
        guard minutes >= 1 else { return nil }

        // An event in progress counts; one that has not started does not.
        guard e.start >= windowStart, e.start <= now else { return nil }

        let title = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        return TitleSample(title: title, minutes: minutes,
                           categorySlug: BlockToken(url: e.url)?.categorySlug, date: e.start)
    }
}
