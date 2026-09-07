import Testing
import Foundation
@testable import Blockey

// The existing suites pin everything to UTC, which has no DST and therefore
// cannot see an entire class of bug. These suites deliberately use a zone that
// does shift, plus the pure edges the first 52 tests do not reach.

private let ny: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// 2026-03-08 America/New_York: 02:00 EST jumps to 03:00 EDT. A 23-hour day.
private let springForward = ny.date(from: DateComponents(year: 2026, month: 3, day: 8))!
/// 2026-11-01 America/New_York: 02:00 EDT falls back to 01:00 EST. A 25-hour day.
private let fallBack = ny.date(from: DateComponents(year: 2026, month: 11, day: 1))!
/// An ordinary day in the same zone, as a control.
private let plainDay = ny.date(from: DateComponents(year: 2026, month: 9, day: 8))!

private func hourMinute(_ date: Date, _ calendar: Calendar = ny) -> (hour: Int, minute: Int) {
    let c = calendar.dateComponents([.hour, .minute], from: date)
    return (c.hour ?? -1, c.minute ?? -1)
}

/// Wall-clock time on `day`, resolved through the calendar rather than by
/// adding seconds — which is the whole point of these tests.
private func wall(_ day: Date, _ hour: Int, _ minute: Int = 0, _ calendar: Calendar = ny) -> Date {
    calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
}

// MARK: - Daylight saving

@Suite("Daylight saving")
struct DaylightSavingTests {

    // --- snap: verified correct, kept as a regression guard -----------------

    @Test("snap keeps the grid on wall-clock time across a spring-forward day")
    func snapSurvivesSpringForward() {
        for minutes in [5, 10, 15, 30] {
            let snapped = DaySchedule.snap(wall(springForward, 9, 7), toMinutes: minutes, calendar: ny)
            let hm = hourMinute(snapped)
            #expect(hm.hour == 9, "snap(\(minutes)) left the 09:00 hour on a DST day")
            #expect(hm.minute % minutes == 0, "snap(\(minutes)) produced an off-grid minute \(hm.minute)")
        }
    }

    @Test("snap keeps the grid on wall-clock time across a fall-back day")
    func snapSurvivesFallBack() {
        for minutes in [5, 10, 15, 30] {
            let snapped = DaySchedule.snap(wall(fallBack, 9, 8), toMinutes: minutes, calendar: ny)
            let hm = hourMinute(snapped)
            #expect(hm.hour == 9, "snap(\(minutes)) left the 09:00 hour on a DST day")
            #expect(hm.minute % minutes == 0, "snap(\(minutes)) produced an off-grid minute \(hm.minute)")
        }
    }

    @Test("snap is stable inside the repeated hour of a fall-back day")
    func snapInsideRepeatedHour() {
        // 01:30 occurs twice on 1 November; both instants must snap to their own
        // 01:30, not collapse onto one another.
        let firstOneThirty = fallBack.addingTimeInterval(1.5 * 3600)   // EDT
        let secondOneThirty = fallBack.addingTimeInterval(2.5 * 3600)  // EST
        #expect(DaySchedule.snap(firstOneThirty, toMinutes: 15, calendar: ny) == firstOneThirty)
        #expect(DaySchedule.snap(secondOneThirty, toMinutes: 15, calendar: ny) == secondOneThirty)
    }

    // --- window: the control, then the defect ------------------------------

    @Test("window lands on the requested wall-clock hours on an ordinary day")
    func windowIsCorrectOnANormalDay() {
        let w = DaySchedule.window(for: plainDay, startMinute: 7 * 60, endMinute: 22 * 60, calendar: ny)
        #expect(hourMinute(w.start) == (7, 0))
        #expect(hourMinute(w.end) == (22, 0))
    }

    @Test("DEFECT: window is an hour late on a spring-forward day")
    func windowDriftsOnSpringForward() {
        let w = DaySchedule.window(for: springForward, startMinute: 7 * 60, endMinute: 22 * 60, calendar: ny)
        // `window` adds startMinute * 60 *seconds* to midnight, and 8 March is
        // only 23 hours long, so a 07:00–22:00 planning window becomes
        // 08:00–23:00. Correct behaviour is (7, 0) / (22, 0); when this test
        // starts failing, the bug has been fixed — change it to expect that.
        #expect(hourMinute(w.start) == (8, 0))
        #expect(hourMinute(w.end) == (23, 0))
    }

