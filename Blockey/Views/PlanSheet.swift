import SwiftUI
import SwiftData

/// "Plan <day>": what adding a template would do, shown before anything is written.
///
/// All the deciding happens in `DayPlanner.preview` and `DayPlanner.stamp(expecting:...)`; this
/// view lays out the values and holds the Keep / Start over choice. Confirming recomputes
/// against a fresh fetch, so a plan that went stale while the sheet was open is shown again
/// rather than written.
struct PlanSheet: View {
    /// The template for this day, or `nil` when none is assigned (it previews as empty).
    let template: StampTemplate?
    let inputs: DayPlanInputs
    let openTasks: [TaskItem]
    /// The day's own blocks, which is what Keep / Start over is about.
    let ownBlocks: [Block]
    var onWritten: (StampResult) -> Void
    var onEditTemplate: () -> Void
    var onTryTomorrow: () -> Void

    @Environment(CalendarService.self) private var calendars
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var mode: StampPreview.Mode = .keep
    @State private var shown: StampPreview
    @State private var isStale = false
    @State private var errorText: String?
    @State private var detent: PresentationDetent = .medium
    @AccessibilityFocusState private var staleFocused: Bool

    init(initial: StampPreview, template: StampTemplate?, inputs: DayPlanInputs,
         openTasks: [TaskItem], ownBlocks: [Block],
         onWritten: @escaping (StampResult) -> Void,
         onEditTemplate: @escaping () -> Void,
         onTryTomorrow: @escaping () -> Void) {
        self.template = template
        self.inputs = inputs
        self.openTasks = openTasks
        self.ownBlocks = ownBlocks
        self.onWritten = onWritten
        self.onEditTemplate = onEditTemplate
        self.onTryTomorrow = onTryTomorrow
        _shown = State(initialValue: initial)
        _mode = State(initialValue: initial.mode)
    }

    private var planner: DayPlanner { DayPlanner(writer: calendars, context: context) }

    // MARK: Derived

    private var dayPhrase: String {
        StampPreview.dayPhrase(for: inputs.date, now: inputs.now, calendar: inputs.calendar)
    }

    private var editable: [Block] { ownBlocks.filter(\.isEditable) }
    private var hasOwnBlocks: Bool { !editable.isEmpty }
    private var keptCount: Int { ownBlocks.filter { !$0.isEditable }.count }
    private var untaggedCount: Int { editable.filter { $0.token == nil }.count }
    /// Keep / Start over only means something when there is something to start over.
    private var activeMode: StampPreview.Mode { hasOwnBlocks ? mode : .keep }

    private var placedRows: [StampPreview.Row] {
        shown.rows.filter { $0.kind != .inbox }.sorted {
            ($0.kind.range?.start ?? .distantFuture) < ($1.kind.range?.start ?? .distantFuture)
        }
    }
    private var inboxRows: [StampPreview.Row] { shown.rows.filter { $0.kind == .inbox } }

