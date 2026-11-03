import Foundation
import SwiftData

/// Everything a planning action needs to know about the day it acts on, passed in rather than
/// read from the environment so the same inputs always give the same result.
struct DayPlanInputs {
    let date: Date
    let now: Date
    /// Whether `date` is today by the real clock. Passed rather than derived from `now`,
    /// because the demo pins `now` and `notBefore` has always followed the real calendar day.
    let isToday: Bool
    /// The user's planning window for `date`.
    let window: TimeRange
    /// The part of `window` still ahead of you (all of it on any day but today).
    let plannableWindow: TimeRange
    /// `nil` when alarms are off.
    let alarmMinutesBefore: Int?
    let calendar: Calendar
    let hiddenCalendarIDs: Set<String>
}

/// A template, flattened to what stamping needs. Keeps `Planning/` from reaching into the
/// template model while the view still owns which template applies today.
struct StampTemplate {
    let items: [TemplateStamper.Item]
    /// Slug per row id, as stored. Rows missing from the map fall back, as
    /// `DayTemplate.categorySlug(forRowID:)` does.
    let slugs: [UUID: String]
    /// The template's name, so a row that falls to the inbox can say where it came from.
    let name: String?

    init(items: [TemplateStamper.Item], slugs: [UUID: String], name: String? = nil) {
        self.items = items
        self.slugs = slugs
        self.name = name
    }

    init(_ template: DayTemplate) {
        self.init(items: template.stampItems,
                  slugs: Dictionary(template.rows.map { ($0.id, $0.categoryRaw) },
                                    uniquingKeysWith: { first, _ in first }),
                  name: template.name)
    }

    func slug(forRowID id: UUID) -> String {
        slugs[id] ?? BlockCategory.fallback.rawValue
    }
}

/// A task as it was when an action deleted it, enough to put it back exactly.
struct TaskSnapshot: Equatable, Sendable {
    let id: UUID
    let title: String
    let estimatedMinutes: Int
    let categoryRaw: String
    let sortIndex: Int
    let createdAt: Date
    /// Always nil today (nothing writes `completedAt` yet), but captured so Undo cannot
    /// silently un-complete a task once completion lands.
    let completedAt: Date?
    let droppedFromTemplate: Bool
    /// Defaulted so the memberwise initialiser keeps working for older call sites.
    var droppedFromTemplateName: String? = nil
}

extension TaskSnapshot {
    // In an extension so the memberwise initialiser survives, which tests and Undo use.
    init(_ task: TaskItem) {
        self.init(id: task.id,
                  title: task.title,
                  estimatedMinutes: task.estimatedMinutes,
                  categoryRaw: task.categoryRaw,
                  sortIndex: task.sortIndex,
                  createdAt: task.createdAt,
                  completedAt: task.completedAt,
                  droppedFromTemplate: task.droppedFromTemplate,
                  droppedFromTemplateName: task.droppedFromTemplateName)
    }

    /// Re-inserts the task unless one with this id already exists. Returns whether it inserted.
    ///
    /// The check is explicit because `TaskItem.id` is `.unique`, which makes a second insert an
    /// upsert: it would overwrite whatever the user changed since, rather than fail. A repeated
    /// Undo, or a task re-created under the same id, must leave the live row alone.
    @discardableResult
    func restore(into context: ModelContext) -> Bool {
        let id = self.id
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        // A failed fetch is treated as "exists": skipping loses nothing, inserting could clobber.
        guard let found = try? context.fetch(descriptor), found.isEmpty else { return false }
        context.insert(TaskItem(id: id, title: title, estimatedMinutes: estimatedMinutes,
                                categoryRaw: categoryRaw, sortIndex: sortIndex,
                                createdAt: createdAt, completedAt: completedAt,
                                droppedFromTemplate: droppedFromTemplate,
                                droppedFromTemplateName: droppedFromTemplateName))
        return true
    }
}

/// What the view shows after an action: the text and whether it is a warning.
struct PlanMessage: Equatable {
    let text: String
    var isWarning = false
}

/// What clearing a day actually did.
///
/// Counted from what was deleted, not from the view's copy of the day: that copy leaves out
/// declined and cancelled events, which are deleted all the same, and it can be a fetch
/// behind the store.
struct ClearResult: Equatable {
    /// A removed block that had a source task, paired with the inbox task the clear made for it.
    /// Paired so Undo can ask, per block, whether that task is still in the inbox.
    struct Returned: Equatable {
        let block: Block
        let insertedTaskID: UUID
    }

