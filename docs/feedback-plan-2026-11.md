# Feedback plan: custom categories, task suggestions, clearer stamping

Date: 2026-11-03
Status: REVIEWED. QA findings folded in; owner answered Q1 to Q4 (section 7). ADRs 005/006 not yet written.
Inputs: two pieces of user feedback, translated from Thai (originals kept off this public repo)
Reviewed by: `designer` (stamp UX), `architect` (data model), `qa-engineer` (tests and edge cases)
Baseline: `scripts/test.sh` gives 146 tests in 20 suites, all passing (2026-11-03)

Nothing in this document has been built. It is a plan.

Note (2026-11-03): the `TodayView.swift` line references below predate task 2.0, which moved stamp,
fill, clear, place and return-to-inbox into `Blockey/Planning/DayPlanner.swift`. Find those by
symbol name, not by line.

---

## 1. Interpretation

### Feedback 1a: "I want custom categories"

The user wants to define their own categories beyond the fixed six (Deep work, Meeting, Admin,
Personal, Health, Rest). The plan assumes this means **add new ones**, and also lets the user
rename, re-emoji or recolour the built-ins. Owner confirmed (Q3).

### Feedback 1b: "when I type a task I've used before, it should pop up so I can tap it"

Typing in the inbox composer ("What needs a slot?") should suggest titles used before, ready to
tap. The plan assumes a tap also brings back that title's last duration and category, and that it
**fills the composer rather than adding the task immediately** (designer's recommendation: adding
on tap would hide the duration and category being chosen).

### Feedback 2: "'stamp work' or whatever, the thing that feels like quick schedule, is a bit confusing"

Interpretation, worked out from the code (both designer and lead agree):

- **"Stamp work" is `Stamp “Workday”`**, the primary bottom-bar button (`TodayView.swift:426`). It is
  the only one-tap "quick schedule" the user can find, which matches "feels like quick schedule".
- What makes it confusing, ranked:
  1. **"Stamp" is jargon.** The button names the template but not what will happen. One tap
     writes five calendar events.
  2. **The user never made "Workday".** `StarterData.swift:16-42` seeds it silently on first
     launch and assigns it to Monday to Friday. The first button on screen names something the
     user has no memory of creating, full of blocks they did not choose.
  3. **No preview, terse result.** The banner says `Stamped 5 blocks · 2 moved to fit · 1 to
     inbox` for 2.6 seconds and names nothing (`TodayView.swift:761-768`, `:476`).
  4. **No undo.** Reversing a stamp means ⋯ › Clear the day, which also deletes hand-placed
     blocks. That makes a one-tap button feel risky.
  5. **The restamp dialog is heavy.** It fires at one or more existing blocks, lists the
     destructive option first, and needs the long warning read to learn that "Replace" deletes
     hand-placed blocks too (`TodayView.swift:83`, `:189-194`).
  6. **Template rows leak into the inbox.** Rows that do not fit become inbox tasks marked only
     `· didn’t fit` (`InboxTray.swift:118-121`), mixed in with tasks the user typed.
- Secondary reading: "quick schedule" could also mean **Fill day**, the real "place everything
  quickly" action. It is hidden in the inbox sheet's top-left slot, where Cancel normally is
  (design review S9, still open), and it has no preview, no confirmation and no undo. The plan
  fixes both readings.

The owner chose this reading (Q1); it is not confirmed with the person who gave the feedback.

---

## 2. Current behaviour (verified against source)

### 2.1 Categories

- **Defined:** `Blockey/Models/BlockCategory.swift:10`. This is a fixed 6-case
  `enum BlockCategory: String`, with title, emoji, symbol and hard-coded light/dark tint.
  `.fallback = .deepWork` (`:87`). Its doc comment says it is deliberately an enum "so colours
  survive anything that happens to local storage".
- **Stored on a block:** in `event.url` as `blockey://block/<uuid>?c=<slug>&t=<task>`
  (`Calendar/BlockToken.swift`). The user can edit this from Calendar.app.
- **Parsed:** `BlockToken.init?(url:)` maps `c` through `BlockCategory(rawValue:) ?? .fallback`
  (`BlockToken.swift:55`). **An unknown slug silently becomes Deep work.** A test asserts this
  today (`BlockeyTests/EdgeCaseTests.swift:222`).
- **Rewritten:** `CalendarService.update` rebuilds the url from the parsed token whenever a
  category is passed (`CalendarService.swift:252-255`). `BlockDetailSheet` seeds its state from the
  already-collapsed `block.category` (`:29`) and passes it on every Save (`:74-78`). So opening an
  unknown-slug block and tapping Save **permanently overwrites its slug with `deep`**. The fix
  belongs in the sheet's `onSave` (pass nil when unchanged); `update` already takes an optional.
- **Stored locally:** `TaskItem.categoryRaw` and `TemplateRow.categoryRaw` are Strings with the
  same enum fallback. `Backup.swift:94,107` collapses unknown slugs on restore too.
- **Picked:** `BlockCategory.allCases` at `InboxTray.swift:77` (chips), `BlockDetailSheet.swift:43`
  and `TemplatesView.swift:200` (menus).
- **Rename or delete today:** impossible; there is no UI and the cases are compile-time. If a case
  were removed, every block, task and template row using it would show as Deep work. Block
  slugs would stay in Calendar until the next Save overwrote them.
- **Doc drift:** ADR 002 already specified editable names and colours with an immutable slug
  (`002:127` uses `categorySlug: String?`), and promised categories "reconstructed from the
  blocks" with a palette hash (`002:206-209`). Neither exists. The code drifted to an enum.

