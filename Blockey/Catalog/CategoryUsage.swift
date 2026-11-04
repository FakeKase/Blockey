import Foundation

/// The words of the archive flow (UI spec 2.5). Counts come from `Planning/CategoryStore`.
enum CategoryUsage {

    /// `3 inbox tasks and 2 template rows use this category.` Nil when nothing uses it, which is
    /// also the "archive without asking" case.
    static func sentence(tasks: Int, rows: Int) -> String? {
        let t = Swift.max(0, tasks), r = Swift.max(0, rows)
        switch (t, r) {
        case (0, 0): return nil
        case (_, 0): return "\(t) inbox \(t == 1 ? "task uses" : "tasks use") this category."
        case (0, _): return "\(r) template \(r == 1 ? "row uses" : "rows use") this category."
        default:
            return "\(t) inbox \(t == 1 ? "task" : "tasks") and \(r) template \(r == 1 ? "row" : "rows") use this category."
        }
    }

    /// `Move 5 and archive`, `Move 1 and archive`. The count is tasks plus rows.
    static func moveButtonTitle(count: Int) -> String { "Move \(Swift.max(0, count)) and archive" }

    static func archiveTitle(name: String) -> String { "Archive \u{201C}\(name)\u{201D}?" }

    static let calendarNote = "Blocks already on your calendar keep this category."
    static let moveHeader = "Move them to"
    static let moveHelper = "Choose a category to move them to, or archive without moving."
    static let archiveWithoutMoving = "Archive without moving"

    static func withoutMovingNote(name: String) -> String {
        "They keep \u{201C}\(name)\u{201D} and still show it. It just won\u{2019}t be offered for new work."
    }

    static func archiveFailure(name: String) -> String {
        "Couldn\u{2019}t archive \u{201C}\(name)\u{201D}. Nothing was changed. Try again."
    }

    static let archiveAlertTitle = "Couldn\u{2019}t archive"
    static let archiveAlertMessage = "Nothing was changed. Try again."

    /// An alert's two lines. Each failing action names itself in the title, so a failed reorder
    /// never reads "Couldn\u{2019}t archive".
    struct Failure: Equatable {
        let title: String
        let message: String
    }
    static let archiveFailureAlert = Failure(title: archiveAlertTitle, message: archiveAlertMessage)
    static let reorderFailureAlert = Failure(title: "Couldn\u{2019}t reorder", message: archiveAlertMessage)
    static let restoreFailureAlert = Failure(title: "Couldn\u{2019}t restore", message: archiveAlertMessage)

    static let lastOneFooter = "Blockey needs at least one category. Add another before archiving this one."

    static func archived(_ name: String) -> String { "Archived \u{201C}\(name)\u{201D}" }
    static func restored(_ name: String) -> String { "Restored \u{201C}\(name)\u{201D}" }
    static func added(_ name: String) -> String { "Added \u{201C}\(name)\u{201D}" }
}

/// What archiving a category should do first (spec 2.5, steps 3 and 4).
enum ArchiveFlow: Equatable {
    /// Nothing uses it: archive now, no dialog.
    case archiveNow
    /// Ask where the inbox tasks and template rows should go, if anywhere.
    case askWhereToMove(tasks: Int, rows: Int)

    static func decide(tasks: Int, rows: Int) -> ArchiveFlow {
        tasks + rows == 0 ? .archiveNow : .askWhereToMove(tasks: tasks, rows: rows)
    }
}
