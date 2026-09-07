import Foundation
import SwiftData

#if DEBUG && targetEnvironment(simulator)
/// Drives the app into a realistic, populated state on launch so the whole
/// screen can be reviewed without tapping through it by hand.
///
/// Simulator-and-Debug only, at compile time rather than behind a runtime flag,
/// so there is no build in which this can touch a real person's calendar.
/// Triggered with `-blockeyDemo` as a launch argument.
enum DemoScenario {

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-blockeyDemo")
    }

    /// `-blockeyNow 10:15` pins the "current time" so screenshots and reviews
    /// show a realistic working hour rather than whenever the build ran.
    static var overrideNow: Date? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-blockeyNow"), index + 1 < args.count else { return nil }
        let parts = args[index + 1].split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.startOfDay(for: .now)
            .addingTimeInterval(TimeInterval(parts[0] * 3600 + parts[1] * 60))
    }

    /// Stamp the weekday's template immediately, for reviewing a planned day.
    static var shouldStamp: Bool {
        ProcessInfo.processInfo.arguments.contains("-blockeyStamp")
    }

    @MainActor
    static func apply(calendars: CalendarService, context: ModelContext, on date: Date) {
        // Blocks live in the calendar and survive app reinstalls, so a repeat
        // demo run would stack a second plan on top of the first.
        _ = try? calendars.deleteAllBlocks(on: date)
        calendars.seedDemoMeetings(on: date)

        let tasks = [
            TaskItem(title: "Write the launch post", estimatedMinutes: 90, category: .deepWork, sortIndex: 0),
            TaskItem(title: "Review pull requests", estimatedMinutes: 45, category: .admin, sortIndex: 1),
            TaskItem(title: "Call the accountant", estimatedMinutes: 30, category: .admin, sortIndex: 2),
            TaskItem(title: "Gym", estimatedMinutes: 60, category: .health, sortIndex: 3)
        ]
        for task in tasks { context.insert(task) }
    }
}
#endif