    /// Every block the clear deleted, as it was, notes and alarms included. A later Undo
    /// recreates these.
    let removed: [Block]
    /// The removed blocks that had a source task, each with the inbox task inserted for it.
    let returned: [Returned]

    /// Own blocks the clear left in place because Blockey cannot edit them (recurring or
    /// multi-day). Undo could not restore a recurrence rule, so they are skipped rather than
    /// deleted. The confirmation dialog (tasks 2.3/2.4) should name this count. It is counted
    /// from `contents`, which hides declined and cancelled events, so such an event that is
    /// also recurring or multi-day is kept but not counted. Rare in Blockey's own calendar.
    let kept: Int

    /// Ids of the inbox tasks the clear inserted.
    var insertedTaskIDs: [UUID] { returned.map(\.insertedTaskID) }
    var returnedCount: Int { returned.count }
    var lost: Int { removed.filter { $0.token == nil }.count }

    var message: PlanMessage {
        switch (returnedCount, lost) {
        case (0, 0):
            return PlanMessage(text: "Day cleared")
        case (let back, 0):
            return PlanMessage(text: "Day cleared \u{00B7} \(back) back in the inbox")
        case (0, let gone):
            return PlanMessage(text: "Day cleared \u{00B7} \(gone) could not be returned", isWarning: true)
        case (let back, let gone):
            return PlanMessage(text: "Day cleared \u{00B7} \(back) back in the inbox, \(gone) lost", isWarning: true)
        }
    }
}

/// What stamping a template did.
struct StampResult: Equatable {
    /// Blocks written, in placement order.
    let created: [Block]
    /// Rows that fit but could not be written. They went to the inbox.
    let failures: [TemplateStamper.Item]
    /// Rows that fit nowhere. They went to the inbox.
    let unplaced: [TemplateStamper.Item]
    let movedCount: Int
    /// Ids of the inbox tasks stamping inserted (`unplaced` then `failures`).
    let insertedTaskIDs: [UUID]
    /// Set when this was a replace: what the clear beforehand did. Its `removed` and
    /// `returned` are what Start-over Undo puts back.
    let cleared: ClearResult?
    /// How to undo this stamp. Built by `DayPlanner` from this result and the inputs.
    let undo: UndoRecord

    var toInbox: Int { unplaced.count + failures.count }

    /// What the banner says. `day` is a phrase from `StampPreview.dayPhrase`, so it reads after
    /// "for": "Added 5 blocks for Monday".
    ///
    /// A clean stamp names the day. Once something has gone wrong the sentence turns to what
    /// the user has to do about it, and the day (which they have just been looking at) is left
    /// out so the warning stays short.
    func message(day: String) -> PlanMessage {
        let count = created.count
        let lost = cleared?.lost ?? 0
        let blocks = count == 0 ? "No blocks added" : "Added \(count) block\(count == 1 ? "" : "s")"

        if toInbox == 0 && lost == 0 {
            var text = "\(blocks) for \(day)"
            if movedCount > 0 { text += " \u{00B7} \(movedCount) moved to fit" }
            return PlanMessage(text: text)
        }

        var sentences = [blocks + "."]
        if unplaced.count == 1, failures.isEmpty, let only = unplaced.first {
            sentences.append("\u{201C}\(only.title)\u{201D} is in your inbox.")
        } else if unplaced.count >= 1 {
            sentences.append("\(unplaced.count) didn\u{2019}t fit and \(unplaced.count == 1 ? "is" : "are") in your inbox.")
        }
        if !failures.isEmpty {
            let n = failures.count
            sentences.append("\(n) couldn\u{2019}t be saved to your calendar and \(n == 1 ? "is" : "are") in your inbox.")
        }
        // Carried in from the clear, which the stamp banner would otherwise overwrite.
        if lost > 0 {
            sentences.append(lost == 1
                             ? "1 block could not be returned and was deleted."
                             : "\(lost) blocks could not be returned and were deleted.")
        }
        return PlanMessage(text: sentences.joined(separator: " "), isWarning: true)
    }
}

/// What confirming a stamp preview did.
enum StampOutcome: Equatable {
    case written(StampResult)
    /// The day no longer matches what was previewed. Nothing was written; this is the plan
    /// as it stands now.
    case stale(StampPreview)
}

