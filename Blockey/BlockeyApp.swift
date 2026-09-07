import SwiftUI
import SwiftData

@main
struct BlockeyApp: App {
    @State private var calendarService = CalendarService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(calendarService)
        }
        .modelContainer(for: [
            TaskItem.self,
            DayTemplate.self,
            TemplateRow.self,
            TemplateAssignment.self
        ])
    }
}

/// User preferences. Small and scalar, so `@AppStorage` rather than a
/// single-row SwiftData model — there is no relational shape here to earn one.
enum SettingsKey {
    static let dayStartMinute = "dayStartMinute"
    static let dayEndMinute = "dayEndMinute"
    static let snapMinutes = "snapMinutes"
    static let hiddenCalendarIDs = "hiddenCalendarIDs"
    static let alarmEnabled = "blockAlarmEnabled"
    static let alarmMinutesBefore = "blockAlarmMinutesBefore"
    static let hasSeededTemplates = "hasSeededStarterTemplates"

    static let defaultDayStart = 7 * 60
    static let defaultDayEnd = 22 * 60
    static let defaultSnap = 15
}
