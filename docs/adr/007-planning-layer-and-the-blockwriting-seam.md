# ADR 007: The planning layer and the BlockWriting seam

Status: proposed. Not to be marked accepted until phase 5.1 of `docs/feedback-plan-2026-11.md`
has checked every mechanism named here against the code.
Date: 2026-11-03. Revised 2026-11-03 to describe task 2.2 (Undo logic) as built, and again the
same day after the "never in neither place" rule changed how Undo resolves Fill-day tasks.

Owner decision (2026-11-03): undoing Start over restores each cleared block's Calendar.app notes
and alarm offsets exactly, not just its title, time and token. So `Block` carries `notes` and
`alarmOffsets`, and only `Calendar/` reads them from or writes them to an event.

Owner decision (2026-11-03), "Skip them": Clear and Start over leave in place the Blockey events
that Blockey cannot edit (recurring, multi-day). Undo could not restore a recurrence rule, so
deleting them would make Start over irreversible for exactly those events. This was recorded only
in the message of commit 87734d9, which is why an earlier revision of this ADR could not find it
in the repo and flagged it as unconfirmed. It is recorded here now.

Lead decision (2026-11-03), the governing rule for Undo: **Undo must never leave work in neither
place. A duplicate is the acceptable failure.** Where Undo cannot tell whether a block still
stands for a task, it puts the task back and says so. The consequences are under "Undo in
`DayPlanner`" below.

## Context

Task 2.0 of the feedback plan (commit c0df6e5) moved stamp, replace, fill, clear, place and
return-to-inbox out of `TodayView` into `DayPlanner`, in a new `Blockey/Planning/` folder, behind a
new `BlockWriting` protocol. That was a refactor with characterisation tests
(`BlockeyTests/DayPlannerTests.swift`, `BlockeyTests/DayPlannerEquivalenceTests.swift`), done so
Undo could be tested against a fake. Task 2.2 then grew the seam for Undo. This ADR records what
the folder and the seam are for, and what Undo does.

File:line citations below were checked against the `sprint-1` working tree with task 2.2 built
and not yet committed (on top of 87734d9). They will drift; re-grep before trusting one.

### What the code does now

- `BlockWriting` (`Planning/BlockWriting.swift:42-80`) is `@MainActor` and has seven members:
  `createBlock(title:range:categorySlug:sourceTaskID:alarmMinutesBefore:)`,
  `createBlock(title:range:token:notes:alarmOffsets:)` (`:54-58`),
  `applyUndo(_:calendar:)` (`:64`), `existingTokenIDs(_:around:days:calendar:)` (`:69`),
  `delete(_:)`, `deleteAllBlocks(on:calendar:)` and `contents(for:ignoring:calendar:)`. It names
  no EventKit type. The same file declares the batch value types `UndoDraft` (`:4-10`),
  `UndoBatch` (`:13-20`) and `UndoApplied` (`:23-34`).
- `CalendarService` conforms with an empty extension in `Calendar/`
  (`Calendar/CalendarService+BlockWriting.swift:6`), because it has those exact signatures.
  `update` (`CalendarService.swift:375-402`) is deliberately not in the protocol: nothing in
  `DayPlanner` calls it.
- `CalendarService` has one write path for a single block. The slug form of `createBlock`
  (`CalendarService.swift:228-238`) mints a token (`:235`) and calls `createBlock(token:)`
  (`:243-256`). That and `applyUndo` both build the event with `makeEvent` (`:273-299`), so the two
  cannot write different fields.
- `DayPlanner` holds `writer: any BlockWriting` and a `ModelContext`. It imports Foundation and
  SwiftData only. `BlockWriting.swift` imports Foundation only.