/// What filling the day did.
struct FillResult: Equatable {
    /// A block written, with the task it was made from, as that task was when it was deleted.
    struct Placement: Equatable {
        let block: Block
        let task: TaskSnapshot
    }

    /// Blocks written, each with the task it came from, in placement order. Paired so Undo
    /// cannot reinsert a task without knowing which block stands in for it.
    let placements: [Placement]
    let failed: Int
    /// How to undo this fill. Built by `DayPlanner` from this result and the inputs.
    let undo: UndoRecord

    var created: [Block] { placements.map(\.block) }
    /// The tasks it deleted, as they were, in deletion order.
    var deletedTasks: [TaskSnapshot] { placements.map(\.task) }

    var placed: Int { created.count }

    var message: PlanMessage {
        if failed > 0 {
            return PlanMessage(text: "Placed \(placed), but \(failed) couldn\u{2019}t be saved to your calendar.",
                               isWarning: true)
        }
        return PlanMessage(text: placed == 0
                           ? "Nothing fits in the time you have left"
                           : "Placed \(placed) task\(placed == 1 ? "" : "s")",
                           isWarning: placed == 0)
    }
}

/// Everything needed to undo one stamp, Start over or Fill day.
///
/// Built by `DayPlanner` from the result and the inputs together, so a view cannot pair one
/// action's result with another's day. It is a class because it is **single use**: the second
/// Undo of a Start over would otherwise recreate the cleared blocks a second time. It becomes
/// spent only after an undo has fully landed, so a throw leaves it usable for a retry.
///
/// Nothing here is persisted. It lives as long as the banner that offers it.
final class UndoRecord: Equatable {
    /// The day the action ran on. Undo acts here, whatever day is selected by then.
    let day: Date
    let calendar: Calendar
    /// Hidden at the time, so the fresh fetch Undo makes sees the same fixed events the
    /// action planned around.
    let hiddenCalendarIDs: Set<String>
    /// The blocks the action created. Removed by token.
    let created: [Block]
    /// Inbox tasks a stamp inserted (unplaced and failed rows).
    let insertedTaskIDs: [UUID]
    /// Fill day: the blocks and the tasks they replaced.
    let placements: [FillResult.Placement]
    /// Start over: what the clear before the stamp removed and returned.
    let cleared: ClearResult?

    private(set) var isSpent = false

    init(inputs: DayPlanInputs,
         created: [Block],
         insertedTaskIDs: [UUID] = [],
         placements: [FillResult.Placement] = [],
         cleared: ClearResult? = nil) {
        self.day = inputs.date
        self.calendar = inputs.calendar
        self.hiddenCalendarIDs = inputs.hiddenCalendarIDs
        self.created = created
        self.insertedTaskIDs = insertedTaskIDs
        self.placements = placements
        self.cleared = cleared
    }

    /// Whether there is anything to undo. A stamp that placed and returned nothing has no
    /// reason to show an Undo button.
    var hasEffect: Bool {
        !created.isEmpty || !insertedTaskIDs.isEmpty || !placements.isEmpty
            || !(cleared?.removed.isEmpty ?? true)
    }

    fileprivate func markSpent() { isSpent = true }

    // Identity, not content: two records of identical actions are still two records.
    static func == (lhs: UndoRecord, rhs: UndoRecord) -> Bool { lhs === rhs }
}

/// What an undo did, in counts the banner can tell the truth with.
struct UndoOutcome: Equatable {
    /// The record had already been applied; nothing was done.
    var alreadyUndone = false
    /// Blocks the action had created.
    var blocksTargeted = 0
    /// Of those, how many were found by token and deleted.
    var blocksRemoved = 0
    /// Found but not removed because Blockey cannot edit them (made recurring in Calendar.app).
    var blocksLeftAlone = 0
    /// Deleted since, moved off the day, or token stripped. None of these was deleted. Derived,
    /// so the counts cannot disagree.
    var blocksMissing: Int { Swift.max(0, blocksTargeted - blocksRemoved - blocksLeftAlone) }
    /// Inbox tasks the action created that Undo deleted. One since placed no longer exists
    /// and is not counted.
    var inboxTasksDeleted = 0
    /// Fill day: deleted tasks put back.
    var tasksReinserted = 0
    /// Of those, how many went back although their block was not removed. It was deleted, or
    /// its token was stripped, and Undo cannot tell which. If it was stripped, the same work is
    /// now in the inbox and on the calendar: a duplicate, the accepted failure, where the
    /// alternative is losing the task.
    var tasksReinsertedBlockUnaccountedFor = 0
    /// Fill day: tasks not put back because their block, found by token, is still on the
    /// calendar within a week of the recorded day (the user moved it).
    var tasksKeptBecauseBlockSurvived = 0
    /// Start over: cleared blocks written back.
    var blocksRecreated = 0
    /// Of those, how many had no token and were given a fresh one.
    var recreatedWithNewIdentity = 0
    /// Start over: cleared blocks left out because their returned task was placed since.
    var notRestoredTaskPlaced = 0
    /// Start over: cleared blocks left out because a fixed event now sits where they were.
    /// Each one is in the inbox as a task (the clear's own, or one made by Undo), never dropped.
    var notRestoredFixedConflict: [Block] = []

