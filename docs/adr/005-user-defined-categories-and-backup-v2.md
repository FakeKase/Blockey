# ADR 005: User-defined categories and Backup v2

Status: proposed. Not to be marked accepted until phase 5.1 of `docs/feedback-plan-2026-11.md`
has checked every mechanism named here against the code.
Date: 2026-11-03

Owner sign-off (2026-11-03) on three decisions that go beyond the plan:
1. Restoring a backup merges categories by slug and never deletes a definition. Calendar events
   outside the backup still point at those definitions.
2. A new category name may not match any existing unarchived category, built-in or custom.
3. Built-ins can be archived, but at least one category must stay unarchived.
The decisions are approved. The *mechanisms* stay proposed until phase 5.1.

Amended 2026-11-04 with two new facts, both recorded in the amendment at the end of this ADR:
4. Plan task 0.3 **passed** on the owner's phone. Thai slugs survive iCloud and an outside edit, so
   slugs are stored as typed and the `.toLatin` fallback is dropped.
5. Owner decision: category colour is **palette + custom**. The curated, measured palette comes
   first, plus an "Other…" option that opens the system colour picker and warns about poor
   readability. This replaces "No free colour picker" in the Palette section.

## Context

Feedback from the user (`docs/feedback-plan-2026-11.md`, 1a): "I want custom categories". The
owner's answer (Q3): add new ones, let the user rename, re-emoji and recolour the six built-ins,
and make deleting a category archive it.

Everything in this ADR is a decision. None of it is built. Where the text says what the code does
*today*, the line has been checked against the source on 2026-11-03.

### What the code does today

- `BlockCategory` is a fixed six-case `enum BlockCategory: String` (`Models/BlockCategory.swift:10`)
  with `.fallback = .deepWork` (`:87`). Its doc comment (`:5-9`) says it is "deliberately a fixed
  enum rather than a user-editable SwiftData model" so that "there is no colour table to lose".
- The category rides in the block's token as `c=<slug>` (`Calendar/BlockToken.swift:8`), and
  parsing maps it straight through the enum: `value("c").flatMap(BlockCategory.init(rawValue:)) ??
  .fallback` (`BlockToken.swift:55`). **An unknown slug silently becomes Deep work**, and
  `BlockeyTests/EdgeCaseTests.swift:222` asserts exactly that.
