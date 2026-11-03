import Foundation

/// A calendar day, as a value that does not move when the clock, the time zone or the display
/// calendar does (issue #7).
///
/// Why not `Date`, or a day offset from some midnight: a "day" is 23, 24 or 25 hours long around
/// DST, so any scheme built on 86,400-second steps drifts, and a stored `Date` means a different
/// day once the phone changes zone. Why not the `Calendar`'s own (era, year, month, day): this
/// owner's `Calendar.current` is Buddhist, so the year is 2569 and, more to the point, the same
/// day would be stored under different components if the calendar setting ever changed, which
/// would silently break every streak.
///
/// So a `CivilDay` is always the proleptic **Gregorian** year, month and day, read in the given
/// calendar's *time zone*. The calendar argument supplies only the zone (which decides where
/// midnight is); its identifier is deliberately ignored. Adjacency is plain integer arithmetic on
/// a day number, with no `Date` and so no DST in it.
///
/// A day is fixed at the moment it is recorded. If the zone changes later the stored day does not
/// move, which is what a streak wants.
struct CivilDay: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The civil day `date` falls on in `calendar`'s time zone.
    init(_ date: Date, in calendar: Calendar) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// "2026-11-03": the storage and backup form. Zero padded so string order is date order.
    var key: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Nil unless `key` is exactly `yyyy-MM-dd` and a real date.
    init?(key: String) {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        // ASCII digits only: `Int("+1")` and `Int("-1")` parse, and must not.
        func digits(_ part: Substring, _ count: Int) -> Bool {
            part.utf8.count == count && part.utf8.allSatisfy { (48...57).contains($0) }
        }
        guard parts.count == 3,
              digits(parts[0], 4), digits(parts[1], 2), digits(parts[2], 2),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), d >= 1
        else { return nil }
        let candidate = CivilDay(year: y, month: m, day: d)
        // Round trip through the day number rejects 30 February and the like.
        guard CivilDay(dayNumber: candidate.dayNumber) == candidate else { return nil }
        self = candidate
    }

    /// Days since 1970-01-01. Howard Hinnant's `days_from_civil`.
    var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// Hinnant's `civil_from_days`.
    init(dayNumber: Int) {
        let z = dayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        self.init(year: y, month: m, day: d)
    }

    func adding(days: Int) -> CivilDay { CivilDay(dayNumber: dayNumber + days) }

    static func < (lhs: CivilDay, rhs: CivilDay) -> Bool { lhs.dayNumber < rhs.dayNumber }
}

/// Everything the UI shows about the streak.
struct StreakSummary: Equatable, Sendable {
    /// Consecutive active days ending today, or ending yesterday if today is not yet counted.
    var current: Int
    /// The best run anywhere in the history, including the current one.
    var longest: Int
    /// Yesterday is active and today is not: adding something today keeps the streak.
    var isAtRisk: Bool
    var countedToday: Bool
    /// The last active day is before yesterday, so the streak has ended. Stays true until the
    /// next add, which is when the user is told about it. `longest` is then the best that was lost.
    var justBroke: Bool

    static let empty = StreakSummary(current: 0, longest: 0, isAtRisk: false,
                                     countedToday: false, justBroke: false)
}

/// The streak rules, as pure functions over a set of active days. No storage, no EventKit.
///
/// An "active day" is a day on which at least one block was added. Undo, Clear and delete never
/// remove a day (issue #7, Q1), so nothing here can lose one.
enum Streak {

    static func summary(days: Set<CivilDay>, now: Date, calendar: Calendar) -> StreakSummary {
        guard !days.isEmpty else { return .empty }
        let today = CivilDay(now, in: calendar)
        let yesterday = today.adding(days: -1)
        let countedToday = days.contains(today)
        let atRisk = !countedToday && days.contains(yesterday)

        // Days after today (a clock or zone quirk: the add was recorded east of here) do not
        // extend the current run, but they are history and still count toward the longest.
        let anchor: CivilDay? = countedToday ? today : (atRisk ? yesterday : nil)
        var current = 0
        if var cursor = anchor {
            while days.contains(cursor) {
                current += 1
                cursor = cursor.adding(days: -1)
            }
        }

        let numbers = days.map(\.dayNumber).sorted()
        var longest = 0, run = 0
        var previous: Int?
        for n in numbers {
            run = (previous == n - 1) ? run + 1 : 1
            longest = max(longest, run)
            previous = n
        }

        let lastActive = numbers.last ?? today.dayNumber
        let justBroke = longest > 0 && lastActive < yesterday.dayNumber
        return StreakSummary(current: current, longest: longest, isAtRisk: atRisk,
                             countedToday: countedToday, justBroke: justBroke)
    }
}

/// Turns the creation dates of existing Blockey events into active days, for the one-time seed so
/// history from before the streak existed counts. Pure: the EventKit read is in `Calendar/`.
enum StreakSeed {

    /// One day per distinct creation day, keeping only dates inside the `windowDays` before `now`.
    /// A creation date after `now` is a clock quirk and is not history.
    static func days(fromCreationDates dates: [Date], now: Date, windowDays: Int,
                     calendar: Calendar) -> Set<CivilDay> {
        let earliest = CivilDay(now, in: calendar).adding(days: -windowDays)
        var result: Set<CivilDay> = []
        for date in dates where date <= now {
            let day = CivilDay(date, in: calendar)
            if day >= earliest { result.insert(day) }
        }
        return result
    }
}
