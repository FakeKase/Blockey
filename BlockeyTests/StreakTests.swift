import Testing
import Foundation
@testable import Blockey

/// The pure streak arithmetic (issue #7). Dates come from `TestDates` and the machine's own
/// calendar (Buddhist here), plus explicit Gregorian and Buddhist calendars for the tests that
/// are about the calendar itself.
@Suite("Streak")
struct StreakTests {

    private let cal = TestDates.calendar()
    /// Midnight of an ordinary day, used as "today" unless a test says otherwise.
    private let base = TestDates.ordinaryDay()

    private func date(_ offset: Int, _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0,
                      from origin: Date? = nil, in calendar: Calendar? = nil) -> Date {
        let c = calendar ?? cal
        let start = c.startOfDay(for: origin ?? base)
        let day = c.date(byAdding: .day, value: offset, to: start) ?? start
        return c.date(bySettingHour: hour, minute: minute, second: second, of: day) ?? day
    }

    private func civil(_ offset: Int, in calendar: Calendar? = nil, from origin: Date? = nil) -> CivilDay {
        CivilDay(date(offset, from: origin, in: calendar), in: calendar ?? cal)
    }

    private func summary(_ offsets: [Int], now offset: Int = 0) -> StreakSummary {
        Streak.summary(days: Set(offsets.map { civil($0) }), now: date(offset), calendar: cal)
    }

    // MARK: Basics

