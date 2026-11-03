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
    /// Skips the "Plan <day>" preview for a one-tap add on an empty day. Off by default, and
    /// not backed up (gap 6): losing it resets it to the safe setting.
    static let skipPlanPreview = "skipPlanPreview"
    /// Set once the first-launch card has been answered. Never reset. Not backed up either, so
    /// a delete and reinstall shows the card again, which is harmless.
    static let hasSeenStarterTemplatesNote = "hasSeenStarterTemplatesNote"

    static let defaultDayStart = 7 * 60
    static let defaultDayEnd = 22 * 60
    static let defaultSnap = 15
}