- The collapse is not only a display problem, because several paths write the collapsed value back:
  - `BlockDetailSheet` seeds its picker from the already-collapsed `block.category` (`:29`) and
    passes it on every Save (`:74-78`). `CalendarService.update` then rebuilds the url whenever a
    category is passed (`CalendarService.swift:252-255`). Opening an unknown-slug block and tapping
    Save permanently rewrites its slug to `deep`.
  - Return to inbox and Clear the day used to build the new `TaskItem` from `block.category` in
    `TodayView`, so a block with an unknown slug came back to the inbox as Deep work. Fixed in
    phase 1: both paths now live in `Blockey/Planning/DayPlanner.swift` (`DayPlanner.returnToInbox`
    and `DayPlanner.clear`, moved there in task 2.0) and take `block.token?.categorySlug`, falling
    back to `deep` only when the token carries no slug.
  - Restore maps every task and template row through the enum (`Models/Backup.swift:94`, `:107`).
    Fixed in phase 1: restore now stores `categoryRaw` verbatim (`Backup.swift:111`, `:126` as of
    2026-11-04). Other `Backup.swift` line numbers in this section are from 2026-11-03; the file has
    since grown (`activityDays`, issue #7).
- `BlockToken.url` always writes `c=` (`BlockToken.swift:64`), so a block whose token had no
  category gains `c=deep` on its first rewrite. `:70` ends in a force unwrap, which CLAUDE.md forbids.
- `TaskItem.categoryRaw` and `TemplateRow.categoryRaw` are already plain `String`s
  (`Models/TaskItem.swift:14`, `Models/DayTemplate.swift:50`). Only their computed accessors know
  about the enum.
- Backup is version 1 (`Backup.swift:16`), holds tasks, templates and assignments, and carries no
  settings and no categories. Restore never reads `version`. Decoding happens in
  `BackupFile.init(configuration:)` (`:178-185`), before the user is asked to confirm, and restore
  rolls back if the save fails (`:117-126`).

### What the earlier ADRs promised and the code never did

ADR 002 already specified this shape: an immutable slug with editable name and colour (`002:99-101`),
`categorySlug: String?` on `Block` (`002:127`), and a recovery step where, after a sandbox wipe,
"categories are reconstructed from the blocks themselves", each distinct slug becoming a Category
with "a colour chosen deterministically from a hash of the slug into a fixed palette"
(`002:206-209`). **None of that exists.** There is no category model, no palette, no hash and no
reconstruction pass. The code drifted to an enum, and the enum's comment rationalised the drift.

### The constraint

**Correctness of data the user cannot see.** The token lives in the user's calendar, outside the
app, and is read back by every future build. A custom category that a later build, an older build,
a restore or a Save quietly turns into Deep work is a silent data loss that nobody notices until a
month of colours is wrong. Speed matters less: the plan already splits this into a half-day phase
that stops the loss and a later phase that adds the feature.

## Options

### A. Definitions in SwiftData, slug in the token, built-ins in code

A new `@Model CategoryDefinition` holds name, emoji, symbol, palette index, sort order and an
archive date, keyed by slug. Rows exist only for custom categories and for built-ins the user has
customised. The six built-ins stay in code, so they always render correctly with no rows at all.

Costs: one new model, and a catalog passed to views in place of the enum at the call sites (53
references to `BlockCategory`, `.category` or `categoryRaw` across 15 files today). Definitions are
local data, so deleting the app without a backup loses names, emoji and chosen colours.

Buys: rename and recolour are a write to one row and never touch a calendar event. Past blocks
follow the definition automatically. The token stays as small as it is now.

### B. Name, emoji and colour in every block's url

Costs: every block carries its own copy. A rename either leaves old blocks stale or rewrites months
of events in the user's iCloud calendar. Keeping copies consistent is a sync engine, which is option
B from ADR 001 wearing a trenchcoat. Buys: survives app deletion with no backup. **Rejected.**

### C. One calendar per category

Costs: breaks ADR 002 tier 1 ("is this event a block? membership in the Blockey calendar"), and
recategorising a block becomes a calendar move, which is exactly the operation the SDK header says
changes `eventIdentifier`. Buys: Calendar.app colours for free. **Rejected.**

## Decision

**A.** The slug in the token is the only thing a block knows about its category. Everything else is
looked up, and a lookup that fails still renders something honest.

### Built-ins stay in code; rows only override

- The six built-ins keep their slugs forever: `deep`, `meeting`, `admin`, `personal`, `health`,
  `rest`. Their default name, emoji, symbol and palette index move into `Catalog/` as plain data.
- A built-in the user has customised gets a `CategoryDefinition` row with the built-in's slug. The
  row overrides the defaults. Deleting the row is "Reset to default", which is also the escape hatch
  for a customisation gone wrong.
- A built-in can be archived like any other category (an override row with `archivedAt` set). At
  least one category must stay unarchived. A nil or absent slug still resolves to `deep` even when
  `deep` is archived; archived means "not offered", never "not rendered".

### Slugs

- Custom slugs are `u-` followed by the normalised name. Built-in slugs never start with `u-`, so a
  custom slug can never collide with a built-in, including one added in a later version.
- Normalisation, in order: NFKC (so full-width Latin becomes ASCII), locale-independent lowercase,
  then walk the string by grapheme cluster. A cluster whose base scalar is a letter or number is
  kept **whole, combining marks included**. Anything else is a separator; runs of separators
  become one `-`, and leading or trailing `-` is dropped.
- **Thai keeps its marks.** `งานบ้าน` mints `u-งานบ้าน`. Folding or dropping marks would make
  `ข้าว` (rice) and `ขาว` (white) the same slug. One visible side effect of NFKC: SARA AM (U+0E33)
  decomposes to U+0E4D U+0E32. It renders the same and is deterministic, which is what matters.
  **Verified 2026-11-04** (plan task 0.3, ADR 002's last addendum): a percent-encoded Thai slug with
  vowel and tone marks and a space survived an iCloud sync and an edit on another client. Slugs are
  stored as typed. There is no transliteration step.
- The body is capped at **32 grapheme clusters**, counted by cluster so a Thai mark is never cut off
  its base consonant.
- A name with no letters or numbers (emoji only, say) mints `u-` plus 6 random characters from
  `a-z0-9`. The random source is injected so the test is deterministic.
- Collisions are checked against every existing slug, **archived ones included**, and resolved by
  appending `-2`, `-3`, and so on after the cap.
- **A slug never changes after creation.** Rename edits the definition, not the slug.
- In the token the slug is stored verbatim as NFC and percent-encoded by `URLComponents`. Parsing is
  case-sensitive (`DEEP` is not `deep`).

### Names

- Rejected: empty, whitespace-only, and names made only of invisible characters (U+200B, U+200C,
  U+200D, U+2060, U+FEFF). Leading and trailing whitespace is trimmed before saving.
- Rejected: a name equal to the current display name of any unarchived category, built-ins included,
  compared through `TitleKey.normalize` (ADR 006). Two identical names in one picker cannot be told
  apart. The plan names only built-ins; extending the rule to all active categories is this ADR's
  decision, for the same reason.
- No cap on the number of categories. Past the palette size, colours repeat deterministically and
  the required emoji keeps them apart.

### Archive, never delete

- "Delete" in the editor sets `archivedAt`. Blocks keep their slug and keep rendering from the
  archived definition, name, emoji and colour intact.
- Archiving asks whether to move the N inbox tasks and M template rows that use the category to
  another one. The user may decline; nothing moves unless they choose.
- **Archived categories and new work.** Pickers never offer an archived category as a *new* choice.
  A picker always shows the item's *current* value, even if it is archived or unknown, so opening
  something is never a silent change. A template row left pointing at an archived category still
  stamps with that slug, and the block renders from the archived definition. This is deliberate:
  archiving hides a category from future choices; it does not rewrite history.
- **Save only writes what changed.** `BlockDetailSheet.onSave` passes the category only if the user
  changed it. `update` already takes an optional (`CalendarService.swift:242`), so the fix is in the
  sheet.

### Unknown slugs get a stand-in, not the fallback

An unknown slug is one with no built-in and no definition: the definition was lost with the app,
the slug was hand-edited in Calendar.app, or a newer build minted it. It resolves to a stand-in:

- **Name** recovered from the slug: drop `u-`, turn `-` into spaces. `u-งานบ้าน` reads `งานบ้าน`.
  This is best effort. Case, collapsed punctuation and whether `-2` was a suffix or part of the name
  are all lost, so the definition is always the real source when there is one.
- **Colour** from a stable hash: **32-bit FNV-1a** over the slug's UTF-8 bytes (offset basis
  `0x811C9DC5`, prime `0x01000193`), modulo the palette count. **Never Swift `hashValue`**: it is
  seeded per process, so the same block would change colour on every launch. A test pins one slug to
  a hard-coded index, which is the only way to catch someone "simplifying" this to `hashValue`.
- **Glyph** is a generic 🏷️ (symbol `tag`), so the user can see the category is not recognised rather
  than being told something false.
- The block sheet offers **Add as category**, which inserts a definition with that exact slug. Every
  block carrying the slug is fixed at once, with no calendar writes.

This replaces ADR 002's reconstruction (`002:206-209`). The difference is that nothing is written
on launch. Resolution happens on read, so there is no reconciliation pass to build, run or get wrong,
and the user decides which stand-ins become real categories.

### Palette

A fixed, measured `CategoryPalette` of about 10 to 12 light/dark pairs. ~~No free colour picker.~~
**Amended 2026-11-04:** the palette comes first, and an "Other…" option allows one custom colour per
category. See "Amendment: palette + custom colour" at the end; the rules below still hold for every
palette swatch. Every swatch must meet the fill-contrast floor in both modes (design review M10), and the built-in
swatches must be pairwise distinguishable above a ΔE floor (M9); both are tests. The six current
built-in tints (`BlockCategory.swift:68-77`) are the first candidates for six of the slots, so
nothing on screen changes unless the designer's measurements say it must. A stored `paletteIndex`
outside the range wraps modulo the count, so a backup from a build with a larger palette cannot
crash an older one. Colour is never the only signal; emoji is required.

### Contract

```swift
// Catalog/: pure. No EventKit, no SwiftUI, no SwiftData, same rules as Scheduling/.
struct CategoryDefinitionValue: Hashable, Sendable {
    var slug: String
    var name: String
    var emoji: String
    var symbolName: String
    var paletteIndex: Int
    var customColorHex: String?    // amended 2026-11-04; a valid "#RRGGBB" wins over paletteIndex
    var sortIndex: Int
    var archivedAt: Date?
}

struct ResolvedCategory: Hashable, Sendable {
    let slug: String?          // nil only for the fallback of an absent slug
    let name: String
    let emoji: String
    let symbolName: String
    let colorChoice: ColorChoice     // amended 2026-11-04: .palette(index) or .custom(hex)
    let colors: CategoryColors       // light and dark records, already derived
    let isArchived: Bool
    let origin: Origin         // .builtIn, .custom, .standIn
}

struct CategoryCatalog: Sendable {
    init(definitions: [CategoryDefinitionValue])
    func resolve(_ slug: String?) -> ResolvedCategory          // never fails
    func choices(current: String?) -> [ResolvedCategory]       // active ones, plus `current` if not
    func validate(name: String, editing slug: String?) -> NameProblem?
}

enum CategorySlug {
    static func mint<R: RandomNumberGenerator>(name: String, taken: Set<String>,
                                               random: inout R) -> String?
    static func displayName(fromSlug slug: String) -> String
}

// Calendar/BlockToken.swift: the token stops knowing the enum.
struct BlockToken {
    var id: UUID
    var categorySlug: String?      // verbatim, NFC; nil when absent, empty or whitespace
    var sourceTaskID: UUID?
    var extraQueryItems: [URLQueryItem]   // round-tripped untouched
}

// Models/CategoryDefinition.swift
@Model final class CategoryDefinition {
    @Attribute(.unique) var slug: String
    var name, emoji, symbolName: String
    var paletteIndex, sortIndex: Int
    var customColorHex: String?    // amended 2026-11-04; ships in the model's first version
    var archivedAt: Date?
}
```

`CategoryDefinition` is registered in the container (`BlockeyApp.swift:13-18`). `TaskItem` and
`TemplateRow` keep the field name `categoryRaw` and gain slug accessors beside it, so there is no
rename and no migration of existing rows. Landmine: SwiftData's `.unique` resolves a conflicting
insert as an upsert rather than an error, so "a duplicate slug is rejected" has to be checked by the
catalog before insert, never left to the attribute.

The token rules that phase 1 ships first, on their own, because they stop the loss before any
feature exists: keep `c=` verbatim; keep unknown query items, in order, duplicates included; an
absent category stays absent on rewrite; an empty or whitespace `c=` counts as absent; the first of
duplicate `c=` items wins; no force unwrap. `category` survives as a computed fallback until every
caller takes slugs.

### Backup v2

The constraint is that both directions of version skew are realistic: the weekly re-sign makes it
normal to have an old build on the phone and a new file in iCloud Drive, or the reverse.

- **Shape.** `version` becomes 2. Two new top-level fields, `categories: [Category]?` and
  `settings: Settings?`. Every field in `Settings` is optional on its own. Optional because
  synthesised `Codable` throws on a missing key, so non-optional new fields would make every v1
  file fail to import.
- **Settings** carried: day start and end, snap, hidden calendar IDs, alarm on/off and minutes
  before, and the plan's new `Skip preview`. Not carried: one-time flags such as
  `hasSeededStarterTemplates` (`BlockeyApp.swift:31`) and the device-specific `blockeyCalendarID`
  (`CalendarService.swift:60`). This **closes known gap 6** once restoring settings is verified.
- **Version gate.** A file whose `version` is greater than this build's is refused before the
  confirmation dialog, with "This backup is from a newer version of Blockey. Update the app, then
  try again." It is never half-read.
- **Validate before deleting.** Decoding already precedes the first delete. v2 adds a pure
  validation step between them that produces the exact restore plan: settings clamped (day window
  within 0 to 1440 with start before end, else ignored; snap one of 5, 10, 15 or 30, else ignored;
  alarm minutes clamped to 0 to 60), duplicate slugs in the file resolved first-wins and counted.
  Only a valid plan reaches `restore(into:)`; the existing rollback stays.
- **Unknown calendar IDs** in the file are kept. They are harmless by construction: the hidden set
  is only ever used for membership (`CalendarService.swift:184-186`), so an ID that matches no
  calendar on this device hides nothing.
- **Slugs are restored verbatim.** Tasks and template rows keep unknown and archived slugs exactly;
  the collapse that was at `Backup.swift:94` and `:107` went in phase 1. A task whose slug has no
  definition renders as a stand-in, like a block.
- **Category colour** rides in `Category.customColorHex: String?`, optional. See the amendment at
  the end for its shape, its validation and why it is kept verbatim.
- **Categories merge by slug; restore never deletes a definition.** This is the one deliberate
  exception to "replace rather than merge" (`Backup.swift:80-84`). A definition is referenced by
  calendar events that are not in the backup, so deleting one would damage data the file cannot put
  back. Each definition in the file is upserted by slug; definitions not in the file are left alone.
- **nil versus empty `categories`.** `nil` means the file predates categories (any v1 file).
  `[]` means a v2 phone with no customisations. **Both change nothing.** The distinction is stated
  here so nobody later "fixes" `[]` into a wipe.
- **The restore warning counts categories**, as it already counts tasks and templates
  (`Backup.swift:147-158`).

**An older build reading a v2 file** decodes it (unknown keys are ignored) and ignores the new
fields. That is not the whole cost: today's build also collapses every custom slug on tasks and
template rows to `deep` while restoring (`Backup.swift:94`, `:107`). The plan says an old build loses
"only the new fields", and that is wrong for the build on the phone today. The mitigation is to ship
the verbatim restore in phase 1 with the token fix, well before any build can mint a custom slug,
so that by the time v2 files exist the installed build no longer collapses them. **Shipped in phase
1** (`Backup.swift:111`, `:126`), so the mitigation is in place before any custom slug exists.

### Thai slugs survive iCloud (resolved 2026-11-04)

This section used to hold a pre-decided fallback (mint custom slugs through
`applyingTransform(.toLatin)` plus `.stripDiacritics`) in case plan task 0.3 showed Thai `c=` values
mangled by Calendar.app or iCloud CalDAV. The owner ran 0.3 on 2026-11-04 with the debug probe
(`Calendar/TokenProbe.swift`) and it **passed**: the token id, a percent-encoded Thai slug with marks
and a space, and the `t=` link all parsed back unchanged after an iCloud sync and an edit made on
another client (ADR 002, addendum of 2026-11-04). **The fallback is dropped.** Slugs are minted as
typed by the rules above, and the mark-preservation rules are live code, not dead code.

What 0.3 did not record: whether the url stayed byte-identical and whether `eventIdentifier`
changed. Neither matters here, because identity and category ride on the *parsed* token. If a later
iOS or iCloud change ever starts mangling the token, that is ADR 002's escape hatch (the `notes`
trailer), not a change to slug minting, because slugs already in calendars cannot be re-minted.

