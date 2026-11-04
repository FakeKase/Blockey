# ADR 005: User-defined categories and Backup v2

Status: accepted, 2026-11-04. Phase 5.1 (addendum at the end): 85 of 99 rows match, 13 differ
(nine amended here because the code is right, two owned by redesign stories, two code follow-ups)
and the 1 missing check, install-over migration, has since passed (see "F1 result" at the end).
`scripts/test.sh` is green at 724 tests.
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

When this ADR was written, none of it was built. Phase 1 and phase 3 have since built all of it
(phase 3 in 6c3e723..3158fc5 on `sprint-1`). The section below describes the code as it was on
2026-11-03, which is the problem the decision answers. Each bullet now also says where that code
went; line numbers marked "now" were checked on 2026-11-04.

### What the code did on 2026-11-03

- `BlockCategory` is a fixed six-case `enum BlockCategory: String` (`Models/BlockCategory.swift:10`)
  with `.fallback = .deepWork` (`:87`). Its doc comment (`:5-9`) says it is "deliberately a fixed
  enum rather than a user-editable SwiftData model" so that "there is no colour table to lose".
  The enum is still there (now the same lines), as a shim; see the addendum, row 96.
- The category rides in the block's token as `c=<slug>` (`Calendar/BlockToken.swift:8`), and
  parsing mapped it straight through the enum: `value("c").flatMap(BlockCategory.init(rawValue:)) ??
  .fallback` (`BlockToken.swift:55` then). **An unknown slug silently became Deep work**, and
  `BlockeyTests/EdgeCaseTests.swift:222` asserted exactly that. Fixed in phase 1: the slug is kept
  verbatim (now `BlockToken.swift:86`), and the test now asserts a stand-in (now
  `EdgeCaseTests.swift:234-239`).
- The collapse is not only a display problem, because several paths write the collapsed value back:
  - `BlockDetailSheet` seeded its picker from the already-collapsed `block.category` (`:29` then)
    and passed it on every Save (`:74-78` then). `CalendarService.update` then rebuilt the url
    whenever a category was passed (`CalendarService.swift:252-255` then). Opening an unknown-slug
    block and tapping Save permanently rewrote its slug to `deep`. Fixed in phase 1: the sheet seeds
    from the raw slug (now `BlockDetailSheet.swift:32`) and passes a slug only when it changed (now
    `:81`, via `CategorySelection.slugToSave`, `Catalog/CategoryPicking.swift:130-132`); `update`
    rewrites the url only for a non-nil slug (now `CalendarService.swift:427-436`).
  - Return to inbox and Clear the day used to build the new `TaskItem` from `block.category` in
    `TodayView`, so a block with an unknown slug came back to the inbox as Deep work. Fixed in
    phase 1: both paths now live in `Blockey/Planning/DayPlanner.swift` (`DayPlanner.returnToInbox`
    and `DayPlanner.clear`, moved there in task 2.0) and take `block.token?.categorySlug`, falling
    back to `deep` only when the token carries no slug (now `DayPlanner.swift:606`, `:703`, `:795`).
  - Restore mapped every task and template row through the enum (`Models/Backup.swift:94`, `:107`
    then). Fixed in phase 1: restore stores `categoryRaw` verbatim (now `Backup.swift:255`, `:270`).
- `BlockToken.url` always wrote `c=` (`BlockToken.swift:64` then), so a block whose token had no
  category gained `c=deep` on its first rewrite, and `:70` ended in a force unwrap. Fixed in phase
  1: `c=` is written only when there is a slug (now `BlockToken.swift:101-103`), and `url` is
  optional with no force unwrap (now `:95-110`).
- `TaskItem.categoryRaw` and `TemplateRow.categoryRaw` were already plain `String`s
  (`Models/TaskItem.swift:14`, now `Models/DayTemplate.swift:56`). Only their computed accessors
  knew about the enum. Both now have `categorySlug` accessors over the same storage (now
  `TaskItem.swift:88-91`, `DayTemplate.swift:81-84`).
