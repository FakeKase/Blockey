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

    @State private var draftTitle = ""
    @State private var draftMinutes = 30
    @State private var draftCategory: BlockCategory = .deepWork
    @FocusState private var titleFocused: Bool

    private let durations = [15, 30, 45, 60, 90, 120]

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
                TextField("What needs a slot?", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .onSubmit(addTask)

                Button(action: addTask) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(draftTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(durations, id: \.self) { minutes in
                        chip(label: durationLabel(minutes),
                             selected: draftMinutes == minutes) { draftMinutes = minutes }
                    }
                    Divider().frame(height: 18).padding(.horizontal, 2)
                    ForEach(BlockCategory.allCases) { category in
                        chip(label: category.title,
                             tint: category.tint,
                             selected: draftCategory == category) { draftCategory = category }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let hours = Double(minutes) / 60
        return hours == hours.rounded() ? "\(Int(hours))h" : String(format: "%.1fh", hours)
    }

    private func addTask() {
        let title = draftTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let task = TaskItem(title: title,
                            estimatedMinutes: draftMinutes,
                            category: draftCategory,
                            sortIndex: (tasks.map(\.sortIndex).max() ?? 0) + 1)
        context.insert(task)
        draftTitle = ""
        titleFocused = true
    }
}