    var message: PlanMessage {
        if alreadyUndone { return PlanMessage(text: "Already undone") }
        func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

        var parts: [String] = []
        if blocksTargeted > 0 {
            let attempted = blocksTargeted - blocksLeftAlone
            if attempted > 0 || blocksLeftAlone == 0 {
                parts.append(blocksMissing == 0
                             ? "Removed \(plural(blocksRemoved, "block"))"
                             : "Removed \(blocksRemoved) of \(plural(attempted, "block"))")
            }
        }
        if blocksLeftAlone > 0 {
            let n = blocksLeftAlone
            parts.append("\(plural(n, "block")) \(n == 1 ? "was" : "were") changed in Calendar, so \(n == 1 ? "it was" : "they were") left")
        }
        if blocksRecreated > 0 { parts.append("Restored \(plural(blocksRecreated, "block"))") }
        let backCleanly = tasksReinserted - tasksReinsertedBlockUnaccountedFor
        if backCleanly > 0 { parts.append("\(plural(backCleanly, "task")) back in the inbox") }
        if tasksReinsertedBlockUnaccountedFor > 0 {
            let n = tasksReinsertedBlockUnaccountedFor
            parts.append("\(plural(n, "task")) \(n == 1 ? "is" : "are") back in your inbox, \(n == 1 ? "its block" : "their blocks") may still be on your calendar")
        }
        if tasksKeptBecauseBlockSurvived > 0 {
            let n = tasksKeptBecauseBlockSurvived
            parts.append("\(plural(n, "task")) not returned, \(n == 1 ? "its block is" : "their blocks are") still on your calendar")
        }
        if notRestoredTaskPlaced > 0 {
            parts.append("\(notRestoredTaskPlaced) \(notRestoredTaskPlaced == 1 ? "block" : "blocks") not restored, \(notRestoredTaskPlaced == 1 ? "its task is" : "their tasks are") no longer in the inbox")
        }
        if !notRestoredFixedConflict.isEmpty {
            parts.append("\(notRestoredFixedConflict.count) \(notRestoredFixedConflict.count == 1 ? "block" : "blocks") not restored, a meeting is there now, kept in the inbox")
        }
        let isWarning = blocksMissing > 0 || blocksLeftAlone > 0 || tasksKeptBecauseBlockSurvived > 0
            || tasksReinsertedBlockUnaccountedFor > 0
            || notRestoredTaskPlaced > 0 || !notRestoredFixedConflict.isEmpty
        return PlanMessage(text: parts.isEmpty ? "Nothing to undo" : parts.joined(separator: " \u{00B7} "),
                           isWarning: isWarning)
    }
}

/// What placing one task did.
struct PlaceResult: Equatable {
    let created: Block
    let deletedTask: TaskSnapshot

    var message: PlanMessage {
        PlanMessage(text: "Blocked \(created.range.start.formatted(date: .omitted, time: .shortened))")
    }
}

/// What sending a block back to the inbox did.
struct ReturnResult: Equatable {
    let removed: Block
    let insertedTaskID: UUID

    var message: PlanMessage { PlanMessage(text: "Returned to inbox") }
}

/// Stamp, fill, clear, place and return-to-inbox, lifted out of `TodayView` so they can be
/// tested against a fake `BlockWriting` and an in-memory store.
///
/// Every method takes its inputs explicitly and returns a value describing what happened, so
/// the view keeps only UI state and a later Undo can be built from the result alone. Errors
/// that stop an action outright are thrown for the view to show; per-row failures are counted
/// in the result and never stop the rest.
///
/// It saves nothing: like the view before it, it inserts and deletes on the context and leaves
/// persistence to SwiftData's autosave.
@MainActor
struct DayPlanner {
    let writer: any BlockWriting
    let context: ModelContext

