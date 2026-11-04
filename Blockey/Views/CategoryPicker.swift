import SwiftUI
import SwiftData

// The reusable category picker (UI spec issue #1, section 1) and the unknown-slug "Add as category"
// flow (section 4). Pickers return slugs and never a `BlockCategory`. Every decision about order,
// status and words lives in `Catalog/CategoryPicking.swift`; this file only draws it.

/// What the last tap on "Add as category" did. Held by whoever owns the footer, so the
/// confirmation survives the list popping and the stand-in becoming a real category.
enum AdoptionOutcome: Equatable {
    case added(name: String)
    case failed
}

/// The 36 pt rounded-square tile of a category: its fill, its border and its glyph. Colour is
/// decoration; the glyph and the name carry the identity (spec 1.3).
struct CategoryTile: View {
    let style: CategoryStyle
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(style.fill)
            RoundedRectangle(cornerRadius: 8).strokeBorder(style.border, lineWidth: 1)
            CategoryGlyph(style: style, size: .title3, tinted: false)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// One tap that saves a stand-in as a real category (spec 4.2). Inserts through `insertIfFree` and
/// saves; the definition keeps the stand-in's colour, so nothing on screen changes. Never touches
/// the block, the task or the calendar.
struct AdoptCategoryButton: View {
    let slug: String
    @Binding var outcome: AdoptionOutcome?

    @Environment(\.categoryCatalog) private var catalog
    @Environment(\.modelContext) private var context

    var body: some View {
        // TODO(3.8): when the plan is `.needsRename` (the recovered name collides with an
        // unarchived category) spec 4.2 opens the category editor in Adopt mode with the
        // duplicate message showing. The editor does not exist until 3.8, so until then the
        // button is not offered for a collision rather than creating two identical names.
        if case .add(let value) = catalog.planAdoption(of: slug) {
            Button { adopt(value) } label: {
                Label("Add as category", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityHint("Adds it with this name. Every block that uses it updates. Nothing in your calendar changes.")
        }
    }

    private func adopt(_ value: CategoryDefinitionValue) {
        do {
            guard try CategoryDefinition.insertIfFree(value, in: context) else {
                outcome = .failed
                return
            }
            try context.save()
            outcome = .added(name: value.name)
            AccessibilityNotification.Announcement("Added as category").post()
        } catch {
            // Autosave could otherwise write the half-done insert later. Remove just that row,
            // not a rollback, which would also drop unrelated unsaved edits in this context.
            let target = value.slug
            if let stray = try? context.fetch(FetchDescriptor<CategoryDefinition>(
                predicate: #Predicate { $0.slug == target })).first {
                context.delete(stray)
            }
            outcome = .failed
        }
    }
}

/// The pushed list (and the composer's sheet). Rows come from `CategoryChoiceLayout`.
struct CategoryChoiceList: View {
    let current: String?
    /// Called with the chosen slug, then the list pops or dismisses itself.
    var onSelect: (String) -> Void
    /// True in the composer's sheet, which needs its own way out.
    var showsCancel = false
    @Binding var outcome: AdoptionOutcome?
    /// TODO(3.8): the `New category…` row (spec 1.5). Left nil, the row is not shown, because the
    /// editor it opens does not exist yet. 3.8 passes a closure that presents the editor and
    /// selects the saved slug.
    var onNewCategory: (() -> Void)?

    @Environment(\.categoryCatalog) private var catalog
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let layout = CategoryChoiceLayout(catalog: catalog, current: current)
        List {
            if let off = layout.current {
                Section("Current") {
                    row(off, selected: true)
                    if off.origin == .standIn, let slug = off.slug {
                        AdoptCategoryButton(slug: slug, outcome: $outcome)
                    }
                }
            }
            Section {
                ForEach(layout.rows, id: \.slug) { row($0, selected: $0.slug == layout.selectedSlug) }
                if let onNewCategory {
                    Button(action: onNewCategory) {
                        Label("New category\u{2026}", systemImage: "plus")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("New category")
                    .accessibilityHint("Opens the category editor")
                }
            }
        }
        .navigationTitle("Category")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func row(_ category: ResolvedCategory, selected: Bool) -> some View {
        let style = CategoryStyle(category)
        return Button {
            if let slug = category.slug { onSelect(slug) }
            dismiss()
        } label: {
            HStack(spacing: 12) {
                CategoryTile(style: style)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = CategoryPickerCopy.subtitle(for: category) {
                        Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor).accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CategoryPickerCopy.listAccessibilityLabel(for: category))
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The Form `Section("Category")` used by the block sheet and the template row editor: one
/// navigation row, plus the status footer and the adopt button for an archived or unknown value.
///
/// The binding is optional because a block may carry no `c=` at all. Choosing the row that is
/// already checked changes nothing, so an untouched `nil` stays `nil` (spec 0.3).
struct CategoryPickerSection: View {
    @Binding var selection: String?

    @Environment(\.categoryCatalog) private var catalog
    @State private var outcome: AdoptionOutcome?
    #if DEBUG && targetEnvironment(simulator)
    /// Screenshots only: `-blockeyCategoryList` pushes the list without a tap.
    @State private var demoPush = false
    #endif

    var body: some View {
        let resolved = catalog.resolve(selection)
        let style = CategoryStyle(resolved)
        let status = CategoryStatus(resolved)
        Section {
            NavigationLink {
                CategoryChoiceList(current: selection, onSelect: choose, outcome: $outcome)
            } label: {
                LabeledContent("Category") {
                    HStack(spacing: 6) {
                        CategoryGlyph(style: style, size: .body).frame(minWidth: 24)
                        Text(resolved.name).multilineTextAlignment(.trailing)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CategoryPickerCopy.rowAccessibilityLabel(for: resolved))
            .accessibilityHint("Opens the list of categories")
            if status == .standIn, let slug = resolved.slug {
                AdoptCategoryButton(slug: slug, outcome: $outcome)
            }
        } header: {
            Text("Category")
        } footer: {
            footer(for: resolved)
        }
        #if DEBUG && targetEnvironment(simulator)
        .navigationDestination(isPresented: $demoPush) {
            CategoryChoiceList(current: selection, onSelect: choose, outcome: $outcome)
        }
        .task { if DemoScenario.wantsCategoryList { demoPush = true } }
        #endif
    }

    @ViewBuilder
    private func footer(for resolved: ResolvedCategory) -> some View {
        switch outcome {
        case .added(let name): Text(CategoryPickerCopy.adopted(name: name))
        case .failed: Text(CategoryPickerCopy.adoptFailure)
        case nil:
            if let text = CategoryPickerCopy.footer(for: resolved) { Text(text) }
        }
    }

    private func choose(_ slug: String) {
        if slug != catalog.resolve(selection).slug { selection = slug }
    }
}
