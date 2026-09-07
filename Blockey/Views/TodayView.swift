import SwiftUI
import SwiftData

/// The whole app, really: one day, what is fixed, what you have blocked, and
/// the two actions that fill the rest — stamp a template, place a task.
struct TodayView: View {
    @Environment(CalendarService.self) private var calendars
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\TaskItem.sortIndex), SortDescriptor(\TaskItem.createdAt)])
    private var tasks: [TaskItem]
    @Query(sort: \DayTemplate.name) private var templates: [DayTemplate]
    @Query private var assignments: [TemplateAssignment]

    @AppStorage(SettingsKey.dayStartMinute) private var dayStartMinute = SettingsKey.defaultDayStart
    @AppStorage(SettingsKey.dayEndMinute) private var dayEndMinute = SettingsKey.defaultDayEnd
    @AppStorage(SettingsKey.snapMinutes) private var snapMinutes = SettingsKey.defaultSnap
    @AppStorage(SettingsKey.hiddenCalendarIDs) private var hiddenCalendarsRaw = ""
    @AppStorage(SettingsKey.alarmEnabled) private var alarmEnabled = false
    @AppStorage(SettingsKey.alarmMinutesBefore) private var alarmMinutesBefore = 5

    @State private var selectedDate = Date()
    @State private var contents = DayContents()
    @State private var armedTask: TaskItem?
    @State private var selectedBlock: Block?
    @State private var sheet: Sheet?
    @State private var banner: Banner?
    @State private var now = Date()
    @State private var isConfirmingRestamp = false

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private var calendar: Calendar { .current }

    private enum Sheet: String, Identifiable {
        case inbox, templates, settings
        var id: String { rawValue }
    }

    private struct Banner: Identifiable, Equatable {
        let id = UUID()
        let text: String
        var isWarning = false
    }

    // MARK: Derived state

    private var window: TimeRange {
        DaySchedule.window(for: selectedDate,
                           startMinute: dayStartMinute,
                           endMinute: dayEndMinute,
                           calendar: calendar)
    }

    /// The window, widened to whole hours around anything scheduled outside it,
    /// so a 6am flight is never invisible.
    private var visibleRange: TimeRange {
        var start = window.start
        var end = window.end
        for range in contents.busy {
            start = min(start, range.start)
            end = max(end, range.end)
        }
        // Always keep the current moment on screen when looking at today,
        // otherwise late-evening planning happens below the fold.
        if isToday {
            start = min(start, now)
            end = max(end, now.addingTimeInterval(1800))
        }
        return TimeRange(start: calendar.flooredToHour(start), end: calendar.ceiledToHour(end))
    }

    private var hiddenCalendarIDs: Set<String> {
        Set(hiddenCalendarsRaw.split(separator: "\n").map(String.init))
    }

    private var openTasks: [TaskItem] { tasks.filter { !$0.isDone } }

    /// Gaps big enough for the armed task. Empty when nothing is armed, which
    /// is what makes the highlight appear only during placement.
    private var candidateGaps: [TimeRange] {
        guard let armedTask else { return [] }
        return DaySchedule.gaps(busy: contents.busy,
                                within: window,
                                minimumDuration: armedTask.duration)
    }

    private var templateForToday: DayTemplate? {
        let weekday = calendar.component(.weekday, from: selectedDate)
        guard let id = assignments.first(where: { $0.weekday == weekday })?.templateID else { return nil }
        return templates.first { $0.id == id }
    }

    private var isToday: Bool { calendar.isDateInToday(selectedDate) }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                timeline
                VStack(spacing: 8) {
                    bannerView
                    bottomBar
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .top, spacing: 0) { dayHeader }

        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .inbox:
                InboxTray(
                    tasks: openTasks,
                    onArm: { task in
                        armedTask = task
                        sheet = nil
                    },
                    onFillDay: fillDay
                )
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            case .templates:
                TemplatesView()
            case .settings:
                SettingsView()
            }
        }
        .confirmationDialog("Today already has \(contents.blocks.count) block\(contents.blocks.count == 1 ? "" : "s")",
                            isPresented: $isConfirmingRestamp,
                            titleVisibility: .visible) {
            Button("Replace them", role: .destructive) {
                perform { try calendars.deleteAllBlocks(on: selectedDate, calendar: calendar) }
                applyTemplate()
            }
            Button("Add on top") { applyTemplate() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Stamping again will plan around the blocks that are already there.")
        }
        .sheet(item: $selectedBlock) { block in
            BlockDetailSheet(
                block: block,
                onSave: { title, range, category in
                    perform { try calendars.update(block, title: title, range: range, category: category) }
                },
                onDelete: { perform { try calendars.delete(block) } },
                onReturnToInbox: { returnToInbox(block) }
            )
            .presentationDetents([.medium])
        }
        .task {
            StarterData.seedIfNeeded(context: context)
            #if DEBUG && targetEnvironment(simulator)
            if let pinned = DemoScenario.overrideNow { now = pinned }
            if DemoScenario.isRequested {
                DemoScenario.apply(calendars: calendars, context: context, on: selectedDate)
            }
            #endif
            reload()
            #if DEBUG && targetEnvironment(simulator)
            if DemoScenario.shouldStamp {
                // Let @Query republish the just-seeded templates first.
                try? await _Concurrency.Task.sleep(for: .milliseconds(600))
                stampTemplate()
            }
            #endif
        }
        .onChange(of: selectedDate) { _, _ in reload() }
        .onChange(of: calendars.revision) { _, _ in reload() }
        .onReceive(clock) { tick in
            #if DEBUG && targetEnvironment(simulator)
            if DemoScenario.overrideNow != nil { return }
            #endif
            now = tick
        }
    }

    private var navigationTitle: String {
        isToday ? "Today" : selectedDate.formatted(.dateTime.weekday(.wide))
    }

    // MARK: Header

    private var dayHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 1) {
                    Text(selectedDate, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.headline)
                    Text(summaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if !isToday {
                    Button("Today") { withAnimation { selectedDate = .now } }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if !contents.allDay.isEmpty {
                allDayBanner
            }
            Divider()
        }
        .background(.bar)
    }

    private var summaryLine: String {
        let blockCount = contents.blocks.count
        let free = DaySchedule.gaps(busy: contents.busy, within: window, minimumDuration: 15 * 60)
            .reduce(0) { $0 + $1.duration }
        let hours = free / 3600
        if blockCount == 0 {
            return String(format: "Nothing blocked · %.1fh free", hours)
        }
        return String(format: "%d block%@ · %.1fh free", blockCount, blockCount == 1 ? "" : "s", hours)
    }

    private var allDayBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.caption2)
            Text(contents.allDay.map(\.title).joined(separator: " · "))
                .font(.caption)
                .lineLimit(1)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: Timeline

    private var timeline: some View {
        TimelineCanvas(
            visible: visibleRange,
            window: window,
            blocks: contents.blocks,
            fixed: contents.fixed,
            candidateGaps: candidateGaps,
            armedDuration: armedTask?.duration,
            now: now,
            snapMinutes: snapMinutes,
            calendar: calendar,
            onSelectBlock: { if armedTask == nil { selectedBlock = $0 } },
            onPlace: { place(armedTask, at: $0) },
            onMove: { block, range in
                perform { try calendars.update(block, range: range) }
            }
        )
    }

    // MARK: Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        if let armedTask {
            HStack(spacing: 10) {
                Image(systemName: "hand.tap.fill")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tap a slot for “\(armedTask.title)”")
                        .font(.subheadline.weight(.medium))
                    Text(candidateGaps.isEmpty
                         ? "No gap is long enough today"
                         : "\(candidateGaps.count) slot\(candidateGaps.count == 1 ? "" : "s") fit \(armedTask.estimatedMinutes) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { self.armedTask = nil }
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            HStack(spacing: 10) {
                Button {
                    stampTemplate()
                } label: {
                    Label(templateForToday.map { "Stamp “\($0.name)”" } ?? "Apply template",
                          systemImage: "square.stack.3d.up.fill")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    sheet = .inbox
                } label: {
                    Label("\(openTasks.count)", systemImage: "tray.full.fill")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var bannerView: some View {
        if let banner {
            Text(banner.text)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(banner.isWarning ? Color.orange.opacity(0.92) : Color.accentColor.opacity(0.92),
                            in: Capsule())
                .foregroundStyle(.white)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    _Concurrency.Task {
                        try? await _Concurrency.Task.sleep(for: .seconds(2.6))
                        withAnimation { self.banner = nil }
                    }
                }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { sheet = .templates } label: { Label("Templates", systemImage: "square.stack.3d.up") }
                Button { sheet = .settings } label: { Label("Settings", systemImage: "gearshape") }
                #if DEBUG && targetEnvironment(simulator)
                Divider()
                Button { calendars.seedDemoMeetings(on: selectedDate); reload() } label: {
                    Label("Seed demo meetings", systemImage: "ladybug")
                }
                #endif
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: Actions

    private func shiftDay(_ delta: Int) {
        guard let next = calendar.date(byAdding: .day, value: delta, to: selectedDate) else { return }
        withAnimation { selectedDate = next }
    }

    private func reload() {
        contents = calendars.contents(for: selectedDate, ignoring: hiddenCalendarIDs, calendar: calendar)
    }

    /// Runs a calendar mutation, surfacing failure rather than swallowing it.
    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            reload()
        } catch {
            show(error.localizedDescription, warning: true)
        }
    }

    private func show(_ text: String, warning: Bool = false) {
        withAnimation { banner = Banner(text: text, isWarning: warning) }
    }

    private func place(_ task: TaskItem?, at start: Date) {
        guard let task else { return }
        let range = TimeRange(start: start, duration: task.duration)
        do {
            try calendars.createBlock(title: task.title,
                                      range: range,
                                      category: task.category,
                                      sourceTaskID: task.id,
                                      alarmMinutesBefore: alarmEnabled ? alarmMinutesBefore : nil)
            // The inbox holds only unscheduled work, so a placed task leaves it.
            // Unscheduling recreates it from the block — symmetric, and there is
            // never a task and a block representing the same thing at once.
            context.delete(task)
            armedTask = nil
            reload()
            show("Blocked \(start.formatted(date: .omitted, time: .shortened))")
        } catch {
            show(error.localizedDescription, warning: true)
        }
    }

    private func returnToInbox(_ block: Block) {
        let task = TaskItem(title: block.title,
                            estimatedMinutes: Int(block.range.duration / 60),
                            category: block.category,
                            sortIndex: (openTasks.map(\.sortIndex).min() ?? 0) - 1)
        context.insert(task)
        perform { try calendars.delete(block) }
        show("Returned to inbox")
    }

    /// Places as many inbox tasks as will fit, in priority order, without
    /// scheduling anything into a moment that has already passed.
    private func fillDay() {
        var busy = contents.busy
        var placed = 0

        for task in openTasks {
            let gaps = DaySchedule.gaps(busy: busy, within: window, minimumDuration: task.duration)
            guard let slot = DaySchedule.firstFit(duration: task.duration,
                                                  in: gaps,
                                                  notBefore: isToday ? now : nil) else { continue }
            do {
                try calendars.createBlock(title: task.title,
                                          range: slot,
                                          category: task.category,
                                          sourceTaskID: task.id,
                                          alarmMinutesBefore: alarmEnabled ? alarmMinutesBefore : nil)
                busy.append(slot)
                context.delete(task)
                placed += 1
            } catch {
                show(error.localizedDescription, warning: true)
                break
            }
        }

        reload()
        show(placed == 0 ? "Nothing fits in the day’s free time" : "Placed \(placed) task\(placed == 1 ? "" : "s")",
             warning: placed == 0)
    }

    private func stampTemplate() {
        guard templateForToday != nil else {
            sheet = .templates
            return
        }
        // Stamping a day that is already planned would quietly double it, and
        // the second set lands in whatever gaps are left — which looks like a
        // bug rather than a second stamp. Make the choice explicit instead.
        if !contents.blocks.isEmpty {
            isConfirmingRestamp = true
            return
        }
        applyTemplate()
    }

    private func applyTemplate() {
        guard let template = templateForToday else { return }
        let result = TemplateStamper.stamp(items: template.stampItems,
                                           on: selectedDate,
                                           busy: contents.busy,
                                           window: window,
                                           calendar: calendar)

        var created = 0
        for (item, range) in result.scheduled {
            do {
                try calendars.createBlock(title: item.title,
                                          range: range,
                                          category: template.category(forRowID: item.id),
                                          alarmMinutesBefore: alarmEnabled ? alarmMinutesBefore : nil)
                created += 1
            } catch {
                show(error.localizedDescription, warning: true)
                break
            }
        }

        // Anything that did not fit becomes an inbox task rather than vanishing.
        var index = (openTasks.map(\.sortIndex).min() ?? 0) - 1
        for item in result.unplaced {
            context.insert(TaskItem(title: item.title,
                                    estimatedMinutes: item.durationMinutes,
                                    category: template.category(forRowID: item.id),
                                    sortIndex: index,
                                    droppedFromTemplate: true))
            index -= 1
        }

        reload()

        var message = "Stamped \(created) block\(created == 1 ? "" : "s")"
        if result.movedCount > 0 { message += " · \(result.movedCount) moved to fit" }
        if !result.unplaced.isEmpty { message += " · \(result.unplaced.count) to inbox" }
        show(message, warning: !result.unplaced.isEmpty)
    }
}
