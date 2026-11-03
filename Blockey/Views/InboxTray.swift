import SwiftUI
import SwiftData

/// Unscheduled work, and the fastest possible way to get it onto the day.
///
/// Tapping a task arms it rather than opening it. That is the primary gesture:
/// tap the task, tap a slot, done — two taps, one-handed, no dragging.
struct InboxTray: View {
    let tasks: [TaskItem]
    var onArm: (TaskItem) -> Void
    var onFillDay: () -> Void
    /// The same banner Today shows, because this sheet covers Today. Without a copy here the
    /// Undo for Fill day would be hidden behind the very sheet that caused it.
    var banner: PlanBanner?
    var onUndo: () -> Void
    var onDismissBanner: () -> Void
    /// At the short "armed" height there is no room for the button or the banner.
    var isCompact: Bool
    var placeAllTitle: String
    var canFill: Bool
    var fillReason: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Environment(CalendarService.self) private var calendars

    @State private var draft = ComposerDraft()
    @State private var suggestionRow = ComposerSuggestionRow()
    @FocusState private var titleFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var draftTitle: Binding<String> {
        Binding(get: { draft.title }, set: { draft.title = $0 })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                composer
                Divider()
                if tasks.isEmpty {
                    emptyState
                } else {
                    taskList
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isCompact { bottomArea }
            }
            // Once per open: the tray is rebuilt each time the sheet presents, so this runs once
            // and never on `.EKEventStoreChanged` or `calendars.revision` (known gap 5).
            .task { loadSuggestionSources() }
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var bottomArea: some View {
        if banner != nil || !tasks.isEmpty {
            VStack(spacing: 8) {
                if let banner {
                    PlanBannerView(banner: banner.withoutAction, onUndo: onUndo,
                                   onDismiss: onDismissBanner, onAction: onDismissBanner)
                }
                if !tasks.isEmpty {
                    Button(action: onFillDay) {
                        Text(placeAllTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canFill)
                    if !canFill {
                        Text(fillReason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("What needs a slot?", text: draftTitle)
                    .textFieldStyle(.plain)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .onSubmit(addTask)
                    // The cap only bites on paste or a very long entry, and trims by Character so it
                    // never cuts a Thai cluster. A field already past 200 is rewritten once; below
                    // that, typing never touches the text, so IME composition is left alone.
                    .onChange(of: draft.title) { _, new in
                        if new.count > ComposerTitle.maxLength {
                            draft.title = String(new.prefix(ComposerTitle.maxLength))
                        }
                    }
                    // Debounce-only: `.task(id:)` cancels the sleep on every keystroke, so chips
                    // update about 250 ms after typing stops. SwiftUI's TextField does not expose
                    // marked text, so chips can update mid-composition if a pause is long enough.
                    .task(id: draft.title) {
                        try? await _Concurrency.Task.sleep(for: ComposerSuggestionRow.debounce)
                        guard !_Concurrency.Task.isCancelled else { return }
                        suggestionRow.refresh(query: draft.title, now: .now)
                    }

                Button(action: addTask) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .disabled(ComposerTitle.forSubmit(draft.title).isEmpty)
                .accessibilityLabel("Add to inbox")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

            suggestionChips

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(draft.durations, id: \.self) { minutes in
                        chip(label: durationLabel(minutes),
                             selected: draft.minutes == minutes) { draft.select(minutes: minutes) }
                    }
                    Divider().frame(height: 18).padding(.horizontal, 2)
                    ForEach(BlockCategory.allCases) { category in
                        chip(label: category.title,
                             tint: category.tint,
                             selected: draft.category == category) { draft.category = category }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Nothing at all (no placeholder, no reserved height) when there is nothing to suggest, and
    /// hidden at the short armed detent, where 54 pt more would push the task list off screen.
    @ViewBuilder
    private var suggestionChips: some View {
        let chips = isCompact ? [] : suggestionRow.visibleChips(for: draft.title)
        Group {
            if !chips.isEmpty {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(chips, id: \.self) { suggestionChip($0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                } else {
                    // Same idiom as the duration row below: chips keep their natural width and
                    // scroll sideways rather than squeezing three titles into one line.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) { ForEach(chips, id: \.self) { suggestionChip($0) } }
                            .padding(1)
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: chips)
    }

    private func suggestionChip(_ suggestion: TitleSuggestion) -> some View {
        Button { apply(suggestion) } label: {
            HStack(spacing: 4) {
                if let category = suggestion.categorySlug.flatMap(BlockCategory.init(rawValue:)) {
                    CategoryGlyph(category: category, size: .caption)
                }
                Text(SuggestionChipText.visible(suggestion))
                    .font(.caption.weight(.medium))
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .truncationMode(.middle)
                    .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 200, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(Capsule().strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SuggestionChipText.accessibilityLabel(suggestion))
        .accessibilityHint("Suggestion. Fills the title, duration and category")
    }

    private func apply(_ suggestion: TitleSuggestion) {
        draft.apply(suggestion)
        suggestionRow.suppress(forText: draft.title)
        titleFocused = true
    }

    private func loadSuggestionSources() {
        #if DEBUG && targetEnvironment(simulator)
        if let text = DemoScenario.composerText { draft.title = text }
        #endif
        let rows = (try? context.fetch(FetchDescriptor<TemplateRow>())) ?? []
        let templates = rows.map {
            TitleSample(title: $0.title, minutes: $0.durationMinutes, categorySlug: $0.categoryRaw, date: nil)
        }
        let history = calendars.blockHistory(endingAt: .now)
        suggestionRow = ComposerSuggestionRow(history: history, templates: templates)
        suggestionRow.refresh(query: draft.title, now: .now)
    }

    private func chip(label: String, tint: Color = .accentColor, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? tint.opacity(0.2) : Color.primary.opacity(0.05),
                            in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? tint.opacity(0.6) : .clear, lineWidth: 1))
                .foregroundStyle(selected ? tint : Color.primary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var taskList: some View {
        List {
            ForEach(tasks) { task in
                Button { onArm(task) } label: {
                    HStack(spacing: 10) {
                        CategoryGlyph(category: task.category)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                            HStack(spacing: 5) {
                                Text(durationLabel(task.estimatedMinutes))
                                if task.droppedFromTemplate {
                                    Text("\u{00B7}").accessibilityHidden(true)
                                    Image(systemName: "exclamationmark.circle")
                                        .foregroundStyle(.orange)
                                        .accessibilityHidden(true)
                                    Text(PlanCopy.inboxNote(templateName: task.droppedFromTemplateName))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "hand.tap")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityHint("Then tap a slot on the day")
                .swipeActions {
                    Button(role: .destructive) { context.delete(task) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            EmojiIllustration(emoji: "\u{1F4E5}", symbolName: "tray")
            Text("Inbox is empty")
                .font(.headline)
            Text("Add what needs doing, then tap it to drop it on the day.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func durationLabel(_ minutes: Int) -> String { SuggestionChipText.duration(minutes) }

    private func addTask() {
        let title = ComposerTitle.forSubmit(draft.title)
        guard !title.isEmpty else { return }
        let task = TaskItem(title: title,
                            estimatedMinutes: draft.minutes,
                            category: draft.category,
                            sortIndex: (tasks.map(\.sortIndex).max() ?? 0) + 1)
        context.insert(task)
        draft.resetTitle()
        suggestionRow.clear()
        titleFocused = true
    }
}
