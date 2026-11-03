import SwiftUI

/// Editing one block. Deliberately small: title, when, how long, what kind,
/// and the two ways out — delete it, or put it back in the inbox.
struct BlockDetailSheet: View {
    let block: Block
    /// The category is nil unless it differs from the original (see `categoryToSave`).
    var onSave: (String, TimeRange, BlockCategory?) -> Void
    var onDelete: () -> Void
    var onReturnToInbox: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var start: Date
    @State private var minutes: Int
    @State private var category: BlockCategory

    init(block: Block,
         onSave: @escaping (String, TimeRange, BlockCategory?) -> Void,
         onDelete: @escaping () -> Void,
         onReturnToInbox: @escaping () -> Void) {
        self.block = block
        self.onSave = onSave
        self.onDelete = onDelete
        self.onReturnToInbox = onReturnToInbox
        _title = State(initialValue: block.title)
        _start = State(initialValue: block.range.start)
        _minutes = State(initialValue: Int(block.range.duration / 60))
        _category = State(initialValue: block.category)
    }

    /// Nil when the picker ends where it began, so a Save that changes nothing about the
    /// category never rewrites the slug, and picking away and back doesn't either. Deliberately
    /// cannot honour an explicit pick of the fallback on a block whose slug is unknown: keeping
    /// the unknown slug is the safer error, and the picker will show unknown slugs properly later.
    static func categoryToSave(initial: BlockCategory, current: BlockCategory) -> BlockCategory? {
        current == initial ? nil : current
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
                    Stepper("\(minutes) minutes", value: $minutes, in: 5...480, step: 5)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(BlockCategory.allCases) { option in
                            Text(option.labelled).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }

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
                               Self.categoryToSave(initial: block.category, current: category))
                        dismiss()
                    }
                }
            }
        }
    }
}