- Backup was version 1 (`Backup.swift:16` then), held tasks, templates and assignments, and carried
  no settings and no categories. Restore never read `version`. Decoding happened before the user was
  asked to confirm, and restore rolled back if the save failed. Now: `currentVersion = 2`
  (`Backup.swift:19-21`); decoding is `BlockeyBackup.decode` (`:161-169`), called from
  `SettingsView.stageRestore` (`Views/SettingsView.swift:220`) before the confirmation alert, not
  from `BackupFile.init(configuration:)`, which the importer no longer uses; the rollback is
  `Backup.swift:306-316`.

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
references to `BlockCategory`, `.category` or `categoryRaw` across 15 files on 2026-11-03). Definitions are
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
  row overrides the defaults. ~~Deleting the row is "Reset to default".~~ **Amended 2026-11-04
  (phase 5.1):** "Reset to default" writes the factory name, emoji, symbol and swatch back into the
  row and clears `customColorHex`, and **keeps the row**, so a reset category keeps its position and
  archive state (UI spec Q3, `docs/ui-spec-issue-1.md:852-854`; code `Catalog/CategoryDraft.swift:130-144`).
  Pixels are identical either way. Deleting the row still yields the defaults, so it remains the
  data-level escape hatch for a customisation gone wrong; no screen offers it.
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
- **Amended 2026-11-04 (phase 5.1):** names are capped at **24 characters** in the editor (UI spec
  Q2, `Catalog/EmojiSuggestions.swift:80-90`), because long names break chips and the timeline. The
  slug cap (32 clusters) is independent.
- **Amended 2026-11-04 (phase 5.1):** the duplicate-name rule applies to the editor, Add as
  category and un-archiving (`Planning/CategoryStore.swift:211-213`), **not to a backup restore**,
  which upserts the file's definitions as they are (`Models/Backup.swift:289-304`). The file was
  valid on the phone that wrote it, and refusing or renaming part of it would make restore lossy.
  A clash needs two different slugs with one display name (a built-in renamed "Gym" on one phone,
  `u-gym` on the other), so it is rare; if it happens, the emoji tells them apart, and opening
  either in the editor shows the duplicate message and blocks Save until one is renamed.
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
- **Amended 2026-11-04 (phase 5.1): one deliberate exception.** A title-suggestion chip in the
  composer fills the slug its history carries even when that category is archived or unknown, and
  the draft then shows it as the current value (UI spec 1.4, `docs/ui-spec-issue-1.md:154-159`;
  code `Views/InboxTray.swift:376-379`). The reason is the same as for template rows: it is the
  owner's own history, and the chip is a shortcut for repeating it, not a picker offering choices.
  The plan (task 3.3, "An archived or unknown remembered category is not restored") and ADR 006 say
  the opposite and are superseded on this point.
- **Save only writes what changed.** `BlockDetailSheet.onSave` passes the category only if the user
  changed it. `update` already took an optional (now `CalendarService.swift:415`), so the fix was in
  the sheet (now `BlockDetailSheet.swift:81`).

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
swatches must be pairwise distinguishable above a ΔE floor (M9); both are tests. The six
built-in tints of 2026-11-03 (`BlockCategory.swift:68-77`) were the first candidates for six of the
slots, so nothing on screen changes unless the designer's measurements say it must. **As built
(phase 5.1):** the measurements did say so. Slots 0 to 5 hold the measured records from
`docs/category-palette.md` (`Catalog/CategoryPalette.swift:27-32`), not the old tints; `admin` is
now teal and the dark spines are lifted, as UI spec section 8 expects. A stored `paletteIndex`
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
    let slug: String?          // amended 2026-11-04: never nil as built; an absent slug resolves to "deep"
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
    private(set) var unknownQueryItems: [URLQueryItem]   // round-tripped untouched
                                                       // (amended 2026-11-04: was `extraQueryItems`)
    func replacingCategorySlug(_ slug: String?) -> BlockToken   // the update path; keeps id and items
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

`CategoryDefinition` is registered in the container (now `BlockeyApp.swift:15-22`). `TaskItem` and
`TemplateRow` keep the field name `categoryRaw` and gain slug accessors beside it, so there is no
rename and no migration of existing rows. Landmine: SwiftData's `.unique` resolves a conflicting
insert as an upsert rather than an error, so "a duplicate slug is rejected" has to be checked by the
catalog before insert, never left to the attribute. As built: every add path goes through
`CategoryDefinition.insertIfFree` (`Models/CategoryDefinition.swift:53-61`), which counts rows with
the slug first; `CategoryDefinitionModelTests.swift:30` pins the upsert behaviour.

The token rules that phase 1 ships first, on their own, because they stop the loss before any
feature exists: keep `c=` verbatim; keep unknown query items, in order, duplicates included; an
absent category stays absent on rewrite; an empty or whitespace `c=` counts as absent; the first of
duplicate `c=` items wins; no force unwrap. `category` survives as a computed fallback until every
caller takes slugs. (As built, every caller now takes slugs and the token's computed `category` is
gone; only the `init(category:)` convenience remains, `BlockToken.swift:46`.)

### Backup v2

The constraint is that both directions of version skew are realistic: the weekly re-sign makes it
normal to have an old build on the phone and a new file in iCloud Drive, or the reverse.