- The tests' stand-in is `BlockeyTests/FakeBlockWriter.swift:8`.
- Every action that touches both stores goes through `DayPlanner`: `stamp` and `replace`
  (calendar writes, then inbox inserts for rows that did not fit or failed), `clear` (calendar
  delete, then inbox inserts for blocks with a source task), `fillDay` and `place` (calendar write,
  then task delete), `returnToInbox` (calendar delete, then task insert), and `undo` (one calendar
  batch and one token lookup, then task deletes and inserts). A grep for `createBlock`,
  `applyUndo`, `delete(`, `deleteAllBlocks`, `context.insert` and `context.delete` under `Blockey/`
  outside `Planning/` finds no other place that does both in one action, with one exception:
  `Models/DemoScenario.swift` (`apply` at `:136-167`, and `exerciseUndo` at `:52-133`), which is
  compiled only under `#if DEBUG && targetEnvironment(simulator)` (`:4`) and is not a user action.
- In every `DayPlanner` method the calendar writes run first and SwiftData changes only follow a
  calendar step that succeeded. The calendar is the side that throws; context inserts and
  deletes do not throw and are persisted later by autosave.
- Clear leaves non-editable events in place, per the owner's "Skip them". `deleteAllBlocks`
  skips all-day events and anything `Block.isEditable` rejects, recurring or multi-day
  (`CalendarService.swift:430-434`), and `ClearResult.kept` (`Planning/DayPlanner.swift:123`)
  counts them.

### What Undo needed that the seam could not do

- **Recreate a block with its old token.** The slug form of `createBlock` always mints a new
  token, whose `id` defaults to `UUID()` (`Calendar/BlockToken.swift:49`). Start-over Undo needs
  the original token UUID back.
- **Undo several things at once.** Start over removes the stamped blocks, recreates the cleared
  ones and deletes the inbox tasks the clear inserted. Doing that as separate calls can leave a
  half-undone day.
- **Keep notes and alarms.** `Block` had no notes or alarm fields, so the `[Block]` that
  `deleteAllBlocks` returned had already lost them, and `createBlock` wrote at most one relative
  alarm.
- **Find a block that left the day.** A Fill-day block the user dragged to another day is not in
  the day's fetch, and nothing on the seam could look further.

### The constraint

**Correctness of a destructive action's reverse.** Undo is only worth shipping if it puts back what
was there. A half-applied undo is worse than no Undo. Between the two ways a non-atomic case can
fail, losing work and duplicating it, the lead's rule picks duplication: a duplicate is visible and
the user can delete it; a lost task is invisible. Speed of delivery is secondary: the seam already
existed and only needed to grow.

## Options

### A. Keep `Planning/` and grow `BlockWriting` only when a caller needs it

`Planning/` stays a coordinator layer between the views and both stores. The protocol gains the
things Undo needs and nothing speculative. Costs: one more folder rule to keep, and a protocol
that must stay in step with `CalendarService` and the fake. Buys: Undo is testable without an event
store, which is the only way most of it can be tested at all, and the two-store rules live in one
file.

### B. Go straight to ADR 001's full `BlockStore`

Give the protocol every intent `CalendarService` exposes, `update` included, now. Costs: methods
with no caller in `Planning/`, each one more thing the fake must mirror correctly. Buys: nothing
Undo needs. **Rejected** as premature, not as wrong; option A grows into it.

### C. Inline `DayPlanner` back into `TodayView`

Costs: Undo cannot be tested without a live store, and the view goes back to owning two-store
consistency. Buys: one less file and one less protocol. **Rejected** for now. It remains the escape
hatch below.

## Decision

**A.**

### The folder rule

- `Planning/` may import Foundation and SwiftData. It never imports SwiftUI or EventKit and never
  names an `EK` type.
- **`Planning/` is the only place where one user action mutates both stores.** A view that needs
  to change the calendar and SwiftData together calls a `DayPlanner` method; it does not do the two
  halves itself. A view may still make a single-store change directly, as `TodayView`'s `+`
  button (`Views/TodayView.swift:548`), its delete (`:184`), its move and resize, and the inbox's
  add and delete (`Views/InboxTray.swift:169`, `:133`) do today.
