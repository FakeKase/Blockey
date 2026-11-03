import Foundation
import SwiftData

/// An unscheduled piece of work waiting for a slot.
///
/// Named `TaskItem` rather than `Task` on purpose: `Task` is Swift
/// Concurrency's type, and shadowing it inside an app that uses `async` is a
/// reliable way to lose an afternoon.
@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var estimatedMinutes: Int
    var categoryRaw: String
    var sortIndex: Int
    var createdAt: Date
    var completedAt: Date?

    /// Set when a template item could not be placed and fell through to the
    /// inbox, so the UI can explain why it appeared.
    var droppedFromTemplate: Bool

    /// The template it fell out of, so the inbox can say "from Workday, no room". Optional and
    /// additive: tasks saved before this existed, and tasks restored from an older backup, have
    /// none, and the UI falls back to "your template".
    var droppedFromTemplateName: String?

    convenience init(title: String,
                     estimatedMinutes: Int = 30,
                     category: BlockCategory = .deepWork,
                     sortIndex: Int = 0,
                     droppedFromTemplate: Bool = false,
                     droppedFromTemplateName: String? = nil) {
        self.init(title: title, estimatedMinutes: estimatedMinutes, categoryRaw: category.rawValue,
                  sortIndex: sortIndex, droppedFromTemplate: droppedFromTemplate,
                  droppedFromTemplateName: droppedFromTemplateName)
    }

    /// Takes the slug as stored, so one this build doesn't know survives a trip through the
    /// inbox. `category` is the lossy view of it.
    init(title: String,
         estimatedMinutes: Int = 30,
         categoryRaw: String,
         sortIndex: Int = 0,
         droppedFromTemplate: Bool = false,
         droppedFromTemplateName: String? = nil) {
        self.id = UUID()
        self.title = title
        self.estimatedMinutes = Swift.max(5, estimatedMinutes)
        self.categoryRaw = categoryRaw
        self.sortIndex = sortIndex
        self.createdAt = .now
        self.completedAt = nil
        self.droppedFromTemplate = droppedFromTemplate
        self.droppedFromTemplateName = droppedFromTemplateName
    }

    /// Puts a task back exactly as an action deleted it (Undo), keeping its identity and
    /// history instead of minting new ones.
    ///
    /// The 5 minute floor still applies. Every value a snapshot holds came from a task that
    /// already passed through the clamp, so on honest data it is a no-op; keeping it means this
    /// path can never produce a task the other inits could not, even from a hand-built or
    /// stale snapshot. Skipping it would give the model two sets of invariants.
    init(id: UUID,
         title: String,
         estimatedMinutes: Int,
         categoryRaw: String,
         sortIndex: Int,
         createdAt: Date,
         completedAt: Date?,
         droppedFromTemplate: Bool,
         droppedFromTemplateName: String? = nil) {
        self.id = id
        self.title = title
        self.estimatedMinutes = Swift.max(5, estimatedMinutes)
        self.categoryRaw = categoryRaw
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.droppedFromTemplate = droppedFromTemplate
        self.droppedFromTemplateName = droppedFromTemplateName
    }

    var category: BlockCategory {
        get { BlockCategory(rawValue: categoryRaw) ?? .fallback }
        set { categoryRaw = newValue.rawValue }
    }

    var duration: TimeInterval { TimeInterval(estimatedMinutes * 60) }
    var isDone: Bool { completedAt != nil }
}
