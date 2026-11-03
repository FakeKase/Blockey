import Testing
import Foundation
import SwiftData
@testable import Blockey

/// Pins the stamp preview (issue #3, task 2.1): what the sheet will show, that confirm
/// recomputes rather than trusting the preview, and that neither ever overlaps a fixed event.
@Suite("Stamp preview and recompute-on-confirm")
@MainActor
struct StampPreviewTests {

    // MARK: Fixtures

    /// Built through the injected calendar so the tests mean the same thing in any time zone.
    private struct World {
        let calendar: Calendar
        /// Start of the world's day. Never a literal year: the default is an ordinary Monday found
        /// from today in the machine's calendar (Buddhist here, see TestDates and issue #6), and
        /// the DST tests pass the next real transition day for their zone.
        let date: Date

        init(calendar: Calendar = .current, date: Date? = nil) {
            self.calendar = calendar
            self.date = date ?? TestDates.ordinaryDay(weekday: 2, in: calendar)
        }

        /// Wall-clock time on the world's day, resolved through the calendar so DST days keep
        /// their real offsets. `dayOffset` steps by calendar days, not by 86,400 seconds.
        func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: date)!
            var parts = calendar.dateComponents([.era, .year, .month, .day], from: day)
            parts.hour = hour; parts.minute = minute
            return calendar.date(from: parts)!
        }

        func range(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int) -> TimeRange {
            TimeRange(start: at(h1, m1), end: at(h2, m2))
        }

        func range(_ h1: Int, _ h2: Int) -> TimeRange { range(h1, 0, h2, 0) }

        /// 24h "HH:mm" in this world's calendar, standing in for the UI's formatter.
        var format: (Date) -> String {
            let cal = calendar
            return { d in
                let c = cal.dateComponents([.hour, .minute], from: d)
                return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            }
        }

        func inputs(date: Date? = nil, now: Date? = nil, isToday: Bool = false) -> DayPlanInputs {
            let target = date ?? self.date
            let window = TimeRange(start: DaySchedule.timeOfDay(7 * 60, on: target, calendar: calendar),
                                   end: DaySchedule.timeOfDay(22 * 60, on: target, calendar: calendar))
            let n = now ?? at(6)
            let plannable = isToday ? TimeRange(start: Swift.max(window.start, n), end: window.end) : window
            return DayPlanInputs(date: target, now: n, isToday: isToday, window: window,
                                 plannableWindow: plannable, alarmMinutesBefore: nil,
                                 calendar: calendar, hiddenCalendarIDs: [])
        }
    }

    @MainActor private struct Rig {
        let writer = FakeBlockWriter()
        let context: ModelContext
        let planner: DayPlanner

        init() throws {
            let container = try ModelContainer(
                for: TaskItem.self, DayTemplate.self, TemplateRow.self, TemplateAssignment.self, ActivityDay.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            context = ModelContext(container)
            planner = DayPlanner(writer: writer, context: context)
        }

        func inbox() throws -> [TaskItem] { try context.fetch(FetchDescriptor<TaskItem>()) }
    }

    private func template(_ rows: [(String, Int, Int)]) -> StampTemplate {
        let items = rows.map { TemplateStamper.Item(title: $0.0, startMinuteOfDay: $0.1, durationMinutes: $0.2) }
        return StampTemplate(items: items, slugs: Dictionary(uniqueKeysWithValues: items.map { ($0.id, "deep") }))
    }

    /// Every pair among `ranges` that overlaps, so a failure names what collided.
    private func overlaps(_ ranges: [TimeRange]) -> [(TimeRange, TimeRange)] {
        var out: [(TimeRange, TimeRange)] = []
        for i in ranges.indices {
            for j in ranges.indices where j > i && ranges[i].overlaps(ranges[j]) { out.append((ranges[i], ranges[j])) }
        }
        return out
    }

    // MARK: Lines

    @Test("Placed, moved and inbox rows read as the sheet will show them")
    func previewLinesShowPlacedMovedAndInbox() throws {
        let w = World(), rig = try Rig()
        rig.writer.addFixed("Standup", w.range(10, 11))
        rig.writer.addFixed("Offsite", w.range(13, 22))
        let t = template([("A", 9 * 60, 60), ("B", 10 * 60, 60), ("C", 11 * 60, 180)])

        let preview = rig.planner.preview(t, inputs: w.inputs(), mode: .keep)
        let lines = preview.rows.map { ($0.title, $0.timeText(w.format), $0.noteText(w.format)) }

        #expect(lines.count == 3)
        #expect(lines[0] == ("A", "09:00 to 10:00", nil))
        #expect(lines[1] == ("B", "11:00 to 12:00", "moved from 10:00"))
        #expect(lines[2] == ("C", nil, "no room"))
        #expect(preview.confirmCount == 2)
        #expect(!preview.isConfirmDisabled)
        #expect(preview.inboxCount == 1)
    }

    @Test("An empty template previews nothing and cannot be confirmed")
    func previewEmptyTemplateDisablesConfirm() throws {
        let w = World(), rig = try Rig()
        let preview = rig.planner.preview(template([]), inputs: w.inputs(), mode: .keep)
        #expect(preview.rows.isEmpty)
        #expect(preview.confirmCount == 0)
        #expect(preview.isConfirmDisabled)
        #expect(preview.hasNoRows)
        #expect(!preview.nothingFits)
    }

    @Test("When every row has gone by, the sheet says nothing fits rather than that it is empty")
    func templateWithAllRowsInThePastShowsNothingFits() throws {
        let w = World(), rig = try Rig()
        let t = template([("A", 9 * 60, 60), ("B", 10 * 60, 60)])
        let preview = rig.planner.preview(t, inputs: w.inputs(now: w.at(22, 30), isToday: true), mode: .keep)
        #expect(preview.confirmCount == 0)
        #expect(preview.isConfirmDisabled)
        #expect(preview.nothingFits)
        #expect(!preview.hasNoRows)
        #expect(preview.rows.allSatisfy { $0.kind == .inbox })
    }

    @Test("No template assigned previews as empty")
    func previewWhenNoTemplateAssigned() throws {
        let w = World(), rig = try Rig()
        let preview = rig.planner.preview(nil, inputs: w.inputs(), mode: .keep)
        #expect(preview.rows.isEmpty)
        #expect(preview.isConfirmDisabled)
        #expect(preview.hasNoRows)
    }

    @Test("A row longer than the day itself goes to the inbox")
    func templateRowLongerThanWindowGoesToInbox() throws {
        let w = World(), rig = try Rig()
        let t = template([("Marathon", 7 * 60, 25 * 60), ("Short", 9 * 60, 30)])
        let preview = rig.planner.preview(t, inputs: w.inputs(), mode: .keep)
        #expect(preview.rows.first { $0.title == "Marathon" }?.kind == .inbox)
        #expect(preview.rows.first { $0.title == "Short" }?.kind == .placed(w.range(9, 0, 9, 30)))
    }

    @Test("A zero-length row is dropped from the preview and never reaches the inbox")
    func zeroDurationRowIsDropped() throws {
        let w = World(), rig = try Rig()
        let t = template([("Nothing", 9 * 60, 0), ("Real", 10 * 60, 30)])
        let preview = rig.planner.preview(t, inputs: w.inputs(), mode: .keep)
        #expect(preview.rows.map(\.title) == ["Real"])
        #expect(preview.droppedCount == 1)
        #expect(preview.confirmCount == 1)

        let outcome = try rig.planner.stamp(t, expecting: preview, mode: .keep, inputs: w.inputs(), openTasks: [])
        guard case .written(let result) = outcome else { Issue.record("expected written"); return }
        #expect(result.created.count == 1)
        #expect(try rig.inbox().isEmpty)
    }

    // MARK: Recompute on confirm

    @Test("A meeting that arrives after the preview makes confirm stale, writes nothing, and a fresh preview avoids it")
    func confirmRecomputesAgainstNewMeetingAndStillAvoidsIt() throws {
        let w = World(), rig = try Rig()
        let t = template([("Deep", 9 * 60, 60)])
        let shown = rig.planner.preview(t, inputs: w.inputs(), mode: .keep)
        #expect(shown.rows.first?.kind == .placed(w.range(9, 10)))

        let meeting = w.range(9, 30, 10, 30)
        rig.writer.addFixed("New meeting", meeting)

        let outcome = try rig.planner.stamp(t, expecting: shown, mode: .keep, inputs: w.inputs(), openTasks: [])
        guard case .stale(let fresh) = outcome else { Issue.record("expected stale"); return }
        #expect(rig.writer.createCalls == 0)
        #expect(rig.writer.blocks.isEmpty)
        #expect(fresh != shown)
        #expect(fresh.rows.first?.kind == .moved(to: w.range(10, 30, 11, 30), from: w.at(9)))

        // Confirming the fresh preview then writes it.
        let second = try rig.planner.stamp(t, expecting: fresh, mode: .keep, inputs: w.inputs(), openTasks: [])
        guard case .written(let result) = second else { Issue.record("expected written"); return }
        #expect(result.created.map(\.range) == [w.range(10, 30, 11, 30)])
        #expect(!result.created[0].range.overlaps(meeting))
    }

    @Test("When now passes a row's time, confirm moves or drops it and never places it in the past")
    func confirmAfterNowPassesRowMovesOrDropsRowNotPlacesInPast() throws {
        let w = World(), rig = try Rig()
        let t = template([("Early", 8 * 60 + 30, 60)])
        let shown = rig.planner.preview(t, inputs: w.inputs(now: w.at(8), isToday: true), mode: .keep)
        #expect(shown.rows.first?.kind == .placed(w.range(8, 30, 9, 30)))

        // Later, 08:30 has gone: the row moves to the first moment still ahead.
        let later = w.inputs(now: w.at(9), isToday: true)
        guard case .stale(let moved) = try rig.planner.stamp(t, expecting: shown, mode: .keep,
                                                              inputs: later, openTasks: []) else {
            Issue.record("expected stale"); return
        }
        guard case .moved(let to, _)? = moved.rows.first?.kind else { Issue.record("expected moved"); return }
        #expect(to.start >= w.at(9))

        // Later still, nothing is left of the day: the row drops to the inbox.
        let night = w.inputs(now: w.at(22, 30), isToday: true)
        guard case .stale(let dropped) = try rig.planner.stamp(t, expecting: shown, mode: .keep,
                                                                inputs: night, openTasks: []) else {
            Issue.record("expected stale"); return
        }
        #expect(dropped.rows.first?.kind == .inbox)
        #expect(rig.writer.createCalls == 0)
    }

    @Test("Previews of different plans, modes or days are not equal")
    func previewAndConfirmDifferingPlansAreDetected() throws {
        let w = World(), rig = try Rig()
        let t = template([("A", 9 * 60, 60)])
        let base = rig.planner.preview(t, inputs: w.inputs(), mode: .keep)
        #expect(base == rig.planner.preview(t, inputs: w.inputs(), mode: .keep))

        #expect(base != rig.planner.preview(t, inputs: w.inputs(), mode: .startOver))

        let nextDay = w.at(0, dayOffset: 1)
        #expect(base != rig.planner.preview(t, inputs: w.inputs(date: nextDay), mode: .keep))

        rig.writer.addFixed("Clash", w.range(9, 10))
        #expect(base != rig.planner.preview(t, inputs: w.inputs(), mode: .keep))
    }

    @Test("A preview for tomorrow uses tomorrow's date, not the clock")
    func previewForDayRolloverUsesSelectedDateNotNow() throws {
        let w = World(), rig = try Rig()
        let tomorrow = w.at(0, dayOffset: 1)
        // It is 23:50 today; tomorrow's 09:00 row must land at 09:00 tomorrow.
        let inputs = w.inputs(date: tomorrow, now: w.at(23, 50), isToday: false)
        let t = template([("Morning", 9 * 60, 60)])
        let preview = rig.planner.preview(t, inputs: inputs, mode: .keep)
        #expect(preview.rows.first?.kind == .placed(TimeRange(start: w.at(9, dayOffset: 1),
                                                               end: w.at(10, dayOffset: 1))))
    }

    // MARK: Modes

    @Test("Start over treats your own blocks as free but fixed events as busy")
    func startOverPreviewTreatsOwnBlocksAsFreeButFixedEventsAsBusy() throws {
        let w = World(), rig = try Rig()
        rig.writer.seedBlock("Mine", w.range(9, 10))
        rig.writer.addFixed("Standup", w.range(10, 11))
        let t = template([("A", 9 * 60, 60), ("B", 10 * 60, 60)])

        let keep = rig.planner.preview(t, inputs: w.inputs(), mode: .keep)
        #expect(keep.rows[0].kind == .moved(to: w.range(11, 12), from: w.at(9)))

        let start = rig.planner.preview(t, inputs: w.inputs(), mode: .startOver)
        #expect(start.rows[0].kind == .placed(w.range(9, 10)))
        #expect(start.rows[1].kind == .moved(to: w.range(11, 12), from: w.at(10)))

        let fixed = [w.range(10, 11)], own = [w.range(9, 10)], locked = [w.range(14, 15)]
        #expect(StampPreview.busy(mode: .keep, fixed: fixed, ownEditable: own, ownLocked: locked)
                == fixed + own + locked)
        // Own blocks the clear cannot delete survive it, so they stay busy.
        #expect(StampPreview.busy(mode: .startOver, fixed: fixed, ownEditable: own, ownLocked: locked)
                == fixed + locked)
    }

    @Test("Start over never frees a fixed event, even one overlapping your own block")
    func startOverNeverFreesFixedEvents() throws {
        let w = World(), rig = try Rig()
        rig.writer.seedBlock("Mine", w.range(9, 30, 10, 30))
        rig.writer.addFixed("Meeting", w.range(9, 10))
        let t = template([("A", 9 * 60, 60)])
        let preview = rig.planner.preview(t, inputs: w.inputs(), mode: .startOver)
        guard let placed = preview.rows.first?.kind.range else { Issue.record("expected a range"); return }
        #expect(!placed.overlaps(w.range(9, 10)))
        #expect(placed == w.range(10, 11))
    }

    @Test("What Start over frees is exactly what the clear deletes: the editable own blocks")
    func contentsBlocksIsExactlyWhatDeleteAllBlocksRemoves() throws {
        let w = World(), rig = try Rig()
        let inDay = rig.writer.seedBlock("In day", w.range(9, 10))
        let spanning = rig.writer.seedBlock("Overnight", TimeRange(start: w.at(23, dayOffset: -1), end: w.at(1)))
        let recurring = rig.writer.seedBlock("Recurring", w.range(14, 15), isEditable: false)
        let multiDay = rig.writer.seedBlock("Multi-day", TimeRange(start: w.at(8, dayOffset: -1), end: w.at(12, dayOffset: 1)),
                                            isEditable: false)
        rig.writer.seedBlock("Banner", w.range(0, 24), allDay: true)
        rig.writer.seedBlock("Tomorrow", TimeRange(start: w.at(9, dayOffset: 1), end: w.at(10, dayOffset: 1)))
        rig.writer.addFixed("Meeting", w.range(11, 12))

        let before = rig.writer.contents(for: w.date, ignoring: [], calendar: w.calendar)
        let removed = try rig.writer.deleteAllBlocks(on: w.date, calendar: w.calendar).map(\.id)
        #expect(Set(before.blocks.filter(\.isEditable).map(\.id)) == Set(removed))
        #expect(Set(removed) == [inDay.id, spanning.id])

        // What survives: fixed events, banners, and the own blocks that cannot be edited.
        let after = rig.writer.contents(for: w.date, ignoring: [], calendar: w.calendar)
        #expect(Set(after.blocks.map(\.id)) == [recurring.id, multiDay.id])
        #expect(after.fixed.count == 1)
        #expect(after.allDay.count == 1)
    }

    @Test("Clearing a day leaves recurring and multi-day own events alone and says how many")
    func clearSkipsRecurringAndMultiDayOwnEvents() throws {
        let w = World(), rig = try Rig()
        rig.writer.seedBlock("Mine", w.range(9, 10))
        rig.writer.seedBlock("Weekly", w.range(11, 12), isEditable: false)
        rig.writer.seedBlock("Trip", TimeRange(start: w.at(8, dayOffset: -1), end: w.at(12, dayOffset: 1)),
                             isEditable: false)

        let result = try rig.planner.clear(inputs: w.inputs(), openTasks: [])

        #expect(result.removed.map(\.title) == ["Mine"])
        #expect(result.kept == 2)
        #expect(Set(rig.writer.blocks.map(\.title)) == ["Weekly", "Trip"])
    }

    @Test("Start over counts own blocks it cannot delete as busy")
    func startOverBusyIncludesNonEditableOwnBlocks() throws {
        let w = World(), rig = try Rig()
        rig.writer.seedBlock("Weekly", w.range(9, 10), isEditable: false)
        let t = template([("A", 9 * 60, 60)])
        for mode in [StampPreview.Mode.keep, .startOver] {
            let preview = rig.planner.preview(t, inputs: w.inputs(), mode: mode)
            #expect(preview.rows.first?.kind == .moved(to: w.range(10, 11), from: w.at(9)), "\(mode)")
        }
    }

    @Test("Confirming Start over never writes on top of a recurring block, which survives")
    func startOverNeverPlacesOnARecurringBlock() throws {
        let w = World(), rig = try Rig()
        let weekly = rig.writer.seedBlock("Weekly", w.range(9, 10), isEditable: false)
        rig.writer.seedBlock("Mine", w.range(11, 12))
        let t = template([("A", 9 * 60, 60), ("B", 11 * 60, 60)])
        let shown = rig.planner.preview(t, inputs: w.inputs(), mode: .startOver)

        guard case .written(let result) = try rig.planner.stamp(t, expecting: shown, mode: .startOver,
                                                                 inputs: w.inputs(), openTasks: []) else {
            Issue.record("expected written"); return
        }
        #expect(result.created.map(\.range) == shown.rows.compactMap { $0.kind.range })
        for block in result.created { #expect(!block.range.overlaps(weekly.range)) }
        #expect(rig.writer.blocks.contains { $0.id == weekly.id })
        #expect(result.cleared?.kept == 1)
        // B's own 11:00 block was freed, so B lands at its intended time.
        #expect(result.created.last?.range == w.range(11, 12))
    }

    @Test("Keep mode plans around every own block, editable or not, and clears nothing")
    func keepModeResultIsUnchangedByTheClearRule() throws {
        let w = World(), rig = try Rig()
        rig.writer.seedBlock("Mine", w.range(9, 10))
        rig.writer.seedBlock("Weekly", w.range(10, 11), isEditable: false)
        let t = template([("A", 9 * 60, 60)])
        let shown = rig.planner.preview(t, inputs: w.inputs(), mode: .keep)
        #expect(shown.rows.first?.kind == .moved(to: w.range(11, 12), from: w.at(9)))
        guard case .written(let result) = try rig.planner.stamp(t, expecting: shown, mode: .keep,
                                                                 inputs: w.inputs(), openTasks: []) else {
            Issue.record("expected written"); return
        }
        #expect(result.cleared == nil)
        #expect(result.created.map(\.range) == [w.range(11, 12)])
        #expect(rig.writer.blocks.count == 3)
    }

    @Test("Confirming Start over clears your blocks and writes the preview")
    func startOverConfirmClearsThenWritesWhatWasPreviewed() throws {
        let w = World(), rig = try Rig()
        rig.writer.seedBlock("Mine", w.range(9, 10))
        rig.writer.addFixed("Standup", w.range(10, 11))
        let t = template([("A", 9 * 60, 60)])
        let shown = rig.planner.preview(t, inputs: w.inputs(), mode: .startOver)

        // A preview made for the other mode is not a promise about this one.
        let wrongMode = try rig.planner.stamp(t, expecting: rig.planner.preview(t, inputs: w.inputs(), mode: .keep),
                                              mode: .startOver, inputs: w.inputs(), openTasks: [])
        guard case .stale = wrongMode else { Issue.record("expected stale"); return }
        #expect(rig.writer.blocks.map(\.title) == ["Mine"])

        guard case .written(let result) = try rig.planner.stamp(t, expecting: shown, mode: .startOver,
                                                                 inputs: w.inputs(), openTasks: []) else {
            Issue.record("expected written"); return
        }
        #expect(result.cleared?.removed.map(\.title) == ["Mine"])
        #expect(rig.writer.blocks.map(\.title) == ["A"])
        #expect(rig.writer.blocks.map(\.range) == [w.range(9, 10)])
    }

    @Test("A matching preview writes exactly what it showed")
    func matchingPreviewConfirmWritesExactlyWhatWasPreviewed() throws {
        let w = World(), rig = try Rig()
        rig.writer.addFixed("Standup", w.range(10, 11))
        rig.writer.addFixed("Offsite", w.range(13, 22))
        let t = template([("A", 9 * 60, 60), ("B", 10 * 60, 60), ("C", 11 * 60, 180)])
        let shown = rig.planner.preview(t, inputs: w.inputs(), mode: .keep)

        guard case .written(let result) = try rig.planner.stamp(t, expecting: shown, mode: .keep,
                                                                 inputs: w.inputs(), openTasks: []) else {
            Issue.record("expected written"); return
        }
        let previewed = shown.rows.compactMap { $0.kind.range }
        #expect(result.created.map(\.range) == previewed)
        #expect(rig.writer.created.map(\.range) == previewed)
        #expect(result.created.count == shown.confirmCount)
        #expect(result.toInbox == shown.inboxCount)
        #expect(try rig.inbox().map(\.title) == ["C"])
    }

    // MARK: Titles

    @Test("The sheet title is Today, Tomorrow, or the weekday")
    func sheetTitleUsesTodayTomorrowOrWeekday() {
        // Pinned to Gregorian + en_US on purpose, so the expected English names are fixed; do not
        // "fix" this back to Calendar.current (this Mac's is Buddhist, see TestDates). The date is
        // still relative to today (the next Monday via World's default): Monday + 3 is Thursday.
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US")
        let w = World(calendar: cal)
        let now = w.at(10)
        #expect(StampPreview.sheetTitle(for: w.date, now: now, calendar: cal) == "Today")
        #expect(StampPreview.sheetTitle(for: w.at(0, dayOffset: 1), now: now, calendar: cal) == "Tomorrow")
        #expect(StampPreview.sheetTitle(for: w.at(0, dayOffset: 3), now: now, calendar: cal) == "Thursday")
        #expect(StampPreview.sheetTitle(for: w.at(0, dayOffset: -1), now: now, calendar: cal) == "Sunday")
    }

    // MARK: DST

    private var newYork: Calendar {
        // The machine's calendar identifier with New York's zone (issue #6, see TestDates).
        TestDates.calendar(timeZone: TimeZone(identifier: "America/New_York") ?? .gmt)
    }

    @Test("Stamping on the spring-forward day still avoids fixed events")
    func stampOnSpringForwardDayRespectsFixedEvents() throws {
        let w = World(calendar: newYork, date: TestDates.nextSpringForward(in: newYork))
        let rig = try Rig()
        let midnight = w.date
        // 02:00 does not exist today, so 03:00 EDT is two real hours after midnight, not three.
        let meeting = TimeRange(start: midnight.addingTimeInterval(2 * 3600),
                                end: midnight.addingTimeInterval(3 * 3600))
        let nine = TimeRange(start: w.at(9), end: w.at(10))
        rig.writer.addFixed("Early", meeting)
        rig.writer.addFixed("Nine", nine)
        let t = template([("Row 1:30", 90, 60), ("Row 9", 9 * 60, 60), ("Row 3", 3 * 60, 60)])

        let shown = rig.planner.preview(t, inputs: w.inputs(), mode: .keep)
        guard case .written(let result) = try rig.planner.stamp(t, expecting: shown, mode: .keep,
                                                                 inputs: w.inputs(), openTasks: []) else {
            Issue.record("expected written"); return
        }
        let fixed = [meeting, nine]
        for block in result.created {
            for f in fixed { #expect(!block.range.overlaps(f), "\(block.title) overlaps \(f)") }
            #expect(block.range.start >= midnight)
        }
        #expect(overlaps(result.created.map(\.range)).isEmpty)
    }

    @Test("Stamping on the fall-back day, with its repeated hour, never overlaps")
    func stampOnFallBackDayRepeatedHourPlacesWithoutOverlap() throws {
        let w = World(calendar: newYork, date: TestDates.nextFallBack(in: newYork))
        let rig = try Rig()
        let midnight = w.date
        // 01:00 EDT is 1h after midnight; the second 01:00 (EST) is 2h after. A meeting holds
        // the second pass, so the repeated hour is half free.
        let repeated = TimeRange(start: midnight.addingTimeInterval(2 * 3600),
                                 end: midnight.addingTimeInterval(3 * 3600))
        rig.writer.addFixed("Repeated hour", repeated)
        rig.writer.addFixed("Nine", TimeRange(start: w.at(9), end: w.at(10)))
        let t = template([("One", 60, 60), ("OneThirty", 90, 60), ("Nine", 9 * 60, 60)])

        let shown = rig.planner.preview(t, inputs: w.inputs(), mode: .keep)
        guard case .written(let result) = try rig.planner.stamp(t, expecting: shown, mode: .keep,
                                                                 inputs: w.inputs(), openTasks: []) else {
            Issue.record("expected written"); return
        }
        let ranges = result.created.map(\.range)
        let all = ranges + rig.writer.fixed.map(\.range)
        #expect(overlaps(all).isEmpty, "\(overlaps(all))")
        let dayEnd = w.calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight
        for r in ranges { #expect(r.start >= midnight && r.end <= dayEnd) }
    }
}
