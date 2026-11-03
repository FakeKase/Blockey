import Testing
import Foundation
import SwiftData
@testable import Blockey

@Suite("Backup round trip of the dropped-from-template note")
@MainActor
struct BackupDroppedTemplateQATests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self, DayTemplate.self, TemplateRow.self, TemplateAssignment.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @Test("A dropped task keeps its template name through capture and restore")
    func nameSurvivesRoundTrip() throws {
        let source = try makeContext()
        source.insert(TaskItem(title: "Lunch", droppedFromTemplate: true, droppedFromTemplateName: "Workday"))
        let data = try JSONEncoder().encode(try BlockeyBackup.capture(context: source))

        let target = try makeContext()
        try JSONDecoder().decode(BlockeyBackup.self, from: data).restore(into: target)
        let task = try #require(try target.fetch(FetchDescriptor<TaskItem>()).first)
        #expect(task.droppedFromTemplate)
        #expect(task.droppedFromTemplateName == "Workday")
    }

    @Test("A legacy dropped task with no name keeps its dropped flag through a backup")
    func legacyDroppedFlagSurvives() throws {
        let source = try makeContext()
        source.insert(TaskItem(title: "Old", droppedFromTemplate: true))
        let data = try JSONEncoder().encode(try BlockeyBackup.capture(context: source))

        let target = try makeContext()
        try JSONDecoder().decode(BlockeyBackup.self, from: data).restore(into: target)
        let task = try #require(try target.fetch(FetchDescriptor<TaskItem>()).first)
        #expect(task.droppedFromTemplate)
    }
}
