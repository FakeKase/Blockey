# ADR 007: The planning layer and the BlockWriting seam

Status: proposed. Not to be marked accepted until phase 5.1 of `docs/feedback-plan-2026-11.md`
has checked every mechanism named here against the code.
Date: 2026-11-03

Owner decision (2026-11-03): undoing Start over restores each cleared block's Calendar.app notes
and alarm offsets exactly, not just its title, time and token. So `Block` will carry `notes` and
`alarmOffsets`, and only `Calendar/` reads them.

## Context

Task 2.0 of the feedback plan (commit c0df6e5) moved stamp, replace, fill, clear, place and
return-to-inbox out of `TodayView` into `DayPlanner`, in a new `Blockey/Planning/` folder, behind a
new `BlockWriting` protocol. That was a refactor with characterisation tests
(`BlockeyTests/DayPlannerTests.swift`, `BlockeyTests/DayPlannerEquivalenceTests.swift`), done so
Undo (plan tasks 2.2 onwards) can be tested against a fake. It also created a folder and a seam
that no ADR describes. This ADR writes down what they are for, before Undo grows them.

Statements about the code below were checked against c0df6e5. `DayPlanner` is changing in
parallel, so it is cited by symbol, never by line.

### What the code does today

- `BlockWriting` (`Planning/BlockWriting.swift:9-27`) is `@MainActor` and has four members:
  `createBlock(title:range:categorySlug:sourceTaskID:alarmMinutesBefore:)`, `delete(_:)`,
  `deleteAllBlocks(on:calendar:)` and `contents(for:ignoring:calendar:)`. It names no EventKit type.
- `CalendarService` conforms with an empty extension in `Calendar/`
  (`Calendar/CalendarService+BlockWriting.swift:6`), because it already had those exact signatures.
  `update` (`CalendarService.swift:257-284`) is deliberately not in the protocol: nothing in
  `DayPlanner` calls it.
- `DayPlanner` holds `writer: any BlockWriting` and a `ModelContext`. It imports Foundation and
  SwiftData only. `BlockWriting.swift` imports Foundation only.
- The tests' stand-in is `BlockeyTests/FakeBlockWriter.swift:8`.
- Every action that touches both stores now goes through `DayPlanner`: `stamp` and `replace`
  (calendar writes, then inbox inserts for rows that did not fit or failed), `clear` (calendar
  delete, then inbox inserts for blocks with a source task), `fillDay` and `place` (calendar write,
  then task delete), `returnToInbox` (calendar delete, then task insert). A grep for
  `createBlock`, `delete(`, `deleteAllBlocks`, `context.insert` and `context.delete` under
  `Blockey/` finds no other place that does both in one action, with one exception:
  `Models/DemoScenario.swift:44`, `:57` and `:70`, which is compiled only under
  `#if DEBUG && targetEnvironment(simulator)` (`:4`) and is not a user action.
- In every `DayPlanner` method the calendar step runs first and SwiftData changes only follow a
  calendar step that succeeded. The calendar is the side that throws; context inserts and
  deletes do not throw and are persisted later by autosave.

### What Undo will need that the seam cannot do yet

- **Recreate a block with its old token.** `createBlock` always mints a new token:
  `CalendarService.swift:241` builds `BlockToken(categorySlug:sourceTaskID:)`, whose `id` defaults
  to `UUID()` (`BlockToken.swift:49`). The plan's Start-over rule needs the original token UUID back.
- **Undo several things at once.** Start over removes the stamped blocks, recreates the cleared
  ones and deletes the inbox tasks the clear inserted. Doing that as separate calls can leave a
  half-undone day.
- **Keep notes and alarms.** `Block` has no notes or alarm fields (`Block.swift:23-44`), so the
  `[Block]` that `deleteAllBlocks` returns (`CalendarService.swift:309`) has already lost them.
  `createBlock` writes at most one relative alarm (`:248-250`).