### 2.2 Task-title history

- **Open tasks:** `TaskItem` in SwiftData.
- **Placement deletes the task:** `TodayView.place()` (`:606`) and `fillDay()` (`:578`) call
  `context.delete(task)` after creating the block (known gap 1). **So SwiftData keeps no history
  of anything that was ever scheduled.** A history built from `TaskItem` would only see the
  current inbox.
- **Return paths recreate tasks from blocks:** `returnToInbox` and `clearBlocks` build a new
  `TaskItem` from the block's title, duration and category.
- **Template rows:** `TemplateRow.title` with start, duration and category, also in SwiftData.
- **Past blocks:** every placed or stamped item survives as an EKEvent in the Blockey calendar,
  with title, real duration (after any resize) and `c=` slug. It is durable (system store and
  iCloud) and survives app deletion, but the user can edit it.
- **Fetching:** `CalendarService.contents(for:)` reads one day only. There is no range or history
  read. `.EKEventStoreChanged` is not debounced (gap 5).
- **Composer:** `InboxTray.swift:52-58`, a plain `TextField`, no suggestions.

### 2.3 Stamp, fill and place: every entry point

| Label | Where | What it does | Confirm | Undo |
|---|---|---|---|---|
| `Stamp “<Template>”` | Today bottom bar, prominent (`TodayView:426`) | `TemplateStamper.stamp`: each row at its intended time, else the next fitting gap later, else earlier, else to the inbox as `droppedFromTemplate`. Fixed events always win. Today only plans from `now`. | Only if the day has 1 or more blocks | None |
| `Set up a template` | Same button with no template assigned, and the empty-day card (`:357`) | Opens Templates | n/a | n/a |
| `Replace with the template` / `Add the template on top` | Restamp dialog (`:189-194`) | Clear the whole day and then stamp, or stamp around what is there | It is the confirm | None |
| `Fill day` | Inbox sheet, **top-leading toolbar** (`InboxTray:37-43`) | Places **all** open tasks first-fit in the plannable window, deletes the tasks, dismisses the sheet | None | None |
| Tap-to-place | Tap an inbox task, then a highlighted gap | Places one task where you tap | None | Block sheet › Return to inbox |
| `+` | Today toolbar (`:485`) | 30-minute "New block" in the first gap, opens the detail sheet | None | Delete in the sheet |
| `Clear the day` | ⋯ menu (`:494`) | Deletes every block on the day; blocks that came from tasks return to the inbox; stamped blocks are deleted | Dialog with count | None |

Where a first-time user gets lost (first launch, a Monday):
1. The empty card says `Stamp “Workday” to lay down your usual day…` (`:346`). What is Workday?
   What is stamping?
2. Tap it: five blocks they never chose appear. The banner flashes for 2.6 s.
3. Open the inbox: `Fill day` sits where Cancel normally is, greyed out when the inbox is empty.
   It's unclear how it differs from Stamp.
4. A row that did not fit shows up as a task they never typed, marked `· didn’t fit`.
5. To take it all back: ⋯ › Clear the day › confirm. That loses anything hand-placed too.

---

## 3. Options and recommendations

### 3.1 Stamp / quick schedule (designer)

| Option | What | Trade-off |
|---|---|---|
| A. Copy only | Drop "stamp" from the UI, label seeded templates as examples, move Fill day out of the Cancel slot, reorder the dialog | Cheapest. Still writes 5 events blind and has no way back. |
| **B. Preview and undo (recommended)** | Primary button opens a small "Plan Monday" sheet listing where each row will land, which moved and which go to the inbox; one confirm. Banner gets **Undo** that removes exactly what that action created. The restamp dialog folds into the sheet as `Keep my 3 blocks` / `Start over`. Fill day moves to a full-width button under the inbox list and gets the same Undo. Includes A's copy. | One extra tap on the morning pass (open, confirm). Mitigated by an optional "Skip preview" setting once Undo exists. |
| C. One "Plan my day" flow | One sheet: "Your usual day" rows and "From your inbox" tasks, tick and add | Ends the Stamp-vs-Fill question, but adds decisions to a 2-minute pass and rebuilds two screens. Revisit if B is still confusing. |

Proposed copy for B:
- Bottom bar: `Add my Workday` (no template: `Set up a template`).
- Header: `Your meetings are in. Add your Workday to fill the rest.`
- Empty card: `Nothing planned yet` / `Add your Workday for a ready-made day, then drop anything
  else into the gaps.` plus a `See what’s in Workday` text button.
- Sheet title `Plan Monday`, subtitle `Your Workday template. Meetings stay where they are.`
  Rows: `9:00 AM  Deep work · 2h`, `11:45 AM  Admin & email · moved from 11:30`,
  `Lunch · no room today · goes to your inbox`. Confirm: `Add 4 blocks to Monday`; none fit:
  disabled `Nothing fits` with `Your day is full from now on. Try tomorrow.`
- With existing blocks: segmented `Keep my 3 blocks` (default) / `Start over`; Start over turns the
  button destructive, `Delete 3 and add 5 blocks`, and keeps the existing untagged-loss sentence.
- Banner: `Added 5 blocks to Monday` + `Undo`, shown 6 s. One miss: `Added 4 blocks. “Lunch” is in
  your inbox.` (tap opens the inbox). After undo: `Removed 4 blocks`.
- Fill day: `Place all 4 on today` (or `on Thursday`), under the list, does not dismiss the sheet;
  disabled reason `Nothing fits in the time you have left.`