## Consequences

**Becomes easy**
- Rename, re-emoji and recolour are one row write. Past blocks follow, and no calendar event is
  touched.
- A lost definition is cosmetic: the block keeps its own name (from the slug), a colour that is the
  same on every launch and every device, and an honest glyph, and one tap restores it.
- Adding a built-in later is safe, because no custom slug can ever equal it.
- Backup covers everything that lives only on the phone, settings included.

**Becomes hard**
- Every view that takes `BlockCategory` today has to take a `ResolvedCategory` from a catalog in the
  environment. That is the bulk of the work and it lands last, behind tests.
- Pickers have two lists to keep straight: what may be chosen, and what is currently set.
- Two version-skew directions now need fixtures: a checked-in v1 file and a checked-in v2 file.

**Cannot undo**
- **Slugs are permanent.** Once a custom slug is in someone's iCloud calendar it is there for good;
  the minting rules can change for new slugs, never for old ones, and every future parser must
  accept every slug ever minted.
- The `u-` prefix and the six built-in slugs are a public format from the first custom category on.

**What this amends and supersedes**
- **ADR 002, consequence 3** (`002:206-209`): replaced by the on-read stand-in above. Tier 2 of
  ADR 002's table becomes "`?c=` slug, else the fallback" (there is no `BlockMeta` to consult). The
  name is recovered from the slug rather than title-cased, because title-casing is meaningless for
  Thai and lossy for everything else.