    @Test("DEFECT: window is an hour early on a fall-back day")
    func windowDriftsOnFallBack() {
        let w = DaySchedule.window(for: fallBack, startMinute: 7 * 60, endMinute: 22 * 60, calendar: ny)
        // 1 November is 25 hours long, so the same arithmetic lands an hour
        // early. Correct behaviour is (7, 0) / (22, 0).
        #expect(hourMinute(w.start) == (6, 0))
        #expect(hourMinute(w.end) == (21, 0))
    }

    @Test("DEFECT: a stamped template is shifted a whole hour on a DST day")
    func stampingDriftsOnADSTDay() throws {
        // Exactly the composition TodayView uses: window(for:) feeding stamp().
        let window = DaySchedule.window(for: springForward,
                                        startMinute: 7 * 60,
                                        endMinute: 22 * 60,
                                        calendar: ny)
        let result = TemplateStamper.stamp(
            items: [TemplateStamper.Item(title: "Deep work", startMinuteOfDay: 9 * 60, durationMinutes: 60)],
            on: springForward,
            busy: [],
            window: window,
            calendar: ny)

        let range = try #require(result.placements.first?.outcome.range)
        // The template says 09:00. It is reported as "placed at the intended
        // time" — while actually being written to the calendar at 10:00.
        #expect(result.placements[0].outcome == .placedAtIntendedTime(range))
        #expect(hourMinute(range.start) == (10, 0))
    }

    @Test("Stamping lands on the requested hour on an ordinary day in the same zone")
    func stampingIsCorrectOnANormalDay() throws {
        let window = DaySchedule.window(for: plainDay, startMinute: 7 * 60, endMinute: 22 * 60, calendar: ny)
        let result = TemplateStamper.stamp(
            items: [TemplateStamper.Item(title: "Deep work", startMinuteOfDay: 9 * 60, durationMinutes: 60)],
            on: plainDay,
            busy: [],
            window: window,
            calendar: ny)

        let range = try #require(result.placements.first?.outcome.range)
        #expect(hourMinute(range.start) == (9, 0))
    }
}

// MARK: - CalendarMath

@Suite("CalendarMath")
struct CalendarMathTests {

    @Test("flooredToHour leaves an exact hour alone")
    func flooredIsIdempotentOnTheHour() {
        let nine = wall(plainDay, 9)
        #expect(ny.flooredToHour(nine) == nine)
    }

    @Test("flooredToHour never moves forward, on any hour of a fall-back day")
    func flooredNeverMovesForward() {
        // 25 hours, sampled every 10 minutes.
        for step in 0...(25 * 6) {
            let d = fallBack.addingTimeInterval(TimeInterval(step * 600))
            let floored = ny.flooredToHour(d)
            #expect(floored <= d, "flooredToHour moved forward at \(d)")
        }
    }

    @Test("ceiledToHour leaves an exact hour alone")
    func ceiledIsIdempotentOnTheHour() {
        let nine = wall(plainDay, 9)
        #expect(ny.ceiledToHour(nine) == nine)
    }

    @Test("ceiledToHour rounds up on an ordinary day")
    func ceiledRoundsUp() {
        #expect(ny.ceiledToHour(wall(plainDay, 9, 1)) == wall(plainDay, 10))
    }

    @Test("DEFECT: ceiledToHour returns an earlier time inside a repeated hour")
    func ceiledGoesBackwardsOnFallBack() {
        // 01:30 EST, i.e. the *second* 01:30 on 1 November.
        let secondOneThirty = fallBack.addingTimeInterval(2.5 * 3600)
        let ceiled = ny.ceiledToHour(secondOneThirty)
        // `flooredToHour` rebuilds the date from (y, m, d, hour), and
        // `Calendar.date(from:)` resolves the ambiguous 01:00 to the *first*
        // occurrence — an hour earlier than it should be. Adding 3600 then
        // lands on the second 01:00, which is *before* the input.
        // A ceiling must never be smaller than its argument.
        #expect(ceiled < secondOneThirty)
        #expect(ceiled == fallBack.addingTimeInterval(2 * 3600))
    }
}

// MARK: - BlockToken

@Suite("BlockToken")
struct BlockTokenTests {

    private let id = UUID(uuidString: "6C1B0D4E-9A2F-4B3C-8D5E-1F2A3B4C5D6E")!
    private let taskID = UUID(uuidString: "11112222-3333-4444-5555-666677778888")!

