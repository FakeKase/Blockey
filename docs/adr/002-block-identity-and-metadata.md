# ADR 002: Block identity and metadata

Status: accepted
Date: 2026-09-07

## Context

ADR 001 makes the block an `EKEvent`. `EKEvent` has no custom fields and no extension mechanism —
EventKit exposes no per-item user data, no x-properties, nothing. Blockey still needs two things
the calendar cannot express:

- **Category colour** — which bucket this block belongs to, so the timeline is readable at a glance.
- **Source task** — the inbox task this block was placed from, so unscheduling returns it to the
  inbox with its duration intact.

The plan proposes `event.url = blockey://block/<uuid>` as durable identity, plus a local `BlockMeta`
record keyed by that UUID. This ADR pressure-tests that and pins down the failure behaviour, because
under free-provisioned sideloading one of the failure modes is not an edge case — it is scheduled
for next Tuesday.

### What was verified, and what was not

Verified from the iOS SDK headers shipped with Xcode
(`iPhoneOS.sdk/System/Library/Frameworks/EventKit.framework/Headers/`):

- `EKEvent.eventIdentifier` — *"Please note that if you change the calendar of an event, this ID
  will likely change. It is currently also possible for the ID to change due to a sync operation.
  For example, if a user moved an event on a different client to another calendar, we'd see it as a
  completely new event here."* It is also documented as possibly `nil` for unsaved events.
- `EKEvent.refresh()` — *"When the database changes, your application is sent an
  EKEventStoreChangedNotification note. You should generally consider all EKEvent instances to be
  invalid as soon as you receive the notification."*
- `EKCalendarItem.calendarItemIdentifier` — *"Item identifiers are not sync-proof in that a full
  sync will lose this identifier, so you should always have a back up plan for dealing with a
  reminder that is no longer fetchable by this property."*
- `EKCalendarItem.calendarItemExternalIdentifier` — server-provided, read-only, `nil` until the item
  belongs to a calendar, *"the same for all occurrences of a recurring event"*, and explicitly
  non-unique in several duplication scenarios.
- `EKCalendarItem.URL` is a settable `NSURL?` (iOS 5+) and `notes` a settable `String?`. Both are
  ordinary writable properties, not computed or restricted.

Verified from Apple support documentation: both the iOS Calendar.app event editor and the
iCloud.com Calendar web editor expose **URL** and **Notes** as first-class user-editable fields.
iCloud stores calendar data as CalDAV `.ics` resources, and `URL` is a standard RFC 5545 `VEVENT`
property, so it has a defined place in the wire format.

**Not verified — treat as unproven:**

- **Whether a non-`http(s)` scheme survives a full round trip through Calendar.app and iCloud
  CalDAV verbatim.** RFC 5545 defines `URL` as a URI, so `blockey://…` is legal, and iCloud stores
  the `.ics` rather than a reduced model — but no public documentation or first-hand report confirms
  that iCloud, Calendar.app, or the iCloud.com web editor preserve a custom scheme without
  normalising it (e.g. prepending `https://`) or dropping it. Nothing found says it fails either.
  This is the single load-bearing unknown in this ADR and it is resolved by experiment, not by
  reading (see *Build order*).
- **Whether `calendarItemExternalIdentifier` is stable on iCloud specifically.** Apple's own forum
  thread on this reports it changing after sync on Exchange, and "changes in some situations" on
  iCloud and Google even after iOS 9 improvements. Contradictory first-hand reports, no Apple
  statement of stability. Treat as unstable.

The design below is built so that *if the unverified claim turns out false, the app still works*.
That is the point of it.

## Options

### A. `eventIdentifier` as the persisted key
Costs: contradicted directly by the SDK header — it changes on calendar move and can change on
sync. Any persisted map from `eventIdentifier` to metadata silently rots. Buys: zero extra fields.
**Rejected on the documentation, not on suspicion.**

### B. `calendarItemExternalIdentifier` as the persisted key
Costs: read-only and `nil` until first save, so metadata cannot be written in the same pass as
creation. Identical for every occurrence of a recurring event. Reported unstable across sync on at
least Exchange, with mixed reports elsewhere. Buys: no visible pollution of the event at all — the
cleanest option if it were reliable, and it is not.

### C. A token the app controls, written into `url`, plus a local `BlockMeta` cache
Costs: user-visible in Calendar.app; the user can overwrite or delete it; unproven CalDAV
round-trip. Buys: the app assigns the identity itself, at creation, before any save; it is stable by
construction because nothing but the user can change it; and a `blockey://` scheme registered in
Info.plist makes the token a working deep link from Calendar.app back into the block.

### D. Same, but the token lives in `notes`
Costs: `notes` is the field a human actually writes in. A token line sitting above the user's own
notes is clutter they will eventually delete, and any "select all, retype" in that field destroys
it. Buys: can carry structured multi-field data, and is the more conservative choice if custom
schemes turn out not to survive CalDAV.

## Decision

**C, with the category carried in the token itself.**

```
blockey://block/<uuid>?c=<category-slug>
```