- **ADR 003, "What we still owe"** (`003:68-71`): the backup now also carries categories and
  settings. Deleting the app still loses them without one.
- **`BlockCategory.swift:5-9`**, the "deliberately a fixed enum" comment, is superseded. Its premise
  ("there is no colour table to lose") is kept by the FNV-1a stand-in rather than by forbidding
  customisation. The enum may survive briefly as a shim for the built-in defaults and is deleted
  once the last caller takes slugs.

**`BlockMeta` is still not built, and nothing here needs it.** Known gap 8 is unchanged. Worth
noting for whoever revisits it: the one job ADR 002 gave `BlockMeta`, the link back to a source task,
already rides in the token as `t=` (`BlockToken.swift:8`, `:56`).

**Not verified**
- ~~Gap 7.~~ **Closed 2026-11-04.** Task 0.3 passed on the owner's phone (ADR 002 addendum), so it
  no longer gates phase 3. Verified once, on one phone and one outside client; a regression from a
  future iOS or iCloud change would show up as stand-ins, not as data loss.
- That adding `CategoryDefinition` to the container migrates an existing store with no data loss.
  Adding a model should be a lightweight change, but it is checked the way ADR 003 checked
  reinstalls: install over a populated simulator build and query the store.
- The palette. No swatch has been measured yet.
- The custom-colour derivation. Its lightness and chroma targets come from the measured palette, so
  they cannot be set until Story 2 (#12) lands, and how a derived colour looks next to the curated
  ones is a judgement for a device screenshot, not a test.
- Old-build behaviour on a v2 file is reasoned from the code above, not observed.

**Escape hatch**
The seam is `CategoryCatalog.resolve`. Every view asks it and nothing else. If definitions in
SwiftData prove a mistake, the catalog can be fed from any other source (a JSON file in iCloud Drive,
say) without touching a view or a single calendar event, because blocks only ever held the slug.
Backing out of custom categories entirely means archiving every custom definition: blocks keep
rendering from them, and nothing in the calendar has to change.

## Build order

Matches phase 1 and phase 3 of `docs/feedback-plan-2026-11.md`. Test names are in its Appendix A.

1. `backend-engineer`: token round-trip tests (A.1), then `BlockToken.categorySlug`, kept verbatim,
   unknown items preserved, force unwrap removed. Starts now.
2. `frontend-engineer`: `BlockDetailSheet.onSave` passes the category only when changed. Check on a
   seeded simulator block.
3. `backend-engineer`: restore stores task and row slugs verbatim (the old-build mitigation). Ships
   with 1 and 2.
4. Owner: plan task 0.3 on a real phone. **Done 2026-11-04, passed.** Step 5 may start.
5. `backend-engineer`: `CategorySlug`, `CategoryCatalog`, `CategoryPalette` tests (A.4), then
   `Catalog/`. The designer supplies measured swatches (Story 2, #12). Then the colour math and
   custom-colour derivation tests (A.4b), then `CategoryColorMath` and `CustomCategoryColor`.
6. `database-engineer`: `CategoryDefinition`, registered in the container, with `customColorHex`
   in its first version, plus slug accessors on `categoryRaw`. Run the install-over migration check.
7. `backend-engineer`: `Block` and `CalendarService` take and return slugs.
8. `frontend-engineer`: catalog in the environment, the three pickers, glyph and tint sites,
   `Add as category`, then the category editor, then its "Other…" colour row (plan task 3.8b).
9. `backend-engineer`: Backup v2 tests (A.5) with checked-in v1 and v2 fixtures, including a v2
   fixture without `customColorHex`, then the implementation.
10. `qa-engineer` and `architect`: phase 5.1. Grep every mechanism above before this ADR is marked
    accepted.

## Amendment: 2026-11-04, palette + custom colour (owner decision)

**Decision (owner, 2026-11-04).** Category colour is "palette + custom". The curated, measured
`CategoryPalette` is the first thing the editor offers. After the swatches comes **Other…**, which
opens the system `ColorPicker` and warns when the result will be hard to read or hard to tell apart.
This reverses "No free colour picker" in the Palette section. Everything else in that section
(measured swatches, both-mode floors, modulo wrap, emoji required) still holds for the palette.

Checked against the source on 2026-11-04 before writing: there is no `CategoryStyle`,
`CategoryPalette`, `CategoryDefinition`, `paletteIndex`, `ColorPicker`, contrast or ΔE code anywhere
in `Blockey/`. Colours today are six hard-coded RGB pairs (`BlockCategory.swift:68-77`), and chips
derive fill and border from them with alpha (`TimelineCanvas.swift:393-394`). Every mechanism
below is new.

### What is stored, and what wins

- `CategoryDefinition` (and `CategoryDefinitionValue`) gain **`customColorHex: String?`**, next to
  `paletteIndex`, which stays non-optional. The model does not exist yet, so the field ships in its
  first version and there is no schema change to plan for.
- Format: `#RRGGBB`, sRGB, 8 bits per channel, no alpha. The writer always emits uppercase. The
  parser (`SRGB(hex:)`) accepts exactly `#` plus six hex digits, either case, and nothing else:
  no 3-digit or 8-digit forms, no missing `#`, no whitespace.
- **What wins:** a `customColorHex` that parses wins. Anything else (nil, empty, unparseable) falls
  back to `paletteIndex`, wrapped modulo the palette count as before. Resolution never fails.
- **Writes:** choosing a palette swatch sets `paletteIndex` and **clears** `customColorHex`.
  Choosing Other… sets `customColorHex` and leaves `paletteIndex` alone, so a bad hex later still
  lands on the swatch the category had before. Picking Other… on an untouched built-in creates its
  override row as usual. Reset to default (deleting the row) drops both.
- Only the one picked colour is stored, never the derived values. Derivation is a pure function, so
  improving it later recolours every custom category consistently, and there is nothing derived to
  go stale in a backup.
- Identifiers use `Color` (American) to match SwiftUI's `Color` and `ColorPicker`; prose stays
  British.

### Deriving light, dark, fill, border and onFill from one colour

One colour cannot serve both modes. A tint that reads on white sits at about 1.2:1 on black, which
is the M10 failure this codebase already fixed once by hand (`BlockCategory.swift:65-67`). So the
picked colour contributes **hue and chroma**; **lightness comes from the palette**.

Pure code in `Catalog/` (Foundation only, same rules as `Scheduling/`):

```swift
struct SRGB: Hashable, Sendable { var r, g, b: Double }     // 0...1; init?(hex:), var hex
struct CategoryColorRecord: Hashable, Sendable { var spine, fill, border, onFill: SRGB }
struct CategoryColors: Hashable, Sendable { var light, dark: CategoryColorRecord }
enum ColorChoice: Hashable, Sendable { case palette(Int), custom(String) }  // canonical hex

enum CategoryColorMath {
    static func contrastRatio(_ a: SRGB, _ b: SRGB) -> Double   // WCAG 2 relative luminance
    static func deltaE76(_ a: SRGB, _ b: SRGB) -> Double        // CIELAB, D65
    // plus OKLab/OKLCH conversion and sRGB gamut mapping, internal
}

enum CustomCategoryColor {
    static func derive(from picked: SRGB, targets: DerivationTargets = .measured) -> CategoryColors
    static func assess(_ colors: CategoryColors, surfaces: ColorSurfaces,
                       others: [(slug: String, colors: CategoryColors)]) -> [ColorConcern]
}
```

- **Derive** converts the pick to OKLCH. For each mode and each of `spine`, `fill` and `border` it
  keeps the hue, sets lightness to that role's target, scales chroma by the role's factor and caps
  it, then gamut-maps into sRGB by lowering chroma only (fixed-iteration bisection, so it is
  deterministic), and clamps. `onFill` is the mode's ink (the `.primary` value), not derived.
  OKLCH because it holds hue steady while lightness moves; CIELAB drifts blue toward purple.
- **Targets** (`DerivationTargets.measured`) are the designer's numbers, fit to the measured
  records from Story 2 (#12): per mode and role, a lightness, a chroma factor and a chroma cap. A
  derived colour therefore sits at the same lightness as its curated neighbours.
- **Greys.** A pick with OKLCH chroma under about 0.02 has no meaningful hue. It derives to greys at
  the target lightness, and the assessment then flags it as looking like a meeting.
- **Measured with the review's method.** Checks use WCAG 2 contrast and **CIE76 ΔE in CIELAB**,
  because that is what `docs/design-review.md` used (M9, M10) and what the redesign targets are
  written in. Derivation in OKLCH, measurement in CIELAB is deliberate: the thresholds stay
  comparable with every number already in the docs.

**Assessment** runs the redesign plan's section 2 floors, light and dark, against the real surfaces
(`ColorSurfaces`: canvas and meeting fill per mode):

| Concern | Check | Floor |
|---|---|---|
| `lowContrast` | `onFill` on `fill` | 4.5:1 |
| `lowContrast` | `spine` and `border` on canvas | 3:1 |
| `lowContrast` | `fill` on canvas | ΔE 8 and 1.3:1 |
| `looksLikeMeeting` | `fill` vs meeting fill | ΔE 15, plus the designer's chroma gap |
| `closeTo(slug)` | `fill` vs each other **active** category's `fill` | ΔE 10 |

Concerns come back worst first, each naming its mode. The same function is the palette's test:
every curated swatch must assess to `[]`, which replaces the separate fill-contrast check in A.4.
Colour-blind simulation is not part of the warning. It stays a best-effort measurement for the
palette (Story 2), and the required emoji carries the distinction.

**Warn, do not auto-adjust (recommended and adopted).** Lightness is always derived; that is how
one colour becomes eight, not a correction. Beyond that the app **only warns**. It never nudges hue
or chroma away from a neighbour, and Save is always allowed:
- a nudge away from one category can land on another, and two custom categories could each push
  the other, so the result would depend on edit order;
- it would override an explicit choice in a single-user app whose owner asked for a warning;
- the emoji is required, so a colour clash is a legibility cost, not a data problem.

The editor shows a live preview chip in **both modes** under the picker, because the derived spine
will not be exactly the picked colour, and one line of copy for the worst concern ("Looks like a
meeting in dark mode", "Close to Admin", "Title may be hard to read"; the designer owns the words).
Honest expectation: because lightness is fixed to measured targets, `lowContrast` should almost
never fire. The concerns users will actually see are `looksLikeMeeting` and `closeTo`. A hue-sweep
test pins that.

### Too close to the meeting style or another category

"Meeting style" means the **fixed-event chip** (`FixedEventChip`, `TimelineCanvas.swift:438`), not
the built-in `meeting` category, which is an ordinary block category with a hue.
- Against meetings: `looksLikeMeeting` when the derived fill in either mode is under ΔE 15 from the
  meeting fill or below the chroma gap. Today the meeting fill is `Color.primary` at 5 to 6 percent
  alpha (`TimelineCanvas.swift:462`), so until Story 1 and Story 3 make it opaque, the surfaces value
  is that alpha composited over the canvas colour.
- Against categories: `closeTo(slug)` for each **unarchived** category other than the one being
  edited, palette-coloured or custom, under ΔE 10 in either mode. Archived categories are skipped:
  they are not offered, so warning about them is noise.
- Both are **edit-time only**. Nothing is stored, nothing re-warns later when another category
  changes, and nothing blocks Save.

### Backup v2

- `BlockeyBackup.Category` carries `slug`, `name`, `emoji`, `symbolName`, `paletteIndex`,
  `sortIndex`, `archivedAt: Date?` and **`customColorHex: String?`**.
- `customColorHex` is optional so that v1 files (no `categories` at all) and any v2 file written
  before the field existed both decode. It should ship in the first v2 anyway, so there is one v2
  shape in practice.
- **Restore canonicalises.** A valid hex is stored uppercase. Anything invalid is stored as `nil`,
  so the category restores on its `paletteIndex`. This differs from slugs, which are kept verbatim
  because calendar events reference them; nothing outside the app references a colour. Resolution
  still treats an invalid stored hex as absent, as a second line of defence.
- **`customColorHex` means `#RRGGBB` sRGB, permanently.** If a later build wants a wider gamut, it
  adds a new field. Reinterpreting this one would make an older build misread a newer file without
  any version bump to stop it.
- `paletteIndex` outside the range still wraps modulo the count.

### The deleted-app stand-in

Unchanged in substance: an unknown slug takes its colour from **32-bit FNV-1a modulo the palette
count**, as specified above, and never from a custom colour. It cannot know one: the colour lived
only in SwiftData and the backup, and the token carries only the slug. So after deleting the app
without a backup, a custom-coloured category's blocks render in their FNV swatch until the backup
is restored or the user re-adopts them. Two additions:
- **Add as category** creates the definition with `paletteIndex` set to the stand-in's FNV index
  and no `customColorHex`, so adopting a stand-in never changes its colour on screen.
- A stand-in resolves to `ColorChoice.palette(fnvIndex)`. A test pins that a stand-in never
  produces `.custom`.

### Effect on the `CategoryStyle` seam (redesign Story 2, #12)

The redesign plan (section 2, "The seam with custom categories") has views read a small
`CategoryStyle` (title, emoji, symbolName, spine, fill, border), built today from `BlockCategory`
and later from `ResolvedCategory`. Custom colours keep that seam and add constraints, so #1 phase 3
and #12 do not collide:
1. **Colours are numbers in `Catalog/`, not asset-catalog names.** The derivation and the warning
   need sRGB values, and a custom colour cannot be an asset-catalog entry. Story 2 records its six
   records as `CategoryColors` values in a Foundation-only `Catalog/` file, and Story 1 exposes the
   canvas and meeting fill as numeric `SRGB` pairs beside the `UIColor` it builds from them.
2. **Story 2 owns the value types, #1 owns the palette.** Story 2 creates `SRGB`,
   `CategoryColorRecord`, `CategoryColors` and the six built-in records. #1 task 3.4 wraps them in
   `CategoryPalette` (slots 7 to 12, FNV lookup). That keeps Story 1's "do not create
   `CategoryPalette` here".
3. **`CategoryColorMath` is built once, by whichever lands first.** With the recommended order
   (redesign Q9) that is Story 2's qa task ("tests that every record meets the floors"), which needs
   contrast and ΔE76 anyway. #1 task 3.3b then adds only OKLCH, gamut mapping, `derive` and
   `assess`. The designer's measurement script and the app must use the same formulas.
4. **`CategoryStyle` is a plain struct with stored colours**, plus `onFill`, built by one adapter
   from any `CategoryColors`: `CategoryStyle(BlockCategory)` until task 3.7,
   `CategoryStyle(ResolvedCategory)` after. It must not be keyed by an enum or switch over
   built-ins, or custom colours have nowhere to go. Under that rule, task 3.7 is still a swap of the
   producer, as the redesign plan intends.
5. `ResolvedCategory` replaces `paletteIndex` with `colorChoice` and `colors` (contract above), so
   no view ever looks up the palette itself.

### Consequences of this amendment

- **Easy:** a category past the palette size can get its own colour; built-ins can be recoloured
  freely; the palette tests and the editor warning are one function.
- **Hard:** the editor gains a picker, a two-mode preview and warning copy (task 3.8b). Derivation
  targets depend on Story 2's measurements, so 3.3b cannot finish before Story 2.
- **Cannot undo:** `customColorHex` as `#RRGGBB` sRGB is part of the backup format from the first v2
  file.
- **Escape hatch:** if custom colours prove a mistake, `CategoryCatalog.resolve` ignores
  `customColorHex` (one line) and every category falls back to its `paletteIndex`. The stored values
  stay, so the decision can be reversed again without data loss.
