# ADR 006: Title suggestions read from the calendar

Status: proposed. Not to be marked accepted until phase 5.1 of `docs/feedback-plan-2026-11.md`
has checked every mechanism named here against the code.
Date: 2026-11-03

## Context

Feedback from the user (`docs/feedback-plan-2026-11.md`, 1b): "when I type a task I've used before,
it should pop up so I can tap it." Typing in the inbox composer should offer titles used before. A
tap fills the composer with that title and its last duration and category, and does not add the
task (designer's recommendation: adding on tap would hide the duration and category being chosen).

Everything below is a decision. None of it is built. Statements about the code *today* were
checked against the source on 2026-11-03.

### Where history could come from

- **SwiftData keeps no history.** `TodayView.place()` deletes the task once its block is written
  (`TodayView.swift:606`), and so does `fillDay()` (`:578`). That is known gap 1. A history built from
  `TaskItem` would see only the current inbox.
- **Template rows** (`TemplateRow.title`, duration, category) are in SwiftData and always present.
- **Past blocks** are the real record. Every placed or stamped item survives as an `EKEvent` in the
  Blockey calendar with its title, its real duration after any resize, and its `c=` slug. That record
  is durable (system store and iCloud) and outlives the app.
- **There is no range read.** `CalendarService.contents(for:)` reads one day
  (`CalendarService.swift:175-211`).
- **`.EKEventStoreChanged` is not debounced** (known gap 5). The observer bumps `revision` on every
  notification (`CalendarService.swift:66-70`), and each bump costs a synchronous main-actor fetch.
- **The composer** is a plain `TextField` (`InboxTray.swift:54-58`) with no suggestions. `addTask`
  trims `.whitespaces` only (`:163`), so a pasted newline survives into the title today.

### The constraint

**Respect ADR 001.** "SwiftData never stores a copy of a block's title, time or duration. There is
exactly one copy of that data and it lives in the calendar database" (`001:68-69`). A suggestion
feature is precisely the kind of thing that tempts a shadow copy, so the decision is shaped by not
making one. The secondary constraint is gap 5: whatever this adds must not make change
notifications more expensive.

## Options

### S1. A new SwiftData `TitleHistory` table

Written on add, place, fill and stamp. Costs: it stores block titles and durations in SwiftData,
which `001:68-69` forbids; it is lost when the app is deleted; it needs writes from about five places,
each one a chance to forget; and it drifts the moment the user renames or resizes a block in
Calendar.app. Buys: fast, exact, testable in memory. **Rejected.** It is a mirror of calendar data,
which is ADR 001's option B in miniature.

### S2 + S3. Past Blockey events plus template rows

`CalendarService` gains one read that returns plain value samples from the Blockey calendar only.
Template rows join them at a lower weight, and a pure ranker merges the two. Costs: a 90-day fetch
whose speed on the phone is unmeasured, and history that follows the calendar, deletions included.
Buys: no new storage, survives app deletion, records real durations, needs no backup, and **gap 1
stops mattering here**, because a placed task lives on as its event.

### S3 only. Template rows

Trivial, and covers only what the user put in a template. Too little.

## Decision

**S2 + S3.** History is read from the calendar, never stored.

### Contract

```swift
// Catalog/TitleSuggestions.swift: pure, no EventKit, no SwiftUI, no SwiftData.
struct TitleSample: Hashable, Sendable {
    let title: String
    let minutes: Int
    let categorySlug: String?   // nil for tokenless events
    let date: Date?             // nil for template rows
}

// Calendar/CalendarService.swift: the only new EventKit code.
func blockHistory(endingAt now: Date, days: Int = 90, limit: Int = 2000,
                  calendar: Calendar = .current) -> [TitleSample]
```

`blockHistory` reads the Blockey calendar and nothing else, maps each event to a plain struct of the
fields below, and hands that to a pure mapping function that applies the exclusions. The mapping is
tested without an event store; only the fetch touches EventKit, per ADR 001's layering rule.

### What counts as history

A sample is anything in the Blockey calendar that Blockey would have treated as an editable block.
Specifically, excluded:

- **Recurring events.** One daily event would add 90 identical samples and swamp the ranking.
- **All-day events.**
- **Multi-day events**, by the same rule `Block.isEditable` already uses: 24 hours or longer
  (`Block.swift:69-73`). One definition of "not a real block", not two.
- **Zero-length events.** Their duration teaches nothing and would be remembered as 0 minutes.
- **Future events.** The window ends at `now` (an event in progress counts). A week stamped ahead
  would otherwise count every template row several times before any of it happened, and template
  rows are already represented by S3.
- **The signing reminder.** Today it is found **by title only**: `ensureSigningReminder` filters
  every event in the Blockey calendar for the next 60 days on `$0.title == SigningReminder.title`
  (`CalendarService.swift:338-341`). The reminder is all-day, so the all-day rule already keeps it out
  of history, but matching by title is wrong in its own right. The decision: mark the reminder with a
  url of its own (`blockey://signing-reminder`) when it is written, find it by that marker, and keep
  accepting an all-day event with the old title so reminders written by today's build are still
  found. History never excludes by title.
- **The default title "New block".** Both the `+` button (`TodayView.swift:552`) and a new template
  row (`TemplatesView.swift:174`) write that literal. It becomes one shared constant in `Catalog/`,
  and any sample or template row whose key equals it is dropped. Otherwise typing "N" suggests "New
  block" forever.

Kept on purpose:

- **Tokenless events** in the Blockey calendar still count. ADR 002: a block is anything in the
  calendar. They carry no remembered category.
- **The current title**, as edited in Calendar.app. History follows the calendar.
- **The actual duration**, after any resize, not the task's original estimate.

### Limits

- **90 days**, counted by calendar-day arithmetic (`calendar.date(byAdding: .day, value: -90, to:
  startOfDay(now))`), not 90 × 86,400 seconds, so a DST change cannot move the boundary.
- **At most 2000 samples**, keeping the newest.
- **At most 3 chips.**
- **Titles capped at 200 characters**, and pasted newlines become spaces at submit, so a chip can
  never fill the field with something unbounded.

### Fetch once per inbox open

The fetch runs when the inbox opens and the result is held for the life of the sheet. It is **never
re-run on `.EKEventStoreChanged`**. A block written while the inbox is open is missing from the chips
until the next open, which costs nothing anyone will notice. This keeps gap 5 exactly as bad as it is
today and no worse. Fixing gap 5 is a separate piece of work and this ADR does not depend on it.

### Normalisation (`TitleKey.normalize`)

A key is for matching and grouping only. The displayed title is always a real spelling the user
typed, the most recent one.

In order: trim; remove U+200B and U+FEFF; **keep U+200D**, because it holds emoji sequences
together; collapse runs of whitespace (including newlines and tabs) to one space; NFKC; fold case and
width with `locale: nil` so the result does not depend on the phone's region.

NFKC rather than NFC because Thai SARA AM can be typed as one scalar (U+0E33) or two (U+0E4D U+0E32),
and only compatibility normalisation makes them the same key.

**No diacritic folding.** `.diacriticInsensitive` strips Thai tone marks and vowels, so `ข้าว` (rice)
would match `ขาว` (white). No fuzzy merging either: "Call mom" and "Call Tom" stay two titles. Trailing
punctuation is part of the key.

### Matching is on Unicode scalars

Swift `String` compares by grapheme cluster, so `"กิน".hasPrefix("ก")` is false: `กิ` is one cluster.
A Thai user typing `ก` expects `กิน`. Matching therefore compares the keys' `unicodeScalars`, so a
partial cluster matches. A query that begins with a combining mark matches nothing, rather than
everything that contains that mark.

Substring matches count as well as prefixes, because Thai is written without spaces between words and
a "word prefix" is often mid-string.

### Ranking

1. Match quality: exact, then prefix, then word-prefix (the start of a whitespace-separated word),
   then substring.
2. Score: the sum over the key's samples of `0.5 ^ (ageInDays / 14)`, a 14-day half-life measured
   from an injected `now`. Recent use beats old frequent use.
3. Title, as a deterministic tie-break.

Template rows have no date. A key that appears only in templates scores 0.5, the weight of one use 14
days ago. A key that appears in history ignores its template rows, so a stamped template is not
counted twice. An exact match for what is typed is still offered, since tapping it brings back the
duration and category.

### What a tap restores

The most recent sample's minutes and slug (a template-only key uses its row's). A duration outside the
preset chips (say 50 minutes) appears as an extra chip so it is visible. An archived or unknown slug
(ADR 005) is **not** restored; the composer keeps its current category instead of choosing something
the pickers would not offer.