    @Test("A full token round-trips through its URL")
    func roundTripsEverything() throws {
        let original = BlockToken(id: id, category: .health, sourceTaskID: taskID)
        let parsed = try #require(BlockToken(url: original.url))
        #expect(parsed == original)
    }

    @Test("A token with no source task round-trips and stays unlinked")
    func roundTripsWithoutTask() throws {
        let original = BlockToken(id: id, category: .rest)
        let parsed = try #require(BlockToken(url: original.url))
        #expect(parsed.sourceTaskID == nil)
        #expect(parsed == original)
    }

    @Test("Every category slug survives a round trip")
    func everyCategoryRoundTrips() throws {
        for category in BlockCategory.allCases {
            let parsed = try #require(BlockToken(url: BlockToken(id: id, category: category).url))
            #expect(parsed.category == category)
        }
    }

    @Test("A bare token with no query parses to the fallback category")
    func missingQueryFallsBack() throws {
        let url = try #require(URL(string: "blockey://block/\(id.uuidString)"))
        let parsed = try #require(BlockToken(url: url))
        #expect(parsed.id == id)
        #expect(parsed.category == .fallback)
        #expect(parsed.sourceTaskID == nil)
    }

    @Test("A category slug that no longer exists degrades to the fallback")
    func unknownCategoryFallsBack() throws {
        let url = try #require(URL(string: "blockey://block/\(id.uuidString)?c=telepathy"))
        let parsed = try #require(BlockToken(url: url))
        #expect(parsed.id == id)
        #expect(parsed.category == .fallback)
    }

    @Test("An empty category value degrades to the fallback")
    func emptyCategoryFallsBack() throws {
        let url = try #require(URL(string: "blockey://block/\(id.uuidString)?c="))
        #expect(BlockToken(url: url)?.category == .fallback)
    }

    @Test("A malformed source task id is dropped, not fatal")
    func malformedTaskIDIsIgnored() throws {
        let url = try #require(URL(string: "blockey://block/\(id.uuidString)?c=admin&t=nonsense"))
        let parsed = try #require(BlockToken(url: url))
        #expect(parsed.category == .admin)
        #expect(parsed.sourceTaskID == nil)
    }

    @Test("A lower-cased uuid still parses, as a CalDAV round trip may produce")
    func lowercasedUUIDParses() throws {
        let url = try #require(URL(string: "blockey://block/\(id.uuidString.lowercased())?c=deep"))
        #expect(BlockToken(url: url)?.id == id)
    }

    @Test("Anything that is not a Blockey token is rejected")
    func rejectsForeignURLs() {
        let rejected = [
            "https://example.com/standup",                 // a call link the user pasted
            "blockey://demo",                              // the simulator seed marker
            "blockey://block/not-a-uuid",                  // hand-typed
            "blockey://block/",                            // token stripped
            "blockey://other/\(id.uuidString)",            // wrong host
            "notblockey://block/\(id.uuidString)",         // wrong scheme
            "\(id.uuidString)"                             // bare text in the URL field
        ]
        for string in rejected {
            #expect(BlockToken(url: URL(string: string)) == nil, "should have rejected \(string)")
        }
        #expect(BlockToken(url: nil) == nil)
    }

    @Test("DEFECT: a case-shifted scheme or host is rejected")
    func caseShiftedURLsAreRejected() throws {
        // URI schemes and hosts are case-insensitive (RFC 3986), and ADR 002
        // explicitly records the CalDAV round trip as unverified. If iCloud or
        // Calendar.app ever normalises case, or the user retypes the URL by
        // hand, `BlockToken.init(url:)` drops the token and the block silently
        // loses its colour and its task link.
        // Fix: compare `url.scheme?.lowercased()` and `url.host?.lowercased()`.
        #expect(BlockToken(url: URL(string: "BLOCKEY://block/\(id.uuidString)?c=deep")) == nil)
        #expect(BlockToken(url: URL(string: "blockey://BLOCK/\(id.uuidString)?c=deep")) == nil)
    }
}

// MARK: - Block

@Suite("Block")
struct BlockTests {

    @Test("A fixed event carries no token and reads as the fallback category")
    func fixedEventHasNoToken() {
        let block = Block(title: "Standup",
                          range: TimeRange(start: wall(plainDay, 9), duration: 900),
                          kind: .fixed)
        #expect(block.isFixed)
        #expect(block.token == nil)
        #expect(block.category == .fallback)
    }

