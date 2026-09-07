import SwiftUI
import SwiftData

/// Templates, and which day of the week each one belongs to.
///
/// The weekday assignment is what turns the morning pass into a single tap:
/// Today already knows which template is yours, so the button says "Stamp
/// Workday" rather than asking you to choose.
struct TemplatesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \DayTemplate.name) private var templates: [DayTemplate]
    @Query private var assignments: [TemplateAssignment]

    @State private var newTemplateName = ""
    @State private var isAddingTemplate = false

    private let weekdaySymbols = Calendar.current.weekdaySymbols

    var body: some View {
        NavigationStack {
            List {
                Section("Your week") {
                    ForEach(1...7, id: \.self) { weekday in
                        HStack {
                            Text(weekdaySymbols[weekday - 1])
                            Spacer()
                            Menu {
                                Button("None") { assign(nil, to: weekday) }
                                ForEach(templates) { template in
                                    Button(template.name) { assign(template.id, to: weekday) }
                                }
                            } label: {
                                Text(templateName(for: weekday) ?? "None")
                                    .font(.subheadline)
                                    .foregroundStyle(templateName(for: weekday) == nil ? .secondary : .primary)
                            }
                        }
                    }
                }

                Section("Templates") {
                    ForEach(templates) { template in
                        NavigationLink {
                            TemplateEditor(template: template)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                Text(subtitle(for: template))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteTemplates)

                    Button {
                        isAddingTemplate = true
                    } label: {
                        Label("New template", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("New template", isPresented: $isAddingTemplate) {
                TextField("Name", text: $newTemplateName)
                Button("Cancel", role: .cancel) { newTemplateName = "" }
                Button("Create") { createTemplate() }
            }
        }
    }

    private func subtitle(for template: DayTemplate) -> String {
        let count = template.rows.count
        let minutes = template.rows.reduce(0) { $0 + $1.durationMinutes }
        if count == 0 { return "Empty" }
        return "\(count) block\(count == 1 ? "" : "s") · \(String(format: "%.1fh", Double(minutes) / 60))"
    }

    private func templateName(for weekday: Int) -> String? {
        guard let id = assignments.first(where: { $0.weekday == weekday })?.templateID else { return nil }
        return templates.first { $0.id == id }?.name
    }

    private func assign(_ templateID: UUID?, to weekday: Int) {
        if let existing = assignments.first(where: { $0.weekday == weekday }) {
            existing.templateID = templateID
        } else {
            context.insert(TemplateAssignment(weekday: weekday, templateID: templateID))
        }
    }

    private func createTemplate() {
        let name = newTemplateName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        context.insert(DayTemplate(name: name))
        newTemplateName = ""
    }

    private func deleteTemplates(at offsets: IndexSet) {
        for index in offsets {
            let template = templates[index]
            // Clear any weekday still pointing at it, or Today would look for a
            // template that no longer exists.
            for assignment in assignments where assignment.templateID == template.id {
                assignment.templateID = nil
            }
            context.delete(template)
        }
    }
}

/// Editing the rows of one template.
struct TemplateEditor: View {
    @Bindable var template: DayTemplate
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            Section {
                TextField("Name", text: $template.name)
            }

            Section("Blocks") {
                ForEach(template.orderedRows) { row in
                    NavigationLink {
                        TemplateRowEditor(row: row)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: row.category.symbolName)
                                .font(.caption)
                                .foregroundStyle(row.category.tint)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                Text("\(timeLabel(row.startMinuteOfDay)) · \(row.durationMinutes) min")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete(perform: deleteRows)

                Button {
                    addRow()
                } label: {
                    Label("Add block", systemImage: "plus")
                }
            }

            Section {
                EmptyView()
            } footer: {
                Text("When you stamp this template, anything that collides with a real meeting moves to the next free slot. If nothing fits, it goes to your inbox instead of being dropped.")
            }
        }
        .navigationTitle(template.name.isEmpty ? "Template" : template.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func timeLabel(_ minuteOfDay: Int) -> String {
        String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }

    private func addRow() {
        // Start the new row after the last one, so building a day is sequential.
        let start = template.orderedRows.last.map { $0.startMinuteOfDay + $0.durationMinutes } ?? 9 * 60
        let row = TemplateRow(title: "New block",
                              startMinuteOfDay: min(start, 23 * 60),
                              durationMinutes: 60)
        row.template = template
        context.insert(row)
    }

    private func deleteRows(at offsets: IndexSet) {
        let ordered = template.orderedRows
        for index in offsets { context.delete(ordered[index]) }
    }
}

/// One row of a template.
struct TemplateRowEditor: View {
    @Bindable var row: TemplateRow

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $row.title)
                DatePicker("Starts", selection: startBinding, displayedComponents: .hourAndMinute)
                Stepper("\(row.durationMinutes) minutes", value: $row.durationMinutes, in: 5...480, step: 5)
            }
            Section("Category") {
                Picker("Category", selection: categoryBinding) {
                    ForEach(BlockCategory.allCases) { option in
                        Label(option.title, systemImage: option.symbolName).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .navigationTitle("Block")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Template times are wall-clock minutes, not dates — they get applied to
    /// whatever day you stamp. The picker needs a Date, so this maps between
    /// them against an arbitrary reference day.
    private var startBinding: Binding<Date> {
        Binding {
            Calendar.current.startOfDay(for: .now)
                .addingTimeInterval(TimeInterval(row.startMinuteOfDay * 60))
        } set: { newValue in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            row.startMinuteOfDay = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
        }
    }

    private var categoryBinding: Binding<BlockCategory> {
        Binding { row.category } set: { row.category = $0 }
    }
}