- **Shape.** `version` becomes 2. Two new top-level fields, `categories: [Category]?` and
  `settings: Settings?`. Every field in `Settings` is optional on its own. Optional because
  synthesised `Codable` throws on a missing key, so non-optional new fields would make every v1
  file fail to import.
- **Settings** carried: day start and end, snap, hidden calendar IDs, alarm on/off and minutes
  before, and the plan's new `Skip preview`. Not carried: one-time flags such as
  `hasSeededStarterTemplates` (now `BlockeyApp.swift:35`; also `hasSeenStarterTemplatesNote` and
  `hasSeededStreakHistory`, which arrived later) and the device-specific `blockeyCalendarID`
  (`CalendarService.swift:60`). This **closes known gap 6** once restoring settings is verified.
  As built, settings restore is covered by `BackupV2Tests.swift:128`, `:152`, `:326`, `:357`; gap 6
  closes when those pass in a run of the suite.
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
  the collapse that was at `Backup.swift:94` and `:107` went in phase 1 (verbatim now at `:255`,
  `:270`). A task whose slug has no definition renders as a stand-in, like a block.
- **Category colour** rides in `Category.customColorHex: String?`, optional. See the amendment at
  the end for its shape, its validation and why it is kept verbatim.
- **Categories merge by slug; restore never deletes a definition.** This is the one deliberate
  exception to "replace rather than merge" (now `Backup.swift:233-241`). A definition is referenced by
  calendar events that are not in the backup, so deleting one would damage data the file cannot put
  back. Each definition in the file is upserted by slug; definitions not in the file are left alone.
- **nil versus empty `categories`.** `nil` means the file predates categories (any v1 file).
  `[]` means a v2 phone with no customisations. **Both change nothing.** The distinction is stated
  here so nobody later "fixes" `[]` into a wipe.
- **The restore warning counts categories**, as it already counts tasks and templates
  (`PendingRestore.warning`, now `Backup.swift:370-389`).

**An older build reading a v2 file** decodes it (unknown keys are ignored) and ignores the new
fields. That is not the whole cost: the build of 2026-11-03 also collapsed every custom slug on tasks
and template rows to `deep` while restoring (`Backup.swift:94`, `:107` then). The plan says an old build loses
"only the new fields", and that is wrong for the build on the phone today. The mitigation is to ship
the verbatim restore in phase 1 with the token fix, well before any build can mint a custom slug,
so that by the time v2 files exist the installed build no longer collapses them. **Shipped in phase
1** (now `Backup.swift:255`, `:270`), so the mitigation is in place before any custom slug exists.

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
already rides in the token as `t=` (`BlockToken.swift:8`, now `:87` and `:104-106`).

**Not verified**
- ~~Gap 7.~~ **Closed 2026-11-04.** Task 0.3 passed on the owner's phone (ADR 002 addendum), so it
  no longer gates phase 3. Verified once, on one phone and one outside client; a regression from a
  future iOS or iCloud change would show up as stand-ins, not as data loss.
- That adding `CategoryDefinition` to the container migrates an existing store with no data loss.
  Adding a model should be a lightweight change, but it is checked the way ADR 003 checked
  reinstalls: install over a populated simulator build and query the store. **Still not run as of
  phase 5.1 (2026-11-04); this is what blocks acceptance.**
- ~~The palette. No swatch has been measured yet.~~ Measured: twelve records in
  `docs/category-palette.md`, recomputed by `CategoryPaletteTests` and `CategoryPalettePinTests`.
- The custom-colour derivation. Its targets are now set (`DerivationTargets.measured`,
  `Catalog/CustomCategoryColor.swift:28-36`) and pinned by the hue sweep, but how a derived colour
  looks next to the curated ones is still a judgement for a device screenshot, not a test.
