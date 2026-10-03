import Testing
import Foundation
@testable import Blockey

/// The dates behind the reminder that keeps a sideloaded build alive.
@Suite("Signing reminder")
struct SigningReminderTests {

    private let calendar = Calendar.current

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test("A week-long profile is warned about two days out")
    func twoDaysNotice() {
        let now = date(2026, 10, 3, 9)
        let expiry = date(2026, 10, 10, 9)

        let day = SigningReminder.day(expiring: expiry, now: now, calendar: calendar)

        #expect(day == calendar.startOfDay(for: date(2026, 10, 8)))
    }

    /// The app cannot be running on an expired profile, so there is nothing to
    /// warn about — and a reminder dated in the past would never fire.
    @Test("An expired profile gets no reminder")
    func alreadyExpired() {
        let now = date(2026, 10, 3)
        #expect(SigningReminder.day(expiring: date(2026, 9, 25), now: now, calendar: calendar) == nil)
        #expect(SigningReminder.day(expiring: now, now: now, calendar: calendar) == nil)
    }

    /// A paid account's profile lasts a year. Reminding about it would be noise,
    /// and the reminder is specifically for the free-signing treadmill.
    @Test("A long-lived profile gets no reminder")
    func paidAccount() {
        let now = date(2026, 10, 3)
        #expect(SigningReminder.day(expiring: date(2027, 9, 8), now: now, calendar: calendar) == nil)
    }

    @Test("The horizon is inclusive at its edge")
    func horizonBoundary() {
        let now = date(2026, 10, 3)
        let inside = now.addingTimeInterval(SigningReminder.horizon)
        let outside = now.addingTimeInterval(SigningReminder.horizon + 60)

        #expect(SigningReminder.day(expiring: inside, now: now, calendar: calendar) != nil)
        #expect(SigningReminder.day(expiring: outside, now: now, calendar: calendar) == nil)
    }

    /// Expiring tomorrow leaves less than the lead time, so the reminder is for
    /// today rather than for yesterday.
    @Test("Short notice reminds today, never in the past")
    func clampsToToday() {
        let now = date(2026, 10, 3, 14)
        let expiry = date(2026, 10, 4, 9)

        let day = SigningReminder.day(expiring: expiry, now: now, calendar: calendar)

        #expect(day == calendar.startOfDay(for: now))
    }

    @Test("Never returns a day in the past, across a month of expiries")
    func neverInThePast() {
        let now = date(2026, 10, 3, 14)
        for hours in stride(from: 1, through: 30 * 24, by: 7) {
            let expiry = now.addingTimeInterval(TimeInterval(hours) * 3600)
            guard let day = SigningReminder.day(expiring: expiry, now: now, calendar: calendar) else { continue }
            #expect(day >= calendar.startOfDay(for: now), "reminder landed before today for +\(hours)h")
            #expect(day < expiry, "reminder landed after the app stops working for +\(hours)h")
        }
    }

    @Test("The alarm fires in the evening of the reminder day")
    func eveningAlarm() {
        let now = date(2026, 10, 3, 9)
        let day = calendar.startOfDay(for: date(2026, 10, 8))

        let alarm = SigningReminder.alarmDate(on: day, now: now, calendar: calendar)

        #expect(calendar.component(.hour, from: alarm) == SigningReminder.alarmHour)
        #expect(calendar.isDate(alarm, inSameDayAs: day))
    }

    /// An alarm set for 7pm when it is already 10pm would simply never fire.
    @Test("An alarm for an hour already past is pushed to the near future")
    func pastAlarmIsClamped() {
        let now = date(2026, 10, 3, 22)
        let day = calendar.startOfDay(for: now)

        let alarm = SigningReminder.alarmDate(on: day, now: now, calendar: calendar)

        #expect(alarm > now)
        #expect(alarm.timeIntervalSince(now) < 300, "should fire promptly, not tomorrow")
    }

    @Test("The notes say when the app stops and how to fix it")
    func notesAreActionable() {
        let notes = SigningReminder.notes(expiry: date(2026, 10, 10))
        #expect(notes.contains("2026"))
        #expect(notes.lowercased().contains("run"))
        #expect(notes.lowercased().contains("backup"))
    }
}
