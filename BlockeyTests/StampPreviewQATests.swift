import Testing
import Foundation
import SwiftData
@testable import Blockey

/// QA additions for issue #3 task 2.1: staleness strictness, and "stale writes nothing" in Start over.
@Suite("Stamp preview staleness (QA)")
@MainActor
struct StampPreviewQATests {

    // The machine's calendar identifier pinned to UTC; the day is found from today (issue #6).
    private let calendar = TestDates.calendar(timeZone: TimeZone(identifier: "UTC") ?? .gmt)
    private let monday: Date

    init() { monday = TestDates.ordinaryDay(weekday: 2, in: calendar) }

    private func at(_ h: Int, _ m: Int = 0, _ s: Int = 0) -> Date {
        calendar.date(bySettingHour: h, minute: m, second: s, of: monday)!
    }
    private func range(_ h1: Int, _ h2: Int) -> TimeRange { TimeRange(start: at(h1), end: at(h2)) }

    private func inputs(now: Date, isToday: Bool = true) -> DayPlanInputs {
        let window = TimeRange(start: at(7), end: at(22))
        return DayPlanInputs(date: at(0), now: now, isToday: isToday, window: window,
                             plannableWindow: TimeRange(start: max(window.start, now), end: window.end),
                             alarmMinutesBefore: nil, calendar: calendar, hiddenCalendarIDs: [])
    }

    private func rig() throws -> (FakeBlockWriter, DayPlanner, ModelContext) {
        let container = try ModelContainer(
            for: TaskItem.self, DayTemplate.self, TemplateRow.self, TemplateAssignment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let w = FakeBlockWriter()
        return (w, DayPlanner(writer: w, context: ctx), ctx)
    }

    private func template(_ rows: [(String, Int, Int)]) -> StampTemplate {
        let items = rows.map { TemplateStamper.Item(title: $0.0, startMinuteOfDay: $0.1, durationMinutes: $0.2) }
        return StampTemplate(items: items, slugs: Dictionary(uniqueKeysWithValues: items.map { ($0.id, "deep") }))
    }

    @Test("The clock advancing a few seconds, with no effect on placement, is not stale")
    func advancingNowWithoutEffectIsNotStale() throws {
        let (writer, planner, _) = try rig()
        let t = template([("Later", 15 * 60, 60)])
        let shown = planner.preview(t, inputs: inputs(now: at(10, 0, 0)), mode: .keep)
        guard case .written = try planner.stamp(t, expecting: shown, mode: .keep,
                                                 inputs: inputs(now: at(10, 0, 20)), openTasks: []) else {
            Issue.record("spurious stale"); return
        }
        #expect(writer.created.count == 1)
    }

    @Test("A row that fitted and now does not becomes stale, writes nothing, inserts no inbox task")
    func inboxSetChangeIsStaleAndWritesNothing() throws {
        let (writer, planner, ctx) = try rig()
        let t = template([("A", 9 * 60, 60)])
        let shown = planner.preview(t, inputs: inputs(now: at(6), isToday: false), mode: .keep)
        writer.addFixed("Everything", range(7, 22))
        guard case .stale(let fresh) = try planner.stamp(t, expecting: shown, mode: .keep,
                                                          inputs: inputs(now: at(6), isToday: false), openTasks: []) else {
            Issue.record("expected stale"); return
        }
        #expect(fresh.inboxCount == 1)
        #expect(writer.createCalls == 0)
        #expect(try ctx.fetch(FetchDescriptor<TaskItem>()).isEmpty)
    }

    @Test("Stale in Start over deletes nothing and inserts nothing")
    func staleStartOverLeavesOwnBlocksAndInboxUntouched() throws {
        let (writer, planner, ctx) = try rig()
        writer.seedBlock("Mine", range(9, 10), source: UUID())
        let t = template([("A", 9 * 60, 60)])
        let shown = planner.preview(t, inputs: inputs(now: at(6), isToday: false), mode: .startOver)
        writer.addFixed("New", range(9, 10))
        guard case .stale = try planner.stamp(t, expecting: shown, mode: .startOver,
                                               inputs: inputs(now: at(6), isToday: false), openTasks: []) else {
            Issue.record("expected stale"); return
        }
        #expect(writer.blocks.map(\.title) == ["Mine"])
        #expect(writer.createCalls == 0)
        #expect(try ctx.fetch(FetchDescriptor<TaskItem>()).isEmpty)
    }

    @Test("Editing the template between preview and confirm is stale")
    func changedRowDurationIsStale() throws {
        let (_, planner, _) = try rig()
        let items = [TemplateStamper.Item(title: "A", startMinuteOfDay: 9 * 60, durationMinutes: 60)]
        let slugs = [items[0].id: "deep"]
        let shown = planner.preview(StampTemplate(items: items, slugs: slugs),
                                    inputs: inputs(now: at(6), isToday: false), mode: .keep)
        let longer = [TemplateStamper.Item(id: items[0].id, title: "A", startMinuteOfDay: 9 * 60, durationMinutes: 90)]
        guard case .stale = try planner.stamp(StampTemplate(items: longer, slugs: slugs), expecting: shown,
                                               mode: .keep, inputs: inputs(now: at(6), isToday: false), openTasks: []) else {
            Issue.record("expected stale"); return
        }
    }
}
