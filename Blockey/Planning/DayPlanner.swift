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

    init(items: [TemplateStamper.Item], slugs: [UUID: String]) {
        self.items = items
        self.slugs = slugs
    }

    init(_ template: DayTemplate) {
        self.init(items: template.stampItems,
                  slugs: Dictionary(template.rows.map { ($0.id, $0.categoryRaw) },
                                    uniquingKeysWith: { first, _ in first }))
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
    let droppedFromTemplate: Bool

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
                  droppedFromTemplate: task.droppedFromTemplate)
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
    /// Every block the clear deleted, as it was. A later Undo recreates these.
    let removed: [Block]
    /// Ids of the inbox tasks the clear inserted, one per removed block that had a source task.
    let insertedTaskIDs: [UUID]

    var returned: Int { insertedTaskIDs.count }
    var lost: Int { removed.filter { $0.token == nil }.count }

    var message: PlanMessage {
        switch (returned, lost) {
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
    /// Set when this was a replace: what the clear beforehand did.
    let cleared: ClearResult?

    var toInbox: Int { unplaced.count + failures.count }

    var message: PlanMessage {
        let count = created.count
        var text = "Stamped \(count) block\(count == 1 ? "" : "s")"
        if movedCount > 0 { text += " \u{00B7} \(movedCount) moved to fit" }
        if toInbox > 0 { text += " \u{00B7} \(toInbox) to inbox" }
        if !failures.isEmpty { text += " (\(failures.count) couldn\u{2019}t be saved)" }
        // Carried in from the clear, which the stamp banner would otherwise overwrite.
        let lost = cleared?.lost ?? 0
        if lost > 0 { text += " \u{00B7} \(lost) lost" }
        return PlanMessage(text: text, isWarning: toInbox > 0 || lost > 0)
    }
}

/// What filling the day did.
struct FillResult: Equatable {
    /// Blocks written, with the task each one came from.
    let created: [Block]
    /// The tasks it deleted, as they were, in deletion order. A later Undo reinserts these.
    let deletedTasks: [TaskSnapshot]
    let failed: Int

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

    /// Stamps `template` around what is already on the day.
    ///
    /// `busy` is the day's current commitments, as the caller last fetched them.
    @discardableResult
    func stamp(_ template: StampTemplate,
               inputs: DayPlanInputs,
               busy: [TimeRange],
               openTasks: [TaskItem]) -> StampResult {
        stamp(template, inputs: inputs, busy: busy,
              nextInboxSortIndex: Self.nextInboxSortIndex(openTasks), cleared: nil)
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
        for item in result.unplaced + failures {
            let task = TaskItem(title: item.title,
                                estimatedMinutes: item.durationMinutes,
                                categoryRaw: template.slug(forRowID: item.id),
                                sortIndex: index,
                                droppedFromTemplate: true)
            context.insert(task)
            insertedIDs.append(task.id)
            index -= 1
        }

        return StampResult(created: created,
                           failures: failures,
                           unplaced: result.unplaced,
                           movedCount: result.movedCount,
                           insertedTaskIDs: insertedIDs,
                           cleared: cleared)
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
        let removed = try writer.deleteAllBlocks(on: inputs.date, calendar: inputs.calendar)
        var index = Self.nextInboxSortIndex(openTasks)
        var insertedIDs: [UUID] = []
        for block in removed where block.token?.sourceTaskID != nil {
            let task = TaskItem(title: block.title,
                                estimatedMinutes: Int(block.range.duration / 60),
                                categoryRaw: block.token?.categorySlug ?? BlockCategory.fallback.rawValue,
                                sortIndex: index)
            context.insert(task)
            insertedIDs.append(task.id)
            index -= 1
        }
        return ClearResult(removed: removed, insertedTaskIDs: insertedIDs)
    }

    // MARK: Fill

    /// Places every open task that fits, first-fit, and deletes each one it places.
    @discardableResult
    func fillDay(inputs: DayPlanInputs, busy: [TimeRange], openTasks: [TaskItem]) -> FillResult {
        var busy = busy
        var created: [Block] = []
        var deleted: [TaskSnapshot] = []
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
                deleted.append(TaskSnapshot(task))
                context.delete(task)
                created.append(block)
            } catch {
                // Keep going: one unwritable event should not strand the rest.
                failed += 1
            }
        }

        return FillResult(created: created, deletedTasks: deleted, failed: failed)
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

    // MARK: Helpers

    /// One step ahead of the front of the inbox, so what comes back lands on top.
    static func nextInboxSortIndex(_ openTasks: [TaskItem]) -> Int {
        (openTasks.map(\.sortIndex).min() ?? 0) - 1
    }
}
