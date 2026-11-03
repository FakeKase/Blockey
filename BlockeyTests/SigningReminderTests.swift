import Testing
import Foundation
@testable import Blockey

/// The dates behind the reminder that keeps a sideloaded build alive.
@Suite("Signing reminder")
struct SigningReminderTests {

    private let calendar = Calendar.current

    /// Day 0 is an ordinary day a little ahead of today in this machine's calendar (Buddhist
    /// here), so no literal year and no DST edge at the start (issue #6, see TestDates).
    private let origin = TestDates.ordinaryDay()

    /// `days` calendar days after day 0, at `hour` o'clock.
    private func date(_ days: Int, _ hour: Int = 12) -> Date {
        let day = calendar.date(byAdding: .day, value: days, to: origin)!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    @Test("A week-long profile is warned about two days out")
    func twoDaysNotice() {
        let now = date(0, 9)
        let expiry = date(7, 9)

        let day = SigningReminder.day(expiring: expiry, now: now, calendar: calendar)

        #expect(day == calendar.startOfDay(for: date(5)))
    }

    /// The app cannot be running on an expired profile, so there is nothing to
    /// warn about — and a reminder dated in the past would never fire.
    @Test("An expired profile gets no reminder")
    func alreadyExpired() {
        let now = date(0)
        #expect(SigningReminder.day(expiring: date(-8), now: now, calendar: calendar) == nil)
        #expect(SigningReminder.day(expiring: now, now: now, calendar: calendar) == nil)
    }

    /// A paid account's profile lasts a year. Reminding about it would be noise,
    /// and the reminder is specifically for the free-signing treadmill.
    @Test("A long-lived profile gets no reminder")
    func paidAccount() {
        let now = date(0)
        #expect(SigningReminder.day(expiring: date(340), now: now, calendar: calendar) == nil)
    }

    @Test("The horizon is inclusive at its edge")
    func horizonBoundary() {
        let now = date(0)
        let inside = now.addingTimeInterval(SigningReminder.horizon)
        let outside = now.addingTimeInterval(SigningReminder.horizon + 60)

        #expect(SigningReminder.day(expiring: inside, now: now, calendar: calendar) != nil)
        #expect(SigningReminder.day(expiring: outside, now: now, calendar: calendar) == nil)
    }

    /// Expiring tomorrow leaves less than the lead time, so the reminder is for
    /// today rather than for yesterday.
    @Test("Short notice reminds today, never in the past")
    func clampsToToday() {
        let now = date(0, 14)
        let expiry = date(1, 9)

        let day = SigningReminder.day(expiring: expiry, now: now, calendar: calendar)

        #expect(day == calendar.startOfDay(for: now))
    }

    @Test("Never returns a day in the past, across a month of expiries")
    func neverInThePast() {
        let now = date(0, 14)
        for hours in stride(from: 1, through: 30 * 24, by: 7) {
            let expiry = now.addingTimeInterval(TimeInterval(hours) * 3600)
            guard let day = SigningReminder.day(expiring: expiry, now: now, calendar: calendar) else { continue }
            #expect(day >= calendar.startOfDay(for: now), "reminder landed before today for +\(hours)h")
            #expect(day < expiry, "reminder landed after the app stops working for +\(hours)h")
        }
    }

    @Test("The alarm fires in the evening of the reminder day")
    func eveningAlarm() {
        let now = date(0, 9)
        let day = calendar.startOfDay(for: date(5))

        let alarm = SigningReminder.alarmDate(on: day, now: now, calendar: calendar)

        #expect(calendar.component(.hour, from: alarm) == SigningReminder.alarmHour)
        #expect(calendar.isDate(alarm, inSameDayAs: day))
    }

    /// An alarm set for 7pm when it is already 10pm would simply never fire.
    @Test("An alarm for an hour already past is pushed to the near future")
    func pastAlarmIsClamped() {
        let now = date(0, 22)
        let day = calendar.startOfDay(for: now)

        let alarm = SigningReminder.alarmDate(on: day, now: now, calendar: calendar)

        #expect(alarm > now)
        #expect(alarm.timeIntervalSince(now) < 300, "should fire promptly, not tomorrow")
    }

    @Test("The notes say when the app stops and how to fix it")
    func notesAreActionable() {
        let notes = SigningReminder.notes(expiry: date(7))
        // The same call SigningReminder.notes makes, so the whole date and time must be there.
        let shown = date(7).formatted(date: .complete, time: .shortened)
        #expect(notes.contains(shown), "\(shown) missing from: \(notes)")
        #expect(notes.lowercased().contains("run"))
        #expect(notes.lowercased().contains("backup"))
    }

    // MARK: - Recognising our own reminder

    private let marker = URL(string: "blockey://signing-reminder")

    /// The bug behind issue #5: cleanup matched on title alone, so a timed block the
    /// user happened to call "Re-sign Blockey" was deleted along with the stale reminder.
    @Test("A timed user block with the same title is not the reminder")
    func timedBlockWithSameTitle() {
        #expect(!SigningReminder.isReminder(title: SigningReminder.title, isAllDay: false, url: nil))
    }

    @Test("A block carrying a real token is not the reminder, even if all-day with the same title")
    func tokenedBlockWithSameTitle() {
        let url = BlockToken(category: .fallback).url
        #expect(!SigningReminder.isReminder(title: SigningReminder.title, isAllDay: false, url: url))
        #expect(!SigningReminder.isReminder(title: SigningReminder.title, isAllDay: true, url: url))
    }

    @Test("The marker url identifies the reminder")
    func markerMatches() {
        #expect(SigningReminder.isReminder(title: nil, isAllDay: true, url: marker))
        // A user retitling it in Calendar.app must not orphan it.
        #expect(SigningReminder.isReminder(title: "renamed", isAllDay: true, url: marker))
    }

    /// Reminders written before the marker existed are all-day with this exact title.
    @Test("An unmarked all-day event with the exact title is a legacy reminder")
    func legacyShape() {
        #expect(SigningReminder.isReminder(title: SigningReminder.title, isAllDay: true, url: nil))
        #expect(!SigningReminder.isReminder(title: "re-sign blockey", isAllDay: true, url: nil))
        #expect(!SigningReminder.isReminder(title: "Something else", isAllDay: true, url: nil))
    }

    @Test("The marker is matched case-insensitively in scheme and host")
    func markerCaseInsensitive() {
        let shouted = URL(string: "BLOCKEY://Signing-Reminder")
        #expect(SigningReminder.isReminder(title: nil, isAllDay: true, url: shouted))
    }

    @Test("The marker never parses as a block token")
    func markerIsNotAToken() {
        #expect(BlockToken(url: marker) == nil)
        #expect(BlockToken(url: SigningReminder.markerURL) == nil)
        #expect(SigningReminder.markerURL == marker)
    }

    // MARK: - QA: edges of the predicate

    @Test("Title variants of an unmarked all-day event are not the reminder")
    func titleVariantsNotMatched() {
        for t in ["Re-sign Blockey ", " Re-sign Blockey", "RE-SIGN BLOCKEY", "Re-sign Blockey (copy)", ""] {
            #expect(!SigningReminder.isReminder(title: t, isAllDay: true, url: nil), "\(t)")
        }
        #expect(!SigningReminder.isReminder(title: nil, isAllDay: true, url: nil))
    }

    @Test("A marker with a path or query is still the reminder")
    func markerWithExtras() {
        for raw in ["blockey://signing-reminder/x", "blockey://signing-reminder?v=2"] {
            #expect(SigningReminder.isReminder(title: nil, isAllDay: true, url: URL(string: raw)), "\(raw)")
        }
    }

    @Test("The marker wins even on a timed event, so only the app should ever write it")
    func markerIgnoresAllDay() {
        #expect(SigningReminder.isReminder(title: "x", isAllDay: false, url: marker))
    }

    @Test("A timed event with a foreign url and the exact title is not the reminder")
    func timedForeignURL() {
        let url = URL(string: "https://example.com")
        #expect(!SigningReminder.isReminder(title: SigningReminder.title, isAllDay: false, url: url))
    }

    /// QA finding: the doc says the fallback is "all-day, exact title, no url", but the code
    /// only excludes block tokens, so an all-day user event with a web link is deleted too.
    @Test("An all-day event with the exact title and a foreign url is not the reminder")
    func allDayForeignURL() {
        let url = URL(string: "https://example.com")
        #expect(!SigningReminder.isReminder(title: SigningReminder.title, isAllDay: true, url: url))
    }

    @Test("isMarked is true only for the marker url")
    func isMarkedOnlyForMarker() {
        #expect(SigningReminder.isMarked(url: marker))
        #expect(SigningReminder.isMarked(url: URL(string: "BLOCKEY://Signing-Reminder")))
        #expect(!SigningReminder.isMarked(url: nil))
        #expect(!SigningReminder.isMarked(url: URL(string: "https://example.com")))
        #expect(!SigningReminder.isMarked(url: BlockToken(category: .fallback).url))
    }
}