    // MARK: Stamp

    /// What stamping `template` would do right now, without writing anything.
    ///
    /// `nil` (no template assigned) previews as an empty template.
    func preview(_ template: StampTemplate?,
                 inputs: DayPlanInputs,
                 mode: StampPreview.Mode) -> StampPreview {
        let contents = writer.contents(for: inputs.date,
                                       ignoring: inputs.hiddenCalendarIDs,
                                       calendar: inputs.calendar)
        return preview(template, inputs: inputs, mode: mode, contents: contents)
    }

    /// A preview plus whether the day has any editable own blocks, both from one fetch, so a
    /// decision to skip the sheet cannot rest on a different picture of the day than the plan.
    func previewWithOwnBlocks(_ template: StampTemplate?,
                              inputs: DayPlanInputs,
                              mode: StampPreview.Mode) -> (preview: StampPreview, hasOwnEditableBlocks: Bool) {
        let contents = writer.contents(for: inputs.date,
                                       ignoring: inputs.hiddenCalendarIDs,
                                       calendar: inputs.calendar)
        return (preview(template, inputs: inputs, mode: mode, contents: contents),
                contents.blocks.contains(where: \.isEditable))
    }

    private func preview(_ template: StampTemplate?,
                         inputs: DayPlanInputs,
                         mode: StampPreview.Mode,
                         contents: DayContents) -> StampPreview {
        // The same floor `stamp` uses, so a preview and the write it leads to cannot disagree
        // about what has already gone.
        StampPreview.make(items: template?.items ?? [],
                          on: inputs.date,
                          mode: mode,
                          fixed: contents.fixed.map(\.range),
                          ownEditable: contents.blocks.filter(\.isEditable).map(\.range),
                          ownLocked: contents.blocks.filter { !$0.isEditable }.map(\.range),
                          window: inputs.window,
                          notBefore: inputs.isToday ? inputs.now : nil,
                          calendar: inputs.calendar)
    }

    /// Stamps `template` around what is already on the day, fetching the day fresh.
    @discardableResult
    func stamp(_ template: StampTemplate,
               inputs: DayPlanInputs,
               openTasks: [TaskItem]) -> StampResult {
        let busy = writer.contents(for: inputs.date,
                                   ignoring: inputs.hiddenCalendarIDs,
                                   calendar: inputs.calendar).busy
        return stamp(template, inputs: inputs, busy: busy,
                     nextInboxSortIndex: Self.nextInboxSortIndex(openTasks), cleared: nil)
    }

    /// Confirms a preview: recomputes against a fresh fetch and the current `inputs.now`, and
    /// writes only if the result is the one the user was shown.
    ///
    /// Otherwise returns the fresh preview and writes nothing, for the sheet to show again.
    /// The user agreed to a plan, not to whatever the calendar looks like a minute later.
    /// Throws, having changed nothing, if Start over cannot clear the day.
    func stamp(_ template: StampTemplate,
               expecting expected: StampPreview,
               mode: StampPreview.Mode,
               inputs: DayPlanInputs,
               openTasks: [TaskItem]) throws -> StampOutcome {
        let contents = writer.contents(for: inputs.date,
                                       ignoring: inputs.hiddenCalendarIDs,
                                       calendar: inputs.calendar)
        let fresh = preview(template, inputs: inputs, mode: mode, contents: contents)
        guard fresh == expected else { return .stale(fresh) }

        switch mode {
        case .keep:
            return .written(stamp(template, inputs: inputs, busy: contents.busy,
                                  nextInboxSortIndex: Self.nextInboxSortIndex(openTasks), cleared: nil))
        case .startOver:
            return .written(try replace(with: template, inputs: inputs, openTasks: openTasks))
        }
    }

    /// Clears the day, then stamps into the emptied day.
    ///
    /// Throws if the clear fails, having changed nothing. The stamp then plans against a fresh
    /// fetch, since the clear changed what is busy.
    @discardableResult
    func replace(with template: StampTemplate,
                 inputs: DayPlanInputs,
                 openTasks: [TaskItem]) throws -> StampResult {
        // The index comes from the tasks as they were before the clear, as it always has.
        let floor = Self.nextInboxSortIndex(openTasks)
        let cleared = try clear(inputs: inputs, openTasks: openTasks)
        let busy = writer.contents(for: inputs.date,
                                   ignoring: inputs.hiddenCalendarIDs,
                                   calendar: inputs.calendar).busy
        return stamp(template, inputs: inputs, busy: busy, nextInboxSortIndex: floor, cleared: cleared)
    }

