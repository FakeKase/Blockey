import SwiftUI
import SwiftData

/// Settings, Categories (UI spec 2): the owner's categories in order, add, reorder, archive with
/// the move-to sheet, and the Archived section with restore. Order, counts and words come from
/// `Catalog/` and `Planning/CategoryStore`; this draws them.
struct CategoriesListView: View {
    @Environment(\.categoryCatalog) private var catalog
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var editor: CategoryEditorRequest?
    @State private var archivePrompt: ArchivePrompt?
    @State private var failure: CategoryUsage.Failure?

    var body: some View {
        let active = catalog.activeInOrder()
        let archived = catalog.archived()
        let onlyOne = active.count <= 1
        List {
            Section {
                ForEach(active, id: \.slug) { category in
                    activeRow(category, in: active)
                }
                .onMove { offsets, destination in
                    move(active, from: offsets, to: destination)
                }
                Button { editor = CategoryEditorRequest(mode: .add) } label: {
                    Label("Add category", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
            } footer: {
                Text(onlyOne ? CategoryUsage.lastOneFooter
                             : "Tap Edit to reorder. This order is used wherever you pick a category.")
            }
            if !archived.isEmpty {
                Section {
                    ForEach(archived, id: \.slug) { archivedRow($0) }
                } header: {
                    Text("Archived")
                } footer: {
                    Text("Archived categories stay on the blocks that use them. They just aren\u{2019}t offered for new work.")
                }
            }
        }
        // Rows move in place; no slide under Reduce Motion (spec 6).
        .animation(reduceMotion ? nil : .default, value: active.map(\.slug))
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
        .sheet(item: $editor) { request in
            CategoryEditorSheet(mode: request.mode, catalog: catalog) { saved in
                if request.mode == .add {
                    AccessibilityNotification.Announcement(CategoryUsage.added(saved.name)).post()
                }
            }
        }
        .sheet(item: $archivePrompt) { prompt in
            CategoryArchiveSheet(prompt: prompt, targets: active.filter { $0.slug != prompt.slug }) { target in
                try CategoryStore(context: context).archive(prompt.slug, moveTo: target, catalog: catalog)
                AccessibilityNotification.Announcement(CategoryUsage.archived(prompt.name)).post()
            }
        }
        .alert(failure?.title ?? CategoryUsage.archiveAlertTitle,
               isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure?.message ?? CategoryUsage.archiveAlertMessage)
        }
        #if DEBUG && targetEnvironment(simulator)
        .task { demoOpen() }
        #endif
    }

    // MARK: Rows

    private func activeRow(_ category: ResolvedCategory, in active: [ResolvedCategory]) -> some View {
        let slug = category.slug ?? ""
        let order = active.compactMap(\.slug)
        let canArchive = catalog.canArchive(slug)
        return Button {
            editor = CategoryEditorRequest(mode: .edit(slug: slug))
        } label: {
            rowLabel(category, subtitle: nil)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canArchive {
                Button { beginArchive(category) } label: { Label("Archive", systemImage: "archivebox") }
                    .tint(.accentColor)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.name)
        .accessibilityHint("Opens the category editor")
        .accessibilityAddTraits(.isButton)
        // Custom actions, absent where they do not apply (spec 2.4, 2.5), so a VoiceOver user
        // never has to find the Edit button to reorder.
        .accessibilityActions {
            if let up = CategoryOrdering.moved(order, slug: slug, by: -1) {
                Button("Move up") { reorder(up, moved: category) }
            }
            if let down = CategoryOrdering.moved(order, slug: slug, by: 1) {
                Button("Move down") { reorder(down, moved: category) }
            }
            if canArchive { Button("Archive") { beginArchive(category) } }
        }
    }

    private func archivedRow(_ category: ResolvedCategory) -> some View {
        let slug = category.slug ?? ""
        return Button {
            editor = CategoryEditorRequest(mode: .archived(slug: slug))
        } label: {
            rowLabel(category, subtitle: "Archived")
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button { restore(category) } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                .tint(.accentColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.name + ", archived")
        .accessibilityHint("Opens the category editor")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Restore") { restore(category) }
    }

    private func rowLabel(_ category: ResolvedCategory, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            CategoryTile(style: CategoryStyle(category))
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name).font(.body).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    // MARK: Actions

    private func move(_ active: [ResolvedCategory], from offsets: IndexSet, to destination: Int) {
        let order = active.compactMap(\.slug)
        let moved = CategoryOrdering.moved(order, fromOffsets: Array(offsets), toOffset: destination)
        guard let first = offsets.first, active.indices.contains(first) else { return }
        reorder(moved, moved: active[first])
    }

    private func reorder(_ newOrder: [String], moved category: ResolvedCategory) {
        do {
            try CategoryStore(context: context).apply(CategoryOrdering.plan(newOrder: newOrder, catalog: catalog))
            if let slug = category.slug, let position = newOrder.firstIndex(of: slug) {
                AccessibilityNotification.Announcement(
                    CategoryOrdering.announcement(name: category.name, position: position + 1, total: newOrder.count)).post()
            }
        } catch {
            failure = CategoryUsage.reorderFailureAlert
        }
    }

    private func beginArchive(_ category: ResolvedCategory) {
        guard let slug = category.slug, catalog.canArchive(slug) else { return }
        do {
            let store = CategoryStore(context: context)
            let usage = try store.usage(of: slug)
            switch ArchiveFlow.decide(tasks: usage.tasks, rows: usage.rows) {
            case .archiveNow:
                try store.archive(slug, catalog: catalog)
                AccessibilityNotification.Announcement(CategoryUsage.archived(category.name)).post()
            case .askWhereToMove:
                archivePrompt = ArchivePrompt(slug: slug, name: category.name, tasks: usage.tasks, rows: usage.rows)
            }
        } catch {
            failure = CategoryUsage.archiveFailureAlert
        }
    }

    /// A restore that would put two identical names in one picker opens the editor on the name
    /// instead (spec 2.6).
    private func restore(_ category: ResolvedCategory) {
        guard let slug = category.slug else { return }
        if catalog.validate(name: category.name, editing: slug) != nil {
            editor = CategoryEditorRequest(mode: .archived(slug: slug))
            return
        }
        do {
            try CategoryStore(context: context).restore(slug)
            AccessibilityNotification.Announcement(CategoryUsage.restored(category.name)).post()
        } catch {
            failure = CategoryUsage.restoreFailureAlert
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Screenshots only. `-blockeyCategoryEditor add` opens Add; `-blockeyArchiveSheet <slug>` opens
    /// the move-to sheet for that category.
    private func demoOpen() {
        if DemoScenario.editorPreset != nil { editor = CategoryEditorRequest(mode: .add) }
        if let slug = DemoScenario.archiveSheetSlug,
           let category = catalog.activeInOrder().first(where: { $0.slug == slug }),
           let usage = try? CategoryStore(context: context).usage(of: slug) {
            archivePrompt = ArchivePrompt(slug: slug, name: category.name, tasks: usage.tasks, rows: usage.rows)
        }
    }
    #endif
}