    @Test("A block reports the category carried in its token")
    func blockCategoryComesFromTheToken() {
        let token = BlockToken(category: .health)
        let block = Block(title: "Gym",
                          range: TimeRange(start: wall(plainDay, 18), duration: 3600),
                          kind: .block(token))
        #expect(!block.isFixed)
        #expect(block.token == token)
        #expect(block.category == .health)
    }

    @Test("All-day events are kept out of the busy set")
    func allDayIsNotBusy() {
        var contents = DayContents()
        contents.allDay = [Block(title: "Public holiday",
                                 range: TimeRange(start: plainDay, duration: 86_400),
                                 kind: .fixed,
                                 isAllDay: true)]
        #expect(contents.busy.isEmpty)
        #expect(!contents.isEmpty)
    }
}

// MARK: - TimelineLayout

@Suite("TimelineLayout")
struct TimelineLayoutTests {

    private func span(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int) -> TimeRange {
        TimeRange(start: wall(plainDay, h1, m1), end: wall(plainDay, h2, m2))
    }

    private func layout(_ ranges: [TimeRange]) -> [TimelineLayout.Placed<TimeRange>] {
        TimelineLayout.columns(for: ranges, range: { $0 })
    }

    @Test("An empty day lays out to nothing")
    func emptyInput() {
        #expect(layout([]).isEmpty)
    }

    @Test("Every item is laid out exactly once")
    func nothingIsLostOrDuplicated() {
        let input = [span(9, 0, 10, 0), span(9, 30, 11, 0), span(9, 30, 11, 0), span(15, 0, 16, 0)]
        #expect(layout(input).count == input.count)
    }

    @Test("A column index is always inside its own column count")
    func columnIndexIsInBounds() {
        let placed = layout([span(9, 0, 17, 0), span(9, 30, 10, 0), span(9, 45, 10, 15),
                             span(10, 0, 11, 0), span(16, 0, 18, 0)])
        for item in placed {
            #expect(item.column >= 0)
            #expect(item.column < item.columnCount)
        }
    }

    @Test("A lone event gets the full width")
    func singleEventIsFullWidth() {
        let placed = layout([span(9, 0, 10, 0)])
        #expect(placed.count == 1)
        #expect(placed[0].columnCount == 1)
        #expect(placed[0].column == 0)
    }

    @Test("Back-to-back events each keep the full width")
    func touchingEventsDoNotShareAWidth() {
        let placed = layout([span(9, 0, 10, 0), span(10, 0, 11, 0)])
        #expect(placed.allSatisfy { $0.columnCount == 1 })
    }

    @Test("Two overlapping events split into two distinct columns")
    func overlapSplitsIntoTwo() {
        let placed = layout([span(9, 0, 10, 30), span(10, 0, 11, 0)])
        #expect(placed.allSatisfy { $0.columnCount == 2 })
        #expect(Set(placed.map(\.column)) == [0, 1])
    }

    @Test("Three simultaneous events split into three columns")
    func threeWayOverlap() {
        let placed = layout([span(9, 0, 10, 0), span(9, 15, 10, 0), span(9, 30, 10, 0)])
        #expect(placed.allSatisfy { $0.columnCount == 3 })
        #expect(Set(placed.map(\.column)) == [0, 1, 2])
    }

    @Test("A long event does not narrow the events after it")
    func aLongEventDoesNotNarrowTheWholeDay() {
        let placed = layout([span(9, 0, 17, 0), span(18, 0, 19, 0)])
        // The all-day-ish event and the evening one never coincide, so neither
        // should be squeezed.
        #expect(placed.allSatisfy { $0.columnCount == 1 })
    }

    @Test("Sequential events reuse a freed column instead of adding one")
    func columnsAreReused() {
        // One long event plus three short sequential ones needs two columns,
        // not four.
        let placed = layout([span(9, 0, 17, 0),
                             span(10, 0, 11, 0), span(11, 0, 12, 0), span(12, 0, 13, 0)])
        #expect(placed.allSatisfy { $0.columnCount == 2 })
    }

    @Test("A zero-length event is still laid out and does not widen the cluster")
    func zeroLengthEventIsHandled() {
        let placed = layout([span(9, 0, 10, 0), span(9, 30, 9, 30)])
        #expect(placed.count == 2)
        #expect(placed.allSatisfy { $0.column < $0.columnCount })
    }

