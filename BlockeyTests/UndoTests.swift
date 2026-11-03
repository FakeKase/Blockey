import Testing
import Foundation
import SwiftData
@testable import Blockey

/// Undo for stamp, Start over and Fill day (issue #3, task 2.2), against the fake writer and an
/// in-memory store. The real `CalendarService.applyUndo` is not exercised here; see the
/// simulator-only exercise in `DemoScenario`.
///
/// Dates are built from `Calendar.current`'s today, never a literal year (issue #6).
@Suite("Undo")
@MainActor
struct UndoTests {

    private let calendar = Calendar.current

    /// A few days ahead, so nothing here depends on what time the suite runs.
    private var day: Date {
        let today = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .day, value: 3, to: today) ?? today
    }

    private func at(_ hour: Int, _ minute: Int = 0, on date: Date? = nil) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date ?? day) ?? day
    }

    private func range(_ h1: Int, _ h2: Int, on date: Date? = nil) -> TimeRange {
        TimeRange(start: at(h1, on: date), end: at(h2, on: date))
    }

    private struct Rig {
        let writer: FakeBlockWriter
        let context: ModelContext
        let planner: DayPlanner
    }

    private func makeRig() throws -> Rig {
        let container = try ModelContainer(
            for: TaskItem.self, DayTemplate.self, TemplateRow.self, TemplateAssignment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let writer = FakeBlockWriter()
        return Rig(writer: writer, context: context, planner: DayPlanner(writer: writer, context: context))
    }

    private func inputs(date: Date? = nil) -> DayPlanInputs {
        let d = date ?? day
        let window = TimeRange(start: at(7, on: d), end: at(22, on: d))
        return DayPlanInputs(date: d, now: at(6, on: d), isToday: false, window: window,
                             plannableWindow: window, alarmMinutesBefore: nil,
                             calendar: calendar, hiddenCalendarIDs: [])
    }

    private func template(_ rows: [(String, Int, Int, String)]) -> StampTemplate {
        let items = rows.map { TemplateStamper.Item(title: $0.0, startMinuteOfDay: $0.1, durationMinutes: $0.2) }
        var slugs: [UUID: String] = [:]
        for (item, row) in zip(items, rows) { slugs[item.id] = row.3 }
        return StampTemplate(items: items, slugs: slugs)
    }

    /// Four rows that fit an empty day.
    private var fourRows: StampTemplate {
        template([("A", 9 * 60, 30, "deep"), ("B", 10 * 60, 30, "rest"),
                  ("C", 11 * 60, 30, "admin"), ("D", 12 * 60, 30, "health")])
    }

    private func inbox(_ context: ModelContext) throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.sortIndex)]))
    }

    private func titles(_ blocks: [Block]) -> [String] { blocks.map(\.title).sorted() }

    // MARK: Stamp

    @Test("Undo removes only the blocks the stamp created, not what was already on the day")
    func undoRemovesOnlyBlocksThisActionCreated() throws {
        let rig = try makeRig()
        let mine = rig.writer.seedBlock("Mine", range(15, 16))
        let meeting = rig.writer.addFixed("Standup", range(13, 14))
        let result = rig.planner.stamp(fourRows, inputs: inputs(), openTasks: [])
        #expect(rig.writer.blocks.count == 5)

        let outcome = try rig.planner.undo(result.undo)

        #expect(rig.writer.blocks.map(\.id) == [mine.id])
        #expect(rig.writer.fixed.map(\.id) == [meeting.id])
        #expect(outcome.blocksTargeted == 4)
        #expect(outcome.blocksRemoved == 4)
        #expect(outcome.message == PlanMessage(text: "Removed 4 blocks"))
    }

    @Test("A block the user moved within the day is still removed: they tapped Undo")
    func undoRemovesBlockUserMovedInWindow() throws {
        let rig = try makeRig()
        let result = rig.planner.stamp(fourRows, inputs: inputs(), openTasks: [])
        rig.writer.move(result.created[1], to: range(18, 19))

        let outcome = try rig.planner.undo(result.undo)

        #expect(rig.writer.blocks.isEmpty)
        #expect(outcome.blocksRemoved == 4)
    }

    @Test("A block already deleted is skipped, counted, and said so")
    func undoSkipsBlockAlreadyDeletedAndReportsCounts() throws {
        let rig = try makeRig()
        let result = rig.planner.stamp(fourRows, inputs: inputs(), openTasks: [])
        rig.writer.userDeletes(result.created[2])

        let outcome = try rig.planner.undo(result.undo)

        #expect(rig.writer.blocks.isEmpty)
        #expect(outcome.blocksRemoved == 3)
        #expect(outcome.blocksMissing == 1)
        #expect(outcome.message == PlanMessage(text: "Removed 3 of 4 blocks", isWarning: true))
    }

    @Test("A block whose token was stripped cannot be found, so it is left alone and reported")
    func undoAfterTokenStrippedReportsPartial() throws {
        let rig = try makeRig()
        let result = rig.planner.stamp(fourRows, inputs: inputs(), openTasks: [])
        let stripped = result.created[0]
        rig.writer.stripToken(of: stripped)

        let outcome = try rig.planner.undo(result.undo)

        // Not deleted: with no token there is no way to tell it is ours.
        #expect(rig.writer.blocks.map(\.id) == [stripped.id])
        #expect(outcome.message == PlanMessage(text: "Removed 3 of 4 blocks", isWarning: true))
    }

    @Test("When one create fails, the record holds only the blocks that were written")
    func partialCreateFailureRecordsOnlySucceededBlocks() throws {
        let rig = try makeRig()
        rig.writer.failCreateAtCalls = [1]
        let result = rig.planner.stamp(template([("A", 9 * 60, 30, "deep"), ("B", 10 * 60, 30, "rest"),
                                                  ("C", 11 * 60, 30, "admin")]),
                                       inputs: inputs(), openTasks: [])
        #expect(result.created.count == 2)
        #expect(result.failures.count == 1)
        #expect(try inbox(rig.context).count == 1)

        let outcome = try rig.planner.undo(result.undo)

        // Two targeted, not three: the failed row never had a block to remove.
        #expect(outcome.blocksTargeted == 2)
        #expect(outcome.message == PlanMessage(text: "Removed 2 blocks"))
        #expect(rig.writer.blocks.isEmpty)
        #expect(try inbox(rig.context).isEmpty)
    }

    @Test("Undo deletes the inbox tasks the stamp created, but not one that has since been placed")
    func undoDeletesInboxTasksCreatedByStampButNotOnesSincePlaced() throws {
        let rig = try makeRig()
        // A wall of meetings, so both rows go to the inbox.
        rig.writer.addFixed("All day busy", range(7, 22))
        let before = TaskItem(title: "Already here", sortIndex: 10)
        rig.context.insert(before)
        let result = rig.planner.stamp(template([("First", 9 * 60, 60, "rest"), ("Second", 10 * 60, 30, "deep")]),
                                       inputs: inputs(), openTasks: [before])
        let dropped = try inbox(rig.context).filter(\.droppedFromTemplate)
        #expect(dropped.count == 2)

        // The user places one of them. Placing deletes the inbox task.
        let placedBlock = try rig.planner.place(dropped[0], at: at(22, 30), inputs: inputs())

        let outcome = try rig.planner.undo(result.undo)

        let left = try inbox(rig.context)
        #expect(left.map(\.title) == ["Already here"])
        #expect(outcome.inboxTasksDeleted == 1)
        // The placed block is the user's work, not the stamp's.
        #expect(rig.writer.blocks.map(\.id) == [placedBlock.created.id])
    }

    // MARK: Fill day

    private func fillRig(_ titles: [String]) throws -> (Rig, [UUID], FillResult) {
        let rig = try makeRig()
        var ids: [UUID] = []
        for (i, title) in titles.enumerated() {
            let t = TaskItem(title: title, estimatedMinutes: 30, categoryRaw: "deep", sortIndex: 5 + i)
            rig.context.insert(t)
            ids.append(t.id)
        }
        let result = rig.planner.fillDay(inputs: inputs(), openTasks: try inbox(rig.context))
        return (rig, ids, result)
    }

    @Test("Fill day undo puts the deleted tasks back once, with their sort order")
    func fillDayUndoReinsertsDeletedTasksOnceWithSortOrder() throws {
        let (rig, ids, result) = try fillRig(["One", "Two", "Three"])
        #expect(try inbox(rig.context).isEmpty)

        let outcome = try rig.planner.undo(result.undo)

        let back = try inbox(rig.context)
        #expect(back.map(\.id) == ids)
        #expect(back.map(\.sortIndex) == [5, 6, 7])
        #expect(back.map(\.title) == ["One", "Two", "Three"])
        #expect(rig.writer.blocks.isEmpty)
        #expect(outcome.tasksReinserted == 3)
        #expect(outcome.message == PlanMessage(text: "Removed 3 blocks \u{00B7} 3 tasks back in the inbox"))
    }

    @Test("A stripped token cannot be told from a deletion, so the task comes back and says its block may remain")
    func fillDayUndoReinsertsTaskWhoseTokenWasStrippedAndSaysSo() throws {
        let (rig, ids, result) = try fillRig(["One", "Two"])
        // The token is stripped in Calendar.app: the block stays, but cannot be found.
        rig.writer.stripToken(of: result.placements[0].block)

        let outcome = try rig.planner.undo(result.undo)

        // Both tasks come back. "One" is now also on the calendar: a duplicate, the accepted
        // failure, because the alternative (guessing by title and time) can lose a task.
        #expect(try inbox(rig.context).map(\.id) == ids)
        #expect(rig.writer.blocks.count == 1)
        #expect(outcome.tasksReinserted == 2)
        #expect(outcome.tasksReinsertedBlockUnaccountedFor == 1)
        #expect(outcome.message == PlanMessage(
            text: "Removed 1 of 2 blocks \u{00B7} 1 task back in the inbox \u{00B7} 1 task is back in your inbox, its block may still be on your calendar",
            isWarning: true))
    }

    @Test("A task whose block the user already deleted does come back")
    func fillDayUndoReinsertsTaskWhoseBlockWasDeleted() throws {
        let (rig, ids, result) = try fillRig(["One", "Two"])
        rig.writer.userDeletes(result.placements[0].block)

        let outcome = try rig.planner.undo(result.undo)

        #expect(try inbox(rig.context).map(\.id) == ids)
        #expect(outcome.blocksMissing == 1)
        #expect(outcome.tasksReinserted == 2)
        #expect(outcome.tasksReinsertedBlockUnaccountedFor == 1)
    }

    @Test("A task the user re-created under the same id is left alone, not overwritten")
    func fillDayUndoLeavesAnExistingTaskUntouched() throws {
        let (rig, ids, result) = try fillRig(["One"])
        rig.context.insert(TaskItem(id: ids[0], title: "Edited since", estimatedMinutes: 30,
                                    categoryRaw: "deep", sortIndex: 1, createdAt: .now,
                                    completedAt: nil, droppedFromTemplate: false))

        _ = try rig.planner.undo(result.undo)

        #expect(try inbox(rig.context).map(\.title) == ["Edited since"])
    }

    // MARK: Single use, freshness, day

    @Test("A second tap does nothing, even after Start over, where a repeat would duplicate")
    func undoTappedTwiceIsNoOp() throws {
        let rig = try makeRig()
        rig.writer.seedBlock("Old", range(15, 16))
        let result = try rig.planner.replace(with: fourRows, inputs: inputs(), openTasks: [])
        _ = try rig.planner.undo(result.undo)
        let after = rig.writer.blocks.map(\.id).sorted()

        let second = try rig.planner.undo(result.undo)

        #expect(second.alreadyUndone)
        #expect(second.message == PlanMessage(text: "Already undone"))
        #expect(rig.writer.blocks.map(\.id).sorted() == after)
        #expect(rig.writer.blocks.count == 1)
    }

    @Test("A record that was never applied stays usable after a thrown error")
    func undoThatThrowsLeavesRecordUsable() throws {
        let rig = try makeRig()
        let result = rig.planner.stamp(fourRows, inputs: inputs(), openTasks: [])
        rig.writer.failApplyUndo = true
        #expect(throws: FakeBlockWriter.Failure.self) { try rig.planner.undo(result.undo) }
        #expect(rig.writer.blocks.count == 4)

        rig.writer.failApplyUndo = false
        let outcome = try rig.planner.undo(result.undo)

        #expect(outcome.blocksRemoved == 4)
        #expect(rig.writer.blocks.isEmpty)
    }

    @Test("Undo finds blocks by token in a fresh fetch, after identifiers changed and a meeting arrived")
    func undoResolvesAgainstFreshFetchAfterStoreChange() throws {
        let rig = try makeRig()
        let result = rig.planner.stamp(fourRows, inputs: inputs(), openTasks: [])
        rig.writer.reidentifyAll()
        rig.writer.addFixed("New meeting", range(9, 10))

        let outcome = try rig.planner.undo(result.undo)

        #expect(rig.writer.blocks.isEmpty)
        #expect(outcome.blocksRemoved == 4)
        #expect(rig.writer.fixed.count == 1)
    }

    @Test("Undo searches the day it was recorded for, whatever day the user is looking at now")
    func undoTargetsRecordedDayNotSelectedDate() throws {
        let rig = try makeRig()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let other = rig.writer.seedBlock("Tomorrow's", range(9, 10, on: tomorrow))
        let result = rig.planner.stamp(fourRows, inputs: inputs(), openTasks: [])
        // One stamped block gets dragged to tomorrow, out of the recorded day.
        rig.writer.move(result.created[0], to: range(9, 10, on: tomorrow))

        let outcome = try rig.planner.undo(result.undo)

        #expect(calendar.isDate(rig.writer.lastUndoBatch?.day ?? .distantPast, inSameDayAs: day))
        #expect(outcome.blocksRemoved == 3)
        #expect(outcome.blocksMissing == 1)
        #expect(Set(rig.writer.blocks.map(\.id)) == [other.id, result.created[0].id])
    }

    // MARK: Start over

    private func startOverRig() throws -> (Rig, Block, Block, TaskItem?) {
        let rig = try makeRig()
        let source = UUID()
        let withTask = rig.writer.seedBlock("Write", range(9, 10), slug: "deep", source: source,
                                            notes: "Bring the laptop", alarmOffsets: [-3600, -600])
        let plain = rig.writer.seedBlock("Lunch", range(12, 13), slug: "rest")
        return (rig, withTask, plain, nil)
    }

    @Test("Undoing Start over brings the cleared blocks back with their original token ids")
    func startOverUndoRecreatesClearedBlocksWithSameTokenIds() throws {
        let rig = try makeRig()
        let source = UUID()
        // An unknown query item, as a newer build or Calendar.app might leave in the url.
        let url = URL(string: "blockey://block/\(UUID().uuidString)?c=deep&t=\(source.uuidString)&x=keep")
        let rich = BlockToken(url: url)
        let withTask = rig.writer.seedBlock("Write", range(9, 10), token: rich)
        let plain = rig.writer.seedBlock("Lunch", range(12, 13), slug: "rest")
        let result = try rig.planner.replace(with: fourRows, inputs: inputs(), openTasks: [])

        _ = try rig.planner.undo(result.undo)

        #expect(rig.writer.blocks.count == 2)
        let restored = Dictionary(uniqueKeysWithValues: rig.writer.blocks.compactMap { b in
            b.token.map { ($0.id, b) } })
        let withTaskID = try #require(withTask.token?.id)
        let plainID = try #require(plain.token?.id)
        let back = try #require(restored[withTaskID])
        #expect(back.token == withTask.token)
        #expect(back.title == "Write")
        #expect(back.range == range(9, 10))
        let lunch = try #require(restored[plainID])
        #expect(lunch.token == plain.token)
        #expect(lunch.range == range(12, 13))
    }

    @Test("Undoing Start over restores each block's notes and alarm offsets exactly")
    func startOverUndoRestoresNotesAndAlarmOffsets() throws {
        let (rig, withTask, _, _) = try startOverRig()
        let result = try rig.planner.replace(with: fourRows, inputs: inputs(), openTasks: [])
        #expect(result.cleared?.removed.first { $0.title == "Write" }?.notes == "Bring the laptop")

        _ = try rig.planner.undo(result.undo)

        let back = try #require(rig.writer.blocks.first { $0.token?.id == withTask.token?.id })
        #expect(back.notes == "Bring the laptop")
        #expect(back.alarmOffsets == [-3600, -600])
        let lunch = try #require(rig.writer.blocks.first { $0.title == "Lunch" })
        #expect(lunch.notes == nil)
        #expect(lunch.alarmOffsets.isEmpty)
    }

    @Test("Undoing Start over deletes the inbox tasks the clear created")
    func startOverUndoRemovesInboxTasksCreatedByTheClear() throws {
        let (rig, _, _, _) = try startOverRig()
        let result = try rig.planner.replace(with: fourRows, inputs: inputs(), openTasks: [])
        #expect(try inbox(rig.context).count == 1)

        let outcome = try rig.planner.undo(result.undo)

        #expect(try inbox(rig.context).isEmpty)
        #expect(outcome.inboxTasksDeleted == 1)
        #expect(outcome.blocksRecreated == 2)
        #expect(outcome.message == PlanMessage(text: "Removed 4 blocks \u{00B7} Restored 2 blocks"))
    }

    @Test("A cleared block whose returned task was since placed is not recreated")
    func startOverUndoSkipsBlockWhoseReturnedTaskWasPlaced() throws {
        let (rig, _, _, _) = try startOverRig()
        let result = try rig.planner.replace(with: fourRows, inputs: inputs(), openTasks: [])
        let returned = try #require(try inbox(rig.context).first)
        // The user places the returned task at 20:00; placing deletes it from the inbox.
        let placed = try rig.planner.place(returned, at: at(20), inputs: inputs())

        let outcome = try rig.planner.undo(result.undo)

        // "Write" must not come back: its task is already on the calendar as the placed block.
        #expect(!rig.writer.blocks.contains { $0.title == "Write" && $0.id != placed.created.id })
        #expect(rig.writer.blocks.filter { $0.title == "Write" }.count == 1)
        #expect(outcome.notRestoredTaskPlaced == 1)
        #expect(outcome.blocksRecreated == 1)
        #expect(outcome.message.isWarning)
    }

    @Test("A cleared block with no token is recreated under a fresh one, and the outcome says so")
    func startOverUndoRecreatesTokenlessBlocksWithAFreshToken() throws {
        let rig = try makeRig()
        rig.writer.seedBlock("Dentist", range(15, 16), tokenless: true, notes: "Ask about the crown")
        let result = try rig.planner.replace(with: fourRows, inputs: inputs(), openTasks: [])

        let outcome = try rig.planner.undo(result.undo)

        let back = try #require(rig.writer.blocks.first)
        #expect(rig.writer.blocks.count == 1)
        #expect(back.title == "Dentist")
        #expect(back.range == range(15, 16))
        #expect(back.notes == "Ask about the crown")
        // Identity it never had, so a later Undo or edit can find it. No category is invented.
        #expect(back.token != nil)
        #expect(back.token?.categorySlug == nil)
        #expect(outcome.recreatedWithNewIdentity == 1)
    }

    @Test("A recreated block that would overlap a meeting added since is reported, not written")
    func restoredBlocksOverlappingNewFixedEventAreReportedNotWritten() throws {
        let (rig, _, _, _) = try startOverRig()
        let result = try rig.planner.replace(with: fourRows, inputs: inputs(), openTasks: [])
        // A meeting lands on top of where "Write" (9:00 to 10:00) used to be.
        rig.writer.addFixed("Board", range(9, 11))

        let outcome = try rig.planner.undo(result.undo)

        #expect(!rig.writer.blocks.contains { $0.title == "Write" })
        #expect(rig.writer.blocks.contains { $0.title == "Lunch" })
        #expect(outcome.notRestoredFixedConflict.map(\.title) == ["Write"])
        #expect(outcome.blocksRecreated == 1)
        // Its returned task stays in the inbox, since the block did not come back.
        #expect(try inbox(rig.context).map(\.title) == ["Write"])
        #expect(outcome.message.isWarning)
    }

    @Test("A failure part-way through the batch changes nothing, so a retry cannot duplicate")
    func startOverUndoPartialFailureLeavesNoDuplicates() throws {
        let (rig, _, _, _) = try startOverRig()
        let result = try rig.planner.replace(with: fourRows, inputs: inputs(), openTasks: [])
        let blocksBefore = rig.writer.blocks.map(\.id)
        let inboxBefore = try inbox(rig.context).map(\.id)
        rig.writer.failUndoCreateAt = [1]

        #expect(throws: FakeBlockWriter.Failure.self) { try rig.planner.undo(result.undo) }

        // Nothing removed, nothing recreated, inbox untouched.
        #expect(rig.writer.blocks.map(\.id) == blocksBefore)
        #expect(try inbox(rig.context).map(\.id) == inboxBefore)

        rig.writer.failUndoCreateAt = []
        _ = try rig.planner.undo(result.undo)
        #expect(titles(rig.writer.blocks) == ["Lunch", "Write"])
        #expect(try inbox(rig.context).isEmpty)
    }

    @Test("A block the user made recurring in Calendar is left alone, counted, and said so")
    func undoLeavesBlockMadeRecurringInCalendar() throws {
        let rig = try makeRig()
        let result = rig.planner.stamp(fourRows, inputs: inputs(), openTasks: [])
        rig.writer.makeRecurring(result.created[1])

        let outcome = try rig.planner.undo(result.undo)

        #expect(rig.writer.blocks.map(\.id) == [result.created[1].id])
        #expect(outcome.blocksRemoved == 3)
        #expect(outcome.blocksLeftAlone == 1)
        #expect(outcome.blocksMissing == 0)
        #expect(outcome.message == PlanMessage(
            text: "Removed 3 blocks \u{00B7} 1 block was changed in Calendar, so it was left", isWarning: true))
    }

    @Test("The fake removes the earliest of two events sharing a token, as the real service does")
    func fakeRemovesEarliestDuplicateToken() throws {
        let rig = try makeRig()
        let token = BlockToken(categorySlug: "deep")
        let late = rig.writer.seedBlock("Late copy", range(15, 16), token: token)
        let early = rig.writer.seedBlock("Early", range(9, 10), token: token)
        let batch = UndoBatch(day: day, removeTokenIDs: [token.id], create: [])

        let applied = try rig.writer.applyUndo(batch, calendar: calendar)

        #expect(applied.removed == [token.id])
        #expect(rig.writer.blocks.map(\.id) == [late.id])
        _ = early
    }

    @Test("existingTokenIDs finds a token within 7 days either side and not beyond")
    func existingTokenIDsSearchesAWeek() {
        let writer = FakeBlockWriter()
        func daysFrom(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: day) ?? day }
        let near = writer.seedBlock("Near", range(9, 10, on: daysFrom(7)))
        let far = writer.seedBlock("Far", range(9, 10, on: daysFrom(9)))
        let found = writer.existingTokenIDs(Set([near.token?.id, far.token?.id].compactMap { $0 }),
                                            around: day, days: 7, calendar: calendar)
        #expect(found == Set([near.token?.id].compactMap { $0 }))
    }

    // MARK: Messages

    @Test("Undo message texts")
    func undoMessageTexts() {
        func msg(_ edit: (inout UndoOutcome) -> Void) -> PlanMessage {
            var o = UndoOutcome()
            edit(&o)
            return o.message
        }
        #expect(msg { $0.blocksTargeted = 4; $0.blocksRemoved = 4 } == PlanMessage(text: "Removed 4 blocks"))
        #expect(msg { $0.blocksTargeted = 1; $0.blocksRemoved = 1 } == PlanMessage(text: "Removed 1 block"))
        #expect(msg { $0.blocksTargeted = 4; $0.blocksRemoved = 3 }
                == PlanMessage(text: "Removed 3 of 4 blocks", isWarning: true))
        #expect(msg { $0.blocksTargeted = 1; $0.blocksRemoved = 0 }
                == PlanMessage(text: "Removed 0 of 1 block", isWarning: true))
        #expect(msg { $0.blocksTargeted = 2; $0.blocksRemoved = 2; $0.tasksReinserted = 1 }
                == PlanMessage(text: "Removed 2 blocks \u{00B7} 1 task back in the inbox"))
        #expect(msg { $0.blocksTargeted = 2; $0.blocksRemoved = 1; $0.blocksLeftAlone = 1 }
                == PlanMessage(text: "Removed 1 block \u{00B7} 1 block was changed in Calendar, so it was left",
                               isWarning: true))
        #expect(msg { $0.blocksTargeted = 2; $0.blocksRemoved = 2; $0.tasksReinserted = 2
                      $0.tasksReinsertedBlockUnaccountedFor = 2 }
                == PlanMessage(text: "Removed 2 blocks \u{00B7} 2 tasks are back in your inbox, their blocks may still be on your calendar",
                               isWarning: true))
        #expect(msg { $0.blocksTargeted = 2; $0.blocksRemoved = 2; $0.tasksKeptBecauseBlockSurvived = 2 }
                == PlanMessage(text: "Removed 2 blocks \u{00B7} 2 tasks not returned, their blocks are still on your calendar",
                               isWarning: true))
        #expect(msg { $0.blocksTargeted = 3; $0.blocksRemoved = 3; $0.blocksRecreated = 2 }
                == PlanMessage(text: "Removed 3 blocks \u{00B7} Restored 2 blocks"))
        #expect(msg { $0.blocksRecreated = 1; $0.notRestoredTaskPlaced = 1 }
                == PlanMessage(text: "Restored 1 block \u{00B7} 1 block not restored, its task is no longer in the inbox",
                               isWarning: true))
        let blocked = Block(title: "X", range: TimeRange(start: .now, duration: 60), kind: .block(nil))
        #expect(msg { $0.notRestoredFixedConflict = [blocked, blocked] }
                == PlanMessage(text: "2 blocks not restored, a meeting is there now, kept in the inbox", isWarning: true))
        #expect(msg { $0.alreadyUndone = true } == PlanMessage(text: "Already undone"))
        #expect(msg { _ in } == PlanMessage(text: "Nothing to undo"))
    }
}

/// The pure half of "fixed events always win" for Undo.
@Suite("RestoreFilter")
struct RestoreFilterTests {
    private func r(_ a: Int, _ b: Int) -> TimeRange {
        let base = Calendar.current.startOfDay(for: .now)
        return TimeRange(start: base.addingTimeInterval(TimeInterval(a * 3600)),
                         end: base.addingTimeInterval(TimeInterval(b * 3600)))
    }

    @Test("Splits candidates into writable and blocked by index; touching is not a conflict")
    func splitsByOverlap() {
        let split = RestoreFilter.split([r(9, 10), r(10, 12), r(12, 13), r(8, 9)],
                                        avoiding: [r(11, 12)])
        #expect(split.writable == [0, 2, 3])
        #expect(split.blocked == [1])
    }

    @Test("No fixed events blocks nothing")
    func emptyFixedBlocksNothing() {
        let split = RestoreFilter.split([r(9, 10)], avoiding: [])
        #expect(split.writable == [0])
        #expect(split.blocked.isEmpty)
    }
}
