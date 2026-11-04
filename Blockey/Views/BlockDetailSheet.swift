import SwiftUI

/// Editing one block. Deliberately small: title, when, how long, what kind,
/// and the two ways out — delete it, or put it back in the inbox.
struct BlockDetailSheet: View {
    let block: Block
    /// The category is nil unless it differs from the original (see `categoryToSave`).
    var onSave: (String, TimeRange, String?) -> Void
    var onDelete: () -> Void
    var onReturnToInbox: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var start: Date
    @State private var minutes: Int
    /// The raw slug as the block carries it, nil when it has none. Kept raw (not resolved) so an
    /// untouched picker still saves nothing.
    @State private var category: String?

    init(block: Block,
         onSave: @escaping (String, TimeRange, String?) -> Void,
         onDelete: @escaping () -> Void,
         onReturnToInbox: @escaping () -> Void) {
        self.block = block
        self.onSave = onSave
        self.onDelete = onDelete
        self.onReturnToInbox = onReturnToInbox
        _title = State(initialValue: block.title)
        _start = State(initialValue: block.range.start)
        _minutes = State(initialValue: Int(block.range.duration / 60))
        _category = State(initialValue: block.categorySlug)
    }

    /// Nil when the picker ends where it began, so a Save that changes nothing about the
    /// category never rewrites the slug, and picking away and back doesn't either. The rule is
    /// pure and lives in `CategorySelection`.
    static func slugToSave(initial: String?, current: String?) -> String? {
        CategorySelection.slugToSave(initial: initial, current: current)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                    Stepper("\(minutes) minutes", value: $minutes, in: 5...480, step: 5)
                }

                CategoryPickerSection(selection: $category)

                Section {
                    Button {
                        onReturnToInbox()
                        dismiss()
                    } label: {
                        Label("Return to inbox", systemImage: "tray.and.arrow.down")
                    }
                    Button(role: .destructive) {
                        onDelete()
                        dismiss()
                    } label: {
                        Label("Delete block", systemImage: "trash")
                    }
                } footer: {
                    Text("This block lives in your Blockey calendar, so changes show up in Calendar too.")
                }
            }
            .navigationTitle("Block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = title.trimmingCharacters(in: .whitespaces)
                        onSave(trimmed.isEmpty ? block.title : trimmed,
                               TimeRange(start: start, duration: TimeInterval(minutes * 60)),
                               Self.slugToSave(initial: block.categorySlug, current: category))
                        dismiss()
                    }
                }
            }
        }
    }
}
