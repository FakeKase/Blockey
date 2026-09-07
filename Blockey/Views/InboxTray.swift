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
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fill day") {
                        onFillDay()
                        dismiss()
                    }
                    .disabled(tasks.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
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
                        Image(systemName: task.category.symbolName)
                            .font(.caption)
                            .foregroundStyle(task.category.tint)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                            HStack(spacing: 5) {
                                Text(durationLabel(task.estimatedMinutes))
                                if task.droppedFromTemplate {
                                    Text("· didn’t fit")
                                        .foregroundStyle(.orange)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "hand.tap")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
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
            Image(systemName: "tray")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
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
