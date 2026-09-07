import Testing
import Foundation
@testable import Blockey

/// All tests pin to UTC so they behave identically on any machine.
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

// MARK: - TimeRange

@Suite("TimeRange")
struct TimeRangeTests {

    @Test("A range cannot run backwards")
    func backwardsRangeCollapses() {
        let r = TimeRange(start: at(10), end: at(9))
        #expect(r.start == at(10))
        #expect(r.end == at(10))
        #expect(r.isEmpty)
    }

    @Test("Back-to-back ranges do not overlap")
    func touchingRangesDoNotOverlap() {
        #expect(!span(9, 0, 10, 0).overlaps(span(10, 0, 11, 0)))
    }

    @Test("Genuinely overlapping ranges are detected in both directions")
    func overlapIsSymmetric() {
        let a = span(9, 0, 10, 30), b = span(10, 0, 11, 0)
        #expect(a.overlaps(b))
        #expect(b.overlaps(a))
    }

    @Test("contains(date) is half-open: start counts, end does not")
    func containsIsHalfOpen() {
        let r = span(9, 0, 10, 0)
        #expect(r.contains(at(9, 0)))
        #expect(r.contains(at(9, 59)))
        #expect(!r.contains(at(10, 0)))
    }

    @Test("Clamping to a disjoint window yields nil")
    func clampDisjoint() {
        #expect(span(6, 0, 6, 30).clamped(to: workday) == nil)
    }

    @Test("Clamping to a touching window yields nil, not an empty range")
    func clampTouching() {
        #expect(span(5, 0, 7, 0).clamped(to: workday) == nil)
    }

    @Test("Clamping trims an overhanging range to the window")
    func clampTrims() {
        #expect(span(6, 0, 9, 0).clamped(to: workday) == span(7, 0, 9, 0))
    }
}

// MARK: - merge

@Suite("DaySchedule.merge")
struct MergeTests {

    @Test("Empty input yields empty output")
    func empty() {
        #expect(DaySchedule.merge([]).isEmpty)
    }

    @Test("Overlapping ranges collapse into one")
    func overlapping() {
        let merged = DaySchedule.merge([span(9, 0, 10, 30), span(10, 0, 11, 0)])
        #expect(merged == [span(9, 0, 11, 0)])
    }

    @Test("Touching ranges collapse: there is no usable gap between them")
    func touching() {
        let merged = DaySchedule.merge([span(9, 0, 10, 0), span(10, 0, 11, 0)])
        #expect(merged == [span(9, 0, 11, 0)])
    }

    @Test("A nested range is absorbed by its container")
    func nested() {
        let merged = DaySchedule.merge([span(9, 0, 12, 0), span(10, 0, 11, 0)])
        #expect(merged == [span(9, 0, 12, 0)])
    }

    @Test("Unsorted input is handled")
    func unsorted() {
        let merged = DaySchedule.merge([span(14, 0, 15, 0), span(9, 0, 10, 0)])
        #expect(merged == [span(9, 0, 10, 0), span(14, 0, 15, 0)])
    }

    @Test("Separate ranges stay separate")
    func disjoint() {
        let input = [span(9, 0, 10, 0), span(11, 0, 12, 0)]
        #expect(DaySchedule.merge(input) == input)
    }

    @Test("Empty ranges are discarded")
    func dropsEmpty() {
        let merged = DaySchedule.merge([span(9, 0, 9, 0), span(10, 0, 11, 0)])
        #expect(merged == [span(10, 0, 11, 0)])
    }
}

// MARK: - gaps

@Suite("DaySchedule.gaps")
struct GapTests {

    @Test("An empty day is one gap spanning the whole window")
    func emptyDay() {
        #expect(DaySchedule.gaps(busy: [], within: workday) == [workday])
    }

    @Test("A midday meeting splits the day in two")
    func splitsDay() {
        let gaps = DaySchedule.gaps(busy: [span(12, 0, 13, 0)], within: workday)
        #expect(gaps == [span(7, 0, 12, 0), span(13, 0, 22, 0)])
    }

    @Test("Busy time outside the window is ignored")
    func clipsToWindow() {
        let gaps = DaySchedule.gaps(busy: [span(5, 0, 6, 0), span(23, 0, 23, 30)], within: workday)
        #expect(gaps == [workday])
    }

    @Test("A meeting overhanging the window edge only consumes the inside part")
    func trimsOverhang() {
        let gaps = DaySchedule.gaps(busy: [span(6, 0, 8, 0)], within: workday)
        #expect(gaps == [span(8, 0, 22, 0)])
    }

    @Test("Back-to-back meetings leave no phantom gap between them")
    func noPhantomGap() {
        let gaps = DaySchedule.gaps(busy: [span(9, 0, 10, 0), span(10, 0, 11, 0)], within: workday)
        #expect(gaps == [span(7, 0, 9, 0), span(11, 0, 22, 0)])
    }