    @Test("Layout is independent of input order")
    func inputOrderDoesNotMatter() {
        let ranges = [span(9, 0, 11, 0), span(10, 0, 12, 0), span(14, 0, 15, 0)]
        let forward = layout(ranges).map { ($0.item, $0.column, $0.columnCount) }
        let reversed = layout(ranges.reversed()).map { ($0.item, $0.column, $0.columnCount) }
        #expect(forward.map(\.0) == reversed.map(\.0))
        #expect(forward.map(\.1) == reversed.map(\.1))
        #expect(forward.map(\.2) == reversed.map(\.2))
    }
}

// MARK: - DaySchedule, the edges the first suite does not reach

@Suite("DaySchedule edges")
struct DayScheduleEdgeTests {

    private func span(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int) -> TimeRange {
        TimeRange(start: wall(plainDay, h1, m1, utc), end: wall(plainDay, h2, m2, utc))
    }
    private var workday: TimeRange { span(7, 0, 22, 0) }

    @Test("merge is idempotent")
    func mergeIsIdempotent() {
        let input = [span(14, 0, 15, 0), span(9, 0, 10, 30), span(10, 0, 11, 0), span(9, 30, 9, 30)]
        let once = DaySchedule.merge(input)
        #expect(DaySchedule.merge(once) == once)
    }

    @Test("merge output is sorted and non-touching")
    func mergeOutputIsDisjoint() {
        let merged = DaySchedule.merge([span(9, 0, 10, 0), span(12, 0, 13, 0), span(9, 30, 11, 0)])
        for (a, b) in zip(merged, merged.dropFirst()) {
            #expect(a.end < b.start, "merge left two ranges touching or overlapping")
        }
    }

    @Test("A window that runs backwards yields no gaps")
    func backwardsWindowHasNoGaps() {
        let backwards = TimeRange(start: wall(plainDay, 22, 0, utc), end: wall(plainDay, 7, 0, utc))
        #expect(DaySchedule.gaps(busy: [], within: backwards).isEmpty)
    }

    @Test("Gaps never overlap the busy time they were computed from")
    func gapsNeverOverlapBusy() {
        let busy = [span(9, 0, 10, 30), span(10, 0, 11, 0), span(6, 0, 8, 0),
                    span(13, 0, 13, 0), span(21, 30, 23, 0)]
        let gaps = DaySchedule.gaps(busy: busy, within: workday)
        for gap in gaps {
            for b in busy where !b.isEmpty {
                #expect(!gap.overlaps(b), "gap \(gap) overlaps busy \(b)")
            }
            #expect(workday.contains(gap), "gap \(gap) escaped the window")
        }
    }

    @Test("A zero-length busy entry does not split the day")
    func zeroLengthBusyIsIgnored() {
        #expect(DaySchedule.gaps(busy: [span(12, 0, 12, 0)], within: workday) == [workday])
    }

    @Test("A negative minimum duration behaves like no minimum")
    func negativeMinimumIsHarmless() {
        #expect(DaySchedule.gaps(busy: [], within: workday, minimumDuration: -3600) == [workday])
    }

