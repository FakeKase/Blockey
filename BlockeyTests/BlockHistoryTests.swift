import Testing
import Foundation
@testable import Blockey

/// Plan Appendix A.7, the mapping half. Runs without an event store: the filter is a pure
/// function over `EventFacts`. Dates are walked back from the real "now" in the machine's own
/// calendar (Buddhist here), never named by year.
@Suite("BlockHistory")
struct BlockHistoryTests {

    let cal = TestDates.calendar()
    var now: Date { TestDates.ordinaryDay(in: cal).addingTimeInterval(14 * 3600) }
    var windowStart: Date { BlockHistory.windowStart(endingAt: now, days: 90, calendar: cal) ?? .distantPast }

    func facts(_ title: String = "Gym", hoursAgo: Double = 5, minutes: Double = 45,
               allDay: Bool = false, recurring: Bool = false, url: URL? = nil,
               ours: Bool = true) -> EventFacts {
        let start = now.addingTimeInterval(-hoursAgo * 3600)
        return EventFacts(title: title, start: start, end: start.addingTimeInterval(minutes * 60),
                          isAllDay: allDay, hasRecurrence: recurring, url: url, isInBlockeyCalendar: ours)
    }

    func map(_ f: [EventFacts], limit: Int = 2000) -> [TitleSample] {
        BlockHistory.samples(from: f, windowStart: windowStart, now: now, limit: limit)
    }

    @Test func historySkipsAllDay() { #expect(map([facts(allDay: true)]).isEmpty) }

    @Test func historySkipsRecurring() { #expect(map([facts(recurring: true)]).isEmpty) }

    @Test func historySkipsDetachedOccurrence() {
        let start = now.addingTimeInterval(-3600 * 5)
        let detached = EventFacts(title: "Standup", start: start, end: start.addingTimeInterval(1800),
                                  isAllDay: false, hasRecurrence: false, url: nil,
                                  isInBlockeyCalendar: true, isDetached: true)
        #expect(map([detached]).isEmpty)
    }

    @Test func historyCapTieOnStartIsDeterministic() {
        let start = now.addingTimeInterval(-3600 * 5)
        func f(_ t: String, _ mins: Double) -> EventFacts {
            EventFacts(title: t, start: start, end: start.addingTimeInterval(mins * 60), isAllDay: false,
                       hasRecurrence: false, url: nil, isInBlockeyCalendar: true)
        }
        let all = [f("B", 30), f("A", 30), f("A", 60), f("C", 30)]
        let expected = ["A", "A", "B"]
        for _ in 0..<5 {
            let r = map(all.shuffled(), limit: 3)
            #expect(r.map(\.title) == expected)
            #expect(r.first?.minutes == 60)
        }
    }

    @Test func historySkipsMultiDay() {
        #expect(map([facts(minutes: 24 * 60)]).isEmpty)
        #expect(map([facts(hoursAgo: 80, minutes: 50 * 60)]).isEmpty)
        #expect(map([facts(minutes: 23 * 60)]).count == 1)
    }

    @Test func historySkipsOtherCalendars() { #expect(map([facts(ours: false)]).isEmpty) }

    @Test func historySkipsSigningReminder() {
        // Marked, and the legacy form: all-day, exact title, no url.
        let marked = facts(SigningReminder.title, url: SigningReminder.markerURL)
        let markedTimed = facts("anything", url: SigningReminder.markerURL)
        let legacy = facts(SigningReminder.title, allDay: true)
        #expect(map([marked, markedTimed, legacy]).isEmpty)
        // A real block the user happened to name the same thing is history.
        #expect(map([facts(SigningReminder.title)]).count == 1)
    }

    @Test func historyKeepsTokenlessEventsWithNoCategory() {
        let r = map([facts("Tokenless")])
        #expect(r.count == 1)
        #expect(r.first?.categorySlug == nil)
        let token = BlockToken(categorySlug: "health")
        let withToken = map([facts("Tokened", url: token.url)])
        #expect(withToken.first?.categorySlug == "health")
        // A url that is not ours (a meeting link) is tokenless, not a reason to skip.
        let link = URL(string: "https://example.com/meet")
        #expect(map([facts("Linked", url: link)]).first?.categorySlug == nil)
    }

    @Test func historyUsesCurrentEventTitle() {
        #expect(map([facts("Renamed in Calendar")]).first?.title == "Renamed in Calendar")
        #expect(map([facts("  \n ")]).isEmpty)
    }

    @Test func historyDurationIsActualDurationZeroDropped() {
        #expect(map([facts(minutes: 50)]).first?.minutes == 50)
        #expect(map([facts(minutes: 0)]).isEmpty)
        #expect(map([facts(minutes: 0.2)]).isEmpty)
        let backwards = EventFacts(title: "Odd", start: now.addingTimeInterval(-3600),
                                   end: now.addingTimeInterval(-7200), isAllDay: false,
                                   hasRecurrence: false, url: nil, isInBlockeyCalendar: true)
        #expect(map([backwards]).isEmpty)
    }

    @Test func historyExcludesFutureEvents() {
        #expect(map([facts(hoursAgo: -1)]).isEmpty)
        // In progress counts: started a minute ago, ends in the future.
        #expect(map([facts(hoursAgo: 1.0 / 60, minutes: 30)]).count == 1)
    }

    @Test func historyBoundaryAt90CalendarDaysAcrossDst() {
        // A zone with DST, with a window that crosses a transition. The boundary is midnight 90
        // calendar days back, not 90 x 86,400 seconds, which would be an hour off.
        let zoned = TestDates.calendar(timeZone: TimeZone(identifier: "America/New_York"))
        guard let springDay = TestDates.nextSpringForward(in: zoned),
              let anchor = zoned.date(byAdding: .day, value: 10, to: springDay) else {
            Issue.record("no anchor"); return
        }
        let at = anchor.addingTimeInterval(12 * 3600)
        let start = BlockHistory.windowStart(endingAt: at, days: 90, calendar: zoned)
        #expect(start == zoned.date(byAdding: .day, value: -90, to: zoned.startOfDay(for: at)))
        #expect(start != Optional(at.addingTimeInterval(-90 * 86_400)))
        guard let start else { return }
        func f(_ s: Date) -> EventFacts {
            EventFacts(title: "T", start: s, end: s.addingTimeInterval(1800), isAllDay: false,
                       hasRecurrence: false, url: nil, isInBlockeyCalendar: true)
        }
        let inside = BlockHistory.samples(from: [f(start)], windowStart: start, now: at, limit: 10)
        let outside = BlockHistory.samples(from: [f(start.addingTimeInterval(-60))], windowStart: start, now: at, limit: 10)
        #expect(inside.count == 1)
        #expect(outside.isEmpty)
    }

    @Test func historyCapKeepsNewest() {
        let many = (0..<50).map { facts("T\($0)", hoursAgo: Double($0) + 1) }
        let r = map(many.shuffled(), limit: 10)
        #expect(r.count == 10)
        #expect(Set(r.map(\.title)) == Set((0..<10).map { "T\($0)" }))
        #expect(r.first?.title == "T0")   // newest first
        #expect(map(many, limit: 0).isEmpty)
    }

    @Test func sampleCarriesStartAsDate() {
        let f = facts("Gym", hoursAgo: 3)
        #expect(map([f]).first?.date == f.start)
    }
}
