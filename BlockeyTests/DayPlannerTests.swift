import Testing
import Foundation
import SwiftData
@testable import Blockey

/// Pins what stamp, fill, clear, place and return-to-inbox did while they lived in `TodayView`,
/// so moving them into `DayPlanner` can be shown to change nothing.
@Suite("DayPlanner characterises the old TodayView behaviour")
@MainActor
struct DayPlannerTests {

    private let calendar = Calendar.current

    /// A Monday far from any DST change in common zones.
    private func day() -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!
    }

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: hour, minute: minute))!
    }

    private func range(_ h1: Int, _ h2: Int) -> TimeRange {
        TimeRange(start: at(h1), end: at(h2))
    }

    private func range(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int) -> TimeRange {
        TimeRange(start: at(h1, m1), end: at(h2, m2))
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self, DayTemplate.self, TemplateRow.self, TemplateAssignment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @MainActor private struct Rig {
        let writer: FakeBlockWriter
        let context: ModelContext
        let planner: DayPlanner
    }

    private func makeRig() throws -> Rig {
        let context = try makeContext()
        let writer = FakeBlockWriter()
        return Rig(writer: writer, context: context, planner: DayPlanner(writer: writer, context: context))
    }

    private func inputs(now: Date? = nil, isToday: Bool = false, alarm: Int? = nil) -> DayPlanInputs {
        let window = range(7, 22)
        let n = now ?? at(6)
        let plannable = isToday
            ? TimeRange(start: max(window.start, n), end: max(window.start, window.end))
            : window
        return DayPlanInputs(date: day(), now: n, isToday: isToday, window: window,
                             plannableWindow: plannable, alarmMinutesBefore: alarm,
                             calendar: calendar, hiddenCalendarIDs: [])
    }

    private func template(_ rows: [(String, Int, Int, String)]) -> StampTemplate {
        let items = rows.map { TemplateStamper.Item(title: $0.0, startMinuteOfDay: $0.1, durationMinutes: $0.2) }
        var slugs: [UUID: String] = [:]
        for (item, row) in zip(items, rows) { slugs[item.id] = row.3 }
        return StampTemplate(items: items, slugs: slugs)
    }

    private func inbox(_ context: ModelContext) throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.sortIndex)]))
    }

    // MARK: Stamp

    @Test("Stamp on an empty day places rows at their intended times")
    func stampEmptyDay() throws {
        let rig = try makeRig()
        let t = template([("Deep", 9 * 60, 120, "deep"), ("Lunch", 12 * 60, 60, "rest")])
        let result = rig.planner.stamp(t, inputs: inputs(), openTasks: [])

        #expect(result.created.map(\.range) == [range(9, 11), range(12, 13)])
        #expect(result.movedCount == 0)
        #expect(result.toInbox == 0)
        #expect(rig.writer.created.map(\.slug) == ["deep", "rest"])
        #expect(try inbox(rig.context).isEmpty)
        #expect(result.message == PlanMessage(text: "Stamped 2 blocks"))
    }

    @Test("A row that collides with a fixed event moves, and the message says so")
    func stampMovesAroundFixed() throws {
        let rig = try makeRig()
        let meeting = range(9, 10)
        rig.writer.addFixed("Standup", meeting)
        let t = template([("Deep", 9 * 60, 60, "deep")])
        let result = rig.planner.stamp(t, inputs: inputs(), openTasks: [])

        #expect(result.created.count == 1)
        #expect(result.movedCount == 1)
        #expect(result.created[0].range.start == at(10))
        #expect(!result.created[0].range.overlaps(meeting))
        #expect(result.message == PlanMessage(text: "Stamped 1 block \u{00B7} 1 moved to fit"))
    }

    @Test("A row that cannot fit becomes a droppedFromTemplate task with its slug, in sortIndex order")
    func stampUnplacedGoesToInbox() throws {
        let rig = try makeRig()
        // Everything from 7 to 22 is taken.
        rig.writer.addFixed("All day busy", range(7, 22))
        let t = template([("First", 9 * 60, 60, "rest"), ("Second", 10 * 60, 30, "telepathy")])
        let existing = TaskItem(title: "Old", sortIndex: 4)
        rig.context.insert(existing)

        let result = rig.planner.stamp(t, inputs: inputs(), openTasks: [existing])

        #expect(result.created.isEmpty)
        #expect(result.unplaced.count == 2)
        let tasks = try inbox(rig.context)
        // nextInboxSortIndex = 4 - 1 = 3, then 2: first row ends up first in the list... descending
        // index means later rows sort earlier, so the order below is the sortIndex order.
        let dropped = tasks.filter(\.droppedFromTemplate)
        #expect(dropped.map(\.sortIndex) == [2, 3])
        #expect(dropped.map(\.title) == ["Second", "First"])
        #expect(dropped.map(\.categoryRaw) == ["telepathy", "rest"])
        #expect(dropped.map(\.estimatedMinutes) == [30, 60])
        #expect(Set(result.insertedTaskIDs) == Set(dropped.map(\.id)))
        #expect(result.message == PlanMessage(text: "Stamped 0 blocks \u{00B7} 2 to inbox", isWarning: true))
    }

    @Test("A create failure sends the row to the inbox and counts as a failure")
    func stampCreateFailure() throws {
        let rig = try makeRig()
        rig.writer.failCreateAtCalls = [0]
        let t = template([("A", 9 * 60, 60, "deep"), ("B", 11 * 60, 60, "rest")])
        let result = rig.planner.stamp(t, inputs: inputs(), openTasks: [])

        #expect(result.created.map(\.title) == ["B"])
        #expect(result.failures.map(\.title) == ["A"])
        let tasks = try inbox(rig.context)
        #expect(tasks.map(\.title) == ["A"])
        #expect(tasks[0].droppedFromTemplate)
        #expect(tasks[0].categoryRaw == "deep")
        #expect(result.message == PlanMessage(
            text: "Stamped 1 block \u{00B7} 1 to inbox (1 couldn\u{2019}t be saved)", isWarning: true))
    }

    @Test("Unplaced rows come before failed rows in the inbox")
    func stampUnplacedThenFailures() throws {
        let rig = try makeRig()
        rig.writer.failCreateAtCalls = [0]
        // "Fail" is placed then fails to write; "Huge" cannot fit anywhere.
        let t = template([("Fail", 9 * 60, 60, "deep"), ("Huge", 10 * 60, 20 * 60, "rest")])
        let result = rig.planner.stamp(t, inputs: inputs(), openTasks: [])
        #expect(result.unplaced.map(\.title) == ["Huge"])
        #expect(result.failures.map(\.title) == ["Fail"])
        // Inserted in that order, with a descending index.
        let tasks = try inbox(rig.context)
        #expect(tasks.map(\.title) == ["Fail", "Huge"])
        #expect(tasks.map(\.sortIndex) == [-2, -1])
    }

    @Test("Alarm minutes reach the writer, and are absent when alarms are off")
    func stampAlarm() throws {
        let rig = try makeRig()
        let t = template([("A", 9 * 60, 60, "deep")])
        rig.planner.stamp(t, inputs: inputs(alarm: 10), openTasks: [])
        rig.planner.stamp(t, inputs: inputs(alarm: nil), openTasks: [])
        #expect(rig.writer.created.map(\.alarm) == [10, nil])
    }

    @Test("notBefore applies only on today")
    func stampNotBeforeOnlyToday() throws {
        let t = template([("Early", 9 * 60, 60, "deep")])
        let now = at(11)

        let today = try makeRig()
        let r1 = today.planner.stamp(t, inputs: inputs(now: now, isToday: true), openTasks: [])
        #expect(r1.created.allSatisfy { $0.range.start >= now })
        #expect(r1.movedCount == 1)

        let other = try makeRig()
        let r2 = other.planner.stamp(t, inputs: inputs(now: now, isToday: false), openTasks: [])
        #expect(r2.created.map(\.range) == [range(9, 10)])
        #expect(r2.movedCount == 0)
    }

    @Test("Fixed events are never overlapped by anything placed")
    func neverOverlapsFixed() throws {
        let rig = try makeRig()
        let fixed = [range(9, 10), range(10, 30, 11, 0), range(13, 15)]
        for (i, r) in fixed.enumerated() { rig.writer.addFixed("M\(i)", r) }
        let t = template([("A", 9 * 60, 60, "deep"), ("B", 10 * 60, 60, "deep"),
                          ("C", 13 * 60, 90, "deep"), ("D", 14 * 60, 60, "deep")])

        let stamped = rig.planner.stamp(t, inputs: inputs(), openTasks: [])
        for block in stamped.created {
            for f in fixed { #expect(!block.range.overlaps(f), "\(block.title) overlaps a fixed event") }
        }

        let tasks = (0..<4).map { TaskItem(title: "T\($0)", estimatedMinutes: 60, sortIndex: $0) }
        tasks.forEach(rig.context.insert)
        let filled = rig.planner.fillDay(inputs: inputs(), openTasks: tasks)
        for block in filled.created {
            for f in fixed { #expect(!block.range.overlaps(f)) }
        }
    }

    // MARK: Replace

    @Test("Replace clears first, returns sourced tasks to the inbox, and counts tokenless blocks as lost")
    func replaceClearsThenStamps() throws {
        let rig = try makeRig()
        let source = UUID()
        rig.writer.seedBlock("From inbox", range(9, 10), slug: "rest", source: source)
        rig.writer.seedBlock("Stamped earlier", range(10, 11))           // token, no source
        rig.writer.seedBlock("Stripped", range(11, 12), tokenless: true)  // lost for good
        let t = template([("New", 9 * 60, 60, "deep")])

        let result = try rig.planner.replace(with: t, inputs: inputs(), openTasks: [])

        #expect(result.cleared?.returned == 1)
        #expect(result.cleared?.lost == 1)
        #expect(result.cleared?.removed.count == 3)
        // The only block left is the new one, at the row's time: the clear freed 9 to 10.
        #expect(rig.writer.blocks.map(\.title) == ["New"])
        #expect(rig.writer.blocks[0].range == range(9, 10))
        let tasks = try inbox(rig.context)
        #expect(tasks.map(\.title) == ["From inbox"])
        #expect(tasks[0].categoryRaw == "rest")
        #expect(!tasks[0].droppedFromTemplate)
        #expect(result.message == PlanMessage(text: "Stamped 1 block \u{00B7} 1 lost", isWarning: true))
    }

    @Test("Replace stamps against the day after the clear, but fixed events stay busy")
    func replaceKeepsFixedBusy() throws {
        let rig = try makeRig()
        rig.writer.addFixed("Meeting", range(9, 10))
        rig.writer.seedBlock("Mine", range(11, 12))
        let t = template([("New", 9 * 60, 60, "deep"), ("Other", 11 * 60, 60, "deep")])
        let result = try rig.planner.replace(with: t, inputs: inputs(), openTasks: [])
        #expect(result.created.map(\.range).contains(range(11, 12)))
        #expect(result.created.allSatisfy { !$0.range.overlaps(range(9, 10)) })
    }

    @Test("A failed clear throws and changes nothing")
    func replaceClearFailure() throws {
        let rig = try makeRig()
        rig.writer.seedBlock("Mine", range(9, 10), source: UUID())
        rig.writer.failDeleteAll = true
        #expect(throws: (any Error).self) {
            try rig.planner.replace(with: template([("New", 9 * 60, 60, "deep")]), inputs: inputs(), openTasks: [])
        }
        #expect(rig.writer.blocks.count == 1)
        #expect(rig.writer.createCalls == 0)
        #expect(try inbox(rig.context).isEmpty)
    }

    // MARK: Clear

    @Test("Clear day messages cover each outcome")
    func clearMessages() throws {
        let rig = try makeRig()
        #expect(try rig.planner.clear(inputs: inputs(), openTasks: []).message == PlanMessage(text: "Day cleared"))

        rig.writer.seedBlock("A", range(9, 10), source: UUID())
        #expect(try rig.planner.clear(inputs: inputs(), openTasks: []).message
                == PlanMessage(text: "Day cleared \u{00B7} 1 back in the inbox"))

        rig.writer.seedBlock("B", range(9, 10), tokenless: true)
        #expect(try rig.planner.clear(inputs: inputs(), openTasks: []).message
                == PlanMessage(text: "Day cleared \u{00B7} 1 could not be returned", isWarning: true))

        rig.writer.seedBlock("C", range(9, 10), source: UUID())
        rig.writer.seedBlock("D", range(10, 11), tokenless: true)
        #expect(try rig.planner.clear(inputs: inputs(), openTasks: []).message
                == PlanMessage(text: "Day cleared \u{00B7} 1 back in the inbox, 1 lost", isWarning: true))
    }

    @Test("Clear inserts returned tasks above the existing inbox, descending")
    func clearSortIndexes() throws {
        let rig = try makeRig()
        let existing = TaskItem(title: "Old", sortIndex: 0)
        rig.context.insert(existing)
        rig.writer.seedBlock("A", range(9, 10), source: UUID())
        rig.writer.seedBlock("B", range(10, 11), source: UUID())
        _ = try rig.planner.clear(inputs: inputs(), openTasks: [existing])
        let tasks = try inbox(rig.context)
        #expect(tasks.map(\.title) == ["B", "A", "Old"])
        #expect(tasks.map(\.sortIndex) == [-2, -1, 0])
    }

    @Test("A failed clear throws and inserts nothing")
    func clearFailure() throws {
        let rig = try makeRig()
        rig.writer.seedBlock("A", range(9, 10), source: UUID())
        rig.writer.failDeleteAll = true
        #expect(throws: (any Error).self) { try rig.planner.clear(inputs: inputs(), openTasks: []) }
        #expect(try inbox(rig.context).isEmpty)
    }

    // MARK: Fill

    @Test("Fill places open tasks first-fit, deletes them, and carries slug and source")
    func fillPlacesAndDeletes() throws {
        let rig = try makeRig()
        rig.writer.addFixed("Meeting", range(7, 8))
        let a = TaskItem(title: "A", estimatedMinutes: 60, categoryRaw: "rest", sortIndex: 0)
        let b = TaskItem(title: "B", estimatedMinutes: 30, categoryRaw: "deep", sortIndex: 1)
        [a, b].forEach(rig.context.insert)
        let idA = a.id, idB = b.id

        let result = rig.planner.fillDay(inputs: inputs(), openTasks: [a, b])

        #expect(result.created.map(\.range) == [range(8, 9), range(9, 0, 9, 30)])
        #expect(rig.writer.created.map(\.slug) == ["rest", "deep"])
        #expect(rig.writer.created.map(\.source) == [idA, idB])
        #expect(try inbox(rig.context).isEmpty)
        #expect(result.deletedTasks.map(\.id) == [idA, idB])
        #expect(result.message == PlanMessage(text: "Placed 2 tasks"))
    }

    @Test("Fill keeps going after one failure and leaves the failed task in the inbox")
    func fillContinuesAfterFailure() throws {
        let rig = try makeRig()
        rig.writer.failCreateAtCalls = [0]
        let a = TaskItem(title: "A", estimatedMinutes: 30, sortIndex: 0)
        let b = TaskItem(title: "B", estimatedMinutes: 30, sortIndex: 1)
        [a, b].forEach(rig.context.insert)

        let result = rig.planner.fillDay(inputs: inputs(), openTasks: [a, b])

        #expect(result.failed == 1)
        #expect(result.placed == 1)
        #expect(try inbox(rig.context).map(\.title) == ["A"])
        // A failed write did not consume its slot: B takes the first one.
        #expect(result.created[0].range.start == at(7))
        #expect(result.message == PlanMessage(
            text: "Placed 1, but 1 couldn\u{2019}t be saved to your calendar.", isWarning: true))
    }

    @Test("Fill says Nothing fits when nothing fits, and a single task reads singular")
    func fillNothingFits() throws {
        let rig = try makeRig()
        let t = TaskItem(title: "Big", estimatedMinutes: 60, sortIndex: 0)
        rig.context.insert(t)
        rig.writer.addFixed("All day busy", range(7, 22))
        let result = rig.planner.fillDay(inputs: inputs(), openTasks: [t])
        #expect(result.placed == 0)
        #expect(result.message == PlanMessage(text: "Nothing fits in the time you have left", isWarning: true))
        #expect(try inbox(rig.context).count == 1)

        let rig2 = try makeRig()
        let one = TaskItem(title: "One", estimatedMinutes: 30, sortIndex: 0)
        rig2.context.insert(one)
        #expect(rig2.planner.fillDay(inputs: inputs(), openTasks: [one]).message
                == PlanMessage(text: "Placed 1 task"))
    }

    @Test("Fill plans inside the plannable window, so nothing lands in elapsed hours")
    func fillUsesPlannableWindow() throws {
        let rig = try makeRig()
        let t = TaskItem(title: "T", estimatedMinutes: 30, sortIndex: 0)
        rig.context.insert(t)
        let result = rig.planner.fillDay(inputs: inputs(now: at(15), isToday: true), openTasks: [t])
        #expect(result.created[0].range.start == at(15))
    }

    // MARK: Place

    @Test("Place writes the block with the task's slug and source, then deletes the task")
    func placeDeletesTask() throws {
        let rig = try makeRig()
        let task = TaskItem(title: "Write", estimatedMinutes: 45, categoryRaw: "telepathy", sortIndex: 0)
        rig.context.insert(task)
        let id = task.id

        let result = try rig.planner.place(task, at: at(14), inputs: inputs(alarm: 5))

        #expect(result.created.range == TimeRange(start: at(14), duration: 45 * 60))
        #expect(rig.writer.created[0].slug == "telepathy")
        #expect(rig.writer.created[0].source == id)
        #expect(rig.writer.created[0].alarm == 5)
        #expect(try inbox(rig.context).isEmpty)
        #expect(result.deletedTask.id == id)
        #expect(result.message.text == "Blocked \(at(14).formatted(date: .omitted, time: .shortened))")
        #expect(!result.message.isWarning)
    }

    @Test("A failed place throws and keeps the task")
    func placeFailureKeepsTask() throws {
        let rig = try makeRig()
        rig.writer.failCreateAtCalls = [0]
        let task = TaskItem(title: "Write", sortIndex: 0)
        rig.context.insert(task)
        #expect(throws: (any Error).self) { try rig.planner.place(task, at: at(14), inputs: inputs()) }
        #expect(try inbox(rig.context).count == 1)
    }

    // MARK: Return to inbox

    @Test("Return to inbox deletes the block, then inserts a task keeping the slug, on top of the inbox")
    func returnInserts() throws {
        let rig = try makeRig()
        let existing = TaskItem(title: "Old", sortIndex: 2)
        rig.context.insert(existing)
        let block = rig.writer.seedBlock("Call", range(9, 0, 9, 45), slug: "telepathy", source: UUID())

        let result = try rig.planner.returnToInbox(block, openTasks: [existing])

        #expect(rig.writer.blocks.isEmpty)
        let tasks = try inbox(rig.context)
        #expect(tasks.map(\.title) == ["Call", "Old"])
        #expect(tasks[0].sortIndex == 1)
        #expect(tasks[0].estimatedMinutes == 45)
        #expect(tasks[0].categoryRaw == "telepathy")
        #expect(result.insertedTaskID == tasks[0].id)
        #expect(result.message == PlanMessage(text: "Returned to inbox"))
    }

    @Test("A tokenless block returns with the fallback slug")
    func returnTokenlessUsesFallback() throws {
        let rig = try makeRig()
        let block = rig.writer.seedBlock("Mystery", range(9, 10), tokenless: true)
        _ = try rig.planner.returnToInbox(block, openTasks: [])
        #expect(try inbox(rig.context)[0].categoryRaw == BlockCategory.fallback.rawValue)
    }

    @Test("Return to inbox does not insert when the delete fails")
    func returnDeleteFailure() throws {
        let rig = try makeRig()
        let block = rig.writer.seedBlock("Call", range(9, 10))
        rig.writer.failAllDeletes = true
        #expect(throws: (any Error).self) { try rig.planner.returnToInbox(block, openTasks: []) }
        #expect(try inbox(rig.context).isEmpty)
        #expect(rig.writer.blocks.count == 1)
    }

    // MARK: Undo-readiness of the results

    @Test("Results carry what an Undo record needs")
    func resultsCarryUndoData() throws {
        let rig = try makeRig()
        let t = template([("A", 9 * 60, 60, "deep")])
        let stamped = rig.planner.stamp(t, inputs: inputs(), openTasks: [])
        #expect(stamped.created.compactMap { $0.token?.id }.count == 1)

        let task = TaskItem(title: "T", estimatedMinutes: 30, categoryRaw: "rest", sortIndex: 7)
        rig.context.insert(task)
        let filled = rig.planner.fillDay(inputs: inputs(), openTasks: [task])
        #expect(filled.deletedTasks == [TaskSnapshot(id: task.id, title: "T", estimatedMinutes: 30,
                                                     categoryRaw: "rest", sortIndex: 7,
                                                     createdAt: filled.deletedTasks[0].createdAt,
                                                     droppedFromTemplate: false)])
        #expect(filled.created[0].token?.sourceTaskID == task.id)
    }
}