    @Test("An empty history is zero everywhere and has not 'just broken'")
    func empty() {
        #expect(summary([]) == StreakSummary(current: 0, longest: 0, isAtRisk: false,
                                             countedToday: false, justBroke: false))
    }

    @Test("Consecutive days ending today count, and today is counted")
    func consecutiveEndingToday() {
        let s = summary([-2, -1, 0])
        #expect(s == StreakSummary(current: 3, longest: 3, isAtRisk: false,
                                   countedToday: true, justBroke: false))
    }

    @Test("Consecutive days ending yesterday still count, and the streak is at risk")
    func atRisk() {
        let s = summary([-3, -2, -1])
        #expect(s.current == 3)
        #expect(s.isAtRisk)
        #expect(!s.countedToday)
        #expect(!s.justBroke)
    }

    @Test("Once today is added the at-risk state clears")
    func addingClearsRisk() {
        let s = summary([-3, -2, -1, 0])
        #expect(s.current == 4)
        #expect(!s.isAtRisk)
        #expect(s.countedToday)
    }

    @Test("A one-day gap ends the run: only the days after the gap count")
    func oneDayGap() {
        let s = summary([-5, -4, -3, -1, 0])
        #expect(s.current == 2)
        #expect(s.longest == 3)
    }

    @Test("A gap of exactly yesterday leaves today as a fresh single day")
    func gapYesterday() {
        let s = summary([-3, -2, 0])
        #expect(s.current == 1)
        #expect(s.longest == 2)
        #expect(s.countedToday)
        #expect(!s.isAtRisk)
        #expect(!s.justBroke)
    }

    @Test("The longest streak can be in the past")
    func longestInThePast() {
        let s = summary([-30, -29, -28, -27, -26, -25, -24, -1, 0])
        #expect(s.current == 2)
        #expect(s.longest == 7)
    }

    @Test("Many adds in one day are one day")
    func manyAddsOneDay() {
        let days = (0..<20).map { CivilDay(date(0, 8, $0), in: cal) }
        let s = Streak.summary(days: Set(days), now: date(0), calendar: cal)
        #expect(Set(days).count == 1)
        #expect(s.current == 1)
        #expect(s.longest == 1)
    }

    // MARK: Breaking

    @Test("A streak that ended before yesterday has just broken")
    func justBroke() {
        let s = summary([-5, -4, -3, -2])
        #expect(s.current == 0)
        #expect(s.longest == 4)
        #expect(s.justBroke)
        #expect(!s.isAtRisk)
        #expect(!s.countedToday)
    }

    @Test("Last add yesterday is at risk, not broken; last add today is neither")
    func notBrokenYet() {
        #expect(!summary([-1]).justBroke)
        #expect(!summary([0]).justBroke)
        #expect(summary([-2]).justBroke)
    }

    @Test("A single old day counts as a break, since the previous best was 1")
    func singleOldDay() {
        let s = summary([-10])
        #expect(s.justBroke)
        #expect(s.longest == 1)
        #expect(s.current == 0)
    }

    @Test("Adding after a break starts a new streak of 1 and keeps the old best")
    func restartAfterBreak() {
        let s = summary([-9, -8, -7, -6, 0])
        #expect(s.current == 1)
        #expect(s.longest == 4)
        #expect(!s.justBroke)
    }

    // MARK: Midnight

    @Test("An add one second before midnight and one second after are consecutive days")
    func aroundMidnight() {
        let before = CivilDay(date(-1, 23, 59, 59), in: cal)
        let after = CivilDay(date(0, 0, 0, 1), in: cal)
        #expect(before != after)
        #expect(after.dayNumber - before.dayNumber == 1)
        let s = Streak.summary(days: [before, after], now: date(0, 0, 0, 2), calendar: cal)
        #expect(s.current == 2)
    }

    @Test("Midnight itself belongs to the new day")
    func exactlyMidnight() {
        let midnight = cal.startOfDay(for: date(0))
        #expect(CivilDay(midnight, in: cal) == civil(0))
        #expect(CivilDay(midnight.addingTimeInterval(-0.001), in: cal) == civil(-1))
    }

    // MARK: DST

    /// The machine's own zone (Bangkok here) has no DST, so these tests pin one that does, while
    /// keeping the machine's calendar identifier.
    private func dstCalendar() throws -> Calendar {
        TestDates.calendar(timeZone: try #require(TimeZone(identifier: "America/New_York")))
    }

    @Test("Days either side of spring-forward are consecutive, at either end of the short day")
    func springForward() throws {
        let c = try dstCalendar()
        let day = try #require(TestDates.nextSpringForward(in: c), "this zone has no spring-forward day")
        try assertConsecutiveAround(day, in: c)
    }

    @Test("Days either side of fall-back are consecutive, at either end of the long day")
    func fallBack() throws {
        let c = try dstCalendar()
        let day = try #require(TestDates.nextFallBack(in: c), "this zone has no fall-back day")
        try assertConsecutiveAround(day, in: c)
    }

    /// Adds at 00:30 and 23:30 of the day before, the day, and the day after, then asks from the
    /// day after. A scheme based on 24-hour offsets from midnight fails one of these.
    private func assertConsecutiveAround(_ day: Date, in c: Calendar) throws {
        var days: Set<CivilDay> = []
        for offset in -1...1 {
            for (h, m) in [(0, 30), (23, 30)] {
                days.insert(CivilDay(date(offset, h, m, from: day, in: c), in: c))
            }
        }
        #expect(days.count == 3)
        let s = Streak.summary(days: days, now: date(1, 12, from: day, in: c), calendar: c)
        #expect(s.current == 3)
        #expect(s.longest == 3)
        // And from the DST day itself.
        let onTheDay = Streak.summary(days: days, now: date(0, 0, 5, from: day, in: c), calendar: c)
        #expect(onTheDay.countedToday)
        #expect(onTheDay.current == 2)
    }

    // MARK: Time zones

    @Test("A day already recorded does not change when the time zone does")
    func zoneChangeKeepsRecordedDays() throws {
        let auckland = try #require(TimeZone(identifier: "Pacific/Auckland"))
        let la = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let calA = TestDates.calendar(timeZone: auckland)
        let calB = TestDates.calendar(timeZone: la)

        // 08:00 in Auckland on day X is the previous afternoon-evening in Los Angeles.
        let instant = date(0, 8, in: calA)
        let dayX = CivilDay(instant, in: calA)
        let dayInLA = CivilDay(instant, in: calB)
        #expect(dayX != dayInLA)
        #expect(dayX.dayNumber - dayInLA.dayNumber == 1)

        // The stored day is a value, so evaluating later under another zone cannot move it.
        let s = Streak.summary(days: [dayX], now: instant, calendar: calA)
        #expect(s.current == 1)
        #expect(s.countedToday)
    }

    @Test("Flying east to west: a second add on the same real day lands on the earlier civil day, nothing is lost")
    func zoneChangeBetweenAdds() throws {
        let auckland = try #require(TimeZone(identifier: "Pacific/Auckland"))
        let la = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let calA = TestDates.calendar(timeZone: auckland)
        let calB = TestDates.calendar(timeZone: la)

        let first = date(0, 8, in: calA)                       // Auckland morning, day X
        let second = first.addingTimeInterval(5 * 3600)        // in LA, still day X-1 locally
        let days: Set<CivilDay> = [CivilDay(first, in: calA), CivilDay(second, in: calB)]
        #expect(days.count == 2)

        // Judged from LA: today (X-1) is counted, X is "in the future" and does not extend the
        // current run, but it is still real history and still counts toward the longest.
        let s = Streak.summary(days: days, now: second, calendar: calB)
        #expect(s.countedToday)
        #expect(s.current == 1)
        #expect(s.longest == 2)
        #expect(!s.justBroke)
    }

    // MARK: Calendars

    private func utc(_ identifier: Calendar.Identifier) -> Calendar {
        var c = Calendar(identifier: identifier)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }

    @Test("Buddhist and Gregorian calendars agree on the same instants, across a year end")
    func buddhistMatchesGregorian() {
        let greg = utc(.gregorian)
        let budd = utc(.buddhist)
        // Explicit Gregorian dates are right here: this test is about the calendar, not the era.
        let instants = [(2026, 12, 30), (2026, 12, 31), (2027, 1, 1)].compactMap {
            greg.date(from: DateComponents(year: $0.0, month: $0.1, day: $0.2, hour: 9))
        }
        let now = greg.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 20)) ?? .now

        let g = Streak.summary(days: Set(instants.map { CivilDay($0, in: greg) }), now: now, calendar: greg)
        let b = Streak.summary(days: Set(instants.map { CivilDay($0, in: budd) }), now: now, calendar: budd)
        #expect(g == b)
        #expect(b.current == 3)
        #expect(b.countedToday)
    }

    @Test("The Buddhist calendar reads 2569 for 2026, and the day key still uses the Gregorian year")
    func buddhistKeyIsGregorian() {
        let greg = utc(.gregorian)
        let budd = utc(.buddhist)
        let instant = greg.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 9)) ?? .now
        #expect(budd.component(.year, from: instant) == 2569)
        #expect(CivilDay(instant, in: budd).key == "2026-12-31")
        #expect(CivilDay(instant, in: greg).key == "2026-12-31")
    }

    @Test("Leap day sits between 28 February and 1 March")
    func leapDay() {
        let greg = utc(.gregorian)
        let d = [(2028, 2, 28), (2028, 2, 29), (2028, 3, 1)].compactMap {
            greg.date(from: DateComponents(year: $0.0, month: $0.1, day: $0.2, hour: 12))
        }
        let days = Set(d.map { CivilDay($0, in: greg) })
        #expect(Streak.summary(days: days, now: d[2], calendar: greg).current == 3)
    }

    @Test("The machine's own calendar works too")
    func machineCalendar() {
        #expect(summary([-1, 0]).current == 2)
        #expect(summary([-1, 0]).longest == 2)
    }

    // MARK: CivilDay

    @Test("Keys round trip, sort chronologically, and reject nonsense")
    func keys() throws {
        let day = civil(0)
        #expect(CivilDay(key: day.key) == day)
        #expect(CivilDay(key: "2026-02-30") == nil)
        #expect(CivilDay(key: "garbage") == nil)
        #expect(CivilDay(key: "2026-1-5") == nil)
        let earlier = try #require(CivilDay(key: "2026-12-31"))
        let later = try #require(CivilDay(key: "2027-01-01"))
        #expect(earlier < later)
        #expect(earlier.key < later.key)
        #expect(earlier.adding(days: 1) == later)
        #expect(later.adding(days: -1) == earlier)
        #expect(later.dayNumber - earlier.dayNumber == 1)
    }

    // MARK: Seeding

    @Test("Seeding maps creation dates to days, once each, inside the window and not in the future")
    func seeding() {
        let now = date(0, 15)
        let dates = [
            date(-1, 9), date(-1, 18),          // one day
            date(-3, 10),
            date(-400, 10),                     // outside the 365-day window
            date(0, 18),                        // later today: not yet happened
            date(2, 9)                          // a clock quirk: future
        ]
        let days = StreakSeed.days(fromCreationDates: dates, now: now, windowDays: 365, calendar: cal)
        #expect(days == [civil(-1), civil(-3)])
    }

    @Test("Seeding nothing gives nothing")
    func seedingEmpty() {
        #expect(StreakSeed.days(fromCreationDates: [], now: date(0), windowDays: 365, calendar: cal).isEmpty)
    }
}