    @Test("A gap exactly the minimum duration is kept, one second less is not")
    func minimumDurationIsInclusive() {
        let busy = [span(9, 0, 10, 0), span(10, 15, 11, 0)]
        #expect(DaySchedule.gaps(busy: busy, within: workday, minimumDuration: 15 * 60)
                    .contains(span(10, 0, 10, 15)))
        #expect(!DaySchedule.gaps(busy: busy, within: workday, minimumDuration: 15 * 60 + 1)
                    .contains(span(10, 0, 10, 15)))
    }

    @Test("firstFit rejects a negative duration")
    func firstFitRejectsNegativeDuration() {
        #expect(DaySchedule.firstFit(duration: -60, in: [workday]) == nil)
    }

    @Test("firstFit with an empty gap list finds nothing")
    func firstFitWithNoGaps() {
        #expect(DaySchedule.firstFit(duration: 900, in: []) == nil)
    }

    @Test("notBefore at the exact start of a gap does not shift the fit")
    func notBeforeAtGapStart() {
        let fit = DaySchedule.firstFit(duration: 3600, in: [span(9, 0, 11, 0)], notBefore: span(9, 0, 9, 0).start)
        #expect(fit == span(9, 0, 10, 0))
    }

    @Test("notBefore at the exact end of a gap skips it")
    func notBeforeAtGapEnd() {
        let gaps = [span(9, 0, 11, 0), span(14, 0, 16, 0)]
        let fit = DaySchedule.firstFit(duration: 3600, in: gaps, notBefore: wall(plainDay, 11, 0, utc))
        #expect(fit == span(14, 0, 15, 0))
    }

    @Test("notBefore leaving exactly the requested duration still fits")
    func notBeforeLeavesAnExactFit() {
        let fit = DaySchedule.firstFit(duration: 3600, in: [span(9, 0, 11, 0)], notBefore: wall(plainDay, 10, 0, utc))
        #expect(fit == span(10, 0, 11, 0))
    }

    @Test("firstFit never returns a slot that escapes its gap")
    func firstFitStaysInsideItsGap() throws {
        let gaps = [span(9, 0, 9, 40), span(11, 7, 12, 53)]
        let fit = try #require(DaySchedule.firstFit(duration: 45 * 60, in: gaps))
        #expect(gaps.contains { $0.contains(fit) })
    }

    @Test("A non-positive snap grid leaves the date untouched")
    func negativeSnapGridIsIgnored() {
        let t = wall(plainDay, 9, 7, utc)
        #expect(DaySchedule.snap(t, toMinutes: -15, calendar: utc) == t)
        #expect(DaySchedule.snap(t, toMinutes: 0, calendar: utc) == t)
    }

    @Test("snap rounds a half-step away from zero, not to even")
    func snapRoundsHalfAway() {
        // 09:07:30 is exactly half a 15-minute step past 09:00.
        let t = wall(plainDay, 9, 0, utc).addingTimeInterval(450)
        #expect(DaySchedule.snap(t, toMinutes: 15, calendar: utc) == wall(plainDay, 9, 15, utc))
    }

    @Test("snap is idempotent")
    func snapIsIdempotent() {
        let once = DaySchedule.snap(wall(plainDay, 9, 7, utc), toMinutes: 15, calendar: utc)
        #expect(DaySchedule.snap(once, toMinutes: 15, calendar: utc) == once)
    }
}

// MARK: - TemplateStamper, the edges the first suite does not reach

@Suite("TemplateStamper edges")
struct TemplateStamperEdgeTests {

    private func at(_ h: Int, _ m: Int = 0) -> Date { wall(plainDay, h, m, utc) }
    private func span(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int) -> TimeRange {
        TimeRange(start: at(h1, m1), end: at(h2, m2))
    }
    private var workday: TimeRange { span(7, 0, 22, 0) }

    private func item(_ title: String, at minuteOfDay: Int, minutes: Int) -> TemplateStamper.Item {
        TemplateStamper.Item(title: title, startMinuteOfDay: minuteOfDay, durationMinutes: minutes)
    }

    private func stamp(_ items: [TemplateStamper.Item], busy: [TimeRange] = []) -> TemplateStamper.Result {
        TemplateStamper.stamp(items: items, on: plainDay, busy: busy, window: workday, calendar: utc)
    }

    @Test("Every item ends up either scheduled or unplaced, never both and never lost")
    func everyItemIsAccountedFor() {
        let items = [item("A", at: 9 * 60, minutes: 60),
                     item("B", at: 9 * 60, minutes: 600),
                     item("C", at: 0, minutes: 0),
                     item("D", at: 13 * 60, minutes: 30)]
        let result = stamp(items, busy: [span(10, 0, 12, 0)])
        #expect(result.placements.count == items.count)
        #expect(result.scheduled.count + result.unplaced.count == items.count)
        #expect(Set(result.placements.map(\.item.id)) == Set(items.map(\.id)))
    }

    @Test("A negative duration is rejected exactly like a zero one")
    func negativeDurationIsRejected() {
        let result = stamp([item("Broken", at: 9 * 60, minutes: -30)])
        #expect(result.placements[0].outcome == .unplaced(.zeroDuration))
        #expect(result.scheduled.isEmpty)
    }

    @Test("Two identical rows do not double-book the same slot")
    func duplicateRowsDoNotCollide() {
        let result = stamp([item("Focus", at: 9 * 60, minutes: 60),
                            item("Focus", at: 9 * 60, minutes: 60)])
        let ranges = result.scheduled.map(\.range)
        #expect(ranges.count == 2)
        #expect(!ranges[0].overlaps(ranges[1]))
    }