### The constraint

**Correctness of a destructive action's reverse.** Undo is only worth shipping if it puts back what
was there. A half-applied undo, or one that duplicates inbox tasks, is worse than no Undo. Speed of
delivery is secondary: the seam already exists and only needs to grow.

## Options

### A. Keep `Planning/` and grow `BlockWriting` only when a caller needs it

`Planning/` stays a coordinator layer between the views and both stores. The protocol gains the
three things Undo needs and nothing speculative. Costs: one more folder rule to keep, and a protocol
that must stay in step with `CalendarService` and the fake. Buys: Undo is testable without an event
store, which is the only way it can be tested at all, and the two-store rules live in one file.

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
  button, its move and resize, and the inbox's add and delete do today.
- Order inside an action stays as it is: the calendar step first, SwiftData only after it
  succeeds. A new action that has to do it the other way round needs a written reason.
- One module means the compiler cannot enforce any of this. `Planning/` already uses types
  declared in files that import SwiftUI (`BlockCategory`, `Models/BlockCategory.swift:1`) and
  EventKit (`Block`, `Calendar/Block.swift:2`). The rule is about what `Planning/` files import and
  name, and it is checked by grep in review:
  `grep -rnE 'import (SwiftUI|EventKit)|\bEK[A-Z]' Blockey/Planning | grep -v '///'` must print
  nothing. The second filter is there because `BlockWriting.swift:8` names `EKEvent` in a doc
  comment, to say where it lives.

### `BlockWriting` is the first slice of ADR 001's `BlockStore`

ADR 001's escape hatch is a `BlockStore` protocol over `Block`. `BlockWriting` is that protocol,
started small and named for what `Planning/` does with it. It grows only when a caller in
`Planning/` needs a method, and every addition lands in `CalendarService` (in `Calendar/`), in
`FakeBlockWriter`, and in a test, together. The planned growth, in order:

1. **`createBlock(token:)`.** Write a block with a given token, title, range, notes and alarm
   offsets, keeping the token's UUID, slug, source task and unknown query items. A nil token writes
   no url, so a tokenless block comes back tokenless rather than gaining an identity it never had.
2. **An atomic, token-keyed undo batch.** One call that removes blocks by token UUID and recreates
   blocks from snapshots, staged with `commit: false` and committed once, with `store.reset()` on
   failure. That is the pattern `deleteAllBlocks` already uses (`CalendarService.swift:311-322`),
   for the reason its comment gives: staged changes survive a thrown error and would be flushed by
   the next unrelated save. It never looks blocks up by `eventIdentifier` alone (ADR 001); it finds
   them by token the way `event(for:)` falls back to doing (`CalendarService.swift:420-430`). It
   returns what it could not find, so the banner can say `Removed 3 of 4 blocks`. Whether a
   recreated block would overlap a fixed event is decided by `DayPlanner` before the call, from a
   fresh `contents(for:)`; the batch writes what it is given.
3. **`update`**, only when a `Planning/` caller needs it. Until then the views call
   `CalendarService.update` directly, which is a single-store change and allowed.

A shape for the first two, to agree before building. Exact names are the backend engineer's call:

```swift
// Planning/BlockWriting.swift
func createBlock(token: BlockToken?, title: String, range: TimeRange,
                 notes: String?, alarmOffsets: [TimeInterval]) throws -> Block

struct UndoBatch: Sendable {
    var removeTokenIDs: [UUID]   // blocks this action created
    var recreate: [Block]        // blocks this action removed, as they were
    var searchRange: TimeRange   // the recorded day, never `selectedDate`
}
struct UndoOutcome: Equatable {
    var removed: [UUID]
    var notFound: [UUID]         // deleted or token stripped since
    var recreated: [Block]
}
func apply(_ batch: UndoBatch) throws -> UndoOutcome   // all or nothing on the calendar side
```

