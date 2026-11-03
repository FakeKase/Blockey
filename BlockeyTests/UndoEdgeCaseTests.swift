import Testing
import Foundation
import SwiftData
@testable import Blockey

/// QA probes for Undo (issue #3, task 2.2): the places where "block not found by token" is
/// ambiguous, and where a spent record cannot be retried. The governing rule: work must never end
/// up in neither place, and a duplicate is the acceptable failure.
@Suite("Undo edge cases")
@MainActor
struct UndoEdgeCaseTests {

    private let calendar = Calendar.current

    private var day: Date {
        let today = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .day, value: 3, to: today) ?? today
    }

    private func at(_ hour: Int, on date: Date? = nil) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date ?? day) ?? day
    }

    private func range(_ h1: Int, _ h2: Int, on date: Date? = nil) -> TimeRange {
        TimeRange(start: at(h1, on: date), end: at(h2, on: date))
    }

    private func makeRig() throws -> (writer: FakeBlockWriter, context: ModelContext, planner: DayPlanner) {
        let container = try ModelContainer(
            for: TaskItem.self, DayTemplate.self, TemplateRow.self, TemplateAssignment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let writer = FakeBlockWriter()
        return (writer, context, DayPlanner(writer: writer, context: context))
    }

    private func inputs() -> DayPlanInputs {
        let window = range(7, 22)
        return DayPlanInputs(date: day, now: at(6), isToday: false, window: window,
                             plannableWindow: window, alarmMinutesBefore: nil,
                             calendar: calendar, hiddenCalendarIDs: [])
    }

    private func inbox(_ context: ModelContext) throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.sortIndex)]))
    }

    private func filled(_ titles: [String]) throws -> (writer: FakeBlockWriter, context: ModelContext,
                                                       planner: DayPlanner, result: FillResult) {
        let rig = try makeRig()
        for (i, title) in titles.enumerated() {
            rig.context.insert(TaskItem(title: title, estimatedMinutes: 30, categoryRaw: "deep", sortIndex: 5 + i))
        }
        let result = rig.planner.fillDay(inputs: inputs(), openTasks: try inbox(rig.context))
        return (rig.writer, rig.context, rig.planner, result)
    }

    @Test("Fill undo: a block the user dragged to another day must not also come back as an inbox task")
    func fillUndoBlockMovedToAnotherDayIsNotDuplicated() throws {
        let rig = try filled(["One", "Two"])
        let moved = rig.result.placements[0].block
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        rig.writer.move(moved, to: range(9, 10, on: nextDay))

        // "One" lives on the next day, found by token within a week; reinserting it would show
        // the same work twice.
        let outcome = try rig.planner.undo(rig.result.undo)
        #expect(try inbox(rig.context).map(\.title) == ["Two"])
        #expect(outcome.tasksKeptBecauseBlockSurvived == 1)
    }

    @Test("Fill undo: a stripped, moved block cannot be found, so its task comes back as a documented duplicate")
    func fillUndoStrippedAndMovedBlockIsADocumentedDuplicate() throws {
        let rig = try filled(["One"])
        let block = rig.result.placements[0].block
        rig.writer.stripToken(of: block)
        rig.writer.move(block, to: range(15, 16))

        let outcome = try rig.planner.undo(rig.result.undo)

        // The block stays on the calendar and the task is in the inbox: a duplicate, which is
        // the accepted failure. Losing the task would not be. The message says so.
        #expect(try inbox(rig.context).map(\.title) == ["One"])
        #expect(rig.writer.blocks.count == 1)
        #expect(outcome.tasksReinsertedBlockUnaccountedFor == 1)
        #expect(outcome.message.text.contains("its block may still be on your calendar"))
        #expect(outcome.message.isWarning)
    }

    @Test("Fill undo: a hand-made tokenless block with the same title and time does not hide a deleted block's task")
    func fillUndoHandMadeLookalikeDoesNotSwallowTask() throws {
        let rig = try filled(["One"])
        let block = rig.result.placements[0].block
        rig.writer.userDeletes(block)
        // The user then makes their own block in the Blockey calendar, same name, same time.
        rig.writer.seedBlock(block.title, block.range, tokenless: true)

        _ = try rig.planner.undo(rig.result.undo)

        #expect(try inbox(rig.context).map(\.title) == ["One"])
    }

    @Test("Fill undo: two identical tasks whose blocks were both stripped both come back")
    func fillUndoTwoIdenticalTasksBothStrippedBothComeBack() throws {
        let rig = try filled(["Same", "Same"])
        for placement in rig.result.placements { rig.writer.stripToken(of: placement.block) }

        let outcome = try rig.planner.undo(rig.result.undo)

        #expect(try inbox(rig.context).count == 2)
        #expect(outcome.tasksReinsertedBlockUnaccountedFor == 2)
        #expect(rig.writer.blocks.count == 2)
    }

    @Test("Fill undo: one stripped and one deleted among identical tasks reinserts both")
    func fillUndoIdenticalTasksOneStrippedOneDeleted() throws {
        let rig = try filled(["Same", "Same"])
        rig.writer.stripToken(of: rig.result.placements[0].block)
        rig.writer.userDeletes(rig.result.placements[1].block)

        _ = try rig.planner.undo(rig.result.undo)

        // Neither can be told from the other, and neither may be lost.
        #expect(try inbox(rig.context).count == 2)
        #expect(rig.writer.blocks.count == 1)
    }

    @Test("Start over undo: a cleared block with no inbox task that now hits a meeting goes to the inbox")
    func startOverUndoConflictedBlockWithoutTaskBecomesInboxTask() throws {
        let rig = try makeRig()
        let existing = TaskItem(title: "Existing", sortIndex: 4)
        rig.context.insert(existing)
        rig.writer.seedBlock("Dentist", range(15, 16), slug: "u-\u{0E07}\u{0E32}\u{0E19}")
        let stamp = TemplateStamper.Item(title: "A", startMinuteOfDay: 9 * 60, durationMinutes: 30)
        let template = StampTemplate(items: [stamp], slugs: [stamp.id: "deep"])
        let result = try rig.planner.replace(with: template, inputs: inputs(), openTasks: [existing])
        rig.writer.addFixed("Offsite", range(14, 17))

        let outcome = try rig.planner.undo(result.undo)

        #expect(outcome.notRestoredFixedConflict.map(\.title) == ["Dentist"])
        #expect(!rig.writer.blocks.contains { $0.title == "Dentist" })
        // Not dropped: it is a task now, with its title, length and verbatim slug, on top.
        let tasks = try inbox(rig.context)
        let dentist = try #require(tasks.first { $0.title == "Dentist" })
        #expect(dentist.estimatedMinutes == 60)
        #expect(dentist.categoryRaw == "u-\u{0E07}\u{0E32}\u{0E19}")
        #expect(dentist.sortIndex == (tasks.map(\.sortIndex).min() ?? 0))
        #expect(dentist.sortIndex < existing.sortIndex)
        #expect(outcome.message.text.contains("kept in the inbox"))
        // The record is spent; nothing is lost by that now.
        #expect(try rig.planner.undo(result.undo).alreadyUndone)
    }

    @Test("Round 2 - Fill undo: a placed block made recurring is left alone and its task is not reinserted")
    func fillUndoLeftAloneBlockKeepsTaskOut() throws {
        let rig = try filled(["A", "B"])
        let kept = try #require(rig.result.created.first)
        rig.writer.makeRecurring(kept)

        let outcome = try rig.planner.undo(rig.result.undo)

        #expect(outcome.blocksLeftAlone == 1)
        #expect(outcome.tasksKeptBecauseBlockSurvived == 1)
        #expect(outcome.tasksReinserted == 1)
        #expect(rig.writer.blocks.map(\.id) == [kept.id])
        #expect(try inbox(rig.context).count == 1)
    }

    @Test("Round 2 - Fill undo: block moved 8 days away is outside the search, so its task is reinserted")
    func fillUndoBlockMovedBeyondAWeekDuplicates() throws {
        let rig = try filled(["A"])
        let placed = try #require(rig.result.created.first)
        let far = calendar.date(byAdding: .day, value: 8, to: day) ?? day
        rig.writer.move(placed, to: range(9, 10, on: far))

        let outcome = try rig.planner.undo(rig.result.undo)

        #expect(try inbox(rig.context).count == 1)
        #expect(rig.writer.blocks.count == 1)
        #expect(outcome.tasksReinsertedBlockUnaccountedFor == 1)
        #expect(outcome.message.isWarning)
    }

    @Test("Round 2 - Fill undo: block moved exactly 7 days away is still found")
    func fillUndoBlockMovedSevenDaysIsFound() throws {
        let rig = try filled(["A"])
        let placed = try #require(rig.result.created.first)
        let edge = calendar.date(byAdding: .day, value: 7, to: day) ?? day
        rig.writer.move(placed, to: range(23, 24, on: edge))

        let outcome = try rig.planner.undo(rig.result.undo)

        #expect(try inbox(rig.context).isEmpty)
        #expect(outcome.tasksKeptBecauseBlockSurvived == 1)
    }
}