- Order inside an action stays as it is: the calendar step first, SwiftData only after it
  succeeds. A new action that has to do it the other way round needs a written reason.
- One module means the compiler cannot enforce any of this. `Planning/` already uses types
  declared in files that import SwiftUI (`BlockCategory`, `Models/BlockCategory.swift:1`) and
  EventKit (`Block`, `Calendar/Block.swift:2`). The rule is about what `Planning/` files import and
  name, and it is checked by grep in review:
  `grep -rnE 'import (SwiftUI|EventKit)|\bEK[A-Z]' Blockey/Planning | grep -v '///'` must print
  nothing. The second filter is there because `BlockWriting.swift:41` names `EKEvent` in a doc
  comment, to say where it lives.
- Pure decisions Undo makes go in `Scheduling/`, with tests, like any other scheduling rule.
  `RestoreFilter.split` (`Scheduling/RestoreFilter.swift:13-25`) is the first.

### `BlockWriting` is the first slice of ADR 001's `BlockStore`

ADR 001's escape hatch is a `BlockStore` protocol over `Block`. `BlockWriting` is that protocol,
started small and named for what `Planning/` does with it. It grows only when a caller in
`Planning/` needs a method, and every addition lands in `CalendarService` (in `Calendar/`), in
`FakeBlockWriter`, and in a test, together. Growth so far, and what is next:

1. **`createBlock(title:range:token:notes:alarmOffsets:)`. Built.** Writes the token verbatim:
   its UUID, slug, source task and unknown query items. A nil token writes no url
   (`CalendarService.swift:284-293`). Each offset is written as a relative `EKAlarm`
   (`:295-297`).
2. **`applyUndo(_ batch: UndoBatch, calendar: Calendar) throws -> UndoApplied`. Built**
   (`CalendarService.swift:311-373`). One call removes blocks by token UUID and writes blocks from
   drafts, staged with `commit: false` and committed once (`:344-363`), with `store.reset()` on any
   throw (`:364-367`). That is the pattern `deleteAllBlocks` uses (`:438-449`), for the reason its
   comment gives: staged changes survive a thrown error and would be flushed by the next unrelated
   save. It never looks blocks up by `eventIdentifier` (ADR 001); it fetches the Blockey calendar
   over `batch.day` and indexes events by token id, earliest first (`:330-338`). A matched event
   that `Block.isEditable` rejects is not removed and is returned in `leftAlone` (`:349-352`), the
   same refusal as `delete` and the same skip as Clear. A token that finds nothing is in neither
   `removed` nor `leftAlone`, and nothing is deleted for it. Whether a recreated block would overlap
   a fixed event is decided by `DayPlanner` before the call; the batch writes what it is given. If
   the Blockey calendar does not exist and there is nothing to create, it returns an empty result
   rather than creating the calendar (`:321-325`), so every target reads as missing.
3. **`existingTokenIDs(_ ids: Set<UUID>, around day: Date, days: Int, calendar: Calendar) ->
   Set<UUID>`. Built** (`CalendarService.swift:260-269`). Returns which of `ids` have a block, by
   token, in the Blockey calendar from `days` days before `day` to `days` days after it. It does
   not throw: no access, no Blockey calendar or a date it cannot compute all return an empty set
   (`:262`, `:264-265`), and an empty set makes Undo reinsert the task. That is the governing
   rule applied to the lookup: failure means a possible duplicate, never a lost task.
4. **`update`**, only when a `Planning/` caller needs it. Until then the views call
   `CalendarService.update` directly, which is a single-store change and allowed.

The built shapes (`Planning/BlockWriting.swift:4-34`), replacing the draft this ADR first
proposed (`apply`, `searchRange: TimeRange`, `recreate: [Block]`, `notFound`, `recreated`) and
the first built version, which also carried `missing: [UUID]`:

```swift
struct UndoDraft: Equatable, Sendable {
    var title: String
    var range: TimeRange
    var token: BlockToken?        // nil writes no url
    var notes: String?
    var alarmOffsets: [TimeInterval]
}
struct UndoBatch: Equatable, Sendable {
    var day: Date                 // the recorded day, never the selected one
    var removeTokenIDs: [UUID]    // blocks the action created
    var create: [UndoDraft]       // blocks to write back, after the removals
}
struct UndoApplied: Equatable, Sendable {
    var removed: [UUID]           // found and deleted
    var leftAlone: [UUID]         // found, but Blockey cannot edit it (made recurring, say)
    var created: [Block]          // in `create` order
}
func applyUndo(_ batch: UndoBatch, calendar: Calendar) throws -> UndoApplied
func existingTokenIDs(_ ids: Set<UUID>, around day: Date, days: Int, calendar: Calendar) -> Set<UUID>
```

`missing` was removed because it was a third list that had to agree with the other two. The
planner derives the count instead (`UndoOutcome.blocksMissing`, `Planning/DayPlanner.swift:282`:
targeted minus removed minus left alone, floored at zero), so the counts cannot disagree.

The day is a `Date` plus the record's `Calendar`, not a `TimeRange`, so the batch finds the day
the same way `deleteAllBlocks` and `contents` do.

### Undo in `DayPlanner`

`DayPlanner.undo(_ record: UndoRecord) throws -> UndoOutcome`
(`Planning/DayPlanner.swift:643-746`) reverses a stamp, Start over or Fill day. The record is
built by `DayPlanner` itself, inside `stamp` (`:527-530`) and `fillDay` (`:595-597`), so a view
cannot pair one action's result with another day.

- **Single use, spent only on success.** `UndoRecord` is a class (`:225-268`) so every holder sees
  one `isSpent` (`:241`). `undo` returns `UndoOutcome(alreadyUndone: true)` for a spent record and
  does nothing (`:644`). It is marked spent only after `applyUndo` returns (`:699`), so a throw
  leaves the record usable for a retry. Everything after that point is SwiftData work and the
  non-throwing token lookup. A second tap after Start over would otherwise recreate the cleared
  blocks twice. Equality is identity (`:267`). Nothing in it is persisted.
- **Fresh state decides what is safe.** `undo` fetches `contents(for: record.day, ignoring:
  record.hiddenCalendarIDs)` once, before the batch (`:646-648`), using the hidden set from the
  time of the action.
- **Fixed events always win, including new ones.** Cleared blocks are passed through
  `RestoreFilter.split` against the fresh fixed ranges (`:670-672`). A block that would overlap a
  meeting is not written and is listed in `notRestoredFixedConflict`. Ranges are half-open, so
  touching is not a conflict.
- **A cleared block whose returned task is gone is not recreated** (`:662-665`): the user placed
  that task again, and recreating the block would put the work on the calendar twice. Counted in
  `notRestoredTaskPlaced`.
- **An inbox task returned for a cleared block is deleted only if that block is written back.**
  `returnedTasksToDelete` collects ids only for blocks in `split.writable` (`:676-690`, the append
  at `:689`). A block left out for a meeting keeps its inbox task, so the work is never in neither
  place.
- **A cleared block with no inbox task that a meeting now blocks becomes an inbox task**
  (`:713-721`). A template-stamped block, or one typed in Calendar.app, has no source task, so the
  clear made no task for it. Without this it would exist nowhere. It goes on top of the inbox with
  its title, duration and slug; its notes and alarms are not carried, since a task has no field for
  them. It is still counted in `notRestoredFixedConflict`, whose banner text says "kept in the
  inbox".
- **A tokenless cleared block comes back with a fresh token**, `BlockToken(categorySlug: nil)`,
  and is counted in `recreatedWithNewIdentity` (`:681-684`). No slug is invented, so it still
  reads as the fallback category. This reverses the first draft of this ADR, which said a
  tokenless block should come back tokenless. Reason: the user's work comes back either way, and a
  token is what lets a later Undo or edit find it. The cost is that the event gains a url it did
  not have.