- Inbox row from a template: `· from Workday, no room` instead of `· didn’t fit`.
- Seeded templates: a footer in Templates, `Workday and Weekend are examples. Edit them or make
  your own.` Owner decision (Q2): keep seeding, and show a one-time `Keep` / `Edit` card.

**The preview is a proposal, not a promise (QA, high).** Confirm re-runs `TemplateStamper.stamp`
against a fresh fetch and the current `now`. If the result differs from what was shown (a meeting
arrived, `now` passed a row, the count changed), the sheet updates and asks again rather than
writing something different from what the user saw. This is the one place the new design could
break "fixed events always win", so it is a hard rule with tests (Appendix A, P1). The sheet
refreshes through Today's existing `revision` path, not a second observer (gap 5).

Undo rules:
- Remove only events this action created, found by token UUID (not `eventIdentifier`, ADR 001).
  Never clear the whole day.
- Remove a created block even if the user edited or moved it inside the undo window: they tapped
  Undo.
- A block already deleted, or whose token was stripped in Calendar.app, cannot be found. Skip
  it and say so honestly: `Removed 3 of 4 blocks`.
- Delete the inbox tasks this action created (unplaced and failed rows), except ones the user has
  since placed.
- Fill day: reinsert the `TaskItem`s it deleted, with their sort order, exactly once.
- Start over, in one operation: remove the new blocks, recreate the cleared blocks **with their
  original token UUIDs**, and delete the inbox tasks the clear created. Without that last step,
  every undo makes a duplicate. A recreated block that would overlap a meeting that has arrived
  since is **not written** and is reported instead (fixed events always win).
- Undo acts on the day it was recorded for, not on `selectedDate`. A second tap does nothing.
  The banner has a single slot, so when a later banner replaces it, the undo record is dropped
  with it.
- Accessibility: while VoiceOver is running, the Undo banner stays until dismissed.

### 3.2 Custom categories (architect)

| Option | What | Trade-off |
|---|---|---|
| **A. Definitions in SwiftData, slug in the token, built-ins in code (recommended)** | New `@Model CategoryDefinition` (slug, name, emoji, symbol, paletteIndex, sortIndex, archivedAt). Rows exist only for custom categories and for customised built-ins. The six built-ins stay in code, so they always render correctly. | One new model, and a catalog passed to views in place of the enum at about 15 sites. Rename and recolour never touch a calendar event. |
| B. Name, emoji and colour in every block's url | Survives app deletion with no backup | Every block holds a copy; a rename either leaves old blocks stale or rewrites months of events. That is a sync engine, "option B wearing a trenchcoat" (ADR 001). Rejected. |
| C. One calendar per category | Calendar.app colours for free | Breaks "a block is anything in the Blockey calendar" (ADR 002 tier 1), and changing a category becomes a calendar move that changes `eventIdentifier`. Rejected. |

Details of A:
- **Slug.** Built-ins keep `deep`, `meeting` etc. forever. Custom slugs are `u-` plus the
  normalised name (lowercase, letters/marks/numbers, other runs become `-`, max 32). **Combining
  marks are kept**, so `งานบ้าน` gives `u-งานบ้าน` and ข้าว does not become ขาว. Collisions,
  including archived slugs, get `-2`, `-3`. An emoji-only name gets `u-` plus 6 random characters.
  Slugs never change after creation.
- **Unknown slug** (deleted, SwiftData lost, hand-edited): render a stand-in. The name comes back
  from the slug (`u-งานบ้าน` reads `งานบ้าน`), the colour comes from a **stable FNV-1a hash** into
  the palette (never Swift `hashValue`, which is seeded per process), and the glyph is a generic 🏷️
  / `tag`. The block sheet offers `Add as category`, which fixes every block with that slug at once.
- **Rename and recolour:** edit the definition. Past blocks follow. No event writes.
- **Delete = archive.** Blocks keep their slug and still render from the archived definition.
  Archiving asks whether to move the N inbox tasks and M template rows to another category.
  Pickers always show the current value even when it is archived or unknown, and Save only rewrites
  the category if the user changed it.
- **Archived categories and new work.** Pickers never offer an archived category for a *new*
  choice. A template row left pointing at an archived category still stamps with that slug; the
  block renders from the archived definition. This is deliberate: archiving hides a category, it
  does not rewrite history.
- **Names.** Empty, whitespace-only and zero-width-only names are rejected. A custom name equal to
  a built-in ("Meeting") is rejected in the editor, because two identical names in a picker can't
  be told apart. The slug cap counts whole grapheme clusters, so a Thai mark is never cut off its
  base. There is no limit on how many categories exist; past the palette size colours repeat
  deterministically, and the emoji keeps them apart.
- **Recovering a name from a slug is best effort.** Lowercasing, collapsed punctuation and `-2`
  suffixes are lost, so the definition is always the real source.
- **Colour:** a fixed, measured `CategoryPalette` of about 10 to 12 light/dark pairs (design review
  M9, M10), offered first. **Amended 2026-11-04 (owner):** plus an "Other…" option that opens the
  system colour picker. The pick is stored as `customColorHex` (`#RRGGBB`) beside `paletteIndex`;
  hue and chroma come from the pick, lightness from the palette, and the editor warns (never
  blocks, never nudges) when it looks like a meeting or is close to another category. Full design
  in ADR 005, "Amendment: palette + custom colour". Emoji is required, so colour is never the only
  signal.
- **Token fix first:** `BlockToken` keeps `categorySlug: String?` verbatim (NFC) and round-trips
  any unknown query items. This alone stops the silent overwrite in 2.1 and is worth shipping first.
  The force unwrap at `BlockToken.swift:70` goes too.