    private func stamp(_ template: StampTemplate,
                       inputs: DayPlanInputs,
                       busy: [TimeRange],
                       nextInboxSortIndex: Int,
                       cleared: ClearResult?) -> StampResult {
        // The floor, not a narrowed window: the stamper widens its window back
        // out to cover each row's intended time, so passing `plannableWindow`
        // here would be undone a few lines into `stamp`. Only `notBefore`
        // survives that widening. Nil on any day but today, which leaves
        // stamping a past or future day exactly as it was.
        let result = TemplateStamper.stamp(items: template.items,
                                           on: inputs.date,
                                           busy: busy,
                                           window: inputs.window,
                                           notBefore: inputs.isToday ? inputs.now : nil,
                                           calendar: inputs.calendar)

        var created: [Block] = []
        var failures: [TemplateStamper.Item] = []
        // A zero-length row is not a task anyone can do, and the preview does not list it.
        let unplaced = result.placements
            .filter { $0.outcome == .unplaced(.noGapFitsInDayWindow) }
            .map(\.item)

        for (item, range) in result.scheduled {
            do {
                let block = try writer.createBlock(title: item.title,
                                                   range: range,
                                                   categorySlug: template.slug(forRowID: item.id),
                                                   sourceTaskID: nil,
                                                   alarmMinutesBefore: inputs.alarmMinutesBefore)
                created.append(block)
            } catch {
                // Carry on rather than break: stopping here used to strand the
                // remaining rows in neither the calendar nor the inbox.
                failures.append(item)
            }
        }

        // Anything that did not fit — or could not be written — becomes an
        // inbox task rather than vanishing.
        var index = nextInboxSortIndex
        var insertedIDs: [UUID] = []
        for item in unplaced + failures {
            let task = TaskItem(title: item.title,
                                estimatedMinutes: item.durationMinutes,
                                categoryRaw: template.slug(forRowID: item.id),
                                sortIndex: index,
                                droppedFromTemplate: true,
                                droppedFromTemplateName: template.name)
            context.insert(task)
            insertedIDs.append(task.id)
            index -= 1
        }

        return StampResult(created: created,
                           failures: failures,
                           unplaced: unplaced,
                           movedCount: result.movedCount,
                           insertedTaskIDs: insertedIDs,
                           cleared: cleared,
                           undo: UndoRecord(inputs: inputs,
                                            created: created,
                                            insertedTaskIDs: insertedIDs,
                                            cleared: cleared))
    }

    // MARK: Clear

    /// Deletes the day's blocks, putting anything that came from the inbox back.
    ///
    /// Blocks carry their source task in the token, which is what makes this
    /// non-destructive for work the user typed: template-stamped blocks have no
    /// source and simply go, while placed tasks return to where they came from.
    ///
    /// Throws, having changed nothing, if the calendar could not delete.
    @discardableResult
    func clear(inputs: DayPlanInputs, openTasks: [TaskItem]) throws -> ClearResult {
        // Counted before the delete, from the same fetch the preview uses. The kept events
        // are exactly the own, non-all-day blocks the clear will not touch.
        let kept = writer.contents(for: inputs.date,
                                   ignoring: inputs.hiddenCalendarIDs,
                                   calendar: inputs.calendar).blocks.filter { !$0.isEditable }.count
        let removed = try writer.deleteAllBlocks(on: inputs.date, calendar: inputs.calendar)
        var index = Self.nextInboxSortIndex(openTasks)
        var returned: [ClearResult.Returned] = []
        for block in removed where block.token?.sourceTaskID != nil {
            let task = TaskItem(title: block.title,
                                estimatedMinutes: Int(block.range.duration / 60),
                                categoryRaw: block.token?.categorySlug ?? BlockCategory.fallback.rawValue,
                                sortIndex: index)
            context.insert(task)
            returned.append(ClearResult.Returned(block: block, insertedTaskID: task.id))
            index -= 1
        }
        return ClearResult(removed: removed, returned: returned, kept: kept)
    }

    // MARK: Fill

