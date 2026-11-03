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

    convenience init(title: String,
                     estimatedMinutes: Int = 30,
                     category: BlockCategory = .deepWork,
                     sortIndex: Int = 0,
                     droppedFromTemplate: Bool = false) {
        self.init(title: title, estimatedMinutes: estimatedMinutes, categoryRaw: category.rawValue,
                  sortIndex: sortIndex, droppedFromTemplate: droppedFromTemplate)
    }

    /// Takes the slug as stored, so one this build doesn't know survives a trip through the
    /// inbox. `category` is the lossy view of it.
    init(title: String,
         estimatedMinutes: Int = 30,
         categoryRaw: String,
         sortIndex: Int = 0,
         droppedFromTemplate: Bool = false) {
        self.id = UUID()
        self.title = title
        self.estimatedMinutes = Swift.max(5, estimatedMinutes)
        self.categoryRaw = categoryRaw
        self.sortIndex = sortIndex
        self.createdAt = .now
        self.completedAt = nil
        self.droppedFromTemplate = droppedFromTemplate
    }

    var category: BlockCategory {
        get { BlockCategory(rawValue: categoryRaw) ?? .fallback }
        set { categoryRaw = newValue.rawValue }
    }

    var duration: TimeInterval { TimeInterval(estimatedMinutes * 60) }
    var isDone: Bool { completedAt != nil }
}
