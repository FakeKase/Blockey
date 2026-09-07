import Foundation
import SwiftData

/// A saved shape for a day — "Deep work Tuesday", "Weekend" — that can be
/// stamped onto any date in one tap.
@Model
final class DayTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TemplateRow.template)
    var rows: [TemplateRow]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.rows = []
    }

    /// Rows in the order they occur during the day.
    var orderedRows: [TemplateRow] {
        rows.sorted { $0.startMinuteOfDay < $1.startMinuteOfDay }
    }

    /// Bridges to the pure stamper, which knows nothing about SwiftData.
    var stampItems: [TemplateStamper.Item] {
        orderedRows.map {
            TemplateStamper.Item(id: $0.id,
                                 title: $0.title,
                                 startMinuteOfDay: $0.startMinuteOfDay,
                                 durationMinutes: $0.durationMinutes)
        }
    }

    /// Category lookup for a stamped item, by row id.
    func category(forRowID id: UUID) -> BlockCategory {
        rows.first { $0.id == id }?.category ?? .fallback
    }
}

/// One line of a template.
@Model
final class TemplateRow {
    @Attribute(.unique) var id: UUID
    var title: String
    var startMinuteOfDay: Int
    var durationMinutes: Int
    var categoryRaw: String
    var template: DayTemplate?

    init(title: String,
         startMinuteOfDay: Int,
         durationMinutes: Int,
         category: BlockCategory = .deepWork) {
        self.id = UUID()
        self.title = title
        self.startMinuteOfDay = startMinuteOfDay
        self.durationMinutes = durationMinutes
        self.categoryRaw = category.rawValue
    }

    var category: BlockCategory {
        get { BlockCategory(rawValue: categoryRaw) ?? .fallback }
        set { categoryRaw = newValue.rawValue }
    }
}

/// Which template is stamped for a given weekday, so the morning pass is one tap.
/// `weekday` follows `Calendar.component(.weekday:)`: 1 = Sunday.
@Model
final class TemplateAssignment {
    @Attribute(.unique) var weekday: Int
    var templateID: UUID?

    init(weekday: Int, templateID: UUID?) {
        self.weekday = weekday
        self.templateID = templateID
    }
}
