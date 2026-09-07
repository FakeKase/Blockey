# ADR 001: Blocks are calendar events

Status: accepted
Date: 2026-09-07

## Context

Blockey schedules time blocks on an iPhone. Every block must show up in Apple Calendar so it
reaches the Lock Screen, Watch and CarPlay without Blockey running. Blocks must also be editable
from Calendar.app, because that is where the user already is when a meeting moves.

Three constraints shape this decision, and only one of them is a preference:

1. **Free Apple ID sideloading.** No App Groups, no CloudKit, no widgets, no Live Activities.
   The signing certificate expires every 7 days, so the app is reinstalled roughly weekly.
   Assume each reinstall wipes the app sandbox. (In practice an upgrade-install over the same
   bundle ID often preserves the container, but that is not something to bet the schedule on.)
2. **Solo developer, no ops.** Nobody is on call for a sync engine. A reconciliation bug that
   duplicates or drops a block is the kind of thing that quietly destroys trust in the app and
   takes a weekend to find.
3. **The user's schedule must outlive the app's sandbox.** This is the constraint that actually
   forces the decision. Anything stored only in SwiftData is gone every Tuesday.

## Options

### A. EventKit is the source of truth. A block *is* an `EKEvent` in a dedicated "Blockey" calendar.

Costs: `EKEvent` has no custom fields, so app-level metadata needs a side channel (ADR 002).
Every read is an asynchronous, permission-gated EventKit fetch — no `@Query`, no free SwiftUI
reactivity. `EKEvent` instances go stale on `.EKEventStoreChanged` and must be refetched, never
held. The block domain is no longer closed: Calendar.app can inject all-day, multi-day,
zero-length and recurring events into the Blockey calendar, and the app must render them without
crashing. Blocks cannot be unit-tested without a live store.

Buys: two-way sync costs zero lines — editing in Calendar.app *is* editing the block, and the app
just refetches on the change notification. There is no conflict resolution, because there is only
one copy. The schedule is backed up in iCloud, outside the sandbox, so the weekly reinstall costs
nothing that matters. Alarms come free via `EKAlarm`. Lock Screen, Watch and CarPlay come free.

### B. SwiftData is the source of truth, mirrored into EventKit.

Costs: a real sync engine. Change tokens, dirty flags, tombstones, last-writer-wins rules, and a
reconciliation pass that has to answer "the user moved this in Calendar.app and I also moved it —
now what?" That is the single largest source of bugs in this app, and it is a source of bugs that
only exists because of this choice. Worse under the sideloading constraint: the local half of the
mirror is destroyed weekly, so every reinstall starts with a full re-import from EventKit — which
means the import path has to be correct anyway, and it has to guess which events it previously
created.

Buys: real custom fields, `@Query`-driven SwiftUI, testable in memory, and the app owns its schema.

### C. SwiftData is the source of truth, EventKit is a write-only publish target.

Costs: edits made in Calendar.app are silently reverted or silently ignored — the worst possible
behaviour, because Calendar.app looks like it worked. Still loses everything weekly.

Buys: simplest code of the three. Genuinely fine for an app that only ever *publishes* a plan.
Not fine here: "move a block when a meeting shifts" is a core interaction, and it will happen in
Calendar.app as often as in Blockey.

## Decision

**A. EventKit is the source of truth for scheduled blocks.** A block is an `EKEvent` in a
dedicated "Blockey" calendar, found-or-created at launch, preferring an iCloud `EKSource` and
falling back to the local source.

SwiftData holds only what EventKit has no place for: tasks, categories, day templates, settings,
and a `BlockMeta` cache (ADR 002). SwiftData never stores a copy of a block's title, time or
duration. There is exactly one copy of that data and it lives in the calendar database.

The calendar fallback matters and is not a downgrade in the case that matters most: even a local
`EKSource` calendar lives in the system calendar store, outside the app sandbox, so blocks survive
the weekly reinstall either way. Choosing iCloud additionally buys cross-device sync and a
server-side backup.

**Layering rule (this is the escape hatch, so it is a rule, not a suggestion):** nothing above
`Calendar/CalendarService.swift` ever sees an `EKEvent`. `CalendarService` returns `Block`, an
immutable value type, and accepts intent — `create`, `move`, `resize`, `delete`. `Scheduling/`
contains no EventKit and no SwiftUI; it is pure functions over time ranges. `Views/` speaks
`Block` and `Task` only.

## Consequences

**Becomes easy**
- Two-way sync, backup, alarms, Lock Screen / Watch / CarPlay: all free, all zero lines.
- The weekly reinstall stops being a data-loss event for the thing the user cares about most.
- No sync engine means no sync bugs. The hardest logic left in the app (gap-finding, collision,
  template stamping) is pure and unit-testable, which is exactly where the tests should go.
- "Which calendars are fixed events" and "which calendar is Blockey" is one uniform mechanism.

**Becomes hard**
- No SwiftUI reactivity for blocks. `CalendarService` must be an `@Observable` that owns a fetched
  window of `Block`s and refetches on `.EKEventStoreChanged`. Debounce it — the notification fires
  in bursts during sync.
- Never hold an `EKEvent` across a change notification. Apple is explicit: *"You should generally
  consider all EKEvent instances to be invalid as soon as you receive the notification."* Fetch,
  map to `Block`, discard the `EKEvent` in the same function.
- Never persist an EventKit identifier (see ADR 002). Blocks are found by fetching the Blockey
  calendar over a date range, always.
- The app must tolerate hostile input in its own calendar: all-day, multi-day, zero-duration and
  recurring events created by Calendar.app. v1 policy: render them read-only in the timeline,
  exclude them from gap arithmetic as if they were fixed events, and never write to them.
- EventKit permission is a first-run gate with a hard failure mode. There is no degraded
  "local-only" mode; if access is denied the app has nothing to show. Accept this and write a
  clear denied-state screen rather than building a fallback store.

**Cannot undo**
- Blocks created in the user's iCloud calendar are the user's data forever. Deleting Blockey does
  not remove them. There is no "uninstall cleans up" story, and there should not be one.
- If the user deletes the "Blockey" calendar in Calendar.app, every block is gone and the app
  holds no backup by construction. This is the accepted cost of having exactly one copy. Mitigate
  only by naming the calendar clearly and re-creating it on launch — do not build a shadow copy,
  because a shadow copy is option B wearing a trenchcoat.

**Escape hatch**
If EventKit turns out to be unworkable, the seam is the `Block` value type. Introduce a
`BlockStore` protocol with the three methods `CalendarService` already exposes, add a SwiftData
implementation behind it, and keep the EventKit implementation as a read-only import source.
`Scheduling/` and `Views/` do not change. No data migration is required in either direction,
because EventKit remains readable regardless. The cost of backing out is roughly one file plus a
sync engine — i.e. exactly the cost of having chosen option B on day one, paid later. That is an
acceptable one-way door: it is expensive to reverse but not destructive, and nothing is lost.
