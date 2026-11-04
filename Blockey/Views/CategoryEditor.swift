import SwiftUI
import SwiftData

// The category editor (UI spec issue #1, section 3): Add, Edit, Archived and Adopt modes in one
// sheet. Every decision (what is valid, what is dirty, what the warning says, what gets written)
// lives in `Catalog/CategoryDraft.swift` and `Planning/CategoryStore.swift`; this file draws it.

/// What the editor hands back to whoever opened it.
struct SavedCategory: Equatable {
    let slug: String
    let name: String
}

/// One presentation of the editor. A new `id` each time, so `.sheet(item:)` re-presents.
struct CategoryEditorRequest: Identifiable {
    let id = UUID()
    let mode: CategoryEditorMode
}

/// The editor in a sheet with its own navigation stack. The catalog is captured when the sheet
/// opens: once Save lands, the live catalog contains the new category, and judging the draft
/// against it would flash "already called" for the very name just saved.
struct CategoryEditorSheet: View {
    var onSaved: (SavedCategory) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var catalog: CategoryCatalog
    @State private var draft: CategoryDraft?
    @State private var nameTouched: Bool
    @State private var saveFailed = false
    @State private var confirmDiscard = false
    @State private var archivePrompt: ArchivePrompt?
    @State private var archiveAlert = false
    @FocusState private var nameFocused: Bool

    init(mode: CategoryEditorMode, catalog: CategoryCatalog, onSaved: @escaping (SavedCategory) -> Void = { _ in }) {
        self.onSaved = onSaved
        let start = CategoryDraft(mode: mode, catalog: catalog)
        _catalog = State(initialValue: catalog)
        _draft = State(initialValue: start)
        // A collision is shown at once for the modes that start with a name already filled in
        // (Adopt, Archived), so the fix is one edit. Add stays quiet until the field is touched.
        let startsFilled = mode != .add && start?.nameProblem(in: catalog) != nil
        _nameTouched = State(initialValue: startsFilled)
    }

