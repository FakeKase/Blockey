import Testing
import Foundation
@testable import Blockey

/// What the user is told before a restore destroys their tasks and templates.
///
/// `BlockeyBackup.restore(into:)` deletes everything first, and for a while the
/// only thing in front of it was a file picker — pick the wrong file and the
/// work was gone with no warning and no undo. The confirmation is the whole
/// defence, so the numbers in it have to be right.
@Suite("Restore warning")
struct RestoreWarningTests {

    private func backup(tasks: Int, templates: Int, exportedAt: Date = .now) -> BlockeyBackup {
        var backup = BlockeyBackup()
        backup.exportedAt = exportedAt
        backup.tasks = (0..<tasks).map {
            BlockeyBackup.Task(title: "Task \($0)", estimatedMinutes: 30,
                               category: BlockCategory.deepWork.rawValue, sortIndex: $0)
        }
        backup.templates = (0..<templates).map {
            BlockeyBackup.Template(id: UUID(), name: "Template \($0)", rows: [])
        }
        return backup
    }

    @Test("The warning names what is about to be deleted")
    func namesWhatIsLost() {
        let pending = PendingRestore(backup: backup(tasks: 7, templates: 3),
                                    existingTasks: 4, existingTemplates: 2)
        let warning = pending.warning

        #expect(warning.contains("4 tasks"), "the tasks being deleted are missing from: \(warning)")
        #expect(warning.contains("2 templates"), "the templates being deleted are missing from: \(warning)")
        #expect(warning.contains("7 tasks"))
        #expect(warning.contains("3 templates"))
        #expect(warning.contains("deletes"), "the warning must say something is deleted")
    }

    @Test("With nothing to lose, the warning does not threaten")
    func nothingToLose() {
        let pending = PendingRestore(backup: backup(tasks: 2, templates: 1),
                                    existingTasks: 0, existingTemplates: 0)
        let warning = pending.warning

        #expect(!warning.contains("deletes"),
                "nothing is being deleted, so the warning should not say so: \(warning)")
        #expect(warning.contains("2 tasks"))
    }

    /// Reaching for last month's file is how this goes wrong, so the date the
    /// backup was saved has to be in front of the user before they confirm.
    @Test("The warning dates the backup")
    func datesTheBackup() {
        // Some weeks back from today in the machine's own calendar (issue #6, see TestDates).
        let saved = Calendar.current.date(byAdding: .day, value: -40, to: TestDates.today())!
        let pending = PendingRestore(backup: backup(tasks: 1, templates: 1, exportedAt: saved),
                                    existingTasks: 5, existingTemplates: 5)

        // The same call PendingRestore.warning makes, so the whole date and time must be there.
        let shown = saved.formatted(date: .abbreviated, time: .shortened)
        #expect(pending.warning.contains(shown), "the backup's date is missing from: \(pending.warning)")
    }

    @Test("Blocks are named as unaffected, because they are")
    func blocksAreSafe() {
        let pending = PendingRestore(backup: backup(tasks: 1, templates: 1),
                                    existingTasks: 1, existingTemplates: 1)
        #expect(pending.warning.contains("blocks are not affected"))
    }

    @Test("Counts read as English")
    func pluralisation() {
        #expect(PendingRestore.counted(0, "task") == "no tasks")
        #expect(PendingRestore.counted(1, "task") == "1 task")
        #expect(PendingRestore.counted(2, "task") == "2 tasks")
        #expect(PendingRestore.counted(1, "template") == "1 template")
    }

    /// A singular count must not produce "1 tasks" anywhere in the sentence.
    @Test("One of each reads correctly in the full sentence")
    func singularInContext() {
        let pending = PendingRestore(backup: backup(tasks: 1, templates: 1),
                                    existingTasks: 1, existingTemplates: 1)
        #expect(!pending.warning.contains("1 tasks"))
        #expect(!pending.warning.contains("1 templates"))
    }
}