    /// Places every open task that fits, first-fit, and deletes each one it places.
    @discardableResult
    func fillDay(inputs: DayPlanInputs, openTasks: [TaskItem]) -> FillResult {
        var busy = writer.contents(for: inputs.date,
                                   ignoring: inputs.hiddenCalendarIDs,
                                   calendar: inputs.calendar).busy
        var placements: [FillResult.Placement] = []
        var failed = 0

        for task in openTasks {
            let gaps = DaySchedule.gaps(busy: busy, within: inputs.plannableWindow, minimumDuration: task.duration)
            guard let slot = DaySchedule.firstFit(duration: task.duration, in: gaps) else { continue }
            do {
                let block = try writer.createBlock(title: task.title,
                                                   range: slot,
                                                   categorySlug: task.categoryRaw,
                                                   sourceTaskID: task.id,
                                                   alarmMinutesBefore: inputs.alarmMinutesBefore)
                busy.append(slot)
                placements.append(FillResult.Placement(block: block, task: TaskSnapshot(task)))
                context.delete(task)
            } catch {
                // Keep going: one unwritable event should not strand the rest.
                failed += 1
            }
        }

        return FillResult(placements: placements,
                          failed: failed,
                          undo: UndoRecord(inputs: inputs,
                                           created: placements.map(\.block),
                                           placements: placements))
    }

    // MARK: Place and return

    /// Places one task at `start`. Throws, having changed nothing, if the calendar refuses.
    @discardableResult
    func place(_ task: TaskItem, at start: Date, inputs: DayPlanInputs) throws -> PlaceResult {
        let block = try writer.createBlock(title: task.title,
                                           range: TimeRange(start: start, duration: task.duration),
                                           categorySlug: task.categoryRaw,
                                           sourceTaskID: task.id,
                                           alarmMinutesBefore: inputs.alarmMinutesBefore)
        // The inbox holds only unscheduled work, so a placed task leaves it.
        // Unscheduling recreates it — symmetric, and there is never a task
        // and a block representing the same thing at once.
        let snapshot = TaskSnapshot(task)
        context.delete(task)
        return PlaceResult(created: block, deletedTask: snapshot)
    }

    /// Turns a block back into an inbox task. Throws, inserting nothing, if the delete fails.
    @discardableResult
    func returnToInbox(_ block: Block, openTasks: [TaskItem]) throws -> ReturnResult {
        // Delete first. Inserting the task up front would leave the same thing
        // in the inbox *and* on the calendar if the delete failed.
        try writer.delete(block)
        let task = TaskItem(title: block.title,
                            estimatedMinutes: Int(block.range.duration / 60),
                            categoryRaw: block.token?.categorySlug ?? BlockCategory.fallback.rawValue,
                            sortIndex: Self.nextInboxSortIndex(openTasks))
        context.insert(task)
        return ReturnResult(removed: block, insertedTaskID: task.id)
    }

    // MARK: Undo