    private func format(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if shown.hasNoRows {
                    emptyTemplate
                } else {
                    planList
                }
            }
            .navigationTitle("Plan \(dayPhrase)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !shown.hasNoRows { confirmBar }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .onAppear {
            if shown.rows.count > 6 || typeSize.isAccessibilitySize { detent = .large }
        }
        // Live refresh (Q5). The confirm-time guard is the real protection; this just keeps
        // the sheet honest while it is open.
        .onChange(of: calendars.revision) { _, _ in refresh(announce: true) }
        .onChange(of: inputs.now) { _, _ in refresh(announce: true) }
        .onChange(of: inputs.date) { _, _ in
            // A different day is a different plan, not a change to this one: start from Keep
            // with no stale note or error carried over, and say so.
            mode = .keep
            isStale = false
            errorText = nil
            refresh(announce: false)
            AccessibilityNotification.Announcement("Now planning \(dayPhrase)").post()
        }
        .onChange(of: mode) { _, _ in
            isStale = false
            errorText = nil
            refresh(announce: false)
        }
    }

    // MARK: Pieces

    private var planList: some View {
        List {
            Section {
                if isStale { staleNote }
                if let errorText { warningRow(errorText) }
                if hasOwnBlocks { keepOrStartOver }
            } header: {
                Text(subtitle)
                    .textCase(nil)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }

            if !placedRows.isEmpty {
                Section {
                    ForEach(placedRows) { row in planRow(row) }
                } header: {
                    Text("On your day").accessibilityAddTraits(.isHeader)
                }
            }
            if !inboxRows.isEmpty {
                Section {
                    ForEach(inboxRows) { row in planRow(row) }
                } header: {
                    Text("Goes to your inbox").accessibilityAddTraits(.isHeader)
                }
            }
            if shown.droppedCount > 0 {
                Section { Text(PlanCopy.zeroLength(count: shown.droppedCount)).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var subtitle: String {
        "Your \(template?.name ?? "") template. Meetings stay where they are."
    }

    private func planRow(_ row: StampPreview.Row) -> some View {
        let symbol: String
        switch row.kind {
        case .placed: symbol = "clock"
        case .moved: symbol = "clock.arrow.circlepath"
        case .inbox: symbol = "tray"
        }
        let time = row.timeText(format)
        // `noteText` is the model's wording and is not reworded here.
        let note = row.noteText(format)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.body)
                if let time { Text(time).font(.subheadline).foregroundStyle(.secondary) }
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowLabel(row, time: time, note: note))
    }

    private func rowLabel(_ row: StampPreview.Row, time: String?, note: String?) -> String {
        // "&" is read as "and" by VoiceOver anyway, but say it so the label is plain text too.
        let title = row.title.replacingOccurrences(of: "&", with: "and")
        return [title, time, note].compactMap { $0 }.joined(separator: ", ")
    }

    private var keepOrStartOver: some View {
        VStack(alignment: .leading, spacing: 8) {
            modePicker

            if mode == .startOver {
                ForEach(PlanCopy.startOverWarnings(deleting: editable.count,
                                                   untagged: untaggedCount,
                                                   kept: keptCount,
                                                   dayPhrase: dayPhrase), id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text(line).font(.footnote).foregroundStyle(.primary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    @ViewBuilder
    private var modePicker: some View {
        let picker = Picker("What to do with the blocks already on \(dayPhrase)", selection: $mode) {
            Text("Keep my \(ownBlocks.count) block\(ownBlocks.count == 1 ? "" : "s")")
                .tag(StampPreview.Mode.keep)
            Text("Start over").tag(StampPreview.Mode.startOver)
        }
        .accessibilityLabel("What to do with the blocks already on \(dayPhrase)")
        // Inline at accessibility sizes, where two segments no longer fit on a line.
        if typeSize.isAccessibilitySize {
            picker.pickerStyle(.inline)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    private var staleNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath").accessibilityHidden(true)
            Text("Your day changed, here\u{2019}s the new plan.").font(.footnote.weight(.medium))
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityFocused($staleFocused)
        .listRowBackground(Rectangle().fill(.regularMaterial))
    }

    private func warningRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(text).font(.footnote.weight(.medium))
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var emptyTemplate: some View {
        VStack(spacing: 10) {
            if let name = template?.name {
                Text("This template is empty").font(.headline)
                Text("Add a few rows to \(name), then come back.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Edit \(name)", action: onEditTemplate)
                    .buttonStyle(.bordered)
            } else {
                Text("No template for \(dayPhrase)").font(.headline)
                Text("Choose one in Templates, then come back.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Open Templates", action: onEditTemplate)
                    .buttonStyle(.bordered)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var confirmBar: some View {
        VStack(spacing: 8) {
            if shown.nothingFits {
                Text(PlanCopy.nothingFits(isToday: inputs.isToday))
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if inputs.isToday {
                    Button(action: onTryTomorrow) {
                        Text("Try tomorrow")
                            .font(.subheadline.weight(.medium))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }
            } else {
                Text(PlanCopy.countLine(for: shown))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button(action: confirm) {
                Text(PlanCopy.confirmTitle(for: shown, deleting: editable.count, dayPhrase: dayPhrase))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .tint(shown.mode == .startOver ? .red : .accentColor)
            .disabled(shown.isConfirmDisabled)
            .accessibilityHint(shown.isConfirmDisabled ? "Nothing fits. Try another day." : "")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    // MARK: Actions

    /// Recomputes without writing. When the plan moved under the user, says so.
    private func refresh(announce: Bool) {
        let fresh = planner.preview(template, inputs: inputs, mode: activeMode)
        guard fresh != shown else { return }
        let changed = announce
        withAnimation { shown = fresh }
        if changed { flagStale() }
    }

    private func flagStale() {
        withAnimation { isStale = true }
        errorText = nil
        AccessibilityNotification.Announcement("Your day changed, here\u{2019}s the new plan.").post()
        staleFocused = true
    }

    private func confirm() {
        guard let template else { return }
        errorText = nil
        do {
            let outcome = try planner.stamp(template, expecting: shown, mode: activeMode,
                                            inputs: inputs, openTasks: openTasks)
            switch outcome {
            case .written(let result):
                onWritten(result)
            case .stale(let fresh):
                // Nothing was written. Show the new plan and wait for a second confirm.
                withAnimation { shown = fresh }
                flagStale()
            }
        } catch {
            // The only throw `stamp(expecting:)` has is Start over failing to clear the day,
            // and `DayPlanner.clear` throws having changed nothing, so this wording is exact.
            // Keep mode cannot reach here.
            let text = "Couldn\u{2019}t clear \(dayPhrase). Nothing was changed. Try again."
            errorText = text
            AccessibilityNotification.Announcement(text).post()
        }
    }
}