### 3.3 Task-title suggestions (architect + designer)

| Option | What | Trade-off |
|---|---|---|
| S1. New SwiftData `TitleHistory` | Written on add, place, fill and stamp | Fast and exact, but stores block titles and durations in SwiftData, which ADR 001:68-69 forbids, is lost on app delete, and needs writes from about 5 places. |
| **S2 + S3. Past Blockey events + template rows (recommended)** | New `CalendarService.blockHistory(endingAt:days:limit:)` returns plain `TitleSample` values (title, minutes, slug, date) from the Blockey calendar only; template rows are added with a lower weight; a pure ranker merges them | No new storage, survives app deletion, records real durations, and **gap 1 does not matter**: placed tasks live on as events. Deleted blocks drop out of history (arguably correct). |
| S3 only. Template rows | Trivial | Too little coverage. |

Details:
- **Fetch** once when the inbox opens (90 days by calendar-day arithmetic, at most 2000 samples
  keeping the newest), never per change notification, so gap 5 gets no worse. Skip all-day,
  multi-day, recurring (one daily event would add 90 identical samples and swamp the ranking),
  zero-length, future-dated, and the signing reminder. The reminder is currently found **by title
  only** (`CalendarService.swift:341`), so give it a token or a notes marker rather than skipping
  every block with that title.
- **Default titles are not history.** The `+` button creates "New block". Share that string as a
  constant and exclude it, or typing "N" suggests "New block" forever.
- **Tokenless events in the Blockey calendar still count** (ADR 002: a block is anything in the
  calendar). They just carry no remembered category.
- **Newlines** pasted into the composer become spaces at submit, and titles are capped at 200
  characters, so a chip can never fill the field with something unbounded.
- **Key** (`TitleKey.normalize`): trim, drop U+200B/U+FEFF, keep U+200D, collapse whitespace, NFKC,
  fold case and width. **No diacritic folding** (it would strip Thai tone marks). No fuzzy merging
  ("Call mom" is not "Call Tom").
- **Match** on Unicode scalars so a partial Thai cluster matches (`ก` finds `กิน`), substring as well
  as prefix because Thai has no word spaces. Rank exact > prefix > word-prefix > substring, then by
  a recency-weighted score (14-day half-life), then by title.
- **Remember** the most recent use's minutes and slug. A non-preset duration (say 50 min) shows as
  an extra chip. ~~An archived or unknown remembered category is not restored.~~ Superseded by
  UI spec 1.4 and ADR 005 (phase 5.1 addendum, row 40): a chip applies the remembered slug even when
  it is archived or unknown, because it is the owner's own history.
- **UI:** one row of up to 3 chips under the field (`🧠 Title · 45m`), shown while the field has text.
  A tap fills title, duration and category, and does not submit. One line per chip, middle-truncated,
  full title in the accessibility label. Empty history shows nothing. Never auto-complete inside the
  field. Debounce about 250 ms and keep the current chips during Thai IME composition so they do not
  flicker.
- **Where the pure code lives:** a new `Blockey/Catalog/` folder (CategorySlug, CategoryPalette,
  CategoryCatalog, TitleKey, TitleSuggestions), under the same rules as `Scheduling/` (no EventKit,
  SwiftUI or SwiftData). Text normalisation is not "functions over time ranges", so it does not
  belong in `Scheduling/`. The stamp preview logic, by contrast, stays in `Scheduling/`.

### 3.4 Durability

- Category definitions and customisations live in SwiftData. ADR 003: they survive re-signing and
  are lost if the app is deleted.
- **Backup v2** adds `categories` and `settings` (day window, snap, alarm, hidden calendars),
  which **closes known gap 6** in the same version bump. The new fields are optionals, because
  synthesised `Codable` throws on a missing key, so every v1 file would otherwise fail to import. A
  backup with no categories does not wipe existing ones. The restore warning counts categories.
- **Without a backup**, deleting the app still leaves every block with its own name (from the slug),
  a stable colour and an honest generic glyph, and one tap restores the category.
- Suggestions need no backup: they come from the calendar.
- **Versions.** Restore today has no version gate (`Backup.swift:16` is a plain `var version = 1`).
  v2 adds one: a file from a *newer* version is refused with a clear message, not half-read. A v2
  file opened by an older build already decodes (unknown keys are ignored), losing only the new
  fields, which matters because the weekly re-sign makes a stale build realistic.
- **Settings from a file are untrusted.** Clamp the day window and snap, and keep calendar IDs
  that don't exist on this device without letting them break anything.
- **Atomicity.** Restore already rolls back if the save fails (`Backup.swift:118-126`). v2 also
  decodes and validates the whole payload *before* the first delete.

---

## 4. Ordered task list (tests first)

Sizes: **S** = under 2 hours, **M** = about half a day, **L** = 1 to 2 days. Sizes include QA's
corrections (about 30 percent above the first draft). Every new Swift file is just created; the
synchronized folder group picks it up, and `project.pbxproj` is never edited. Test names for each
task are in Appendix A.

**Phase 0, decisions and the one manual experiment**
- 0.1 Owner decisions. **Done** (section 7).
- 0.2 Write ADR 005 "User-defined categories and Backup v2" and ADR 006 "Title suggestions read
  from the calendar", both marked **Proposed** until 5.1 checks them against the code. Architect.
  **S**