The SwiftData half of an undo (deleting the inbox tasks the action inserted, reinserting the tasks
it deleted from their `TaskSnapshot`s) stays in `DayPlanner` and runs only after `apply` returns.

### Notes and alarm offsets (owner decision)

- `Block` gains `notes: String?` and `alarmOffsets: [TimeInterval]`, filled in
  `Block.init(event:blockeyCalendarID:)` (`Block.swift:54`) from `event.notes` and `event.alarms`.
- A relative alarm is stored as its `relativeOffset`. An absolute-date alarm is stored as its
  offset from the event's start. Recreation is at the original range, so that offset is exact.
- **Only `Calendar/` reads them.** `Planning/` carries them inside a `Block` and passes them back
  untouched; `Views/` never read them. Grep check: `\.notes\b|alarmOffsets` outside `Calendar/`
  and `BlockeyTests/` must print nothing.
- `Block` is `Equatable`, so equality now includes both fields. Results that hold `[Block]`
  (`ClearResult.removed`, `StampResult.created`) compare them too, and the fake must fill them.

## Consequences

**Becomes easy**
- Undo for every planning action is testable against `FakeBlockWriter` and an in-memory store,
  with no event store and no simulator.
- Two-store ordering and failure rules live in one file, and a reviewer knows where to look.
- Start over can be undone to the state the user saw, notes and alarms included.

**Becomes hard**
- Three things must agree on every protocol change: `CalendarService`, `FakeBlockWriter` and the
  protocol. A fake that drifts from the service makes the tests prove the wrong thing. The fake
  already documents each mirrored rule beside the method; keep doing that.
- **Clear deletes events Blockey otherwise refuses to touch.** `deleteAllBlocks` filters out only
  all-day events (`CalendarService.swift:308`), so a recurring occurrence or a timed multi-day event
  in the Blockey calendar is removed, while `delete` refuses the same event as not editable
  (`:288`). ADR 001's v1 policy is to "never write to them". Recreating one from a `Block` would
  give back a one-off event with its recurrence rule gone, so Undo cannot be exact for it. Proposed:
  `deleteAllBlocks` skips non-editable events as it already skips all-day ones, and Clear reports
  them as left in place. This changes Clear and needs the owner's yes before it is built.
- Not restored exactly, even after this ADR: a url on a tokenless event that is not a Blockey token
  (a meeting link, say), location, availability and any other `EKEvent` field. A block whose
  title was nil comes back titled `(no title)` (`Block.swift:59`).

**Cannot undo**
- Nothing here is stored. `notes` and `alarmOffsets` are read from the calendar and written back to
  it; no new data lives in SwiftData.

**Escape hatch**
Inline `DayPlanner` back into `TodayView` and delete the `BlockWriting` protocol and its conformance
file. The methods already take explicit inputs and return values, so inlining is mechanical, and
`CalendarService` keeps every method it has today. What is lost is the fake-backed Undo tests,
which is the reason this layer exists. No data migration in either direction.

## Build order

1. `backend-engineer`: add `notes` and `alarmOffsets` to `Block`, filled in `init(event:)` and
   defaulted in the memberwise init, and to `FakeBlockWriter.seedBlock`. Starts now; it touches no
   `DayPlanner` code.
2. `backend-engineer`: tests, then `createBlock(token:)` on the protocol, `CalendarService` and the
   fake, including a tokenless round trip and unknown query items kept.
3. Owner: yes or no on Clear leaving non-editable events in place. Blocks step 4's Start-over tests
   for those events only.
4. `backend-engineer`: tests, then `UndoBatch` and `apply`, with an injected failure that proves
   nothing is half-committed. Then the `DayPlanner` undo methods on top.
5. `frontend-engineer`: the Undo banner (plan section 3.1), calling `DayPlanner` only.
6. `qa-engineer` and `architect`: phase 5.1. Run both grep checks above before this ADR is marked
   accepted.