    var body: some View {
        NavigationStack {
            if let draftBinding = Binding($draft) {
                form(draftBinding)
            } else {
                // Cannot happen from the UI (a stand-in has an Adopt path, not an Edit one).
                ContentUnavailableView("This category can\u{2019}t be edited", systemImage: "questionmark.circle")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(draft?.isDirty ?? false)
    }

    // MARK: Form

    private func form(_ draft: Binding<CategoryDraft>) -> some View {
        let d = draft.wrappedValue
        let problem = d.nameProblem(in: catalog)
        return ScrollViewReader { proxy in
        Form {
            banner(for: d.mode)
            if saveFailed {
                Section { Label { Text(CategoryEditorCopy.saveFailure) } icon: {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                } }
            }
            nameSection(draft, problem: problem)
            CategoryEmojiSection(draft: draft, showsRequired: !d.hasEmoji && CategorySlug.hasContent(d.value.name))
            CategoryColorSection(draft: draft, catalog: catalog).id("colour")
            if d.mode.isEditing { actionSections(draft, canArchive: d.mode.slug.map(catalog.canArchive) ?? false) }
        }
        .navigationTitle(d.mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { if d.isDirty { confirmDiscard = true } else { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { commit(d, restoring: false) }.disabled(!d.canSave(in: catalog))
            }
        }
        .confirmationDialog(CategoryEditorCopy.discardTitle, isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .sheet(item: $archivePrompt) { prompt in
            CategoryArchiveSheet(prompt: prompt, targets: catalog.activeInOrder().filter { $0.slug != prompt.slug }) { target in
                try archive(d, moveTo: target)
            }
        }
        .alert(CategoryUsage.archiveAlertTitle, isPresented: $archiveAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text(CategoryUsage.archiveAlertMessage) }
        .task {
            // Add mode only: the other modes open on something already filled in.
            if d.mode == .add {
                #if DEBUG && targetEnvironment(simulator)
                if DemoScenario.editorPreset != nil {
                    applyDemoPreset()
                    if DemoScenario.editorColor != nil { proxy.scrollTo("colour", anchor: .top) }
                    return
                }
                #endif
                nameFocused = true
            }
        }
        }
    }

    @ViewBuilder
    private func banner(for mode: CategoryEditorMode) -> some View {
        switch mode {
        case .archived:
            Section { Label(CategoryEditorCopy.archivedBanner, systemImage: "archivebox") }
        case .adopt:
            Section { Label(CategoryEditorCopy.adoptBanner, systemImage: "tag") }
        case .add, .edit:
            EmptyView()
        }
    }

    // MARK: Name

    private func nameSection(_ draft: Binding<CategoryDraft>, problem: NameProblem?) -> some View {
        let name = Binding<String>(
            get: { draft.wrappedValue.value.name },
            set: { nameTouched = true; draft.wrappedValue.setName($0) })
        return Section {
            TextField("Category name", text: name)
                .focused($nameFocused)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit { nameFocused = false }
                .frame(minHeight: 44)
                .accessibilityLabel("Name")
            if nameTouched, let problem {
                Label { Text(CategoryEditorCopy.nameMessage(problem, catalog: catalog)) } icon: {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                }
                .font(.footnote)
            }
        } header: {
            Text("Name")
        } footer: {
            if CategoryNameField.isAtCap(draft.wrappedValue.value.name) { Text(CategoryNameField.capFooter) }
        }
    }

    // MARK: Actions

    @ViewBuilder
    private func actionSections(_ draft: Binding<CategoryDraft>, canArchive: Bool) -> some View {
        let d = draft.wrappedValue
        if d.canReset {
            Section {
                Button { draft.wrappedValue.resetToDefault(); nameTouched = true } label: {
                    Label("Reset to default", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
        }
        Section {
            if case .archived = d.mode {
                Button { commit(d, restoring: true) } label: {
                    Label("Restore category", systemImage: "arrow.uturn.backward")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!d.canRestore(in: catalog))
            } else {
                Button { beginArchive(d) } label: {
                    Label("Archive category", systemImage: "archivebox")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .disabled(!canArchive || d.nameProblem(in: catalog) != nil || !d.hasEmoji)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if !canArchive, !(d.mode.isArchivedMode) { Text(CategoryUsage.lastOneFooter) }
                Text(CategoryEditorCopy.pastBlocksFooter)
            }
        }
    }

    // MARK: Writes

    private func commit(_ d: CategoryDraft, restoring: Bool) {
        do {
            let slug = try CategoryStore(context: context).save(d, catalog: catalog, restoring: restoring)
            saveFailed = false
            onSaved(SavedCategory(slug: slug, name: d.cleanedName))
            if restoring { AccessibilityNotification.Announcement(CategoryUsage.restored(d.cleanedName)).post() }
            dismiss()
        } catch {
            saveFailed = true
        }
    }

    /// Archive from the editor: save the draft and archive in one write, asking where to move
    /// what uses the category first (spec 3.6 and 2.5).
    private func beginArchive(_ d: CategoryDraft) {
        guard let slug = d.mode.slug else { return }
        do {
            let usage = try CategoryStore(context: context).usage(of: slug)
            switch ArchiveFlow.decide(tasks: usage.tasks, rows: usage.rows) {
            case .archiveNow:
                try archive(d, moveTo: nil)
            case .askWhereToMove:
                archivePrompt = ArchivePrompt(slug: slug, name: d.cleanedName, tasks: usage.tasks, rows: usage.rows)
            }
        } catch {
            archiveAlert = true
        }
    }

    private func archive(_ d: CategoryDraft, moveTo target: String?) throws {
        try CategoryStore(context: context).saveAndArchive(d, moveTo: target, catalog: catalog)
        AccessibilityNotification.Announcement(CategoryUsage.archived(d.cleanedName)).post()
        archivePrompt = nil
        dismiss()
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Screenshots only: `-blockeyEditorName`, `-blockeyEditorEmoji`, `-blockeyEditorColor`.
    private func applyDemoPreset() {
        guard var d = draft else { return }
        if let name = DemoScenario.editorName { d.setName(name) }
        if let emoji = DemoScenario.editorEmoji { d.chooseEmoji(emoji) }
        if let hex = DemoScenario.editorColor { d.chooseCustom(hex: hex) }
        draft = d
        nameTouched = DemoScenario.editorName != nil
        if DemoScenario.wantsEditorAutoSave, d.canSave(in: catalog) {
            // After the sheet has finished presenting: dismissing during the presentation is dropped.
            _Concurrency.Task {
                try? await _Concurrency.Task.sleep(for: .seconds(1))
                commit(d, restoring: false)
            }
        }
    }
    #endif
}

private extension CategoryEditorMode {
    var isArchivedMode: Bool {
        if case .archived = self { return true }
        return false
    }
}