- 0.3 **Owner, on a real phone with iCloud:** run ADR 002's token-survival experiment (gap 7),
  adding a percent-encoded Thai `c=` slug. This **gates phase 3**. **Done 2026-11-04: passed**
  (ADR 002, last addendum). Thai slugs survive iCloud and an outside edit, so slugs are stored as
  typed and the pre-decided `.toLatin` fallback is dropped. Phase 3 is unblocked. **S**

**Phase 1, stop losing slugs (ships alone)**
- 1.1 Tests: token round-trips (A.1). **S**
- 1.2 `BlockToken` gains `categorySlug: String?`, kept verbatim, and keeps unknown query items.
  `category` stays as a computed fallback, so nothing else changes yet. Remove the force unwrap
  at `:70`. **S**
- 1.3 `BlockDetailSheet.onSave` passes the category only if the user changed it. Check on a
  seeded simulator block. **S**

**Phase 2, clearer stamping (independent of phases 3 and 4)**
- 2.0 Move `applyTemplate`, `fillDay` and `clearBlocks` out of `TodayView` into a testable
  coordinator behind a small `BlockWriting` protocol that `CalendarService` conforms to. Without
  this, Undo can only be tested against a real event store. No behaviour change; the existing
  146 tests stay green. **M**
- 2.1 Tests (pure, `Scheduling/`): `StampPreview` row lines, Keep vs Start over busy sets,
  staleness detection, DST (A.2). **M**
- 2.2 Tests: the undo record and coordinator undo against a fake `BlockWriting` (A.3). **M**
- 2.3 Copy pass: drop "stamp" from UI text, reorder the dialog safe-first, the
  `· from Workday, no room` row note, the Templates footer. **S**
- 2.4 Preview sheet replacing the restamp dialog, recompute-on-confirm, and the `Skip preview`
  setting (default off). **L**
- 2.5 Banner Undo for stamp and Fill day (6 s, kept while VoiceOver is running). **L**
- 2.6 Fill day becomes `Place all N on <day>` under the inbox list, and no longer dismisses the
  sheet. **S**
- 2.7 First-launch card for the seeded templates, shown once: `We added a sample Workday for
  Mon–Fri.` with `Keep` / `Edit`. Seeding stays. **S**
- 2.8 Designer reviews `scripts/demo.sh` screenshots (simulator only; emoji show as tofu there,
  which is expected). **S**

**Phase 3, custom categories (0.3 passed 2026-11-04, unblocked)**

