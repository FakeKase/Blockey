import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A portable copy of everything that lives only on this device.
///
/// Blocks are deliberately absent: they are calendar events and are already
/// safe outside the app. What is at risk is tasks and templates, and only in
/// one situation — deleting the app from the Home Screen. Re-signing and
/// reinstalling preserve them (see docs/adr/003).
///
/// Needs no entitlement and no App Group, so it works under free-provisioned
/// sideloading where CloudKit does not.
struct BlockeyBackup: Codable {
    var version = 1
    var exportedAt = Date()
    var tasks: [Task] = []
    var templates: [Template] = []
    var assignments: [Assignment] = []

    struct Task: Codable {
        var title: String
        var estimatedMinutes: Int
        var category: String
        var sortIndex: Int
    }

    struct Template: Codable {
        var id: UUID
        var name: String
        var rows: [Row]

        struct Row: Codable {
            var title: String
            var startMinuteOfDay: Int
            var durationMinutes: Int
            var category: String
        }
    }

    struct Assignment: Codable {
        var weekday: Int
        var templateID: UUID?
    }

    // MARK: Capture

    static func capture(context: ModelContext) throws -> BlockeyBackup {
        var backup = BlockeyBackup()

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        backup.tasks = tasks.filter { !$0.isDone }.map {
            Task(title: $0.title,
                 estimatedMinutes: $0.estimatedMinutes,
                 category: $0.categoryRaw,
                 sortIndex: $0.sortIndex)
        }

        let templates = try context.fetch(FetchDescriptor<DayTemplate>())
        backup.templates = templates.map { template in
            Template(id: template.id,
                     name: template.name,
                     rows: template.orderedRows.map {
                         Template.Row(title: $0.title,
                                      startMinuteOfDay: $0.startMinuteOfDay,
                                      durationMinutes: $0.durationMinutes,
                                      category: $0.categoryRaw)
                     })
        }

        let assignments = try context.fetch(FetchDescriptor<TemplateAssignment>())
        backup.assignments = assignments.map { Assignment(weekday: $0.weekday, templateID: $0.templateID) }

        return backup
    }

    // MARK: Restore

    /// Replaces everything currently stored.
    ///
    /// Replace rather than merge, deliberately: merging would silently
    /// duplicate every template on a second import, and "restore my backup"
    /// means the state in the file, not the union of two states.
    @discardableResult
    func restore(into context: ModelContext) throws -> (tasks: Int, templates: Int) {
        for task in try context.fetch(FetchDescriptor<TaskItem>()) { context.delete(task) }
        for template in try context.fetch(FetchDescriptor<DayTemplate>()) { context.delete(template) }
        for assignment in try context.fetch(FetchDescriptor<TemplateAssignment>()) { context.delete(assignment) }

        for task in tasks {
            context.insert(TaskItem(title: task.title,
                                    estimatedMinutes: task.estimatedMinutes,
                                    categoryRaw: task.category,
                                    sortIndex: task.sortIndex))
        }

        // Templates keep their identifiers so weekday assignments still resolve.
        for payload in templates {
            let template = DayTemplate(name: payload.name)
            template.id = payload.id
            context.insert(template)
            for rowPayload in payload.rows {
                let row = TemplateRow(title: rowPayload.title,
                                      startMinuteOfDay: rowPayload.startMinuteOfDay,
                                      durationMinutes: rowPayload.durationMinutes,
                                      categoryRaw: rowPayload.category)
                row.template = template
                context.insert(row)
            }
        }

        for assignment in assignments {
            context.insert(TemplateAssignment(weekday: assignment.weekday, templateID: assignment.templateID))
        }

        do {
            try context.save()
        } catch {
            // Every task and template was deleted a few lines above and those
            // deletions are still pending. Without this the user is told the
            // restore failed while the next autosave quietly carries out the
            // destruction anyway.
            context.rollback()
            throw error
        }
        return (tasks.count, templates.count)
    }

    var suggestedFilename: String {
        "Blockey-\(exportedAt.formatted(.iso8601.year().month().day())).json"
    }
}

/// A decoded backup waiting on the user's confirmation, and what accepting it costs.
///
/// `restore(into:)` deletes every task, template and weekday assignment before
/// inserting the backup's, and the only thing standing between that and a
/// mis-tap in a file picker is this confirmation — so the warning states the
/// numbers rather than the idea, and names the date the backup was saved, since
/// reaching for last month's file is the way this goes wrong.
struct PendingRestore {
    let backup: BlockeyBackup
    let existingTasks: Int
    let existingTemplates: Int

    var warning: String {
        let saved = backup.exportedAt.formatted(date: .abbreviated, time: .shortened)
        let incoming = "\(Self.counted(backup.tasks.count, "task")) and \(Self.counted(backup.templates.count, "template"))"

        guard existingTasks + existingTemplates > 0 else {
            return "Saved \(saved). It holds \(incoming). Your calendar blocks are not affected."
        }

        let losing = "\(Self.counted(existingTasks, "task")) and \(Self.counted(existingTemplates, "template"))"
        return "Saved \(saved). This deletes the \(losing) on this phone and puts back \(incoming). "
            + "Your calendar blocks are not affected."
    }

    /// "1 task", "4 tasks", "no tasks" — a count the sentence can absorb.
    static func counted(_ n: Int, _ noun: String) -> String {
        switch n {
        case 0:  return "no \(noun)s"
        case 1:  return "1 \(noun)"
        default: return "\(n) \(noun)s"
        }
    }
}

/// Wraps a backup so SwiftUI's file exporter and importer can carry it.
struct BackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var backup: BlockeyBackup

    init(backup: BlockeyBackup) { self.backup = backup }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        backup = try decoder.decode(BlockeyBackup.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return FileWrapper(regularFileWithContents: try encoder.encode(backup))
    }
}
