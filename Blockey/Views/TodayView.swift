import SwiftUI
import SwiftData

/// The whole app, really: one day, what is fixed, what you have blocked, and
/// the two actions that fill the rest: add a template ("Add my Workday"), place a task.
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
    @AppStorage(SettingsKey.skipPlanPreview) private var skipPlanPreview = false
    @AppStorage(SettingsKey.hasSeededTemplates) private var hasSeededTemplates = false
    @AppStorage(SettingsKey.hasSeenStarterTemplatesNote) private var hasSeenStarterNote = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverRunning
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedDate = Date()
    @State private var contents = DayContents()
    @State private var armedTask: TaskItem?
    @State private var selectedBlock: Block?
    @State private var sheet: Sheet?
    @State private var inboxDetent: PresentationDetent = .medium
    @State private var banner: PlanBanner?
    /// Held while the plan sheet dismisses, then shown, so the sheet's own animation does not
    /// swallow the first moments of a message the user needs to read.
    @State private var pendingBanner: PlanBanner?
    /// The preview the plan sheet opens with.
    @State private var planDraft: StampPreview?
    @State private var now = Date()
    /// Nil until first computed, so the first load is never announced (issue #7).
    @State private var streak: StreakSummary?
    @State private var isConfirmingClear = false

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    private var calendar: Calendar { .current }

    /// The tray height that leaves the timeline usable while a task is armed.
    private static let armedDetent = PresentationDetent.height(112)

    private enum Sheet: String, Identifiable {
        case inbox, templates, settings, plan
        var id: String { rawValue }
    }

    /// What the banner timer is waiting on. A new key restarts the wait, which is how pausing
    /// (and resuming with a full lifetime) works.
    private struct BannerTimerKey: Hashable {
        let id: UUID?
        let isPaused: Bool
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
    ///
    /// Only blocks the clear will actually delete count: a block Blockey cannot edit survives it.
    private var untaggedBlocks: Int {
        contents.blocks.filter { $0.isEditable && $0.token == nil }.count
    }

    /// What "Clear the day" deletes. Blocks Blockey cannot edit survive it, so they are not counted.
    private var editableBlockCount: Int {
        contents.blocks.filter(\.isEditable).count
    }

    private var clearWarning: String {
        let promise = "Anything you placed from the inbox goes back to the inbox."
        guard untaggedBlocks > 0 else { return promise }
        return promise + " " + PlanCopy.untaggedLoss(count: untaggedBlocks)
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

    /// "today", "tomorrow" or "Monday", for use after "for".
    private var dayPhrase: String {
        StampPreview.dayPhrase(for: selectedDate, now: now, calendar: calendar)
    }

    /// Whether a banner timer should hold still: under VoiceOver (the banner stays until it is
    /// dismissed), and while a sheet other than the inbox covers the banner (Q7). The inbox
    /// shows its own copy, so it does not pause.
    private var isBannerTimerPaused: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if DemoScenario.holdsBanner { return true }
        #endif
        return voiceOverRunning || selectedBlock != nil || (sheet != nil && sheet != .inbox)
    }

    /// The first-launch card: only for people who were handed the sample templates and have
    /// not answered it, while Workday still exists to be shown.
    private var showsStarterCard: Bool {
        hasSeededTemplates && !hasSeenStarterNote && armedTask == nil
            && templates.contains { $0.name == "Workday" }
    }

    /// Whether Fill day would place anything. First-fit goes task by task, so if no task fits
    /// on its own against the day as it stands, none fits at all.
    private var fillFitCount: Int {
        openTasks.filter { task in
            !DaySchedule.gaps(busy: contents.busy, within: plannableWindow,
                              minimumDuration: task.duration).isEmpty
        }.count
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
        .sheet(item: $sheet, onDismiss: showPendingBanner) { destination in
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
                    onFillDay: fillDay,
                    banner: banner,
                    onUndo: undoBanner,
                    onDismissBanner: dismissBanner,
                    isCompact: inboxDetent == Self.armedDetent,
                    placeAllTitle: PlanCopy.placeAllTitle(count: openTasks.count, fitting: fillFitCount,
                                                          dayPhrase: dayPhrase),
                    canFill: fillFitCount > 0,
                    fillReason: PlanCopy.placeAllReason(isToday: isToday, dayPhrase: dayPhrase)
                )
                .presentationDetents([Self.armedDetent, .medium, .large], selection: $inboxDetent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            case .templates:
                TemplatesView()
            case .settings:
                SettingsView()
            case .plan:
                if let draft = planDraft {
                    PlanSheet(initial: draft,
                              template: templateForToday.map { StampTemplate($0) },
                              inputs: planInputs,
                              openTasks: openTasks,
                              ownBlocks: contents.blocks,
                              onWritten: { result in
                                  reload()
                                  // The starter card's job ("add it with one tap") is done.
                                  hasSeenStarterNote = true
                                  pendingBanner = stampBanner(result)
                                  sheet = nil
                              },
                              onEditTemplate: { sheet = .templates },
                              onTryTomorrow: { shiftDay(1) })
                }
            }
        }
        .sheet(item: $selectedBlock) { block in
            BlockDetailSheet(
                block: block,
                onSave: { title, range, category in
                    perform { try calendars.update(block, title: title, range: range, categorySlug: category) }
                },
                onDelete: { perform { try calendars.delete(block) } },
                onReturnToInbox: { returnToInbox(block) }
            )
            .presentationDetents([.medium])
        }
        .confirmationDialog("Clear \(editableBlockCount) block\(editableBlockCount == 1 ? "" : "s")?",
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
                demoStamp()
            }
            if DemoScenario.wantsPlanSheet {
                // The template query has not landed yet on a cold launch without `-blockeyStamp`.
                try? await _Concurrency.Task.sleep(for: .milliseconds(600))
                demoOpenPlanSheet()
            }
            if DemoScenario.wantsSettings { sheet = .settings }
            if let title = DemoScenario.openBlockTitle {
                try? await _Concurrency.Task.sleep(for: .milliseconds(800))
                selectedBlock = contents.blocks.first { $0.title == title }
            }
            if DemoScenario.wantsInbox {
                inboxDetent = .medium
                sheet = .inbox
            }
            #endif
        }
        // Once per banner id. Announcing from the banner view would repeat it whenever the
        // inbox tray, which shows a copy, opens.
        .onChange(of: banner?.id) { _, _ in
            if let banner { AccessibilityNotification.Announcement(banner.text).post() }
        }
        .task(id: BannerTimerKey(id: banner?.id, isPaused: isBannerTimerPaused)) {
            guard let current = banner, !isBannerTimerPaused else { return }
            try? await _Concurrency.Task.sleep(for: .seconds(current.lifetime))
            guard !_Concurrency.Task.isCancelled else { return }
            withAnimation { if banner?.id == current.id { banner = nil } }
        }
        .onChange(of: selectedDate) { _, _ in reload() }
        .onChange(of: calendars.revision) { _, _ in reload() }
        .onReceive(clock) { tick in
            #if DEBUG && targetEnvironment(simulator)
            if DemoScenario.overrideNow != nil { return }
            #endif
            now = tick
            refreshStreak()
        }
    }

    // MARK: Header

    /// "Today" with the streak beside it, on today only. At accessibility sizes the streak drops
    /// to its own line, the way the summary line already wraps.
    @ViewBuilder
    private var titleLine: some View {
        let title = Text(isToday ? "Today" : selectedDate.formatted(.dateTime.weekday(.wide)))
            .font(.headline)
        if isToday, let badge = streak.flatMap(StreakCopy.badge(for:)) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 1) { title; streakLabel(badge) }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) { title; streakLabel(badge) }
            }
        } else {
            title
        }
    }

    /// Not a button. Colour is never the only signal: the symbol and the words differ by state.
    private func streakLabel(_ badge: StreakCopy.Badge) -> some View {
        let isActive: Bool = { if case .active = badge { return true } else { return false } }()
        return Label {
            Text(badge.text)
                .foregroundStyle(isActive ? .primary : .secondary)
        } icon: {
            Image(systemName: isActive ? "flame.fill" : "flame")
                .foregroundStyle(isActive ? Color.orange : Color.secondary)
        }
        .font(.caption.weight(.medium))
        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
        .fixedSize(horizontal: false, vertical: true)
        .contentTransition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.accessibility)
    }

    /// Recomputed wherever it can change: reload (every add path calls it), and the day tick.
    private func refreshStreak() {
        let old = streak
        let new = StreakStore(context: context, calendar: calendar).summary(now: now)
        guard new != old else { return }
        if reduceMotion {
            streak = new
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { streak = new }
        }
        if voiceOverRunning, StreakCopy.shouldAnnounce(from: old, to: new) {
            AccessibilityNotification.Announcement(StreakCopy.incrementAnnouncement(new.current)).post()
        }
    }

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
                    titleLine
                    Text(summaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
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
            return "Your meetings are in. Add your \(template.name) to fill the rest."
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
                    Text("Add your \(template.name) for a ready-made day, then drop anything else into the gaps.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("See what\u{2019}s in \(template.name)") { sheet = .templates }
                        .buttonStyle(.bordered)
                        .padding(.top, 2)
                } else {
                    Text("No template for \(weekdayName)s yet")
                        .font(.headline)
                    Text("A template is your usual day. Set one up and every \(weekdayName) takes one tap.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Set up a template") { sheet = .templates }
                        .buttonStyle(.bordered)
                        .padding(.top, 2)
                }
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 28)
        }
    }

    // MARK: Action area

    private var actionArea: some View {
        VStack(spacing: 8) {
            if showsStarterCard { starterCard }
            // The inbox tray shows its own copy, so VoiceOver never meets two Undo buttons.
            if sheet != .inbox { bannerView }
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
        // Stacked at accessibility sizes, where the two buttons cannot share a line.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Button {
                addTemplate()
            } label: {
                Label(templateForToday.map { "Add my \($0.name)" } ?? "Set up a template",
                      systemImage: "square.stack.3d.up.fill")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .minimumScaleFactor(0.8)
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

    @ViewBuilder
    private var bannerView: some View {
        if let banner {
            PlanBannerView(banner: banner,
                           onUndo: undoBanner,
                           onDismiss: dismissBanner,
                           onAction: { openInboxFromBanner() })
        }
    }

    private var starterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("We added a sample Workday for Mon\u{2013}Fri.")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Add it to a day with one tap. Change it any time.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Keep") { hasSeenStarterNote = true }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityHint("Hides this note")
                Button("Edit") {
                    hasSeenStarterNote = true
                    // The list, not the Workday editor (Q4): the editor needs a navigation
                    // push the sheet cannot be handed yet.
                    sheet = .templates
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityHint("Opens your templates")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
        seedStreakIfNeeded()
        contents = calendars.contents(for: selectedDate, ignoring: hiddenCalendarIDs, calendar: calendar)
        refreshStreak()
    }

    /// One-time, flag-guarded: counts the days Blockey events were already created on (issue #7).
    /// Cheap after the first success. Retried while calendar access is not granted yet.
    private func seedStreakIfNeeded() {
        StreakStore(context: context, calendar: calendar)
            .seedIfNeeded(now: .now) { calendars.blockCreationDates(since: $0, calendar: calendar) }
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
        withAnimation { banner = PlanBanner(text: text, isWarning: warning) }
    }

    private func dismissBanner() {
        withAnimation { banner = nil }
    }

    private func showPendingBanner() {
        planDraft = nil
        guard let pending = pendingBanner else { return }
        pendingBanner = nil
        withAnimation { banner = pending }
    }

    private func openInboxFromBanner() {
        // The banner stays, and with it any Undo record: the tray shows the same banner
        // (`withoutAction`), and its timer keeps running because the inbox does not pause it.
        // At the armed detent the tray hides the banner, so one arriving there can expire
        // unseen; accepted, since arming is a deliberate move away from the message.
        inboxDetent = .medium
        sheet = .inbox
    }

    /// Reverses what the banner offered to. On failure nothing has changed, so the same
    /// record goes back on the banner for another try.
    private func undoBanner() {
        guard let record = banner?.undo else { return }
        do {
            let outcome = try planner.undo(record)
            reload()
            let message = outcome.message
            withAnimation {
                banner = PlanBanner(text: message.text, isWarning: message.isWarning, afterUndo: true)
            }
        } catch {
            withAnimation {
                banner = PlanBanner(text: "Couldn\u{2019}t undo. Nothing was changed. Try again.",
                                    isWarning: true, undo: record)
            }
        }
    }

    private func stampBanner(_ result: StampResult) -> PlanBanner {
        let message = result.message(day: dayPhrase)
        return PlanBanner(text: message.text,
                          isWarning: message.isWarning,
                          undo: result.undo,
                          action: result.toInbox > 0 ? .openInbox : nil)
    }

    private func addBlock() {
        let length = TimeInterval(30 * 60)
        let gaps = DaySchedule.gaps(busy: contents.busy, within: plannableWindow, minimumDuration: length)
        let fallback = DaySchedule.snap(isToday ? now : window.start, toMinutes: snapMinutes, calendar: calendar)
        let start = DaySchedule.firstFit(duration: length, in: gaps)?.start ?? fallback
        do {
            // Through the planner so the day is counted toward the streak (issue #7).
            let block = try planner.addBlock(title: DefaultTitles.newBlock,
                                             range: TimeRange(start: start, duration: length),
                                             categorySlug: CategoryCatalog.fallbackSlug,
                                             inputs: planInputs)
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
        withAnimation {
            banner = PlanBanner(text: result.message.text, isWarning: result.message.isWarning,
                                undo: result.undo)
        }
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

    /// "Add my Workday". Opens the plan sheet, except when the user has opted out of the
    /// preview, the day has none of its own blocks, and something would actually be placed.
    /// Then it writes at once, still through the confirm-time guard, and a plan that moved
    /// since the preview opens the sheet instead.
    private func addTemplate() {
        guard let template = templateForToday else {
            sheet = .templates
            return
        }
        let stamp = StampTemplate(template)
        // One fetch for both, so skipping the sheet is decided from the day the plan was made on.
        let (preview, hasOwnBlocks) = planner.previewWithOwnBlocks(stamp, inputs: planInputs, mode: .keep)

        if skipPlanPreview, !hasOwnBlocks, preview.confirmCount > 0 {
            do {
                switch try planner.stamp(stamp, expecting: preview, mode: .keep,
                                         inputs: planInputs, openTasks: openTasks) {
                case .written(let result):
                    reload()
                    hasSeenStarterNote = true
                    withAnimation { banner = stampBanner(result) }
                    return
                case .stale(let fresh):
                    planDraft = fresh
                    sheet = .plan
                    return
                }
            } catch {
                show(error.localizedDescription, warning: true)
                return
            }
        }
        planDraft = preview
        sheet = .plan
    }

    #if DEBUG && targetEnvironment(simulator)
    /// `-blockeyPlanSheet`: opens the sheet as a tap on "Add my Workday" would, for screenshots.
    private func demoOpenPlanSheet() {
        guard let template = templateForToday else { return }
        let mode: StampPreview.Mode = DemoScenario.wantsStartOver ? .startOver : .keep
        planDraft = planner.preview(StampTemplate(template), inputs: planInputs, mode: mode)
        sheet = .plan
    }

    /// The demo's `-blockeyStamp` flag: writes straight away, skipping the sheet, so a
    /// screenshot run needs no taps.
    private func demoStamp() {
        guard let template = templateForToday else { return }
        let result = planner.stamp(StampTemplate(template), inputs: planInputs, openTasks: openTasks)
        reload()
        withAnimation { banner = stampBanner(result) }
    }
    #endif
}