Colour work depends on redesign Story 2 (#12), which owns the six measured records and the
`SRGB` / `CategoryColors` value types (ADR 005 amendment, "Effect on the `CategoryStyle` seam").
- 3.1 Tests: `CategorySlug` (A.4). **S**
- 3.2 Tests: `CategoryCatalog` over a plain `CategoryDefinitionValue` struct, so tests never
  build `@Model` objects (A.4). Includes custom hex winning over `paletteIndex`. **S**
- 3.3 Tests: `CategoryPalette`. The designer supplies measured light/dark pairs (A.4). **M**
- 3.3b Tests: custom colour (A.4b). Hex parsing, OKLCH round trip and gamut mapping, `derive`
  (deterministic, hue-sweep meets every floor, curated spines land near their records) and
  `assess` (meeting, neighbour, both modes, self and archived skipped). Contrast and ΔE76
  reference values too, unless Story 2's qa task already wrote them. The designer supplies
  `DerivationTargets` fit to Story 2's records and the meeting chroma gap. backend-engineer and
  designer. **M** (added 2026-11-04)
- 3.4 Implement `Catalog/` until the tests pass. **M**
- 3.4b Implement `CustomCategoryColor` (and `CategoryColorMath` if Story 2 has not) until 3.3b
  passes. backend-engineer. **M** (added 2026-11-04)
- 3.5 `CategoryDefinition` model with a unique `slug`, registered in the container, with
  `customColorHex: String?` in its first version. Slug accessors on the existing `categoryRaw`,
  which is not renamed, so no migration. database-engineer. **S**
- 3.6 `Block` and `CalendarService` take and return slugs. **M**
- 3.7 Catalog in the environment. Replace the three `allCases` pickers and the glyph/tint sites.
  Add `Add as category` on unknown slugs. **L**
- 3.8 Category editor in Settings (add, edit, reorder, archive with a move-to prompt), plus a
  Category chip in the composer that opens the full list. **M**
- 3.8b "Other…" colour row in the editor: `ColorPicker` with `supportsOpacity: false`, conversion
  of the picked `Color` to sRGB with components clamped to 0...1 (a Display P3 pick can fall
  outside), a preview chip in light and dark side by side, and one line for the worst concern.
  Choosing a swatch clears the custom hex. frontend-engineer, designer for copy. **M** (added
  2026-11-04)
- 3.9 Backup v2 tests first (A.5), then implement. Checked-in v1 and v2 fixtures, plus a v2 fixture
  without `customColorHex`. **L**

**Phase 4, title suggestions**
- 4.1 Tests: `TitleKey` (A.6). **S**
- 4.2 Tests: `TitleSuggestions` (A.6). **M**
- 4.3 Implement until the tests pass. **S**
- 4.4 `CalendarService.blockHistory` plus a pure sample-mapping function with its own tests
  (A.7). Seeding goes inside the existing `#if DEBUG && targetEnvironment(simulator)` gate and
  runs on the simulator only. Mark the signing reminder by something other than its title. **M**
- 4.5 Suggestion row in the composer. **M**, or **L** if Thai IME needs a `UITextField` wrapper.
- 4.6 **Manual check on the phone** with the Thai Kedmanee keyboard. Type `ก` then `า`;
  suggestions must stay put and the field text must never change while composing. **S**

**Phase 5, review**
- 5.1 qa-engineer and architect review the work against ADRs 005 and 006. Grep every mechanism
  the ADRs name against the source before marking them Accepted. Update the CLAUDE.md known
  gaps: close gap 6 only once restoring settings is verified. **S**
  **ADR 005, architect pass done 2026-11-04:** 85 matches, 13 differs, 1 missing (addendum at the
  end of the ADR). Still **Proposed**, blocked on its follow-up F1, the install-over migration
  check for `CategoryDefinition` (**S**, qa-engineer, simulator). Code follow-ups F2 (retire the
  `BlockCategory` shim: **S** for the comment and dead code, **M** to delete the enum) and F3
  (stale comments, **S**) do not block. Gap 6 closes when F1 passes and the suite is green.
  ADR 006 not yet done.

Rough total: **8 to 12 working days** as first planned; the custom-colour tasks (3.3b, 3.4b, 3.8b,
three **M**) add about 1.5 days, so **9.5 to 13.5** from 2026-11-04. Phase 1 takes about half a day
and is the most urgent.

---

## 5. Risks and known gaps touched

| Risk | Mitigation |
|---|---|
| The preview goes stale and confirm writes over a meeting that arrived since | Recompute on confirm, ask again if the plan changed (P1 tests) |
| Undo duplicates tasks or leaves a half-done state, worst on Start over | Undo record keyed by token UUID, plus inbox tasks the clear created; done in one operation; tested against a fake writer |
| A token stripped in Calendar.app breaks Undo, suggestions and colour | Undo reports partial results; history still counts the title; the block keeps working (ADR 002) |
| Thai slugs mangled by iCloud CalDAV | **Retired 2026-11-04**: experiment 0.3 passed, slugs stored as typed |
| A custom colour that reads like a meeting or another category | Lightness derived from the palette; edit-time warning against meeting fill and active categories; emoji required |
| App deleted without a backup loses category names and colours | Slug-derived stand-in with stable FNV-1a colour, one-tap adopt, Backup v2 |
| A backup from a newer version opened by an older build | Version gate refuses newer files; older builds ignore unknown keys |
| A half-finished restore | Validate before the first delete; the existing rollback on save |
| Recurring events or "New block" flood suggestions | Both excluded, with tests |
| A user block titled like the signing reminder vanishes from history | Mark the reminder explicitly (task 4.4) |
| The single banner slot drops Undo | The record expires with its banner, tested |
| The preview adds a tap to the morning routine | Two taps on a blank day; `Skip preview` setting |
| Rewriting the enum touches about 15 sites | Token and catalog land behind tests first; views switch last |

Known gaps from CLAUDE.md:
- **Gap 1** (placing deletes the task): suggestions sidestep it. The Fill-day undo has to
  reinsert deleted tasks. Owner should know: because history comes from events, deleting a block
  in Calendar.app also drops its title from suggestions. Gap 1 itself is not fixed.
- **Gap 2** (no completion): untouched. Completion, rollover and reflow are outside this plan.
- **Gap 3** (multi-day timed events count as busy): untouched, but it can make the preview say
  "no room" for a reason the user cannot see. History skips those events.
- **Gap 4** (hidden calendars default to empty): untouched. Suggestions read only the Blockey
  calendar, so they are unaffected. Busy time is still affected.
- **Gap 5** (no debounce): not made worse. The preview reuses Today's refresh path, and
  suggestions fetch once per inbox open.
- **Gap 6** (backup omits settings): **closed** by Backup v2, once verified in 5.1.
- **Gap 7** (token-survival experiment): widened by Thai slugs, made a gating task (0.3), and
  **closed 2026-11-04** when 0.3 passed on the owner's phone.
- **Gap 8** (`BlockMeta`): still not built, and nothing here needs it. ADR 005 should say so.

---

## 6. Unverified, and why

- **That the feedback means "I didn't know what `Stamp “Workday”` does".** The owner chose this
  reading. It hasn't been confirmed with the person who gave the feedback.
- ~~Whether a percent-encoded Thai `blockey://` url survives Calendar.app and iCloud.~~ Verified
  2026-11-04 by task 0.3 (passed). Not recorded: whether the url stayed byte-identical.
- **How fast a 90-day Blockey-calendar fetch is on the phone.** It can only be measured on the
  device.
- **SwiftUI `TextField` with Thai marked text.** It doesn't expose `markedTextRange`, so the
  debounce approach is untested and may need a wrapper (task 4.6).
- **Palette contrast and ΔE values.** Not designed yet.
- **How a derived custom colour looks beside the curated ones.** Tests pin the floors, not taste;
  it needs a device screenshot (simulator colours are fine, only emoji are not).
- **QA did not run the suite.** The 146-test baseline is from the lead's run on 2026-11-03.

Verified against the source in this pass:
- **Categories and tokens:**
  - the enum and its fallback
  - the slug collapse at `BlockToken:55`, and the test asserting it (`EdgeCaseTests:222`)
  - the force unwrap at `BlockToken:70`
  - `BlockDetailSheet` seeding from the collapsed category and always saving it (`:29`, `:74-78`)
  - `update` rewriting the url (`CalendarService:252-255`)
  - the `allCases` pickers (`InboxTray:77`, `BlockDetailSheet:43`, `TemplatesView:200`)
- **Tasks and history:** `place()` and `fillDay()` delete the task (`TodayView:606`, `:578`).
- **Stamping and filling:**
  - there is no undo anywhere
  - Fill day sits in the leading slot (`InboxTray:37-43`)
  - banner timings are 2.6 s and 7 s (`TodayView:476`)
  - `notBefore` applies only on today
  - `StarterData` seeds and assigns Workday
- **Calendar and backup:**
  - the signing reminder is found by title (`CalendarService:341`)
  - restore has no version gate but does roll back if the save fails (`Backup.swift`)

Doc claims found false again:
- ADR 002's category reconstruction (`002:206-209`) does not exist.
- `BlockMeta` does not exist.
- `.EKEventStoreChanged` is not debounced.
- `BLOCKEY_IMPROVEMENTS.md` 1.4 asks to "verify undo", and there is no undo to verify.

---

## 7. Decisions (owner, 2026-11-03)

- **Q1, the stamp confusion:** "I didn't know what it does". Go with option B (preview and undo).
  Option C stays a later idea.
- **Q2, seeding:** keep seeding the templates, and ask once on first launch (`Keep` / `Edit`).
- **Q3, categories:** add new ones, and let the user edit the six built-ins (name, emoji, colour).
  Deleting a category archives it.
- **Q4, the extra tap:** acceptable, with a `Skip preview` setting (off by default).

Added 2026-11-04 (owner):
- **Task 0.3 passed.** Thai slugs are stored as typed; the `.toLatin` fallback is dropped.
- **Q5, category colour:** "palette + custom". The curated palette first, plus "Other…" opening the
  system colour picker, with a warning about poor readability. Design in ADR 005's amendment.

---

## Appendix A. Tests to write first

All dates are built with `Calendar.current`. DST tests pass an injected calendar with a fixed
zone through the existing `calendar:` parameters; that is still `Calendar` API, not hand-rolled
offsets.

**A.1 BlockToken (1.1)**
- unknownSlugSurvivesRoundTrip (replaces `EdgeCaseTests:222`; also asserts the resolved
  `category` is still `.fallback`)
- thaiSlugRoundTripsVerbatim
- nfdSlugParsesToNfc
- percentEncodedThaiSlugRegeneratesSameToken
- rawThaiHandEditedUrlIsTokenlessNotCrash
- absentCategoryStaysAbsentOnRewrite
- emptyCategoryValueIsAbsent
- whitespaceOnlyCategoryValueIsAbsent
- duplicateCQueryItemsFirstWins
- categoryValueIsCaseSensitive (`DEEP` is not `deep`)
- unknownQueryItemsSurviveRoundTrip (including items before `c`, and duplicate unknown keys)
- sourceTaskSurvivesWhenCategoryUnknown
- urlIsAlwaysProducedForAnySlug
- saveWithUnchangedCategoryDoesNotRewriteToken

**A.2 StampPreview (2.1)**
- previewLinesShowPlacedMovedAndInbox
- previewEmptyTemplateDisablesConfirm
- templateWithAllRowsInThePastShowsNothingFits
- previewWhenNoTemplateAssigned
- templateRowLongerThanWindowGoesToInbox
- zeroDurationRowIsDropped
- confirmRecomputesAgainstNewMeetingAndStillAvoidsIt
- confirmAfterNowPassesRowMovesOrDropsRowNotPlacesInPast
- previewAndConfirmDifferingPlansAreDetected
- previewForDayRolloverUsesSelectedDateNotNow
- startOverPreviewTreatsOwnBlocksAsFreeButFixedEventsAsBusy
- startOverNeverFreesFixedEvents
- stampOnSpringForwardDayRespectsFixedEvents
- stampOnFallBackDayRepeatedHourPlacesWithoutOverlap
- sheetTitleUsesTodayTomorrowOrWeekday

**A.3 Undo (2.2, against a fake `BlockWriting`)**
- undoRemovesOnlyBlocksThisActionCreated
- undoRemovesBlockUserMovedInWindow
- undoSkipsBlockAlreadyDeletedAndReportsCounts
- undoAfterTokenStrippedReportsPartial
- partialCreateFailureRecordsOnlySucceededBlocks
- undoDeletesInboxTasksCreatedByStampButNotOnesSincePlaced
- fillDayUndoReinsertsDeletedTasksOnceWithSortOrder
- undoTappedTwiceIsNoOp
- undoRecordDroppedWhenBannerReplaced
- undoResolvesAgainstFreshFetchAfterStoreChange
- undoTargetsRecordedDayNotSelectedDate
- startOverUndoRecreatesClearedBlocksWithSameTokenIds
- startOverUndoRemovesInboxTasksCreatedByTheClear
- startOverUndoReportsTokenlessBlocksItCannotRestore
- restoredBlocksOverlappingNewFixedEventAreReportedNotWritten
- startOverUndoPartialFailureLeavesNoDuplicates

**A.4 Categories (3.1 to 3.3)**
- CategorySlug:
  - mintPrefixesCustomSlugs
  - mintKeepsThaiCombiningMarks
  - mintLowercasesLatinAndDashesPunctuation
  - fullWidthLatinNameSlugsToAscii
  - slugFromNfdAndNfcNameIsIdentical
  - mintAppendsSuffixOnCollision
  - mintCollidesWithArchivedSlugs
  - renameDoesNotChangeSlug
  - emojiOnlyNameGetsRandomSlug (random source is injectable)
  - mintCapsAt32WithoutSplittingAThaiCluster
  - emptyWhitespaceOrZeroWidthNameIsRejected
  - nameEqualToBuiltInIsRejected
  - builtInSlugsAreNeverMintable
  - displayNameFromSlugIsBestEffort
- CategoryCatalog:
  - definitionOverridesBuiltIn
  - builtInResolvesWithNoDefinitions
  - unknownSlugResolvesStandInWithDerivedName
  - nilSlugResolvesFallback
  - archivedCategoryStillResolvesNameEmojiAndTint
  - archivedHiddenFromNewChoices
  - pickerIncludesCurrentArchivedOrUnknown
  - archivedRowStampsWithArchivedSlug
  - archivingMovesTasksAndRowsOnlyWhenChosen
  - duplicateSlugInsertIsRejected
- CategoryPalette:
  - unknownSlugIndexMatchesHardCodedValue (catches per-process `hashValue`)
  - paletteWrapsDeterministicallyPastCount
  - everySwatchMeetsFillContrastInBothModes (M10; implemented as `assess(swatch) == []`)
  - builtInSwatchesPairwiseDeltaEAboveFloor (M9)
- CategoryCatalog, colour (3.2):
  - validCustomHexWinsOverPaletteIndex
  - invalidCustomHexFallsBackToPaletteIndex
  - choosingPaletteSwatchClearsCustomHex
  - standInNeverResolvesToCustomColor
  - addAsCategoryKeepsStandInPaletteIndex

**A.4b Custom colour (3.3b)**
- SRGB hex:
  - hexParsesUppercaseAndLowercase
  - hexRejectsShortLongAlphaMissingHashWhitespaceAndJunk
  - hexWriterEmitsCanonicalUppercase
  - hexRoundTripsThroughEightBitSRGB
- CategoryColorMath (skip any Story 2 already wrote):
  - contrastRatioMatchesWcagReferencePairs (black on white is 21:1)
  - deltaE76MatchesPinnedReferenceValue
  - oklchRoundTripsInGamutColors
  - gamutMappingKeepsLightnessAndHue
- CustomCategoryColor.derive:
  - deriveIsDeterministic
  - derivedRecordsMeetContrastFloorsAcrossHueSweep (every 15 degrees, high chroma, both modes)
  - deriveFromCuratedSpineLandsNearCuratedRecord (threshold set by the designer)
  - greyPickDerivesToGreysWithoutCrashing
  - outOfGamutPickIsMappedNotClipped
- CustomCategoryColor.assess:
  - greyPickWarnsLooksLikeMeeting
  - pickNearActiveCategoryWarnsWithItsSlug
  - assessSkipsSelfAndArchivedCategories
  - assessReportsEachModeSeparately
  - concernsAreOrderedWorstFirst

**A.5 Backup v2 (3.9)**
- v1FileDecodesUnderV2
- v2FileDecodesUnderV1Shape
- restoreRefusesNewerVersion
- v2RoundTripsCategoriesAndSettings
- restoringV1FileKeepsExistingCategories
- nilAndEmptyCategoriesBehaveAsSpecified
- restoreKeepsUnknownAndArchivedSlugsVerbatim
- restoreTaskReferencingMissingCategoryGetsStandIn
- restoreDuplicateSlugsInFileDoesNotCrash
- restoreSettingsClampsOutOfRangeValues
- restoreKeepsUnknownCalendarIDsHarmlessly
- restoreValidatesBeforeDeleting
- restoreWarningCountsCategories
- v2FileWithoutCustomColorHexDecodes
- customColorHexRoundTrips
- lowercaseCustomColorHexRestoresCanonical
- invalidCustomColorHexRestoresAsNilOnPaletteIndex

**A.6 Titles (4.1, 4.2)**
- TitleKey:
  - trimsAndCollapsesWhitespaceNewlinesAndTabs
  - foldsCaseAndWidthLocaleIndependently
  - nfcAndNfdAreSameKey
  - thaiSaraAmComposedAndDecomposedMatch
  - stripsZwspAndBomKeepsZwj
  - keepsThaiToneMarks (ข้าว is not ขาว)
  - trailingPunctuationIsADifferentKey
  - callMomAndCallTomStaySeparate
- TitleSuggestions:
  - thaiPartialClusterMatches (`ก` finds `กิน`)
  - substringMatchesThaiMidWord
  - loneCombiningMarkQueryMatchesNothingSpurious
  - exactBeatsPrefixBeatsSubstring
  - recentOutranksOldFrequent
  - recencyUsesInjectedNow
  - dedupesVariantsShowingLatestSpelling
  - tieBreakIsDeterministic
  - remembersLatestMinutesAndSlug
  - nonPresetDurationSurvives
  - unknownOrArchivedSlugIsNotRestored
  - templateRowsCountWithoutDate
  - templateRowSameKeyAsHistoryDoesNotDoubleCount
  - exactTypedMatchStillOffered
  - emptyOrWhitespaceQueryReturnsNothing
  - emptyHistoryNoTemplatesReturnsNothing
  - templatesOnlyHistoryStillSuggests
  - defaultNewBlockTitleIsExcluded
  - longTitlesMatchWithinBudget (2000 samples × 500 characters)
  - respectsLimits

**A.7 History mapping (4.4) and composer (4.5)**
- historySkipsAllDay
- historySkipsRecurring
- historySkipsMultiDay
- historySkipsSigningReminder
- historyKeepsTokenlessEventsWithNoCategory
- historyUsesCurrentEventTitle
- historyDurationIsActualDurationZeroDropped
- historyExcludesFutureEvents
- historyBoundaryAt90CalendarDaysAcrossDst
- historyCapKeepsNewest
- chipTapFillsWithoutSubmitting
- pastedNewlinesBecomeSpaces
- titleCappedAt200