    @Test("A row that exactly fills the only gap is placed, not moved")
    func exactFitIsPlacedAtIntendedTime() {
        let result = stamp([item("Focus", at: 10 * 60, minutes: 60)],
                           busy: [span(7, 0, 10, 0), span(11, 0, 22, 0)])
        #expect(result.placements[0].outcome == .placedAtIntendedTime(span(10, 0, 11, 0)))
    }

    @Test("A zero-length busy entry does not displace a row")
    func emptyBusyEntryIsIgnored() {
        let result = stamp([item("Focus", at: 9 * 60, minutes: 60)], busy: [span(9, 30, 9, 30)])
        #expect(result.placements[0].outcome == .placedAtIntendedTime(span(9, 0, 10, 0)))
    }

    @Test("No placement ever overlaps a fixed commitment, however messy the day")
    func placementsNeverOverlapBusy() {
        let busy = [span(8, 15, 9, 5), span(9, 0, 9, 45), span(12, 0, 13, 30), span(16, 0, 16, 20)]
        let result = stamp([item("A", at: 8 * 60, minutes: 90),
                            item("B", at: 9 * 60, minutes: 45),
                            item("C", at: 12 * 60, minutes: 60),
                            item("D", at: 16 * 60, minutes: 30)], busy: busy)
        for range in result.scheduled.map(\.range) {
            for b in busy {
                #expect(!range.overlaps(b), "\(range) collided with fixed commitment \(b)")
            }
        }
    }

    @Test("DEFECT: a long late row lets another row spill onto the next day")
    func windowWideningCanPlaceOnTheFollowingDay() throws {
        // "Wind down" at 23:00 for 8 hours widens the effective window to 07:00
        // the *following* morning — the stamper only ever widens, never clips to
        // the day being stamped. An overnight fixed event then leaves the only
        // fitting gap after midnight, and "Focus" is silently scheduled there.
        // TodayView writes it to the calendar but only ever fetches `selectedDate`,
        // so the block is invisible in the app that created it.
        // Fix: clamp `effective` to the calendar day of `date`, or reject any
        // candidate range not contained in that day.
        let overnight = TimeRange(start: at(7, 0), end: at(7, 0).addingTimeInterval(18 * 3600)) // 07:00 → 01:00
        let result = stamp([item("Focus", at: 9 * 60, minutes: 60),
                            item("Wind down", at: 23 * 60, minutes: 480)],
                           busy: [overnight])

        let focus = try #require(result.placements.first { $0.item.title == "Focus" }?.outcome.range)
        #expect(!utc.isDate(focus.start, inSameDayAs: plainDay),
                "Focus was expected to land on the following day; if it no longer does, the bug is fixed")
        #expect(focus == TimeRange(start: at(0, 0).addingTimeInterval(25 * 3600), duration: 3600)) // next day 01:00
    }

    @Test("Widening for an early row does not drag later rows out of the window")
    func earlyRowDoesNotUnlockTheWholeMorning() throws {
        // A 06:00 workout widens the window down to 06:00. A later row that
        // cannot fit must not quietly claim 06:45–07:00 of pre-window time
        // unless it genuinely needs it — this pins the current behaviour so a
        // change to the widening rule is visible.
        let result = stamp([item("Workout", at: 6 * 60, minutes: 45),
                            item("Focus", at: 9 * 60, minutes: 30)],
                           busy: [span(7, 0, 22, 0)])
        let focus = try #require(result.placements.first { $0.item.title == "Focus" }?.outcome.range)
        #expect(focus == span(6, 45, 7, 15))
    }

    @Test("An item at the very end of the window is placed, not dropped")
    func lastSlotOfTheDayIsUsable() {
        let result = stamp([item("Wrap up", at: 21 * 60 + 30, minutes: 30)],
                           busy: [span(7, 0, 21, 30)])
        #expect(result.placements[0].outcome == .placedAtIntendedTime(span(21, 30, 22, 0)))
    }

    @Test("A template stamped onto a completely full day loses nothing to the inbox")
    func fullDaySendsEverythingToTheInbox() {
        let result = stamp([item("A", at: 9 * 60, minutes: 60),
                            item("B", at: 11 * 60, minutes: 60)],
                           busy: [span(0, 0, 23, 59)])
        #expect(result.scheduled.isEmpty)
        #expect(result.unplaced.map(\.title) == ["A", "B"])
    }
}