### Interface

One row of up to 3 chips under the field (`🧠 Title · 45m`), shown while the field has text. A tap
fills title, duration and category and does not submit. One line per chip, middle-truncated, with the
full title in the accessibility label. Empty history shows nothing. Never autocomplete inside the
field. Update about 250 ms after typing stops, and keep the current chips while a Thai IME is
composing so they do not flicker.

### Where the pure code lives

`Blockey/Catalog/`, with `CategorySlug`, `CategoryPalette` and `CategoryCatalog` from ADR 005, under
the same rules as `Scheduling/`: no EventKit, SwiftUI or SwiftData. Text normalisation is not
"functions over time ranges", so it does not belong in `Scheduling/`.

## Consequences

**Becomes easy**
- No new table, no new writes, nothing to back up. Suggestions survive app deletion and come back on
  a new install the moment calendar access is granted.
- Real durations, including resizes made in Calendar.app.
- Gap 1 is irrelevant to this feature.

**Becomes hard**
- A 90-day read on the main actor each time the inbox opens. Its cost on the phone is unknown, and
  the 2000 cap is the only bound until it is measured.
- History depends on what is in the calendar, and the user controls that.

**What the owner should know.** Because history comes from events, **deleting a block in Calendar.app
also drops its title from suggestions.** So does anything in Blockey that deletes events: Clear the
day, Return to inbox (the title is in the inbox then anyway) and the planned Undo. Renaming a block in
Calendar.app renames its history entry. A title used only in a template is still suggested.
Arguably that is correct (a deleted block is a plan the user took back), but it is a behaviour, and
it is written here so it is not reported as a bug.