- **Blocks Blockey cannot edit are left alone** (`UndoApplied.leftAlone`, counted in
  `blocksLeftAlone`, `:701`). A block the user made recurring in Calendar.app is not deleted by
  Undo, for the same reason Clear skips it. The banner says it was changed in Calendar and left.
- **The SwiftData half runs only after the batch lands** (`:706-708`): it deletes the inbox tasks
  the stamp inserted plus the returned tasks above, skipping any the user has since placed.
- **Fill day reinserts a task unless its block is found by token** (`:723-744`). This replaces the
  first built version, which looked in the day's fetch for an unmatched tokenless block with the
  same title and range and, if it found one, kept the task out. That heuristic is **removed**: a
  hand-made lookalike, or a deleted block that happened to share a title and time with another,
  could swallow a task, which breaks the governing rule. Now, per placement:
  - token id in `applied.removed`: the block is gone, so the task is reinserted;
  - otherwise, token id returned by `existingTokenIDs` over ±7 days of the recorded day
    (`:729-733`): the block is still on the calendar (dragged to another day, or left alone as
    non-editable on this one), so the task is not reinserted and is counted in
    `tasksKeptBecauseBlockSurvived`;
  - otherwise: the block was deleted, or its token was stripped, and the two cannot be told apart.
    The task is reinserted and counted in both `tasksReinserted` and
    `tasksReinsertedBlockUnaccountedFor`, whose banner text says the task is back and its block
    may still be on the calendar. If the token was stripped, that is the documented duplicate.
  The lookup runs only when some placement is unresolved. Reinsertion goes through
  `TaskSnapshot.restore(into:)` (`:79-90`), which never overwrites a live task with the same id.

`UndoOutcome` (`Planning/DayPlanner.swift:271-346`) holds counts the banner can tell the truth
with: `alreadyUndone`, `blocksTargeted`, `blocksRemoved`, `blocksLeftAlone`, `blocksMissing`
(derived), `inboxTasksDeleted`, `tasksReinserted`, `tasksReinsertedBlockUnaccountedFor`,
`tasksKeptBecauseBlockSurvived`, `blocksRecreated`, `recreatedWithNewIdentity`,
`notRestoredTaskPlaced` and `notRestoredFixedConflict: [Block]`. Its `message` gives
`Removed 3 of 4 blocks` and the other banner texts, and is a warning whenever anything was missing,
left alone, kept, unaccounted for or not restored.

### Notes and alarm offsets (owner decision)

- `Block` has `notes: String?` and `alarmOffsets: [TimeInterval]` (`Calendar/Block.swift:46-54`),
  filled in `Block.init(event:blockeyCalendarID:)` (`:64`, `:78-89`) and defaulted in the
  memberwise init.
- A relative alarm is stored as its `relativeOffset`. An absolute-date alarm is stored as its
  offset from the event's start; recreation is at the original range, so that offset is exact. A
  location-based alarm is dropped (`:79-81`), since it has no time to restore.
- **Alarm offsets are a set, kept sorted** (`:87-89`). EventKit does not keep the order alarms
  were added in, and the simulator hands them back reordered, so unsorted offsets would make two
  reads of the same event compare unequal. The fake sorts too.
