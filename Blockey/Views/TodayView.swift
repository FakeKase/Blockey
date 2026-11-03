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
    @State private var inboxDetent: PresentationDetent = .medium
    @State private var banner: Banner?
    @State private var now = Date()
    @State private var isConfirmingRestamp = false
    @State private var isConfirmingClear = false

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private var calendar: Calendar { .current }

    /// The tray height that leaves the timeline usable while a task is armed.
    private static let armedDetent = PresentationDetent.height(112)

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

    /// The part of the window still ahead of you.
    ///
    /// Planning is always forward-looking: counting this morning's elapsed
    /// hours as "free", or offering them as slots, is just wrong by lunchtime.
    private var plannableWindow: TimeRange {
        guard isToday else { return window }
        return TimeRange(start: max(window.start, now), end: max(window.start, window.end))
    }

    /// Blocks whose token is gone, so Blockey can no longer tell whether they
    /// came from a task. Theirs is the one case "back to the inbox" cannot
    /// honour, and the only way work is lost for good.
    private var untaggedBlocks: Int {
        contents.blocks.filter { $0.token == nil }.count
    }

    private var clearWarning: String {
        let promise = "Anything you placed from the inbox goes back to the inbox."
        guard untaggedBlocks > 0 else { return promise }
        return promise + " " + untaggedLossSentence
    }

    /// Replacing clears the day first, so it carries the same risk and says so.
    private var restampWarning: String {
        let base = "Replacing clears every block on \(weekdayName) \u{2014} including ones you placed by hand \u{2014} and stamps the template fresh. Adding keeps them and plans around them."
        guard untaggedBlocks > 0 else { return base }
        return base + " " + untaggedLossSentence
    }

    /// Said wherever blocks are about to be deleted: a block with no token
    /// cannot be traced back to a task, so it cannot be put back.
    private var untaggedLossSentence: String {
        untaggedBlocks == 1
            ? "One block has lost its Blockey tag, so it cannot be returned \u{2014} this deletes it for good."
            : "\(untaggedBlocks) blocks have lost their Blockey tag, so they cannot be returned \u{2014} this deletes them for good."
    }

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

    /// Gaps big enough for the armed task, and still ahead of you.
    private var candidateGaps: [TimeRange] {
        guard let armedTask else { return [] }
        return DaySchedule.gaps(busy: contents.busy,
                                within: plannableWindow,
                                minimumDuration: armedTask.duration)
    }

    private var longestFreeStretch: TimeInterval {
        DaySchedule.gaps(busy: contents.busy, within: plannableWindow)
            .map(\.duration).max() ?? 0
    }

    private var templateForToday: DayTemplate? {
        let weekday = calendar.component(.weekday, from: selectedDate)
        guard let id = assignments.first(where: { $0.weekday == weekday })?.templateID else { return nil }
        return templates.first { $0.id == id }
    }

    private var isToday: Bool { calendar.isDateInToday(selectedDate) }

    private var weekdayName: String {
        selectedDate.formatted(.dateTime.weekday(.wide))
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            timeline
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .top, spacing: 0) { dayHeader }
                // An inset rather than an overlay: the scroll view then reserves
                // room for the bar, instead of hiding the last hour behind it.
                .safeAreaInset(edge: .bottom, spacing: 0) { actionArea }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .inbox:
                InboxTray(
                    tasks: openTasks,
                    onArm: { task in
                        armedTask = task
                        // Shrink rather than dismiss: re-opening the tray for
                        // every task is the single biggest cost in the morning
                        // pass, and the timeline stays reachable behind it.
                        withAnimation { inboxDetent = Self.armedDetent }
                    },
                    onFillDay: fillDay
                )
                .presentationDetents([Self.armedDetent, .medium, .large], selection: $inboxDetent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            case .templates:
                TemplatesView()
            case .settings:
                SettingsView()
            }
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
        .confirmationDialog(restampTitle, isPresented: $isConfirmingRestamp, titleVisibility: .visible) {
            Button("Replace with the template", role: .destructive) { replaceWithTemplate() }
            Button("Add the template on top") { applyTemplate() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(restampWarning)
        }
        .confirmationDialog("Clear \(contents.blocks.count) block\(contents.blocks.count == 1 ? "" : "s")?",
                            isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear the day", role: .destructive) { clearDay() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(clearWarning)
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
            scheduleSigningReminder()
            #if DEBUG && targetEnvironment(simulator)
            if DemoScenario.shouldStamp {
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

    private var restampTitle: String {
        let count = contents.blocks.count
        return "\(weekdayName) already has \(count) block\(count == 1 ? "" : "s")"
    }

    // MARK: Header

    private var dayHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { shiftDay(-1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous day")

                VStack(alignment: .leading, spacing: 1) {
                    Text(isToday ? "Today" : selectedDate.formatted(.dateTime.weekday(.wide)))
                        .font(.headline)
                    Text(summaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()

                if !isToday {
                    Button("Today") { withAnimation { selectedDate = .now } }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Button { shiftDay(1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next day")
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .padding(.vertical, 2)

            if !contents.allDay.isEmpty { allDayBanner }
            Divider()
        }
        .background(.bar)
    }

    private var summaryLine: String {
        let free = DaySchedule.gaps(busy: contents.busy, within: plannableWindow, minimumDuration: 15 * 60)
            .reduce(0) { $0 + $1.duration }
        let hours = free / 3600
        let freeText = hours >= 1
            ? String(format: "%.0fh free", hours.rounded())
            : "\(Int(free / 60)) min free"

        if contents.blocks.isEmpty, !contents.fixed.isEmpty, let template = templateForToday {
            return "Your meetings are in. Stamp “\(template.name)” to fill the rest."
        }
        if contents.blocks.isEmpty {
            return "Nothing blocked · \(freeText)"
        }
        let count = contents.blocks.count
        return "\(count) block\(count == 1 ? "" : "s") · \(freeText)"
    }

    private var allDayBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar").font(.caption2)
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
        .overlay { emptyDayCard }
    }

    /// Shown only when the day is genuinely blank. With meetings present the
    /// ruler is already doing useful work and a card would be in the way.
    @ViewBuilder
    private var emptyDayCard: some View {
        if contents.isEmpty && armedTask == nil {
            VStack(spacing: 7) {
                EmojiIllustration(emoji: "\u{1F5D3}\u{FE0F}", symbolName: "calendar")
                    .padding(.bottom, 2)
                if let template = templateForToday {
                    Text("Nothing planned yet")
                        .font(.headline)
                    Text("Stamp “\(template.name)” to lay down your usual day, then drop anything else into the gaps.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("No template for \(weekdayName)s yet")
                        .font(.headline)
                    Text("A template is your usual day. Set one up and every \(weekdayName) takes one tap.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Set up a template") { sheet = .templates }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 2)
                }
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 28)
            .allowsHitTesting(templateForToday == nil)
        }
    }

    // MARK: Action area

    private var actionArea: some View {
        VStack(spacing: 8) {
            bannerView
            if let armedTask {
                armedBar(for: armedTask)
            } else {
                defaultBar
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private func armedBar(for task: TaskItem) -> some View {
        let fits = !candidateGaps.isEmpty
        return HStack(spacing: 10) {
            Image(systemName: fits ? "hand.tap.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(fits ? Color.accentColor : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(fits ? "Tap a slot for “\(task.title)”" : "Nowhere to put “\(task.title)”")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(fits
                     ? "\(candidateGaps.count) slot\(candidateGaps.count == 1 ? "" : "s") fit \(task.estimatedMinutes) min"
                     : "The longest free stretch is \(Int(longestFreeStretch / 60)) min.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            // A dead end otherwise: the app knows the day is full and would
            // offer nothing but retreat.
            if !fits {
                Button("Tomorrow") {
                    shiftDay(1)
                }
                .font(.subheadline.weight(.medium))
            }
            Button("Cancel") { disarm() }
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var defaultBar: some View {
        HStack(spacing: 10) {
            Button {
                stampTemplate()
            } label: {
                Label(templateForToday.map { "Stamp “\($0.name)”" } ?? "Set up a template",
                      systemImage: "square.stack.3d.up.fill")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                inboxDetent = .medium
                sheet = .inbox
            } label: {
                Label(openTasks.isEmpty ? "Inbox" : "\(openTasks.count)",
                      systemImage: openTasks.isEmpty ? "tray" : "tray.full.fill")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(openTasks.isEmpty ? "Inbox, empty" : "Inbox, \(openTasks.count) tasks")
        }
        .controlSize(.large)
    }

    /// Material-backed with a semantic tint rather than white-on-orange, which
    /// measured 2.08:1 — unreadable at a glance, and a glance is all a banner gets.
    @ViewBuilder
    private var bannerView: some View {
        if let banner {
            HStack(spacing: 7) {
                Group {
                    if Emoji.isSupported {
                        Text(banner.isWarning ? "\u{26A0}\u{FE0F}" : "\u{2705}")
                    } else {
                        Image(systemName: banner.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    }
                }
                .font(.caption)
                Text(banner.text)
                    .font(.footnote.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(banner.isWarning ? Color.orange : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onTapGesture { withAnimation { self.banner = nil } }
            .task(id: banner.id) {
                // Warnings linger: an error that disappears in 2.6 seconds may
                // as well not have been shown.
                try? await _Concurrency.Task.sleep(for: .seconds(banner.isWarning ? 7 : 2.6))
                withAnimation { self.banner = nil }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { addBlock() } label: { Image(systemName: "plus") }
                .accessibilityLabel("New block")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { sheet = .templates } label: { Label("Templates", systemImage: "square.stack.3d.up") }
                Button { sheet = .settings } label: { Label("Settings", systemImage: "gearshape") }
                if !contents.blocks.isEmpty {
                    Divider()
                    Button(role: .destructive) { isConfirmingClear = true } label: {
                        Label("Clear the day", systemImage: "trash")
                    }
                }
                #if DEBUG && targetEnvironment(simulator)
                Divider()
                Button { calendars.seedDemoMeetings(on: selectedDate); reload() } label: {
                    Label("Seed demo meetings", systemImage: "ladybug")
                }
                #endif
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
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

    private func disarm() {
        withAnimation {
            armedTask = nil
            inboxDetent = .medium
        }
    }

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

    private func addBlock() {
        let length = TimeInterval(30 * 60)
        let gaps = DaySchedule.gaps(busy: contents.busy, within: plannableWindow, minimumDuration: length)
        let fallback = DaySchedule.snap(isToday ? now : window.start, toMinutes: snapMinutes, calendar: calendar)
        let start = DaySchedule.firstFit(duration: length, in: gaps)?.start ?? fallback
        do {
            let block = try calendars.createBlock(title: "New block",
                                                  range: TimeRange(start: start, duration: length),
                                                  category: .deepWork,
                                                  alarmMinutesBefore: alarmEnabled ? alarmMinutesBefore : nil)
            reload()
            selectedBlock = block
        } catch {
            show(error.localizedDescription, warning: true)
        }
    }

    /// Everything the planner needs to know about the selected day.
    private var planInputs: DayPlanInputs {
        DayPlanInputs(date: selectedDate,
                      now: now,
                      isToday: isToday,
                      window: window,
                      plannableWindow: plannableWindow,
                      alarmMinutesBefore: alarmEnabled ? alarmMinutesBefore : nil,
                      calendar: calendar,
                      hiddenCalendarIDs: hiddenCalendarIDs)
    }

    private var planner: DayPlanner {
        DayPlanner(writer: calendars, context: context)
    }

    private func fillDay() {
        let result = planner.fillDay(inputs: planInputs, openTasks: openTasks)
        reload()
        showPlan(result.message)
    }

    private func place(_ task: TaskItem?, at start: Date) {
        guard let task else { return }
        do {
            let result = try planner.place(task, at: start, inputs: planInputs)
            disarm()
            reload()
            showPlan(result.message)
        } catch {
            show(error.localizedDescription, warning: true)
        }
    }

    private func returnToInbox(_ block: Block) {
        do {
            let result = try planner.returnToInbox(block, openTasks: openTasks)
            reload()
            showPlan(result.message)
        } catch {
            show(error.localizedDescription, warning: true)
        }
    }

    private func showPlan(_ message: PlanMessage) {
        show(message.text, warning: message.isWarning)
    }

    /// Asks the calendar to remind the user to re-sign before this build stops
    /// launching. A no-op on a build that does not expire, and on the simulator,
    /// where there is no provisioning profile to read.
    private func scheduleSigningReminder() {
        guard let expiry = ProvisioningProfile.expirationDate else { return }
        // Failing to write a reminder is not worth interrupting the user over;
        // they came here to plan their day.
        // `@discardableResult` does not survive `try?`, which wraps it in an Optional.
        _ = try? calendars.ensureSigningReminder(expiring: expiry, now: now)
    }

    private func clearDay() {
        do {
            let result = try planner.clear(inputs: planInputs, openTasks: openTasks)
            reload()
            showPlan(result.message)
        } catch {
            show(error.localizedDescription, warning: true)
        }
    }

    private func stampTemplate() {
        guard templateForToday != nil else {
            sheet = .templates
            return
        }
        // Stamping a planned day would quietly double it, and the second set
        // lands in whatever gaps are left — which reads as a bug rather than a
        // second stamp. Make the choice explicit.
        if !contents.blocks.isEmpty {
            isConfirmingRestamp = true
            return
        }
        applyTemplate()
    }

    private func replaceWithTemplate() {
        guard let template = templateForToday else { return }
        do {
            let result = try planner.replace(with: StampTemplate(template),
                                             inputs: planInputs,
                                             openTasks: openTasks)
            reload()
            showPlan(result.message)
        } catch {
            show(error.localizedDescription, warning: true)
        }
    }

    private func applyTemplate() {
        guard let template = templateForToday else { return }
        let result = planner.stamp(StampTemplate(template),
                                   inputs: planInputs,
                                   openTasks: openTasks)
        reload()
        showPlan(result.message)
    }
}
