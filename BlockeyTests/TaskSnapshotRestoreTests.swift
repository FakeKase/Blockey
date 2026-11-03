import Testing
import Foundation
import SwiftData
@testable import Blockey

// Undo puts back tasks that place() and fillDay() deleted. These pin the data-layer half:
// the restore must be exact, and must never duplicate (id is @Attribute(.unique), so a second
// insert would silently upsert rather than fail).

@Suite("Restoring a task from its snapshot")
@MainActor
struct TaskSnapshotRestoreTests {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TaskItem.self, DayTemplate.self, TemplateRow.self, TemplateAssignment.self, ActivityDay.self,
            configurations: config)
        return ModelContext(container)
    }

    private func count(_ context: ModelContext, id: UUID) throws -> Int {
        try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).count
    }

    private func snapshot(id: UUID = UUID(), minutes: Int = 45, slug: String = "rest",
                          completedAt: Date? = nil) -> TaskSnapshot {
        TaskSnapshot(id: id, title: "Write", estimatedMinutes: minutes, categoryRaw: slug,
                     sortIndex: 7, createdAt: Date(timeIntervalSince1970: 1_000_000),
                     completedAt: completedAt, droppedFromTemplate: true)
    }

    @Test("Restore init keeps id, createdAt, sortIndex and slug rather than minting new ones")
    func restoreInitPreservesIdCreatedAtSortIndexAndSlug() {
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_000_000)
        let done = Date(timeIntervalSince1970: 2_000_000)
        let task = TaskItem(id: id, title: "T", estimatedMinutes: 40, categoryRaw: "rest",
                            sortIndex: 7, createdAt: created, completedAt: done,
                            droppedFromTemplate: true)
        #expect(task.id == id)
        #expect(task.createdAt == created)
        #expect(task.completedAt == done)
        #expect(task.sortIndex == 7)
        #expect(task.categoryRaw == "rest")
        #expect(task.estimatedMinutes == 40)
        #expect(task.droppedFromTemplate)
    }

    @Test("Restore applies the same 5 minute floor as every other init")
    func restoreAppliesMinutesClamp() {
        let task = TaskItem(id: UUID(), title: "T", estimatedMinutes: 1, categoryRaw: "rest",
                            sortIndex: 0, createdAt: .now, completedAt: nil,
                            droppedFromTemplate: false)
        #expect(task.estimatedMinutes == 5)
    }

    @Test("A snapshot taken from a task carries completedAt")
    func snapshotCapturesCompletedAt() {
        let done = Date(timeIntervalSince1970: 2_000_000)
        let task = TaskItem(title: "T")
        task.completedAt = done
        #expect(TaskSnapshot(task).completedAt == done)
        #expect(TaskSnapshot(TaskItem(title: "U")).completedAt == nil)
    }

    @Test("Restore inserts a task that is gone, exactly as snapshotted")
    func restoreInsertsMissingTask() throws {
        let context = try makeContext()
        let snap = snapshot(completedAt: Date(timeIntervalSince1970: 2_000_000))
        #expect(snap.restore(into: context))
        let fetched = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(fetched.count == 1)
        #expect(TaskSnapshot(fetched[0]) == snap)
    }

    @Test("Restore leaves an existing task with that id alone and reports false")
    func restoreSkipsExistingId() throws {
        let context = try makeContext()
        let snap = snapshot()
        let existing = TaskItem(id: snap.id, title: "Edited since", estimatedMinutes: 10,
                                categoryRaw: "deep", sortIndex: 0, createdAt: .now,
                                completedAt: nil, droppedFromTemplate: false)
        context.insert(existing)
        #expect(snap.restore(into: context) == false)
        #expect(try count(context, id: snap.id) == 1)
        #expect(existing.title == "Edited since")
    }

    @Test("Restoring the same snapshot twice inserts once")
    func restoringTwiceInsertsOnce() throws {
        let context = try makeContext()
        let snap = snapshot()
        #expect(snap.restore(into: context))
        #expect(snap.restore(into: context) == false)
        #expect(try count(context, id: snap.id) == 1)
    }

    @Test("A slug this build doesn't know survives the round trip")
    func restoredTaskKeepsUnknownSlugVerbatim() throws {
        let context = try makeContext()
        let snap = snapshot(slug: "งานบ้าน")
        #expect(snap.restore(into: context))
        let fetched = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(fetched[0].categoryRaw == "งานบ้าน")
    }
}
