import Foundation
import SwiftData

/// First-run content.
///
/// An empty time-blocking app is hard to judge: you cannot see what stamping
/// does until a template exists. Two plausible templates, wired to the right
/// weekdays, mean the first morning pass works before anything is configured.
enum StarterData {

    static func seedIfNeeded(context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: SettingsKey.hasSeededTemplates) else { return }
        defaults.set(true, forKey: SettingsKey.hasSeededTemplates)

        let workday = DayTemplate(name: "Workday")
        let workdayRows = [
            TemplateRow(title: "Deep work", startMinuteOfDay: 9 * 60, durationMinutes: 120, category: .deepWork),
            TemplateRow(title: "Admin & email", startMinuteOfDay: 11 * 60 + 30, durationMinutes: 45, category: .admin),
            TemplateRow(title: "Lunch", startMinuteOfDay: 12 * 60 + 30, durationMinutes: 45, category: .rest),
            TemplateRow(title: "Deep work", startMinuteOfDay: 13 * 60 + 30, durationMinutes: 90, category: .deepWork),
            TemplateRow(title: "Wrap up & plan tomorrow", startMinuteOfDay: 17 * 60, durationMinutes: 30, category: .admin)
        ]

        let weekend = DayTemplate(name: "Weekend")
        let weekendRows = [
            TemplateRow(title: "Workout", startMinuteOfDay: 9 * 60, durationMinutes: 60, category: .health),
            TemplateRow(title: "Personal project", startMinuteOfDay: 10 * 60 + 30, durationMinutes: 120, category: .personal),
            TemplateRow(title: "Errands", startMinuteOfDay: 14 * 60, durationMinutes: 90, category: .personal)
        ]

        context.insert(workday)
        context.insert(weekend)
        for row in workdayRows { row.template = workday; context.insert(row) }
        for row in weekendRows { row.template = weekend; context.insert(row) }

        // Calendar weekdays: 1 = Sunday … 7 = Saturday.
        for weekday in 2...6 {
            context.insert(TemplateAssignment(weekday: weekday, templateID: workday.id))
        }
        context.insert(TemplateAssignment(weekday: 1, templateID: weekend.id))
        context.insert(TemplateAssignment(weekday: 7, templateID: weekend.id))
    }
}