- **Only `Calendar/` reads them from or writes them to an event.** `Planning/` copies them from a
  `Block` into an `UndoDraft` and back, untouched; `Views/` never touch them. Grep checks:
  `grep -rnE '\.notes\b|alarmOffsets' Blockey/Views` must print nothing, and the same grep over
  `Blockey/Planning` must print only the declarations in `BlockWriting.swift` (`:9`, `:58`) and the
  copy into the draft in `DayPlanner.undo` (`:685-686`). (The first draft's check, "nothing outside
  `Calendar/` and `BlockeyTests/`", could never pass, because `Planning/` has to carry them.)
- `Block` is `Equatable`, so equality includes both fields. Results that hold `[Block]`
  (`ClearResult.removed`, `StampResult.created`) compare them too, and the fake must fill them.

## Consequences

**Becomes easy**
- Undo for stamp, Start over and Fill day is testable against `FakeBlockWriter` and an in-memory
  store (`BlockeyTests/UndoTests.swift`, `BlockeyTests/UndoEdgeCaseTests.swift`), with no event
  store and no simulator.
- Two-store ordering and failure rules live in one file, and a reviewer knows where to look.
- Start over can be undone to the state the user saw, notes and alarms included.
- One rule decides every ambiguous case: if Undo cannot prove the work is still on the calendar,
  the task goes back to the inbox.

**Becomes hard**
- Three things must agree on every protocol change: `CalendarService`, `FakeBlockWriter` and the
  protocol. A fake that drifts from the service makes the tests prove the wrong thing. The fake
  documents each mirrored rule beside the method (earliest event per token, sorted alarms, the
  ±7-day window, the editable check); keep doing that.
- Clear and Start over no longer empty a day that holds a recurring or multi-day block. That is
  the owner's choice. The confirmation dialog (tasks 2.3 and 2.4) should name `ClearResult.kept`,
  or the user will see blocks survive a clear with no explanation.
- The governing rule means the banner sometimes has to say "may still be on your calendar". That
  is honest, not tidy; resist the urge to make it tidy by guessing.

**Known limits, accepted**
- **A stripped token yields a duplicate.** If the user (or a CalDAV round trip, ADR 002) strips a
  Fill-day block's url, Undo cannot find the block and reinserts the task, so the work shows on
  the calendar and in the inbox. The banner says so (`tasksReinsertedBlockUnaccountedFor`). The
  same holds when the token is stripped *and* the block is moved or retitled; nothing about the
  block can then identify it, and the test "a stripped, moved block cannot be found, so its task
  comes back as a documented duplicate" (`UndoEdgeCaseTests.swift:72`) pins it. For a stamp, a
  stripped block is not found and so not removed; it stays on the calendar and reads as missing.
- **A Fill-day block moved more than 7 days away, or dragged into another calendar, yields a
  duplicate.** Moved within ±7 days of the recorded day, `existingTokenIDs` finds it and the task
  stays out (`UndoEdgeCaseTests.swift:58`). Beyond that window, or in a calendar other than
  Blockey's (where the token is ignored and the event reads as fixed, `Block.swift:71-74`), it is
  not found and the task comes back as well. The app cannot move blocks across days, so this
  needs Calendar.app inside the undo window.
- **Duplicates in Calendar.app.** `applyUndo` removes only the earliest event per token on the day
  (`CalendarService.swift:332-338`). A block the user duplicated in Calendar.app keeps its url, so
  two events share a token; the later one is treated as the user's own copy and left alone. For a
  Fill-day block that means the task is reinserted (the token was removed) while the copy stays.
- Not restored exactly: a url on a tokenless event that is not a Blockey token (a meeting link,
  say) is replaced by a fresh token; location, availability and any other `EKEvent` field are not
  carried; a block whose title was nil comes back titled `(no title)` (`Block.swift:69`); the
  recreated event has a new `eventIdentifier`, so its `Block.id` changes; a cleared block that
  comes back as an inbox task because of a meeting loses its notes and alarms.

**Verification, and what is fake-tested only**
- Unit tests: `BlockeyTests/UndoTests.swift` (suites `Undo` and `RestoreFilter`),
  `BlockeyTests/UndoEdgeCaseTests.swift` (suite `Undo edge cases`),
  `BlockeyTests/BlockNotesAlarmsTests.swift` and `BlockeyTests/TaskSnapshotRestoreTests.swift`.
- **`-blockeyUndoExercise`** (`Models/DemoScenario.swift:40-43`, `:52-133`) runs Undo through the
  real `CalendarService` in the simulator. It is inside the file's
  `#if DEBUG && targetEnvironment(simulator)` gate and is called from `DemoScenario.apply`
  (`:141`), so it needs `-blockeyDemo` as well (`Views/TodayView.swift:207-208`); no script passes
  it. It works on the day two days after the selected date (`:55`), clears the days it touched
  afterwards, and writes PASS/FAIL lines to `undo-exercise.txt` in the app's temporary directory
  (`:131-132`). It covers: Start over then Undo with the original token restored verbatim (id,
  slug, source task, unknown query item), notes, sorted alarm offsets and range; a tokenless block
  recreated with a fresh token and its notes; the returned inbox task deleted; a second Undo doing
  nothing; `existingTokenIDs` finding a token 5 days out and not one 9 days out or an unknown one
  (`:103-117`); and a stamp with one block deleted reading `Removed 2 of 3 blocks`.
- It does not cover Fill-day undo end to end, the fixed-conflict path, `leftAlone` (a block made
  recurring through EventKit), or a failure mid-batch. **The mid-batch `store.reset()` path and
  `leftAlone` are tested only against the fake** (`UndoTests.swift:437-455` and `:457-471`). The
  fake's staging-on-a-copy stands in for `commit: false` plus `reset()`, and its `makeRecurring`
  stands in for `hasRecurrenceRules`. No test has made EventKit throw part-way through a real
  batch.

**Cannot undo**
- Nothing here is stored. `notes` and `alarmOffsets` are read from the calendar and written back to
  it, and `UndoRecord` lives only as long as the banner that offers it; no new data lives in
  SwiftData.
- A tokenless block that Undo recreated keeps its new token. That is a one-way change to the
  user's event, though a harmless one (ADR 002: losing or gaining a token is cosmetic).
- A duplicate task Undo reinserted stays until the user deletes it. That is the price of the
  governing rule, chosen over the alternative of losing it.

**Escape hatch**
Inline `DayPlanner` back into `TodayView` and delete the `BlockWriting` protocol and its conformance
file. The methods already take explicit inputs and return values, so inlining is mechanical, and
`CalendarService` keeps every method it has. What is lost is the fake-backed Undo tests, which is
the reason this layer exists. No data migration in either direction. Backing out of "Skip them"
alone is one filter in `deleteAllBlocks` (`CalendarService.swift:434`) and the `leftAlone` guard in
`applyUndo` (`:349-352`), but it makes Start over irreversible for recurring blocks.

## Build order

1. `backend-engineer`: `notes` and `alarmOffsets` on `Block` and `FakeBlockWriter.seedBlock`.
   **Built, uncommitted.**
2. `backend-engineer`: `createBlock(token:)` on the protocol, `CalendarService` and the fake,
   with a tokenless round trip and unknown query items kept. **Built, uncommitted.**
3. Owner: yes or no on Clear leaving non-editable events in place. **Decided 2026-11-03: "Skip
   them"** (commit 87734d9's message, recorded at the top of this ADR).
4. `backend-engineer`: `UndoBatch`, `applyUndo`, `existingTokenIDs` and `DayPlanner.undo` under the
   governing rule, with an injected mid-batch failure and the edge-case suite. **Built,
   uncommitted; QA review in progress.**
5. `frontend-engineer`: the Undo banner (plan tasks 2.5 and 3.1), calling `DayPlanner` only, and
   dropping the record when a later banner replaces it (plan test
   `undoRecordDroppedWhenBannerReplaced`, not yet written). The Clear and Start-over confirmation
   (tasks 2.3 and 2.4) names `ClearResult.kept`.
6. `qa-engineer` and `architect`: phase 5.1. Run the grep checks above and `-blockeyUndoExercise`
   on the simulator before this ADR is marked accepted. Consider extending the exercise to Fill-day
   undo and `leftAlone` (a recurrence rule set through EventKit on the simulator), the two
   real-service paths still unexercised.