- The floors are judged against `ColorSurfaces.assumedPendingStory1`, the designer's assumed canvas
  and meeting fill, until redesign Story 1 (#11) publishes real surfaces.
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
    accepted. **Architect pass done 2026-11-04** (addendum below); acceptance waits on F1.

## Amendment: 2026-11-04, palette + custom colour (owner decision)

**Decision (owner, 2026-11-04).** Category colour is "palette + custom". The curated, measured
`CategoryPalette` is the first thing the editor offers. After the swatches comes **Other…**, which
opens the system `ColorPicker` and warns when the result will be hard to read or hard to tell apart.
This reverses "No free colour picker" in the Palette section. Everything else in that section
(measured swatches, both-mode floors, modulo wrap, emoji required) still holds for the palette.

Checked against the source on 2026-11-04 before writing: there was no `CategoryStyle`,
`CategoryPalette`, `CategoryDefinition`, `paletteIndex`, `ColorPicker`, contrast or ΔE code anywhere
in `Blockey/`. Colours were six hard-coded RGB pairs (`BlockCategory.swift:68-77`), and chips
derived fill and border from them with alpha (`TimelineCanvas.swift:393-394` then). Every mechanism
below was new. All of it is now built; see the phase 5.1 addendum. Chips still derive fill and
border from the spine with alpha (now `TimelineCanvas.swift:397-398`), deliberately, until
redesign Story 3.

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
  override row as usual. Reset to default ~~(deleting the row) drops both~~ writes the factory
  `paletteIndex` and clears `customColorHex`, keeping the row (amended 2026-11-04, see "Built-ins
  stay in code").
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

"Meeting style" means the **fixed-event chip** (`FixedEventChip`, now `TimelineCanvas.swift:442`), not
the built-in `meeting` category, which is an ordinary block category with a hue.
- Against meetings: `looksLikeMeeting` when the derived fill in either mode is under ΔE 15 from the
  meeting fill or below the chroma gap. Today the meeting fill is `Color.primary` at 5 to 6 percent
  alpha (now `TimelineCanvas.swift:466`), so until Story 1 and Story 3 make it opaque, the surfaces value
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

**As built (phase 5.1, 2026-11-04).** Points 1, 3, 4 and 5 hold. Two differ, both accepted:
- Point 2: #1 built `SRGB`, `CategoryColorRecord`, `CategoryColors` and all twelve records itself,
  in b9e96a2 (tagged #1 and #12), from the designer's `docs/category-palette.md`, because Story 2's
  code had not started. The split of ownership no longer matters: the types exist once, in
  `Catalog/`, and Story 2 consumes them.
- Point 1, second half: Story 1 has not published surfaces. `ColorSurfaces.assumedPendingStory1`
  (`Catalog/ColorSurfaces.swift:13-22`) holds the designer's assumed values, in one declaration, so
  Story 1 changes one line and every floor test reruns.
- Point 4: `CategoryStyle` stores `colors: CategoryColors` and exposes `spine`, `fill`, `border` and
  `onFill` through a SwiftUI extension (`Views/CategoryStyle+Color.swift:11-21`). The
  `CategoryStyle(BlockCategory)` adapter no longer exists; only `CategoryStyle(ResolvedCategory)`
  and a memberwise init do.
- Not a difference in the seam but worth stating: the timeline chip reads only `style.spine`, and
  paints its fill and border as the spine at 17 to 30 percent and 45 to 70 percent alpha
  (`TimelineCanvas.swift:384-398`). The opaque `fill` and `border` that the floors, the palette
  tests and the `closeTo` and `looksLikeMeeting` warnings measure are drawn in the editor preview
  and picker tiles, not yet on the timeline. That is the UI spec's scope line (section 8: "keep
  every opacity ... exactly as it is"); opaque fills are redesign Story 3. Until it lands, a warning
  describes the chip the timeline will draw, not the one it draws today.

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

## Addendum: phase 5.1 verification, 2026-11-04

Architect, against `sprint-1` at 3158fc5. Every mechanism, type, function, field and rule this ADR
names was grepped and read in the source, not inferred from the docs. Paths are under `Blockey/`
unless they start with `BlockeyTests/`. "Differs" rows say which side was right; where the code
was right the body above is amended and marked "Amended 2026-11-04 (phase 5.1)" or "As built".
The suite was **not run** in this pass; test files are cited as evidence the behaviour is pinned,
not that it passes.

**Counts: 85 matches, 13 differs, 1 missing.**

| # | Mechanism | Where in the code (file:line) | Status |
|---|---|---|---|
| | **Token and phase 1** | | |
| 1 | `BlockToken.categorySlug`, verbatim, NFC | `Calendar/BlockToken.swift:32`, `:61-64`, `:86` | matches |
| 2 | Unknown query items kept, in order, duplicates included | `BlockToken.swift:36`, `:88`, `:107` | differs: named `unknownQueryItems` and `private(set)`, not `extraQueryItems`. Code right; contract amended |
| 3 | An absent category stays absent on rewrite | `BlockToken.swift:101-103` | matches |
| 4 | Empty or whitespace `c=` counts as absent | `BlockToken.swift:61-64` | matches |
| 5 | First of duplicate `c=` items wins | `BlockToken.swift:80-86` | matches |
| 6 | No force unwrap; `url` optional; callers keep the old url on nil | `BlockToken.swift:91-110`; `Calendar/CalendarService.swift:429-435` | matches |
| 7 | Token's computed `category` retired once callers take slugs | gone; only `init(category:)` remains, `BlockToken.swift:46` | matches |
| 8 | Block sheet passes the category only when changed | `Views/BlockDetailSheet.swift:32`, `:81`; `Catalog/CategoryPicking.swift:124-138` | matches |
| 9 | `update` takes an optional slug and rewrites the url only when given one | `CalendarService.swift:412-436` | matches |
| 10 | Return to inbox and Clear carry the token's slug | `Planning/DayPlanner.swift:606`, `:703`, `:795` | matches |
| 11 | Restore stores task and row slugs verbatim | `Models/Backup.swift:255`, `:270` | matches |
| 12 | The unknown-slug test asserts a stand-in, not the collapse | `BlockeyTests/EdgeCaseTests.swift:221-239` | matches |
| 13 | `categoryRaw` kept, slug accessors beside it, no migration | `Models/TaskItem.swift:14`, `:88-91`; `Models/DayTemplate.swift:56`, `:81-84` | matches |
| 14 | `Block` and `CalendarService` take and return slugs | `Calendar/Block.swift:64`; `CalendarService.swift:264-274`, `:415` | matches |
| | **Built-ins** | | |
| 15 | Six fixed built-in slugs, defaults as plain data in `Catalog/` | `Catalog/CategoryCatalog.swift:77-86` | matches |
| 16 | An override row with the built-in's slug wins over defaults | `CategoryCatalog.swift:118-125` | matches |
| 17 | Reset to default deletes the row | `Catalog/CategoryDraft.swift:130-144`; `Views/CategoryEditor.swift:164-167` | differs: writes defaults into the row and keeps it (UI spec Q3). Code right; amended |
| 18 | Built-ins archive through an override row | `Planning/CategoryStore.swift:77-88` | matches |
| 19 | At least one category stays unarchived | `CategoryCatalog.swift:244-248`; `CategoryStore.swift:72`, `:100` | matches |
| 20 | A nil or absent slug resolves to `deep`, even when `deep` is archived | `CategoryCatalog.swift:113-117`; `BlockeyTests/CategoryCatalogTests.swift:56` | matches |
| 21 | `ResolvedCategory.slug` is nil for an absent slug | `CategoryCatalog.swift:43-45` | differs: never nil; an absent slug resolves to `"deep"` so views can key on it. Code right; contract amended |
| 22 | New work never starts on an archived category | `CategoryCatalog.swift:169-173`; `Views/TodayView.swift:748`; `Views/TemplatesView.swift:185` | matches |
| | **Slugs** | | |
| 23 | `u-` prefix on custom slugs | `Catalog/CategorySlug.swift:12`, `:43` | matches |
| 24 | NFKC, lowercase, grapheme walk keeping marks, separators collapse | `CategorySlug.swift:94-124` | matches |
| 25 | Body capped at 32 grapheme clusters | `CategorySlug.swift:15`, `:110-112` | matches |
| 26 | Emoji-only name mints `u-` plus 6 of `a-z0-9`, RNG injected | `CategorySlug.swift:20-21`, `:30-41` | matches |
| 27 | Collisions checked against all slugs, archived included; suffix after the cap | `CategorySlug.swift:43-48`; `CategoryCatalog.swift:238` | matches |
| 28 | A slug never changes after creation | `CategoryStore.swift:227-241` | matches |
| 29 | Slugs are case-sensitive | `BlockToken.swift:57-63`; `BlockeyTests/CategoryCatalogTests.swift:82` | matches |
| 30 | No `.toLatin` fallback | no `toLatin` or `stripDiacritics` anywhere in `Blockey/` | matches |
| | **Names** | | |
| 31 | Empty, whitespace and invisible-only names refused; ends trimmed | `CategorySlug.swift:18`, `:85-89`; `CategoryCatalog.swift:254`, `:269-271` | matches |
| 32 | No name equal to an unarchived category's, via `TitleKey.normalize` | `CategoryCatalog.swift:253-262`; enforced again at the write, `CategoryStore.swift:211-213` | matches |
| 33 | The name rule during a backup restore | `Backup.swift:289-304` (not applied) | differs: ADR was silent; restore upserts names as the file has them. Code right; amended |
| 34 | Name length | `Catalog/EmojiSuggestions.swift:80-90` | differs: 24-character cap (UI spec Q2) the ADR did not have. Code right; amended |
| 35 | No cap on the number of categories | none; composer collapses past 8, `CategoryPicking.swift:112-122` | matches |
| | **Archive** | | |
| 36 | Delete means archive; blocks keep rendering from the archived definition | `CategoryStore.swift:71-94`; `CategoryCatalog.swift:118-125` | matches |
| 37 | Move-to prompt counts tasks and rows; nothing preselected; may decline | `Views/CategoryArchiveSheet.swift:12-13`, `:98-107`; `CategoryStore.swift:53-55`, `:134-148` | matches |
| 38 | Pickers offer unarchived categories plus the current value | `CategoryCatalog.swift:151-163`; `CategoryPicking.swift:18-29` | matches |
| 39 | A template row on an archived category stamps with that slug | `DayTemplate.swift:44-46`; `DayPlanner.swift:45-46` | matches |
| 40 | Archived categories are never applied to new work | `Views/InboxTray.swift:376-379` | differs: a suggestion chip applies an archived or unknown slug (UI spec 1.4). Code right; amended as an exception |
| 41 | A move target is never archived or unknown | `CategoryStore.swift:127-132` | matches |
| | **Stand-ins** | | |
| 42 | Name recovered from the slug | `CategorySlug.swift:54-60` | matches |
| 43 | 32-bit FNV-1a modulo palette count, never `hashValue`, pinned by a test | `CategorySlug.swift:65-80`; `BlockeyTests/CategorySlugTests.swift:152-165` | matches |
| 44 | Generic glyph 🏷️ and symbol `tag` | `CategoryCatalog.swift:88-91` | matches |
| 45 | Add as category inserts the exact slug, FNV index, no hex | `CategoryCatalog.swift:213-220`; `Views/CategoryPicker.swift:35-90` (plus a rename path when the name clashes, `CategoryPicking.swift:104-110`) | matches |
| 46 | Resolution on read; nothing written on launch | `Views/CategoryCatalogEnvironment.swift:17-27` | matches |
| 47 | A stand-in never resolves to `.custom` | `CategoryCatalog.swift:292-300`; `CategoryCatalogTests.swift:147` | matches |
| | **Palette** | | |
| 48 | Fixed, measured `CategoryPalette` of 12 light/dark records | `Catalog/CategoryPalette.swift:26-41` | matches |
| 49 | Fill-contrast floor and pairwise ΔE are tests | `BlockeyTests/CategoryPaletteTests.swift:55`, `:71`, `:87` | matches |
| 50 | Old built-in tints as the first six slots | `CategoryPalette.swift:27-32` vs `Models/BlockCategory.swift:68-77` | differs: replaced by measured records, as UI spec section 8 expects. Code right; amended |
| 51 | Out-of-range `paletteIndex` wraps modulo | `CategoryPalette.swift:47-53`; `CategoryCatalog.swift:285-290` | matches |
| 52 | Emoji required | `CategoryCatalog.swift:264-266`; `CategoryStore.swift:201-203`; `CategoryDraft.swift:116-120` | matches |
| | **Contract and model** | | |
| 53 | `CategoryDefinitionValue` | `CategoryCatalog.swift:5-31` | matches |
| 54 | `ResolvedCategory` fields and `Origin` | `CategoryCatalog.swift:40-56` | matches |
| 55 | `CategoryCatalog` `init`, `resolve`, `choices`, `validate` | `CategoryCatalog.swift:99`, `:113`, `:158`, `:253` | matches |
| 56 | `CategorySlug.mint` and `displayName` | `CategorySlug.swift:30`, `:54` | matches |
| 57 | `@Model CategoryDefinition`, unique slug, `customColorHex` in v1 | `Models/CategoryDefinition.swift:12-34` | matches |
| 58 | Registered in the model container | `BlockeyApp.swift:15-22` | matches |
| 59 | `.unique` upsert guarded by a check before insert | `CategoryDefinition.swift:53-61`; `CategoryCatalog.swift:236-241`; `BlockeyTests/CategoryDefinitionModelTests.swift:30` | matches |
| 60 | `Catalog/` is Foundation only | no SwiftUI, SwiftData, EventKit or UIKit import in `Catalog/` | matches |
| 61 | Install-over migration check for the new model | none; `CategoryDefinition.swift:11` itself says unverified | **missing** |
| | **Backup v2** | | |
| 62 | `version` 2; optional `categories` and `settings` | `Backup.swift:19-37` | matches |
| 63 | Settings carried; one-time flags and calendar ID not carried | `Backup.swift:53-69`, `:328-355` | matches |
| 64 | Newer version refused before the confirmation, with the stated copy | `Backup.swift:150-169`, `:186`; `Views/SettingsView.swift:220-226` | matches |
| 65 | Where decoding happens | `SettingsView.swift:220` calls `BlockeyBackup.decode` | differs: not `BackupFile.init(configuration:)`, which import no longer uses. Code right; Context amended |
| 66 | Validate before the first delete; clamps; duplicate slugs first-wins and counted | `Backup.swift:176-226`, `:246` | matches |
| 67 | Unknown calendar IDs kept | `Backup.swift:216-220`; `CalendarService.swift:184-186` | matches |
| 68 | Categories merge by slug; restore never deletes a definition | `Backup.swift:289-304` | matches |
| 69 | `nil` and `[]` categories both change nothing | `Backup.swift:31-34`, `:190` | matches |
| 70 | The restore warning counts categories | `Backup.swift:370-389` | matches |
| 71 | Rollback on a failed save; settings written only after it | `Backup.swift:306-316` | matches |
| 72 | Checked-in v1, v2 and v2-without-`customColorHex` fixtures | `BlockeyTests/Fixtures/*.json`; `BlockeyTests/BackupV2Tests.swift:49-84` | matches |
| 73 | `Category.customColorHex` carried and canonicalised on restore | `Backup.swift:39-51`, `:203` | matches |
| | **Custom colour (amendment)** | | |
| 74 | `#RRGGBB` grammar; uppercase writer | `Catalog/SRGB.swift:26-41`; `CategoryCatalog.swift:273-281` | matches |
| 75 | A valid hex wins; anything else falls back to `paletteIndex` | `CategoryCatalog.swift:285-290` | matches |
| 76 | A swatch clears the hex; Other… keeps the index | `CategoryCatalog.swift:16-30` | matches |
| 77 | Only the picked colour is stored; derivation on read | `CategoryPalette.swift:57-65` | matches |
| 78 | `SRGB`, `CategoryColorRecord`, `CategoryColors`, `ColorChoice` | `SRGB.swift:6-72`; `CategoryCatalog.swift:34-38` | matches |
| 79 | Derive in OKLCH: target lightness, chroma factor and cap, chroma-only bisection | `Catalog/CustomCategoryColor.swift:59-72`; `Catalog/CategoryColorMath.swift:104-130` | matches |
| 80 | `DerivationTargets.measured` | `CustomCategoryColor.swift:19-37` | matches |
| 81 | Greys under chroma 0.02 derive to greys | `CustomCategoryColor.swift:53-55`, `:61-66` | matches |
| 82 | WCAG 2 contrast and CIE76 ΔE for measurement | `CategoryColorMath.swift:38-71` | matches |
| 83 | The assessment floors table | `Catalog/ColorSurfaces.swift:29-37`; `CustomCategoryColor.swift:79-113` | matches |
| 84 | Concerns worst first, per mode | `CustomCategoryColor.swift:74-113` | matches |
| 85 | Every curated swatch assesses to `[]` | `CategoryPaletteTests.swift:87` | matches |
| 86 | Hue-sweep test | `BlockeyTests/CustomCategoryColorTests.swift:40` | matches |
| 87 | Warn only; Save never blocked by a concern | `CategoryDraft.swift:116-120` | matches |
| 88 | Other… row: `ColorPicker` without opacity, P3 clamp, two-mode preview, one line | `Views/CategoryColorSection.swift:20-46`, `:92-129`, `:133-173`; `SRGB.swift:43-48` | matches |
| 89 | `closeTo` skips the edited and archived categories | `CategoryDraft.swift:148-155` | matches |
| 90 | Canvas and meeting fill as numeric surfaces from Story 1 | `ColorSurfaces.swift:13-22` | differs: designer's assumed values pending redesign Story 1 (#11). Owned by Story 1; amended |
| | **The `CategoryStyle` seam** | | |
| 91 | Colours are numbers in `Catalog/`, not asset-catalog names | `CategoryPalette.swift`; `SRGB.swift` | matches |
| 92 | Story 2 owns the value types, #1 the palette | built together in b9e96a2 (#1, #12) | differs: #1 built them. Harmless; amended |
| 93 | `CategoryStyle` is a plain struct, never a switch over the enum | `Catalog/CategoryStyle.swift:7-23`; `Views/CategoryStyle+Color.swift:11-21` | matches |
| 94 | Chips draw the category's `fill` and `border` | `Views/TimelineCanvas.swift:384-398` | differs: the timeline paints the spine at alpha, deliberately until redesign Story 3 (UI spec section 8). Owned by Story 3; amended |
| 95 | Views ask the catalog only (the escape hatch) | `CategoryCatalogEnvironment.swift:29-32`; the one direct palette read is the editor's swatch grid, `CategoryColorSection.swift:54-63` | matches |
| | **What this supersedes** | | |
| 96 | The enum's "deliberately fixed" comment is superseded; the shim is deleted once callers take slugs | `Models/BlockCategory.swift:5-9`, `:63`, `:79-85` | differs: **code wrong**. The comment still argues against this ADR; `tint` and `labelled` have no callers; the enum survives in `StarterData.swift:18-29`, `DemoScenario.swift:284`, `:313-316`, the `TaskItem` and `TemplateRow` convenience inits, `BlockCategory.fallback.rawValue` (`DayPlanner.swift:46`, `:606`, `:703`, `:795`; `DayTemplate.swift:45`) and `ComposerSuggestionRow.swift:76`. Follow-up F2 |
| 97 | `BlockMeta` not built and not needed | no match in `Blockey/` | matches |
| 98 | The source-task link rides in the token as `t=` | `BlockToken.swift:87`, `:104-106` | matches |
| 99 | Code comments that restate this ADR's backup scope | `BlockeyApp.swift:36-38`; `Backup.swift:26-28`; `CategoryDefinition.swift:7`; `ColorSurfaces.swift:18-19` | differs: **code wrong**. They say Skip preview is not backed up, that `version` stays 1, that Backup v2 has not landed, and cite `TimelineCanvas.swift:462` (now `:466`). Follow-up F3 |

### Follow-ups

Code that is wrong, or verification that is owed. Sizes as in the plan: **S** under 2 hours,
**M** about half a day. None is a data-loss bug in the code as written.

- **F1. Install-over migration check (row 61). S. Blocks acceptance.** `qa-engineer`, simulator
  only. Build the last commit before `CategoryDefinition` existed (find it with
  `git log --diff-filter=A -- Blockey/Models/CategoryDefinition.swift`), populate tasks, templates,
  assignments and streak days, install `sprint-1` over it without deleting the app, and query the
  store: every count unchanged, `CategoryDefinition` empty, the app launches. Record the result in
  this ADR's "Not verified" list.
- **F2. Retire the `BlockCategory` shim (row 96).** Two sizes, and the first can ship alone:
  - **S:** replace the doc comment at `BlockCategory.swift:5-9` with one that points at this ADR
    and says the enum is only the built-ins' factory data, and delete the uncalled `tint`,
    `components` and `labelled`. That also drops its `import SwiftUI`.
  - **M:** delete the enum. Move `StarterData` and `DemoScenario` to slugs, replace
    `BlockCategory.fallback.rawValue` with `CategoryCatalog.fallbackSlug`, drop the enum
    convenience inits and `DayTemplate.category(forRowID:)`, take `knownSlugs` without a default in
    `ComposerSuggestionRow`, and move the tests that iterate `BlockCategory.allCases` to
    `CategoryCatalog.builtIns`. `CategoryCatalogTests.swift:28` pins the two copies together until
    then.
- **F3. Stale comments (row 99). S.** Correct the four comments named in row 99. No behaviour
  changes.

Already planned elsewhere, so not new work: real surfaces (row 90) are redesign Story 1 (#11);
opaque chip fills (row 94) are redesign Story 3. Until Story 3 lands, the colour warnings describe
the chip the timeline will draw, not the one it draws today.

Outside this ADR but found on the way: ADR 006 and plan task 3.3 still say "an archived or
unknown remembered category is not restored", which row 40 supersedes. ADR 006's own phase 5.1
pass should amend it.

### Acceptance

Not accepted. Nothing in the code is missing, but row 61 is: the one check that adding a model
cannot cost the owner the tasks and templates that exist only on the phone (ADR 003). Mark this
ADR accepted when F1 passes and `scripts/test.sh` is green. F2 and F3 do not block it.

Known gap 6 (backup omits settings) closes on the same condition: settings are carried and
restored (rows 63, 66, 71), and `BackupV2Tests` pins it, but this pass did not run the suite.


### F1 result: install-over migration check, 2026-11-04, PASS

Run by `qa-engineer` on the simulator. A store written by `422767e` (`6c3e723^`, the last commit
before `CategoryDefinition`, a descendant of the token-probe build on the owner's phone) was
populated with the old build's demo and starter data, then HEAD was installed over it with
`xcrun simctl install` and no uninstall, keeping the same data container.

| Entity | Before | After |
|---|---|---|
| TaskItem | 4 | 4 |
| DayTemplate | 2 | 2 |
| TemplateRow | 8 | 8 |
| TemplateAssignment | 7 | 7 |
| ActivityDay | 13 | 13 |
| CategoryDefinition | table absent | table present, 0 rows |

Hashes of the user-visible columns (titles, category raw values, minutes, ids, times) and the full
ActivityDay rows are identical before and after. The app launched with no re-seeding and showed
the existing streak, inbox and templates. SwiftData's lightweight migration added the new table
and left everything else intact.