- `<uuid>` is a v4 UUID generated by Blockey at block creation. It is the block's app-level
  identity. It is stable because only the user can change it.
- `?c=<category-slug>` is a **self-describing hint**, not a foreign key. The slug is immutable once
  a Category is created; the category's display name and colour stay editable in the app without
  invalidating any existing block.

**Identity is tiered, and only the first tier is allowed to be load-bearing:**

| Tier | Question | Mechanism | Reliability required |
|---|---|---|---|
| 1 | Is this event a block? | Membership in the Blockey calendar | Absolute |
| 2 | What is its colour? | `?c=` slug, else `BlockMeta`, else default | Best effort |
| 3 | Which task did it come from? | `BlockMeta` keyed by uuid | Best effort |
| 4 | Re-find the event I just touched | `eventIdentifier`, within one fetch cycle | Session-scoped only |

The consequence that makes everything else simple: **Blockey persists no EventKit identifier,
anywhere, ever.** Blocks are always found by fetching the Blockey calendar over a date range. There
is no stored list of "my event IDs" to go stale, so the entire `eventIdentifier` stability problem
is designed out rather than defended against. `eventIdentifier` is carried on the in-memory `Block`
value and used only to address a save or delete within the same fetch cycle; a stale one makes
`event(withIdentifier:)` return `nil`, which is handled as "refetch and retry once, then tell the
user the block changed underneath them."

### Contract

```swift
// Calendar/Block.swift — a value type, rebuilt from EKEvent on every fetch, never persisted.
struct Block: Identifiable, Hashable {
    let eventID: String        // EKEvent.eventIdentifier. SESSION-SCOPED. Never written to disk.
    let blockID: UUID?         // parsed from url; nil if absent, mangled, or user-overwritten
    let categorySlug: String?  // parsed from url query
    var title: String
    var start: Date
    var end: Date
    let isEditable: Bool       // false for all-day / recurring / multi-day intruders (ADR 001)
}

// Calendar/BlockToken.swift — the ONLY place that knows the token format.
enum BlockToken {
    static func make(_ id: UUID, category: String?) -> URL
    static func parse(_ event: EKEvent) -> (id: UUID, category: String?)?
}

// Models/BlockMeta.swift — a cache. Losing it is a supported state, not an error.
@Model final class BlockMeta {
    @Attribute(.unique) var blockID: UUID
    var sourceTaskID: UUID?
    var lastKnownStart: Date   // fetch hint + garbage-collection key
    var updatedAt: Date
}
```

`BlockMeta` deliberately does **not** store the category — the token carries it. `BlockMeta` exists
for exactly one thing that cannot ride in the URL: the link back to an inbox task, whose identity is
meaningless outside the local database anyway.

Garbage collection: on launch, delete every `BlockMeta` with `lastKnownStart` more than 30 days in
the past. Bounded growth, one line, no orphan tracking.

## Consequences

### 1. `eventIdentifier` stability

Apple states it changes on calendar move and *can* change on sync. Because nothing persists it, this
is a non-event. Within a fetch cycle it works; across one, the app refetches anyway. If a sync
renumbers every block in the Blockey calendar overnight, Blockey notices nothing the next morning.

The one place it can still bite: a block detail sheet held open across an `.EKEventStoreChanged`
burst. Rule — on that notification, refetch the window and re-resolve the open sheet's block by
`blockID` (tier 2), not by `eventID`. If it cannot be re-resolved, dismiss the sheet.

### 2. Editing and deleting in Calendar.app

- **Time, title or alarm edited in Calendar.app** — same record, `url` untouched, token intact.
  Blockey refetches on the change notification and shows the new time. This is the whole payoff of
  ADR 001 and it costs zero lines.
- **Moved to a different calendar** — it stops being a block, by definition, because tier 1 is
  calendar membership. It reappears as a fixed event. Correct behaviour, again zero lines. Its
  `BlockMeta` is orphaned and gets collected in 30 days.
- **Deleted in Calendar.app** — the next fetch does not return it. If its `BlockMeta` carried a
  `sourceTaskID`, that task must return to the inbox. This is the *only* reconciliation logic in the
  app, and it is small enough to state completely: after each fetch of a day window, for every
  `BlockMeta` whose `lastKnownStart` falls inside that window and whose `blockID` is absent from the
  fetched blocks, mark its source task unscheduled and delete the `BlockMeta`. Scoped to the fetched
  window, so a block a month out is never mistaken for deleted.
- **Made recurring in Calendar.app** — every occurrence carries the same token and the same
  `calendarItemExternalIdentifier`. Colour resolves correctly for all of them; a source-task link
  would be wrong (one task, N blocks). Rule: ignore `sourceTaskID` for any event with a recurrence
  rule. v1 never creates recurring blocks.
- **URL field edited or cleared by the user** — the token is gone. The block still renders, in the
  default colour, and unlinks from its task. Degraded, never broken. See 3.
