import Testing
import Foundation
@testable import Blockey

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private let day = cal.date(from: DateComponents(year: 2026, month: 9, day: 8))!

private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    day.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
}

private func span(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int) -> TimeRange {
    TimeRange(start: at(h1, m1), end: at(h2, m2))
}

private let workday = span(7, 0, 22, 0)

private func item(_ title: String, at hour: Int, _ minute: Int = 0, minutes: Int) -> TemplateStamper.Item {
    TemplateStamper.Item(title: title, startMinuteOfDay: hour * 60 + minute, durationMinutes: minutes)
}

private func stamp(_ items: [TemplateStamper.Item], busy: [TimeRange] = []) -> TemplateStamper.Result {
    TemplateStamper.stamp(items: items, on: day, busy: busy, window: workday, calendar: cal)
}

@Suite("TemplateStamper")
struct TemplateStamperTests {

    // MARK: Placement at the intended time

    @Test("On an empty day every item lands exactly where the template asks")
    func emptyDayPlacesAtIntendedTime() {
        let result = stamp([
            item("Deep work", at: 9, minutes: 120),
            item("Email", at: 13, minutes: 30)
        ])
        #expect(result.placements.count == 2)
        #expect(result.placements[0].outcome == .placedAtIntendedTime(span(9, 0, 11, 0)))
        #expect(result.placements[1].outcome == .placedAtIntendedTime(span(13, 0, 13, 30)))
        #expect(result.unplaced.isEmpty)
        #expect(result.movedCount == 0)
    }

    @Test("An item butted against a meeting still counts as its intended time")
    func adjacentToMeetingIsNotAConflict() {
        let result = stamp([item("Deep work", at: 9, minutes: 60)],
                           busy: [span(10, 0, 11, 0)])
        #expect(result.placements[0].outcome == .placedAtIntendedTime(span(9, 0, 10, 0)))
    }

    // MARK: Displacement

    @Test("A collision pushes the item to the next gap that fits")
    func collisionMovesItemLater() {
        let result = stamp([item("Deep work", at: 9, minutes: 60)],
                           busy: [span(9, 0, 10, 30)])
        #expect(result.placements[0].outcome == .movedToFit(span(10, 30, 11, 30)))
        #expect(result.movedCount == 1)
    }

    @Test("A partial overlap is still a collision")
    func partialOverlapMoves() {
        let result = stamp([item("Deep work", at: 9, minutes: 60)],
                           busy: [span(9, 30, 10, 0)])
        #expect(result.placements[0].outcome == .movedToFit(span(10, 0, 11, 0)))
    }

    @Test("A fixed event is never moved; the template yields to it")
    func fixedEventsWin() {
        let meeting = span(9, 0, 10, 0)
        let result = stamp([item("Deep work", at: 9, minutes: 60)], busy: [meeting])
        let placed = try! #require(result.placements[0].outcome.range)
        #expect(!placed.overlaps(meeting))
    }

    @Test("When nothing later fits, the item falls back to an earlier gap")
    func fallsBackToEarlierGap() {
        // 08:00-09:00 free, then solid until the end of the window.
        let result = stamp([item("Review", at: 14, minutes: 60)],
                           busy: [span(7, 0, 8, 0), span(9, 0, 22, 0)])
        #expect(result.placements[0].outcome == .movedToFit(span(8, 0, 9, 0)))
    }

    // MARK: Unplaced

    @Test("An item that fits nowhere is left for the inbox")
    func noRoomLeavesItemUnplaced() {
        let result = stamp([item("Deep work", at: 9, minutes: 60)],
                           busy: [span(7, 0, 22, 0)])
        #expect(result.placements[0].outcome == .unplaced(.noGapFitsInDayWindow))
        #expect(result.unplaced.map(\.title) == ["Deep work"])
        #expect(result.scheduled.isEmpty)
    }

    @Test("A zero-duration item is rejected rather than placed")
    func zeroDurationIsRejected() {
        let result = stamp([item("Nothing", at: 9, minutes: 0)])
        #expect(result.placements[0].outcome == .unplaced(.zeroDuration))
    }

    @Test("Only the item that does not fit is dropped; the rest still land")
    func partialFailureDoesNotLoseTheDay() {
        let result = stamp([
            item("Fits", at: 8, minutes: 60),
            item("Too big", at: 10, minutes: 600)
        ], busy: [span(12, 0, 22, 0)])
        #expect(result.scheduled.count == 1)
        #expect(result.unplaced.map(\.title) == ["Too big"])
    }

    // MARK: Self-collision

    @Test("A template cannot double-book itself")
    func templateDoesNotOverlapItself() {
        let result = stamp([
            item("First", at: 9, minutes: 120),
            item("Second", at: 10, minutes: 60)
        ])
        let ranges = result.scheduled.map(\.range)
        #expect(ranges.count == 2)
        #expect(!ranges[0].overlaps(ranges[1]))
        #expect(result.placements[1].outcome == .movedToFit(span(11, 0, 12, 0)))
    }

    @Test("Items are placed in chronological order regardless of input order")
    func inputOrderDoesNotMatter() {
        let forward = stamp([item("A", at: 9, minutes: 60), item("B", at: 8, minutes: 60)])
        let reversed = stamp([item("B", at: 8, minutes: 60), item("A", at: 9, minutes: 60)])
        #expect(forward.placements.map(\.item.title) == ["B", "A"])
        #expect(forward.placements.map(\.outcome) == reversed.placements.map(\.outcome))
    }

    // MARK: Window handling

    @Test("An early item keeps its time instead of being dragged into the window")
    func windowWidensForEarlyItems() {
        // 06:00 workout, but the planning window starts at 07:00.
        let result = stamp([item("Workout", at: 6, minutes: 45)])
        #expect(result.placements[0].outcome == .placedAtIntendedTime(span(6, 0, 6, 45)))
    }

    @Test("A late item keeps its time too")
    func windowWidensForLateItems() {
        let result = stamp([item("Wind down", at: 22, minutes: 30)])
        #expect(result.placements[0].outcome == .placedAtIntendedTime(span(22, 0, 22, 30)))
    }

    // MARK: Whole-day behaviour

    @Test("A realistic day: template yields around two meetings and loses nothing")
    func realisticDay() {
        let meetings = [span(9, 30, 10, 0), span(14, 0, 15, 0)]
        let result = stamp([
            item("Deep work", at: 9, minutes: 120),
            item("Lunch", at: 12, minutes: 60),
            item("Admin", at: 14, minutes: 30),
            item("Review", at: 17, minutes: 30)
        ], busy: meetings)

        #expect(result.unplaced.isEmpty)
        let ranges = result.scheduled.map(\.range)
        // Nothing collides with a real meeting...
        for meeting in meetings {
            #expect(!ranges.contains { $0.overlaps(meeting) })
        }
        // ...and nothing collides with anything else the template placed.
        for (i, a) in ranges.enumerated() {
            for b in ranges[(i + 1)...] {
                #expect(!a.overlaps(b))
            }
        }
    }

    @Test("An empty template produces no placements and no crash")
    func emptyTemplate() {
        let result = stamp([])
        #expect(result.placements.isEmpty)
        #expect(result.scheduled.isEmpty)
        #expect(result.unplaced.isEmpty)
    }
}