**Cannot undo.** Nothing. There is no stored state, so backing out is deleting the chip row and the
`blockHistory` method.

**Not verified**
- How long a 90-day Blockey-calendar fetch takes on the phone. It can only be measured there.
- SwiftUI `TextField` does not expose `markedTextRange`, so holding chips during Thai IME composition
  is untested and may need a `UITextField` wrapper (plan task 4.6, a manual check with the Kedmanee
  keyboard).
- Known gap 7: if tokens do not survive iCloud, history still has titles and durations but loses
  every remembered category. Suggestions degrade; they do not break.

**Known gaps touched.** Gap 1: sidestepped, not fixed. Gap 4: unaffected, since history reads only the
Blockey calendar. Gap 5: not made worse. Gap 3: history skips multi-day events by its own rule.

**Escape hatch.** The seam is `[TitleSample]`. If the calendar read proves too slow, put a cache
behind `blockHistory` that is rebuilt from the calendar and never written to by anything else; if
the calendar proves the wrong source altogether, S1 can produce the same samples. The ranker and the
UI do not change in either case.

## Build order

Matches phase 4 of `docs/feedback-plan-2026-11.md`. Test names are in its Appendix A.6 and A.7.

1. `backend-engineer`: `TitleKey` tests, then `TitleSuggestions` tests, then the implementation in
   `Catalog/`. Starts now; it depends on nothing in ADR 005 except the slug type, which is a
   `String`.
2. `backend-engineer`: the shared "New block" constant at both sites, and the signing-reminder marker
   with the legacy title fallback.
3. `backend-engineer`: `blockHistory` plus the pure sample-mapping function and its tests. Seeding
   history for manual checks goes inside the existing `#if DEBUG && targetEnvironment(simulator)` gate
   and runs on the simulator only.
4. `frontend-engineer`: the chip row in the composer, the 200-character cap and newline folding at
   submit.
5. Owner: the Thai keyboard check on the phone (plan task 4.6).
6. `qa-engineer` and `architect`: phase 5.1. Grep every mechanism above before this ADR is marked
   accepted.
