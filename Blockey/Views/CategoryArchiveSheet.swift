import SwiftUI

/// What archiving is about to affect, handed to the move-to sheet.
struct ArchivePrompt: Identifiable, Equatable {
    var id: String { slug }
    let slug: String
    let name: String
    let tasks: Int
    let rows: Int
}

/// The move-to sheet (UI spec 2.5). Nothing is preselected: the owner's rule (ADR 005) is that
/// nothing moves unless they choose it, and the cost is one extra tap, on purpose.
struct CategoryArchiveSheet: View {
    let prompt: ArchivePrompt
    /// Every other unarchived category.
    let targets: [ResolvedCategory]
    /// Archives, moving to the slug when non-nil. Throws when the save fails; the sheet then stays
    /// open with an inline warning and nothing changed.
    let onArchive: (String?) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var choice: String?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        // The full question wraps here; the navigation title stays short so a
                        // 24-character or Thai name is never truncated.
                        Text(CategoryUsage.archiveTitle(name: prompt.name))
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 4)
                            .accessibilityAddTraits(.isHeader)
                        if let usage = CategoryUsage.sentence(tasks: prompt.tasks, rows: prompt.rows) { Text(usage) }
                        Text(CategoryUsage.calendarNote).foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                Section {
                    ForEach(targets, id: \.slug) { target in
                        Button { choice = target.slug } label: { row(target) }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(target.name)
                            .accessibilityValue(choice == target.slug ? "Selected" : "")
                            .accessibilityAddTraits(choice == target.slug ? [.isButton, .isSelected] : .isButton)
                    }
                } header: {
                    Text(CategoryUsage.moveHeader)
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(CategoryUsage.moveHelper)
                        Text(CategoryUsage.withoutMovingNote(name: prompt.name))
                    }
                }
            }
            // Only the two buttons are pinned, so they are visible at the medium detent; the
            // explanatory notes scroll with the list.
            .safeAreaInset(edge: .bottom, spacing: 0) { actions }
            .navigationTitle("Archive category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        // Large only: at medium the pinned buttons and the usage text leave no room to choose a
        // category, which is the point of the sheet.
        .presentationDetents([.large])
    }

    private func row(_ category: ResolvedCategory) -> some View {
        HStack(spacing: 12) {
            CategoryTile(style: CategoryStyle(category))
            Text(category.name).font(.body).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if choice == category.slug {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor).accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if failed {
                Label { Text(CategoryUsage.archiveFailure(name: prompt.name)).font(.footnote) } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(ColorConcernCopy.spoken(CategoryUsage.archiveFailure(name: prompt.name)))
            }
            Button { run(choice) } label: {
                Text(CategoryUsage.moveButtonTitle(count: prompt.tasks + prompt.rows))
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .disabled(choice == nil)
            Button { run(nil) } label: {
                Text(CategoryUsage.archiveWithoutMoving).frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func run(_ target: String?) {
        do {
            try onArchive(target)
            failed = false
            dismiss()
        } catch {
            failed = true
        }
    }
}