- **`url` round trip through iCloud CalDAV** — unproven, per *Context*. If it fails, every block
  loses its token on the first sync and the app permanently renders default-coloured blocks with no
  task links. Still functional, still not acceptable. Resolved by the Phase 2 experiment below; the
  fallback is option D, and because `BlockToken` is the only file that knows the format, the swap is
  one file plus a read-side fallback that keeps existing blocks resolvable.

### 3. `BlockMeta` loss — the weekly case

This is not a hypothetical; assume it happens every 7 days.

A sandbox wipe does not lose `BlockMeta` in isolation — it loses **`BlockMeta`, tasks, categories,
templates and settings together**. That is fortunate, and worth stating explicitly, because it rules
out the genuinely nasty failure: a partial loss where a task reappears in the inbox while its block
still sits on the calendar, producing a duplicate. A total wipe cannot produce that, because the
task is gone too.

After a wipe, on first launch:
- Every block renders — correct title, time, duration, alarm. The calendar was never in the sandbox.
- Categories are **reconstructed from the blocks themselves**: each distinct `?c=` slug encountered
  becomes a Category with a title-cased name and a colour chosen deterministically from a hash of
  the slug into a fixed palette. Colours therefore come back *identical* to before the wipe with no
  backup of any kind. This is the reason the slug rides in the token instead of in `BlockMeta`.
- `sourceTaskID` links are gone, harmlessly — the tasks are gone too.
- Templates, tasks and settings are gone, and nothing brings them back.

**That last line is the real problem, and it is larger than this ADR's subject.** The plan's
one-tap morning pass depends on templates; templates being erased weekly destroys the app's core
value proposition, and no amount of EventKit cleverness fixes it because templates are not calendar
data. The only mechanism available without paid-account entitlements is a user-driven
`UIDocumentPicker` export/import of a single JSON file (which the user can point at iCloud Drive).
It needs no entitlement and no App Group. It should be built earlier than the plan's Phase 5 —
see *Build order*. Blocks were always safe; tasks and templates never were.

### 4. `url` versus `notes`

Both are user-visible and user-editable in Calendar.app and on iCloud.com, so neither is safe. The
question is only which one the user is *likelier to touch*.

`notes` loses: it is the field a person writes in. A machine token pinned above someone's own notes
on a block is clutter they will eventually delete, and it is destroyed by any wholesale retype of
that field. `url` on a self-created time block is a field the user has no reason to fill in — and
when they do have a reason (pasting a call link onto a block), losing the token is the correct
trade, because the user's link matters more than the app's colour hint.

`url` also buys something `notes` cannot: register `blockey` as a URL scheme in Info.plist and the
token becomes a live deep link — tap the URL on a block in Calendar.app and Blockey opens that
block. A free feature falling out of the identity mechanism.

Accepted costs: `blockey://block/…?c=deep-work` is visible clutter on the event; one user edit
silently orphans the metadata; and the custom scheme's CalDAV survival is unproven.

**Escape hatch:** `BlockToken` is the only file that knows the format. If Phase 2 shows the URL does
not round-trip, change `make` to write a `notes` trailer line and add a read-side fallback (`url`
first, then a token line in `notes`), so blocks written under the old scheme keep resolving. If
custom schemes specifically are the problem but the field survives, switch to
`https://blockey.local/b/<uuid>?c=<slug>` — same parse, no normalisation risk, but the deep link is
lost. Nothing above `CalendarService` changes in any of these cases.

## Build order

Amends the plan's build order. Two changes, both earned above.

0. **Skeleton** — project, bundle ID `com.kase.blockey`, `NSCalendarsFullAccessUsageDescription`,
   and register the `blockey` URL scheme now so the deep link can be tested in Phase 2.
1. **Read-only Today** — access, fetch, timeline of fixed events, now-line, day navigation.
2. **Blocks** — find-or-create the Blockey calendar; create, move, resize, delete; `BlockToken`;
   refresh on `.EKEventStoreChanged`.
   **2a. Run the token round-trip experiment before writing any more code that depends on it.**
   Create a block in Blockey. Confirm the URL field in Calendar.app reads
   `blockey://block/<uuid>?c=test` verbatim and is tappable. Edit the block's time in Calendar.app
   and save. Force an iCloud sync and confirm the token is unchanged on iCloud.com and on a second
   device if one is available. Refetch in Blockey and confirm the token still parses. Record the
   result as an addendum to this ADR, including whether `eventIdentifier` changed. If the token does
   not survive, take the escape hatch above before proceeding.
3. **Inbox** — SwiftData tasks, quick-add, tap-to-place, drag-to-place, unschedule, Fill day.
   Includes the `BlockMeta` deletion-reconciliation pass described in Consequence 2.
   **3a. JSON export/import via `UIDocumentPicker`, and a first-launch "restore from file" prompt.**
   Moved forward from Phase 5. Without it the weekly reinstall erases every task and template, and
   Phase 4 is not worth building.
4. **Templates** — model, editor, weekday assignment, stamping with the fixed-events-win rule.
5. **Polish** — categories and colours (including the hash-from-slug reconstruction in
   Consequence 3), day window, alarm toggle, empty states, haptics; install on device.
