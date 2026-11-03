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

    /// `-blockeyPlanSheet` opens the "Plan <day>" sheet after any `-blockeyStamp` has landed;
    /// add `-blockeyStartOver` to open it with Start over selected (needs a stamped day).
    static var wantsPlanSheet: Bool {
        ProcessInfo.processInfo.arguments.contains("-blockeyPlanSheet")
    }
    static var wantsStartOver: Bool {
        ProcessInfo.processInfo.arguments.contains("-blockeyStartOver")
    }

    /// `-blockeyInbox` opens the inbox tray at its medium height.
    static var wantsInbox: Bool {
        ProcessInfo.processInfo.arguments.contains("-blockeyInbox")
    }

    /// `-blockeyComposerText <text>` pre-fills the inbox composer, so suggestions can be
    /// screenshotted without a keyboard.
    static var composerText: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-blockeyComposerText"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    /// `-blockeyHoldBanner` stops the banner timer, so a screenshot can catch it.
    static var holdsBanner: Bool {
        ProcessInfo.processInfo.arguments.contains("-blockeyHoldBanner")
    }

    /// A run of back-to-back evening blocks, one of them only 30 minutes long.
    /// Short blocks are where the timeline's layout is under the most pressure,
    /// so this is the scenario worth being able to reproduce on demand.
    static var wantsEvening: Bool {
        ProcessInfo.processInfo.arguments.contains("-blockeyEvening")
    }

    /// `-blockeyUndoExercise` runs `exerciseUndo` against the real `CalendarService`.
    static var wantsUndoExercise: Bool {
        ProcessInfo.processInfo.arguments.contains("-blockeyUndoExercise")
    }

    /// Runs Undo through the real EventKit path, which unit tests cannot reach (they use a fake),
    /// and writes a PASS/FAIL report to `undo-exercise.txt` in the app's temporary directory.
    ///
    /// Works on the day two days after `date`, in the simulator's calendar, and clears that day
    /// afterwards, so the day on screen is untouched. It is inside the same
    /// `#if DEBUG && targetEnvironment(simulator)` gate as the rest of this file.
    @MainActor
    static func exerciseUndo(calendars: CalendarService, context: ModelContext, on date: Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let day = cal.date(byAdding: .day, value: 2, to: start) ?? start
        func at(_ hour: Int) -> Date { cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day }
        func span(_ a: Int, _ b: Int) -> TimeRange { TimeRange(start: at(a), end: at(b)) }

        var report: [String] = []
        func check(_ name: String, _ ok: Bool) { report.append("\(ok ? "PASS" : "FAIL") \(name)") }

        _ = try? calendars.deleteAllBlocks(on: day)
        let window = span(7, 22)
        let inputs = DayPlanInputs(date: day, now: at(6), isToday: false, window: window,
                                   plannableWindow: window, alarmMinutesBefore: nil,
                                   calendar: cal, hiddenCalendarIDs: [])
        let planner = DayPlanner(writer: calendars, context: context)
        let rows = [("Alpha", 13 * 60), ("Beta", 14 * 60), ("Gamma", 15 * 60)]
        let items = rows.map { TemplateStamper.Item(title: $0.0, startMinuteOfDay: $0.1, durationMinutes: 30) }
        let stampTemplate = StampTemplate(items: items,
                                          slugs: Dictionary(uniqueKeysWithValues: items.map { ($0.id, "deep") }))

        do {
            // 1. Start over, then Undo: token, notes and alarms must come back through EventKit.
            let source = UUID()
            let url = URL(string: "blockey://block/\(UUID().uuidString)?c=rest&t=\(source.uuidString)&x=keep")
            let token = BlockToken(url: url)
            try calendars.createBlock(title: "Write", range: span(9, 10), token: token,
                                      notes: "Bring the laptop", alarmOffsets: [-600, -3600])
            try calendars.createBlock(title: "Dentist", range: span(17, 18), token: nil,
                                      notes: "Ask about the crown", alarmOffsets: [])
            let stamped = try planner.replace(with: stampTemplate, inputs: inputs, openTasks: [])
            check("start over wrote 3 blocks", calendars.contents(for: day, ignoring: [], calendar: cal).blocks.count == 3)
            let outcome = try planner.undo(stamped.undo)
            let after = calendars.contents(for: day, ignoring: [], calendar: cal).blocks
            check("undo removed the 3 stamped blocks", outcome.blocksRemoved == 3)
            check("undo left exactly the 2 original blocks", Set(after.map(\.title)) == ["Write", "Dentist"] && after.count == 2)
            let write = after.first { $0.title == "Write" }
            check("original token restored verbatim (id, slug, source, unknown item)", write?.token == token)
            check("notes restored", write?.notes == "Bring the laptop")
            check("alarm offsets restored (got \(write?.alarmOffsets ?? []))", write?.alarmOffsets == [-3600, -600])
            check("range restored", write?.range == span(9, 10))
            let dentist = after.first { $0.title == "Dentist" }
            check("tokenless block recreated with a fresh token and its notes",
                  dentist?.token != nil && dentist?.notes == "Ask about the crown")
            // By title, not "no tasks at all": a store left over from an earlier demo run has some.
            let leftovers = (try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.title == "Write" }))) ?? []
            check("returned inbox task removed", leftovers.isEmpty)
            let again = try planner.undo(stamped.undo)
            check("second undo is a no-op", again.alreadyUndone
                  && calendars.contents(for: day, ignoring: [], calendar: cal).blocks.count == 2)

            // The new lookup: a token at +5 days is found, an unknown one is not, one at +9 is outside.
            let nearDay = cal.date(byAdding: .day, value: 5, to: day) ?? day
            let farDay = cal.date(byAdding: .day, value: 9, to: day) ?? day
            func tokenAt(_ d: Date) throws -> UUID {
                let t = BlockToken(categorySlug: "deep")
                let s = cal.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
                try calendars.createBlock(title: "Lookup", range: TimeRange(start: s, duration: 1800),
                                          token: t, notes: nil, alarmOffsets: [])
                return t.id
            }
            let nearID = try tokenAt(nearDay), farID = try tokenAt(farDay)
            let found = calendars.existingTokenIDs([nearID, farID, UUID()], around: day, days: 7, calendar: cal)
            check("existingTokenIDs finds +5 days, not +9 or unknown", found == [nearID])
            _ = try? calendars.deleteAllBlocks(on: nearDay)
            _ = try? calendars.deleteAllBlocks(on: farDay)

            // 2. A stamp where the user deleted one block: Removed 2 of 3.
            let keep = planner.stamp(stampTemplate, inputs: inputs, openTasks: [])
            if let victim = keep.created.first { try calendars.delete(victim) }
            let partial = try planner.undo(keep.undo)
            check("deleted block is reported: \(partial.message.text)", partial.message.text == "Removed 2 of 3 blocks")
            check("only the originals remain",
                  calendars.contents(for: day, ignoring: [], calendar: cal).blocks.count == 2)
        } catch {
            report.append("FAIL threw: \(error.localizedDescription)")
        }

        _ = try? calendars.deleteAllBlocks(on: day)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("undo-exercise.txt")
        try? report.joined(separator: "\n").write(to: path, atomically: true, encoding: .utf8)
    }

    @MainActor
    static func apply(calendars: CalendarService, context: ModelContext, on date: Date) {
        // Blocks live in the calendar and survive app reinstalls, so a repeat
        // demo run would stack a second plan on top of the first.
        _ = try? calendars.deleteAllBlocks(on: date)
        calendars.seedDemoMeetings(on: date)
        calendars.seedDemoHistory(now: date)
        if wantsUndoExercise { exerciseUndo(calendars: calendars, context: context, on: date) }

        if wantsEvening {
            let evening: [(String, Int, Int, BlockCategory)] = [
                ("Running",        17 * 60 + 30, 120, .health),
                ("Eating",         19 * 60 + 30,  90, .rest),
                ("Reading",        21 * 60,       30, .deepWork),
                ("Shower & Relax", 21 * 60 + 30,  60, .rest),
                ("Vitamins",       22 * 60 + 30,  15, .health)
            ]
            for (title, startMinute, minutes, category) in evening {
                let start = DaySchedule.timeOfDay(startMinute, on: date)
                _ = try? calendars.createBlock(title: title,
                                               range: TimeRange(start: start,
                                                                duration: TimeInterval(minutes * 60)),
                                               category: category)
            }
        }

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
