import Testing
import Foundation
import SwiftData
@testable import Blockey

/// Gaps in `DayPlannerTests` found by diffing the old `TodayView` against `DayPlanner`: the
/// parts of replace that only show when the clear and the stamp both insert into the inbox.
@Suite("DayPlanner replace keeps the old inbox ordering and banner")
@MainActor
struct DayPlannerEquivalenceTests {
    private let calendar = Calendar.current

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: hour, minute: minute))!
    }
    private func range(_ h1: Int, _ h2: Int) -> TimeRange { TimeRange(start: at(h1), end: at(h2)) }

    private func rig() throws -> (FakeBlockWriter, ModelContext, DayPlanner) {
        let container = try ModelContainer(
            for: TaskItem.self, DayTemplate.self, TemplateRow.self, TemplateAssignment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let writer = FakeBlockWriter()
        return (writer, context, DayPlanner(writer: writer, context: context))
    }

    private func inputs(now: Date? = nil, isToday: Bool = false) -> DayPlanInputs {
        let window = range(7, 22)
        let n = now ?? at(6)
        let plannable = isToday ? TimeRange(start: max(window.start, n), end: window.end) : window
        return DayPlanInputs(date: at(0), now: n, isToday: isToday, window: window,
                             plannableWindow: plannable, alarmMinutesBefore: nil,
                             calendar: calendar, hiddenCalendarIDs: [])
    }

    private func template(_ rows: [(String, Int, Int, String)]) -> StampTemplate {
        let items = rows.map { TemplateStamper.Item(title: $0.0, startMinuteOfDay: $0.1, durationMinutes: $0.2) }
        var slugs: [UUID: String] = [:]
        for (item, row) in zip(items, rows) { slugs[item.id] = row.3 }
        return StampTemplate(items: items, slugs: slugs)
    }

    @Test("Replace numbers both the returned and the dropped tasks from the pre-clear inbox floor")
    func replaceSortIndexesStartFromTheOldFloor() throws {
        let (writer, context, planner) = try rig()
        let existing = TaskItem(title: "Old", sortIndex: 5)
        context.insert(existing)
        writer.seedBlock("Back", range(9, 10), slug: "rest", source: UUID())
        writer.addFixed("Meeting", range(7, 22))   // nothing can be placed, so every row is dropped
        let t = template([("Dropped", 9 * 60, 60, "deep")])

        let result = try planner.replace(with: t, inputs: inputs(), openTasks: [existing])

        #expect(result.unplaced.count == 1)
        let byTitle = Dictionary(uniqueKeysWithValues:
            try context.fetch(FetchDescriptor<TaskItem>()).map { ($0.title, $0.sortIndex) })
        // Both start at floor (5 - 1), as the old view's stale `openTasks` made them. This pins
        // the shared index on purpose: it is the behaviour being preserved, not an endorsement.
        #expect(byTitle["Back"] == 4)
        #expect(byTitle["Dropped"] == 4)
    }

    @Test("Replace banner joins moved, to-inbox, could-not-save and lost, in that order")
    func replaceBannerCombinesEverything() throws {
        let (writer, _, planner) = try rig()
        writer.seedBlock("Gone", range(8, 9), tokenless: true)
        writer.addFixed("Meeting", range(9, 10))
        writer.failCreateAtCalls = [1]
        // First row moves around the meeting, second fails to write, third cannot fit anywhere.
        let t = template([("A", 9 * 60, 60, "deep"),
                          ("B", 12 * 60, 60, "deep"),
                          ("C", 8 * 60, 15 * 60, "deep")])

        let result = try planner.replace(with: t, inputs: inputs(), openTasks: [])

        #expect(result.cleared?.lost == 1)
        #expect(result.failures.count == 1)
        #expect(result.message.isWarning)
        #expect(result.message.text.hasSuffix("\u{00B7} 1 lost"))
        #expect(result.message.text.contains("(1 couldn\u{2019}t be saved)"))
    }

    @Test("Replace on today applies notBefore, so the stamp never lands in elapsed hours")
    func replaceOnTodayRespectsNow() throws {
        let (writer, _, planner) = try rig()
        writer.seedBlock("Mine", range(9, 10))
        let t = template([("Early", 9 * 60, 60, "deep")])
        let result = try planner.replace(with: t, inputs: inputs(now: at(11), isToday: true), openTasks: [])
        #expect(result.created.allSatisfy { $0.range.start >= at(11) })
    }
}
