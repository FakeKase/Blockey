import Testing
import Foundation
@testable import Blockey

/// Stamping must not plan hours that have already gone.
///
/// Stamping at 11am used to write a 9:00 block into the morning that had been
/// and gone, and report it as a success. Passing a window that starts at `now`
/// does not fix it on its own: the stamper deliberately widens its window to
/// cover every row's intended time, so a window starting at 11am is widened
/// straight back to 9am. The floor has to be applied *after* that widening,
/// which is what `notBefore` is for.
@Suite("Stamping into the past")
struct StampingIntoThePastTests {

    private let calendar = Calendar.current

    /// Found from today in this machine's calendar, never a literal year (issue #6). Stored, so
    /// a run that crosses midnight does not move the day under a test.
    private let day = TestDates.ordinaryDay(weekday: 2)

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func window() -> TimeRange {
        TimeRange(start: at(7), end: at(22))
    }

    private let morning = TemplateStamper.Item(title: "Deep work", startMinuteOfDay: 9 * 60, durationMinutes: 60)
    private let evening = TemplateStamper.Item(title: "Reading", startMinuteOfDay: 20 * 60, durationMinutes: 30)

    @Test("A row whose hour has passed is never placed at its intended time")
    func elapsedRowIsNotPlacedInThePast() {
        let result = TemplateStamper.stamp(items: [morning],
                                           on: day,
                                           busy: [],
                                           window: window(),
                                           notBefore: at(11),
                                           calendar: calendar)

        let outcome = result.placements[0].outcome
        if case .placedAtIntendedTime = outcome {
            Issue.record("a 9:00 row was stamped into the past at 11:00")
        }
        if let range = outcome.range {
            #expect(range.start >= at(11), "block starts at \(range.start), before now")
        }
    }

    /// The stamping rule says a row that cannot have its time takes the next gap
    /// that fits — it should not simply vanish while the day is still young.
    @Test("An elapsed row moves forward rather than disappearing")
    func elapsedRowMovesForward() {
        let result = TemplateStamper.stamp(items: [morning],
                                           on: day,
                                           busy: [],
                                           window: window(),
                                           notBefore: at(11),
                                           calendar: calendar)

        #expect(result.unplaced.isEmpty, "there is room later in the day; it should have moved")
        #expect(result.movedCount == 1)
    }

    @Test("Rows still ahead of you are untouched")
    func futureRowKeepsItsTime() {
        let result = TemplateStamper.stamp(items: [evening],
                                           on: day,
                                           busy: [],
                                           window: window(),
                                           notBefore: at(11),
                                           calendar: calendar)

        #expect(result.placements[0].outcome == .placedAtIntendedTime(
            TimeRange(start: at(20), duration: 30 * 60)))
    }

    /// Stamping a past or future day passes no floor at all, and must behave
    /// exactly as it always did — including honouring a 06:00 row that sits
    /// outside the planning window.
    @Test("Without a floor, nothing changes")
    func noFloorIsUnchanged() {
        let early = TemplateStamper.Item(title: "Workout", startMinuteOfDay: 6 * 60, durationMinutes: 45)
        let result = TemplateStamper.stamp(items: [early, morning, evening],
                                           on: day,
                                           busy: [],
                                           window: window(),
                                           calendar: calendar)

        #expect(result.unplaced.isEmpty)
        #expect(result.movedCount == 0, "every row should have kept its intended time")
        #expect(result.placements[0].outcome.range?.start == at(6))
    }

    /// Opening the app after the day window has closed leaves nowhere to plan,
    /// so every row goes to the inbox rather than being written to a time that
    /// has passed.
    @Test("Stamping after the day is over places nothing")
    func afterTheWindowCloses() {
        let result = TemplateStamper.stamp(items: [morning, evening],
                                           on: day,
                                           busy: [],
                                           window: window(),
                                           notBefore: at(23),
                                           calendar: calendar)

        #expect(result.scheduled.isEmpty)
        #expect(result.unplaced.count == 2)
    }

    @Test("The floor holds across a whole day of stamp times")
    func floorHoldsAllDay() {
        for hour in 7...21 {
            let result = TemplateStamper.stamp(items: [morning, evening],
                                               on: day,
                                               busy: [],
                                               window: window(),
                                               notBefore: at(hour),
                                               calendar: calendar)
            for (item, range) in result.scheduled {
                #expect(range.start >= at(hour),
                        "\(item.title) landed at \(range.start) when stamping at \(hour):00")
            }
        }
    }
}
