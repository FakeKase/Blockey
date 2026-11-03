import Foundation

/// Shared date fixtures for tests (issue #6).
///
/// Why this exists: `Calendar.current` on the owner's Mac (and probably the phone) is Buddhist.
/// `DateComponents(year: 2026, ...)` read through it means 2026 BE, which is 1483 CE, an era with
/// historic local-mean-time offsets and different weekdays. Tests built that way pass, but they
/// exercise a date the app never sees. So nothing in the tests names a year: every date is found
/// by walking forward from a real "now" in whatever calendar the machine uses, with calendar
/// arithmetic (`byAdding`), never by adding 86,400 seconds, so month ends, year ends and DST
/// weeks all work.
///
/// The one place a Gregorian calendar is still right is a test about weekday *names*, which
/// pins the expectation to English Gregorian names; those tests say so in a comment.
enum TestDates {

    /// `Calendar.current`'s calendar and locale, optionally pinned to a zone. Keeps the machine's
    /// identifier (Buddhist, Gregorian, ...) on purpose, which is the whole point of this file.
    static func calendar(timeZone: TimeZone? = nil) -> Calendar {
        var c = Calendar.current
        if let timeZone { c.timeZone = timeZone }
        return c
    }

    /// Midnight at the start of today in `calendar`.
    static func today(in calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: .now)
    }

    /// Real length of the calendar day containing `date`: 23h, 24h or 25h around DST.
    static func dayLength(_ date: Date, in calendar: Calendar) -> TimeInterval {
        guard let interval = calendar.dateInterval(of: .day, for: date) else { return 86_400 }
        return interval.duration
    }

    /// Start of the first day on or after tomorrow that is an ordinary 24-hour day, with
    /// ordinary days either side, and, when `weekday` is given (1 = Sunday ... 7 = Saturday,
    /// the same numbering in every calendar), falls on that weekday.
    ///
    /// "Either side" matters: tests schedule across midnight and look at neighbouring days, and a
    /// run during a DST week must not turn them into DST tests by accident. Searching starts
    /// tomorrow so a test never straddles "now" ticking over midnight.
    static func ordinaryDay(weekday: Int? = nil, in calendar: Calendar = .current) -> Date {
        let start = today(in: calendar)
        for offset in 1...800 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            if let weekday, calendar.component(.weekday, from: day) != weekday { continue }
            if isOrdinary(day, in: calendar) { return day }
        }
        preconditionFailure("no ordinary day found in 800 days")
    }

    /// Start of the next day on which clocks go forward in `calendar`'s zone (a 23-hour day), or
    /// nil if there is none within the search window.
    static func nextSpringForward(in calendar: Calendar) -> Date? {
        nextDay(in: calendar, where: { $0 < 86_400 }, what: "spring-forward")
    }

    /// Start of the next day on which clocks go back in `calendar`'s zone (a 25-hour day), or
    /// nil if there is none within the search window.
    static func nextFallBack(in calendar: Calendar) -> Date? {
        nextDay(in: calendar, where: { $0 > 86_400 }, what: "fall-back")
    }

    // MARK: Private

    private static func isOrdinary(_ day: Date, in calendar: Calendar) -> Bool {
        for delta in -1...1 {
            guard let d = calendar.date(byAdding: .day, value: delta, to: day),
                  dayLength(d, in: calendar) == 86_400 else { return false }
        }
        return true
    }

    /// Searches from today (inclusive) for 800 days, which covers any zone with yearly DST
    /// twice over. Returns nil if the zone has no such day, so a DST suite can `try #require` it
    /// and fail rather than crash the whole test process.
    private static func nextDay(in calendar: Calendar, where matches: (TimeInterval) -> Bool,
                                what: String) -> Date? {
        let start = today(in: calendar)
        for offset in 0...800 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            if matches(dayLength(day, in: calendar)) { return day }
        }
        return nil
    }
}
