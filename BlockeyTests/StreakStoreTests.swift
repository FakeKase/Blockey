import Testing
import Foundation
import SwiftData
@testable import Blockey

/// Streak storage and the DayPlanner hooks (issue #7). Hooks are tested through the same
/// `FakeBlockWriter` the other planner suites use.
@Suite("Streak storage and hooks")
@MainActor
struct StreakStoreTests {

    private let calendar = Calendar.current
    private let monday = TestDates.ordinaryDay(weekday: 2)

    private func at(_ hour: Int, _ minute: Int = 0, on day: Date? = nil) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day ?? monday) ?? monday
    }

    private func range(_ h1: Int, _ h2: Int) -> TimeRange { TimeRange(start: at(h1), end: at(h2)) }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self, DayTemplate.self, TemplateRow.self, TemplateAssignment.self, ActivityDay.self, CategoryDefinition.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @MainActor private struct Rig {
        let writer: FakeBlockWriter
        let context: ModelContext
        let planner: DayPlanner
        let store: StreakStore
    }

    private func makeRig() throws -> Rig {
        let context = try makeContext()
        let writer = FakeBlockWriter()
        return Rig(writer: writer, context: context,
                   planner: DayPlanner(writer: writer, context: context, clock: { [now = at(10)] in now }),
                   store: StreakStore(context: context, calendar: calendar))
    }

    /// `now` is the real moment the user acts (default 10:00 on `monday`); `date` is the day
    /// being planned, which may differ from it.
    private func inputs(now: Date? = nil, planning date: Date? = nil, alarm: Int? = nil) -> DayPlanInputs {
        let planned = date ?? monday
        let window = TimeRange(start: at(7, on: planned), end: at(22, on: planned))
        let n = now ?? at(10)
        return DayPlanInputs(date: planned, now: n, isToday: calendar.isDate(planned, inSameDayAs: n),
                             window: window, plannableWindow: window, alarmMinutesBefore: alarm,
                             calendar: calendar, hiddenCalendarIDs: [])
    }

    private func template(_ rows: [(String, Int, Int)]) -> StampTemplate {
        let items = rows.map { TemplateStamper.Item(title: $0.0, startMinuteOfDay: $0.1, durationMinutes: $0.2) }
        return StampTemplate(items: items, slugs: Dictionary(uniqueKeysWithValues: items.map { ($0.id, "deep") }),
                             name: "Test")
    }

    private func today() -> CivilDay { CivilDay(at(10), in: calendar) }

    private func rows(_ context: ModelContext) throws -> [ActivityDay] {
        try context.fetch(FetchDescriptor<ActivityDay>())
    }

    // MARK: Store

    @Test("Recording is once per day: the second call on the same day adds nothing")
    func recordIsIdempotent() throws {
        let rig = try makeRig()
        #expect(rig.store.record(now: at(9)))
        #expect(!rig.store.record(now: at(9, 30)))
        #expect(!rig.store.record(now: at(23, 59)))
        #expect(try rows(rig.context).count == 1)
        #expect(try rows(rig.context).first?.key == today().key)
    }

    @Test("The next calendar day is a second row")
    func nextDay() throws {
        let rig = try makeRig()
        rig.store.record(now: at(23, 59))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: monday) ?? monday
        #expect(rig.store.record(now: at(0, 1, on: tomorrow)))
        #expect(try rows(rig.context).count == 2)
    }

    @Test("Summary reads the stored days")
    func summaryReads() throws {
        let rig = try makeRig()
        for back in [3, 2, 1] {
            let d = calendar.date(byAdding: .day, value: -back, to: at(10)) ?? at(10)
            rig.store.record(now: d)
        }
        let s = rig.store.summary(now: at(10))
        #expect(s.current == 3)
        #expect(s.isAtRisk)
        #expect(!s.countedToday)
        rig.store.record(now: at(10))
        #expect(rig.store.summary(now: at(11)).current == 4)
    }

    @Test("Merging skips days already stored and reports how many were new")
    func merge() throws {
        let rig = try makeRig()
        rig.store.record(now: at(10))
        let other = today().adding(days: -1)
        let added = rig.store.merge([today(), other, other], recordedAt: at(10))
        #expect(added == 1)
        #expect(try rows(rig.context).count == 2)
    }

    // MARK: Hooks: adds record

    @Test("Stamping records the day the user acted, not the day that was planned")
    func stampRecordsActingDay() throws {
        let rig = try makeRig()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: monday) ?? monday
        rig.planner.stamp(template([("A", 9 * 60, 60)]), inputs: inputs(planning: tomorrow), openTasks: [])
        #expect(try rows(rig.context).map(\.key) == [today().key])
    }

    @Test("A stamp that writes nothing does not record")
    func stampNothingWritten() throws {
        let rig = try makeRig()
        rig.writer.addFixed("Busy", range(7, 22))
        rig.planner.stamp(template([("A", 9 * 60, 60)]), inputs: inputs(), openTasks: [])
        #expect(try rows(rig.context).isEmpty)
    }

    @Test("A stamp whose every write fails does not record")
    func stampAllFail() throws {
        let rig = try makeRig()
        rig.writer.failCreateAtCalls = [0, 1]
        rig.planner.stamp(template([("A", 9 * 60, 60), ("B", 11 * 60, 60)]), inputs: inputs(), openTasks: [])
        #expect(try rows(rig.context).isEmpty)
    }

    @Test("A stamp where one write lands records")
    func stampPartial() throws {
        let rig = try makeRig()
        rig.writer.failCreateAtCalls = [0]
        rig.planner.stamp(template([("A", 9 * 60, 60), ("B", 11 * 60, 60)]), inputs: inputs(), openTasks: [])
        #expect(try rows(rig.context).count == 1)
    }

    @Test("Confirming a preview records; a stale preview writes nothing and records nothing")
    func stampExpecting() throws {
        let rig = try makeRig()
        let t = template([("A", 9 * 60, 60)])
        let shown = rig.planner.preview(t, inputs: inputs(), mode: .keep)

        // The calendar changed after the preview: stale, nothing written.
        rig.writer.addFixed("New meeting", range(10, 11))
        let stale = try rig.planner.stamp(t, expecting: shown, mode: .keep, inputs: inputs(), openTasks: [])
        guard case .stale(let fresh) = stale else {
            Issue.record("expected a stale outcome")
            return
        }
        #expect(try rows(rig.context).isEmpty)

        let written = try rig.planner.stamp(t, expecting: fresh, mode: .keep, inputs: inputs(), openTasks: [])
        guard case .written = written else {
            Issue.record("expected a written outcome")
            return
        }
        #expect(try rows(rig.context).count == 1)
    }

    @Test("Start over records when it stamps")
    func startOverRecords() throws {
        let rig = try makeRig()
        rig.writer.seedBlock("Old", range(13, 14))
        let t = template([("A", 9 * 60, 60)])
        try rig.planner.replace(with: t, inputs: inputs(), openTasks: [])
        #expect(try rows(rig.context).count == 1)
    }

    @Test("Fill day records when it places something, and not when it places nothing")
    func fillDay() throws {
        let empty = try makeRig()
        empty.planner.fillDay(inputs: inputs(), openTasks: [])
        #expect(try rows(empty.context).isEmpty)

        let rig = try makeRig()
        let task = TaskItem(title: "Write", estimatedMinutes: 30, sortIndex: 0)
        rig.context.insert(task)
        rig.planner.fillDay(inputs: inputs(), openTasks: [task])
        #expect(try rows(rig.context).count == 1)
    }

    @Test("Fill day with nothing that fits records nothing")
    func fillDayNothingFits() throws {
        let rig = try makeRig()
        rig.writer.addFixed("Busy", range(7, 22))
        let task = TaskItem(title: "Write", estimatedMinutes: 30, sortIndex: 0)
        rig.context.insert(task)
        rig.planner.fillDay(inputs: inputs(), openTasks: [task])
        #expect(try rows(rig.context).isEmpty)
    }

    @Test("Placing an inbox task records; a failed placement does not")
    func place() throws {
        let rig = try makeRig()
        let task = TaskItem(title: "Write", estimatedMinutes: 30, sortIndex: 0)
        rig.context.insert(task)
        rig.writer.failCreateAtCalls = [0]
        #expect(throws: (any Error).self) { try rig.planner.place(task, at: at(9), inputs: inputs()) }
        #expect(try rows(rig.context).isEmpty)

        try rig.planner.place(task, at: at(9), inputs: inputs())
        #expect(try rows(rig.context).count == 1)
    }

    @Test("The New block button records through the planner")
    func addBlock() throws {
        let rig = try makeRig()
        rig.writer.failCreateAtCalls = [0]
        #expect(throws: (any Error).self) {
            try rig.planner.addBlock(title: "New block", range: range(9, 10), categorySlug: "deep", inputs: inputs())
        }
        #expect(try rows(rig.context).isEmpty)

        let block = try rig.planner.addBlock(title: "New block", range: range(9, 10),
                                             categorySlug: "deep", inputs: inputs(alarm: 5))
        #expect(block.title == "New block")
        #expect(rig.writer.created.last?.alarm == 5)
        #expect(try rows(rig.context).count == 1)
    }

    @Test("The recorded day comes from the clock, not from a stale inputs.now")
    func clockDecidesTheDay() throws {
        let context = try makeContext()
        let writer = FakeBlockWriter()
        let justAfterMidnight = at(0, 0, on: calendar.date(byAdding: .day, value: 1, to: monday))
        let planner = DayPlanner(writer: writer, context: context, clock: { justAfterMidnight })
        // The view's ticking state still says 23:59:40 on Monday.
        planner.stamp(template([("A", 9 * 60, 60)]), inputs: inputs(now: at(23, 59), planning: calendar.date(byAdding: .day, value: 1, to: monday)),
                     openTasks: [])
        let expected = CivilDay(justAfterMidnight, in: calendar).key
        #expect(try rows(context).map(\.key) == [expected])
        #expect(expected != today().key)
    }

    @Test("Restore stores the canonical key and rejects signed or short parts")
    func restoreCanonical() throws {
        let target = try makeRig()
        let backup = try decode("""
        {"version":1,"exportedAt":"2026-10-01T09:00:00Z","tasks":[],"templates":[],"assignments":[],
         "activityDays":["2026-+1-05","2026--1-05","2026-1-05","2026-10-05"]}
        """)
        try backup.restore(into: target.context)
        #expect(try rows(target.context).map(\.key) == ["2026-10-05"])
        #expect(CivilDay(key: "2026-+1-05") == nil)
    }

    // MARK: Hooks: removals do not unrecord

    @Test("Undo does not remove the day")
    func undoKeepsDay() throws {
        let rig = try makeRig()
        let result = rig.planner.stamp(template([("A", 9 * 60, 60)]), inputs: inputs(), openTasks: [])
        #expect(try rows(rig.context).count == 1)
        _ = try rig.planner.undo(result.undo)
        #expect(rig.writer.blocks.isEmpty)
        #expect(try rows(rig.context).count == 1)
        #expect(rig.store.summary(now: at(11)).countedToday)
    }

    @Test("Clear does not remove the day")
    func clearKeepsDay() throws {
        let rig = try makeRig()
        rig.planner.stamp(template([("A", 9 * 60, 60)]), inputs: inputs(), openTasks: [])
        try rig.planner.clear(inputs: inputs(), openTasks: [])
        #expect(rig.writer.blocks.isEmpty)
        #expect(try rows(rig.context).count == 1)
    }

    @Test("Returning a block to the inbox does not remove the day")
    func returnKeepsDay() throws {
        let rig = try makeRig()
        let result = rig.planner.stamp(template([("A", 9 * 60, 60)]), inputs: inputs(), openTasks: [])
        try rig.planner.returnToInbox(try #require(result.created.first), openTasks: [])
        #expect(try rows(rig.context).count == 1)
    }

    @Test("Deleting a block through the writer does not remove the day")
    func deleteKeepsDay() throws {
        let rig = try makeRig()
        let result = rig.planner.stamp(template([("A", 9 * 60, 60)]), inputs: inputs(), openTasks: [])
        try rig.writer.delete(try #require(result.created.first))
        #expect(try rows(rig.context).count == 1)
    }

    @Test("Undoing a Fill day does not remove the day, and the Undo itself records nothing new")
    func undoFill() throws {
        let rig = try makeRig()
        let task = TaskItem(title: "Write", estimatedMinutes: 30, sortIndex: 0)
        rig.context.insert(task)
        let fill = rig.planner.fillDay(inputs: inputs(), openTasks: [task])
        _ = try rig.planner.undo(fill.undo)
        #expect(try rows(rig.context).count == 1)

        // Undo on a fresh day, with no add that day, must not create a day by itself.
        let other = try makeRig()
        let stamped = other.planner.stamp(template([("A", 9 * 60, 60)]), inputs: inputs(), openTasks: [])
        for row in try rows(other.context) { other.context.delete(row) }
        _ = try other.planner.undo(stamped.undo)
        #expect(try rows(other.context).isEmpty)
    }

    // MARK: Seeding once

    private func freshDefaults() throws -> UserDefaults {
        let name = "BlockeyStreakTests-\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: name))
    }

    @Test("Seeding reads once, merges the days, and sets the flag")
    func seedOnce() throws {
        let rig = try makeRig()
        let defaults = try freshDefaults()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: at(9)) ?? at(9)
        var reads = 0

        let added = rig.store.seedIfNeeded(defaults: defaults, now: at(10)) { _ in
            reads += 1
            return [yesterday, yesterday, at(8)]
        }
        #expect(added == 2)
        #expect(reads == 1)
        #expect(defaults.bool(forKey: SettingsKey.hasSeededStreak))
        #expect(rig.store.summary(now: at(11)).current == 2)

        let again = rig.store.seedIfNeeded(defaults: defaults, now: at(10)) { _ in
            reads += 1
            return [at(10)]
        }
        #expect(again == nil)
        #expect(reads == 1)
    }

    @Test("Seeding is retried while the calendar cannot be read, and does not set the flag")
    func seedWaitsForAccess() throws {
        let rig = try makeRig()
        let defaults = try freshDefaults()
        let result = rig.store.seedIfNeeded(defaults: defaults, now: at(10)) { _ in nil }
        #expect(result == nil)
        #expect(!defaults.bool(forKey: SettingsKey.hasSeededStreak))

        // Empty is "maybe not synced yet" and retries too.
        let empty = rig.store.seedIfNeeded(defaults: defaults, now: at(10)) { _ in [] }
        #expect(empty == nil)
        #expect(!defaults.bool(forKey: SettingsKey.hasSeededStreak))

        let later = rig.store.seedIfNeeded(defaults: defaults, now: at(10)) { _ in [at(8)] }
        #expect(later == 1)
        #expect(defaults.bool(forKey: SettingsKey.hasSeededStreak))
    }

    @Test("Seeding hands the reader the start of the 365-day window")
    func seedWindow() throws {
        let rig = try makeRig()
        let defaults = try freshDefaults()
        var since: Date?
        rig.store.seedIfNeeded(defaults: defaults, now: at(10)) { start in since = start; return [at(8)] }
        let expected = calendar.date(byAdding: .day, value: -365, to: calendar.startOfDay(for: at(10)))
        #expect(since == expected)
    }

    // MARK: Backup

    private func decode(_ json: String) throws -> BlockeyBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BlockeyBackup.self, from: Data(json.utf8))
    }

    @Test("A backup written before activityDays existed still decodes")
    func oldBackupDecodes() throws {
        let backup = try decode("""
        {"version":1,"exportedAt":"2026-10-01T09:00:00Z","tasks":[],"templates":[],"assignments":[]}
        """)
        #expect(backup.activityDays == nil)
        #expect(backup.version == 1)
    }

    @Test("Capture and restore round trip the days, and the version is current")
    func roundTrip() throws {
        let source = try makeRig()
        source.store.record(now: at(10))
        source.store.record(now: calendar.date(byAdding: .day, value: -1, to: at(10)) ?? at(10))
        let backup = try BlockeyBackup.capture(context: source.context)
        #expect(backup.version == BlockeyBackup.currentVersion)
        #expect(Set(backup.activityDays ?? []) == Set(try rows(source.context).map(\.key)))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reread = try decoder.decode(BlockeyBackup.self, from: try encoder.encode(backup))

        let target = try makeRig()
        try reread.restore(into: target.context)
        #expect(Set(try rows(target.context).map(\.key)) == Set(try rows(source.context).map(\.key)))
    }

    @Test("Restore merges: days already on the phone survive, and a missing key touches nothing")
    func restoreMerges() throws {
        let target = try makeRig()
        target.store.record(now: at(10))
        let before = try rows(target.context).map(\.key)

        let old = try decode("""
        {"version":1,"exportedAt":"2026-10-01T09:00:00Z","tasks":[],"templates":[],"assignments":[]}
        """)
        try old.restore(into: target.context)
        #expect(try rows(target.context).map(\.key) == before)

        let withDays = try decode("""
        {"version":1,"exportedAt":"2026-10-01T09:00:00Z","tasks":[],"templates":[],"assignments":[],
         "activityDays":["2026-09-30","2026-10-01","not-a-day","\(before[0])"]}
        """)
        try withDays.restore(into: target.context)
        let keys = Set(try rows(target.context).map(\.key))
        #expect(keys == ["2026-09-30", "2026-10-01", before[0]])
    }
}