    @Test("Nested meetings are handled as one busy stretch")
    func nestedBusy() {
        let gaps = DaySchedule.gaps(busy: [span(9, 0, 12, 0), span(10, 0, 11, 0)], within: workday)
        #expect(gaps == [span(7, 0, 9, 0), span(12, 0, 22, 0)])
    }

    @Test("A fully booked day has no gaps")
    func fullyBooked() {
        #expect(DaySchedule.gaps(busy: [span(6, 0, 23, 0)], within: workday).isEmpty)
    }

    @Test("Slivers below the minimum duration are discarded")
    func dropsSlivers() {
        let busy = [span(9, 0, 10, 0), span(10, 5, 11, 0)]
        let gaps = DaySchedule.gaps(busy: busy, within: workday, minimumDuration: 15 * 60)
        #expect(!gaps.contains(span(10, 0, 10, 5)))
        #expect(gaps == [span(7, 0, 9, 0), span(11, 0, 22, 0)])
    }

    @Test("A meeting flush against the window start produces no leading gap")
    func flushStart() {
        let gaps = DaySchedule.gaps(busy: [span(7, 0, 9, 0)], within: workday)
        #expect(gaps == [span(9, 0, 22, 0)])
    }

    @Test("A meeting flush against the window end produces no trailing gap")
    func flushEnd() {
        let gaps = DaySchedule.gaps(busy: [span(20, 0, 22, 0)], within: workday)
        #expect(gaps == [span(7, 0, 20, 0)])
    }

    @Test("An empty window has no gaps")
    func emptyWindow() {
        #expect(DaySchedule.gaps(busy: [], within: span(9, 0, 9, 0)).isEmpty)
    }
}

// MARK: - firstFit

@Suite("DaySchedule.firstFit")
struct FirstFitTests {

    @Test("Takes the earliest gap that is large enough")
    func earliestFit() {
        let gaps = [span(9, 0, 9, 30), span(11, 0, 13, 0)]
        let fit = DaySchedule.firstFit(duration: 3600, in: gaps)
        #expect(fit == span(11, 0, 12, 0))
    }

    @Test("A gap of exactly the right size is accepted")
    func exactFit() {
        let fit = DaySchedule.firstFit(duration: 3600, in: [span(9, 0, 10, 0)])
        #expect(fit == span(9, 0, 10, 0))
    }

    @Test("Returns nil when nothing is large enough")
    func noFit() {
        #expect(DaySchedule.firstFit(duration: 7200, in: [span(9, 0, 10, 0)]) == nil)
    }

    @Test("notBefore trims a gap that has partly passed")
    func notBeforeTrims() {
        let fit = DaySchedule.firstFit(duration: 3600, in: [span(9, 0, 13, 0)], notBefore: at(11, 30))
        #expect(fit == span(11, 30, 12, 30))
    }

    @Test("notBefore skips a gap it renders too small")
    func notBeforeSkips() {
        let gaps = [span(9, 0, 12, 0), span(14, 0, 16, 0)]
        let fit = DaySchedule.firstFit(duration: 3600, in: gaps, notBefore: at(11, 45))
        #expect(fit == span(14, 0, 15, 0))
    }

    @Test("Zero duration never fits anywhere")
    func zeroDuration() {
        #expect(DaySchedule.firstFit(duration: 0, in: [workday]) == nil)
    }
}

// MARK: - snap

@Suite("DaySchedule.snap")
struct SnapTests {

    @Test("Rounds down below the halfway point")
    func roundsDown() {
        #expect(DaySchedule.snap(at(9, 7), toMinutes: 15, calendar: cal) == at(9, 0))
    }

    @Test("Rounds up at and above the halfway point")
    func roundsUp() {
        #expect(DaySchedule.snap(at(9, 8), toMinutes: 15, calendar: cal) == at(9, 15))
    }

    @Test("A time already on the grid is unchanged")
    func alreadyAligned() {
        #expect(DaySchedule.snap(at(9, 30), toMinutes: 15, calendar: cal) == at(9, 30))
    }

    @Test("Rounding can be forced downward")
    func explicitFloor() {
        let snapped = DaySchedule.snap(at(9, 14), toMinutes: 15, calendar: cal, rounding: .down)
        #expect(snapped == at(9, 0))
    }

    @Test("A non-positive grid leaves the date untouched")
    func zeroGrid() {
        #expect(DaySchedule.snap(at(9, 7), toMinutes: 0, calendar: cal) == at(9, 7))
    }
}

// MARK: - window

@Suite("DaySchedule.window")
struct WindowTests {

    @Test("Builds the planning window from minutes past midnight")
    func buildsWindow() {
        let w = DaySchedule.window(for: at(15), startMinute: 7 * 60, endMinute: 22 * 60, calendar: cal)
        #expect(w == workday)
    }
}