    /// Reverses a stamp, Start over or Fill day.
    ///
    /// The calendar half is one atomic batch (`BlockWriting.applyUndo`); the SwiftData half runs
    /// only after it lands. Throws, having changed nothing and left `record` usable, if the
    /// batch fails. A record already applied returns an `alreadyUndone` outcome and does nothing.
    ///
    /// Fresh state, not recorded state, decides what is safe: the fixed events a recreated block
    /// must avoid, and whether a returned task is still in the inbox, are read now.
    @discardableResult
    func undo(_ record: UndoRecord) throws -> UndoOutcome {
        guard !record.isSpent else { return UndoOutcome(alreadyUndone: true) }

        let fresh = writer.contents(for: record.day,
                                    ignoring: record.hiddenCalendarIDs,
                                    calendar: record.calendar)
        var outcome = UndoOutcome()
        outcome.blocksTargeted = record.created.count

        // Start over: decide which cleared blocks come back.
        var restorable: [(block: Block, taskID: UUID?)] = []
        if let cleared = record.cleared {
            var taskForBlock: [String: UUID] = [:]
            for pair in cleared.returned { taskForBlock[pair.block.id] = pair.insertedTaskID }
            for block in cleared.removed {
                let taskID = taskForBlock[block.id]
                // The clear turned this block into an inbox task. If that task has gone, the
                // user placed it again, and recreating the block would put it on the calendar
                // twice.
                if let taskID, !taskExists(taskID) {
                    outcome.notRestoredTaskPlaced += 1
                    continue
                }
                restorable.append((block, taskID))
            }
        }
        // Fixed events always win, including ones that arrived after the clear.
        let split = RestoreFilter.split(restorable.map(\.block.range),
                                        avoiding: fresh.fixed.map(\.range))
        outcome.notRestoredFixedConflict = split.blocked.map { restorable[$0].block }

        var drafts: [UndoDraft] = []
        var returnedTasksToDelete: [UUID] = []
        for index in split.writable {
            let (block, taskID) = restorable[index]
            // A block that had no token is recreated with a fresh one (no slug is invented).
            // Leaving it tokenless would also work, but a token is what lets any later Undo or
            // edit find it, and the user's work comes back either way.
            if block.token == nil { outcome.recreatedWithNewIdentity += 1 }
            drafts.append(UndoDraft(title: block.title,
                                    range: block.range,
                                    token: block.token ?? BlockToken(categorySlug: nil),
                                    notes: block.notes,
                                    alarmOffsets: block.alarmOffsets))
            // Only a block that really comes back releases its inbox task. One left out for a
            // meeting keeps its task, or the work would be in neither place.
            if let taskID { returnedTasksToDelete.append(taskID) }
        }

        let batch = UndoBatch(day: record.day,
                              removeTokenIDs: record.created.compactMap { $0.token?.id },
                              create: drafts)
        var applied = UndoApplied(removed: [], leftAlone: [], created: [])
        if !batch.removeTokenIDs.isEmpty || !batch.create.isEmpty {
            applied = try writer.applyUndo(batch, calendar: record.calendar)
        }
        record.markSpent()
        outcome.blocksRemoved = applied.removed.count
        outcome.blocksLeftAlone = applied.leftAlone.count
        outcome.blocksRecreated = applied.created.count

        // SwiftData half. The inbox tasks this action created are deleted unless the user has
        // since placed them, which already removed them.
        for id in record.insertedTaskIDs + returnedTasksToDelete {
            if deleteTask(id) { outcome.inboxTasksDeleted += 1 }
        }

        // A cleared block that a new meeting stops us recreating, and that has no inbox task
        // from the clear (it came from a template or was typed in Calendar.app), would exist
        // nowhere. Give it a task, on top of the inbox, so it is never dropped.
        var nextIndex = (((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).map(\.sortIndex).min() ?? 0) - 1
        for index in split.blocked where restorable[index].taskID == nil {
            let block = restorable[index].block
            context.insert(TaskItem(title: block.title,
                                    estimatedMinutes: Int(block.range.duration / 60),
                                    categoryRaw: block.token?.categorySlug ?? BlockCategory.fallback.rawValue,
                                    sortIndex: nextIndex))
            nextIndex -= 1
        }

        // Fill day: a task goes back unless its block is found by token. A block Undo removed
        // is plainly gone. For the rest, look for the token within a week of the recorded day,
        // which finds a block the user dragged elsewhere. Anything not found is reinserted:
        // it was deleted, or its token was stripped, and the two cannot be told apart. No
        // lookalike guessing by title and time, which can swallow a task. The rule is that work
        // must never end up in neither place; a duplicate is the acceptable failure.
        let removedIDs = Set(applied.removed)
        let unresolved = Set(record.placements.compactMap { $0.block.token?.id }.filter { !removedIDs.contains($0) })
        let stillThere = unresolved.isEmpty
            ? []
            : writer.existingTokenIDs(unresolved, around: record.day, days: 7, calendar: record.calendar)
        for placement in record.placements {
            let id = placement.block.token?.id
            if let id, removedIDs.contains(id) {
                if placement.task.restore(into: context) { outcome.tasksReinserted += 1 }
            } else if let id, stillThere.contains(id) {
                outcome.tasksKeptBecauseBlockSurvived += 1
            } else if placement.task.restore(into: context) {
                outcome.tasksReinserted += 1
                outcome.tasksReinsertedBlockUnaccountedFor += 1
            }
        }
        return outcome
    }

    private func taskExists(_ id: UUID) -> Bool {
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        // A failed fetch reads as "gone": the safe error here is not recreating a block.
        return ((try? context.fetch(descriptor))?.isEmpty ?? true) == false
    }

    /// Deletes the task with this id if it exists. Returns whether it did.
    private func deleteTask(_ id: UUID) -> Bool {
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let task = (try? context.fetch(descriptor))?.first else { return false }
        context.delete(task)
        return true
    }

    // MARK: Helpers

    /// One step ahead of the front of the inbox, so what comes back lands on top.
    static func nextInboxSortIndex(_ openTasks: [TaskItem]) -> Int {
        (openTasks.map(\.sortIndex).min() ?? 0) - 1
    }
}
