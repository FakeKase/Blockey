# UI spec: issue #1, custom categories (plan tasks 3.7, 3.8, 3.8b)

Date: 2026-11-04
Author: `designer` agent (read-only spec, no code)
Status: **DRAFT.** Open questions Q1 to Q4 (section 10) need the owner's answers, but every one has a
recommendation the build can start on.
Builds on: ADR 005 and its 2026-11-04 amendment, `docs/category-palette.md` (copy table, owner
decisions), `docs/redesign-epic-plan.md` (Story 2 chip anatomy, Story 7 sheets), and the pure layer
that already exists: `CategoryCatalog`, `CategoryPalette.pickerOrder`, `CustomCategoryColor`,
`CategoryDefinition.insertIfFree`, `CategoryStyle`.

The designer had no shell, so `gh issue view 1` was **not run**. This spec was written from ADR 005,
the feedback plan and the source. Skim `gh issue view 1 --comments` for acceptance criteria this
spec missed before building. The last paragraph of section 9 lists what to compare.

What was checked against the source on 2026-11-04 before writing (grep, not memory):
- The three pickers still enumerate `BlockCategory.allCases`: `BlockDetailSheet.swift:57`,
  `TemplatesView.swift:206`, `InboxTray.swift:143`. `ComposerDraft.category` is a `BlockCategory`
  (`ComposerSuggestionRow.swift:10`).
- `CategoryCatalog` is not in the environment yet. `CategoryDefinition` is registered
  (`BlockeyApp.swift:19`) and Backup already round-trips definitions (`Backup.swift:136`, `:290`).
- No `ColorPicker`, `EditButton`, `.onMove` or archive UI exists anywhere in `Blockey/`.
- `CategoryStyle` and its `Color` bridge exist (`Catalog/CategoryStyle.swift`,
  `Views/CategoryStyle+Color.swift`) and **no view uses them yet**. Every tint site still reads
  `BlockCategory.tint`: `TimelineCanvas.swift:314`, `:381`, `Emoji.swift:76`, `InboxTray.swift:145`,
  `RootView.swift:40`.
- `ColorSurfaces.assumedPendingStory1` is still the assumed canvas, so the preview patches and the
  warnings are judged against assumed surfaces until Story 1 publishes real ones.
- The pure layer has **no** function for: listing archived categories, reordering, counting what
  uses a category, picking a default swatch, the emoji suggestions, or turning a concern into a
  sentence. Section 9 lists them. Do not build views that compute these inline.

---

## 0. Shared decisions

- **0.1 One catalog, one seam.** Views ask `CategoryCatalog.resolve` and wrap the result in
  `CategoryStyle(resolved)`. No view looks up the palette, the built-in table or a hex itself.
- **0.2 Slugs everywhere.** A picker's value is a `String?` slug, exactly what the token, `TaskItem`
  and `TemplateRow` store. A picker never hands back a `BlockCategory`.
- **0.3 Save only writes what changed.** The block sheet already honours this. The picker keeps it:
  choosing the row that is already checked is a no-op and keeps the **original raw value**, including
  `nil`. Without this, opening a block with no `c=` and tapping "Deep work" would write `c=deep`.
- **0.4 Symbols as the fallback, always.** Every glyph is `CategoryGlyph`-style: the emoji where
  `Emoji.isSupported`, otherwise the category's `symbolName`. A simulator screenshot is not what the
  phone shows (CLAUDE.md). Every status mark added by this spec is an SF Symbol.
- **0.5 Warning and error style** follow `ui-spec-issue-3.md` 0.3. Warnings: orange
  `exclamationmark.triangle.fill` plus `.primary` text. Blocking errors: red
  `exclamationmark.circle.fill` plus `.primary` text. No coloured text, because it fails contrast
  (design review M5, S4), and colour is never the only signal.
- **0.6 Tone.** Sentence case. No blame in the second person. Errors name the cause and the fix.
  Buttons say what happens. British spelling in prose and copy ("colour"), matching
  `category-palette.md`. Curly quotes around names: `“Errands”`.
- **0.7 Names are never transformed for display.** No capitalisation, no ASCII folding, no filtering
  by script. Thai names with tone marks must render uncut at every size (section 6).

---

## 1. The category picker (task 3.7)

### 1.1 One component, two presentations

`CategoryPicker` is one view type with one data source, `catalog.choices(current:)`, and two
presentations. It is used in three places.

| Where | Presentation | Value source | On select |
|---|---|---|---|
| `BlockDetailSheet` | Form row that pushes `CategoryChoiceList` | `block.categorySlug` | Sets sheet state. Save passes the slug only if it differs from the original (0.3) |
| `TemplateRowEditor` | Same Form row | `row.categorySlug` | Writes `row.categorySlug` immediately, as the row editor writes everything now |
| `InboxTray` composer | Chip row (1.4) | `draft.category` (becomes a slug) | Sets `draft.category` |

**Why a pushed list and not the current `.menu` picker.** A menu cannot show a category's colour,
cannot hold the "Add as category" button or a status line, and gets long once the owner adds
categories. A pushed list is the platform's own idiom for "choose one of many", costs the same two
taps (tap the row, tap the choice; selecting pops back), and survives Dynamic Type and long names.

### 1.2 The Form row

- `Section("Category")` stays. Inside it, one row: label `Category`, value = glyph + category name,
  trailing chevron (the standard navigation row).
- The glyph is the category's emoji (or symbol), 24 pt box, decorative.
- At accessibility text sizes the label stacks above the value, as `LabeledContent` already does.
  Value `lineLimit(nil)`. Never truncate a name in this row.
- The row's status footer (`Section` footer) depends on the value:

| Current value | Footer |
|---|---|
| Active category | none |
| Archived | `“Errands” is archived. It still shows here, but it won’t be offered for new work.` |
| Unknown (stand-in) | `“Errands” isn’t saved as a category on this phone.` followed by the **Add as category** button (section 4) |

### 1.3 `CategoryChoiceList` (the pushed screen, and the sheet used by the composer)

Title `Category`, inline. Rows come from `catalog.choices(current:)`, which is already: unarchived
categories in `sortIndex` order, then the current value appended if it is archived or unknown.

**The order.** (a) A `Current` section first, **only** when the current value is archived or unknown.
(b) Then the unarchived categories in catalog order, which is the order the owner set in Settings.
Built-ins and customs are interleaved by `sortIndex`, never split into groups. (c) Last, one action
row `New category…` (1.5).

The `Current` section exists because `choices` appends the off-list value at the end, and a checked
row at the bottom of a long list reads as an afterthought. The view takes the final element of
`choices` when `resolve(current).isArchived || origin == .standIn`, shows it in `Current`, and filters
it out of the main section. When the current value is a normal category there is no `Current`
section and no section headers at all.

**Row anatomy** (min height 44 pt, whole row is the tap target):

```
[ tile 36 ]  Errands                                   (check)
             Archived                       <- subtitle, only for off-list rows
```

- **Tile:** 36 pt rounded square (radius 8), `fill` from `CategoryStyle`, 1 pt `border`, the glyph
  centred (`.title3`). The tile scales with `@ScaledMetric`. Colour is decoration; the glyph and the
  name carry the identity.
- **Name:** `.body`, `.primary`, no line limit, wraps.
- **Subtitle:** `.footnote`, `.secondary`. Archived rows: `Archived`. Stand-in rows:
  `Not saved as a category`.
- **Check:** `checkmark` on the checked row, accent colour, trailing. Also the `.isSelected` trait.
- A stand-in row in `Current` carries the **Add as category** button directly under it (section 4).

**Selecting** a row calls `onSelect(slug)` and pops (or dismisses, in the composer sheet). Selecting
the already-checked row pops without changing anything (0.3).

**Never offered:** an archived category other than the current value.

### 1.4 The composer (`InboxTray`)

The composer keeps the idiom it has: one horizontal chip row, duration chips, a divider, then
category chips. What changes is the data and the end of the row.

- **Category chips** are the unarchived categories in catalog order, plus the draft's category if it
  has become archived while the tray was open. Each chip: glyph + name, `lineLimit(1)`, max width
  180 pt, tail truncation.
- **Hit target:** the visible capsule may stay about 34 pt tall, but the tap area is at least
  44 x 44 pt (`frame(minHeight: 44)` plus `contentShape`). The current chips are about 28 pt and
  miss the target; this fixes it.
- **Selected state:** background `fill`, 1.5 pt `border`, and a leading `checkmark` glyph in
  `.primary`. Unselected: `Color.primary.opacity(0.05)` background, no border (unchanged). Text is
  `.primary` in both states (S4: never the tint as text). Traits: `.isButton`, plus `.isSelected`.
- **Paint ownership.** Story 7 owns the chip restyle and ships first. If it has landed, use what it
  shipped. If not, keep today's paint (tint at the existing opacities) with the tint now coming from
  `style.spine`, and keep the text colour change above. Do not invent a third look.
- **Trailing chip `New`** (symbol `plus`, VoiceOver label `New category`) opens the category editor in
  a sheet. On Save the new category becomes the draft's category and the row scrolls to it. Without
  animation under Reduce Motion.
- **Overflow rule.** When there are more than 8 unarchived categories, or the text size is an
  accessibility size, the category chips collapse into **one** chip showing the current category
  (glyph, name, `chevron.up.chevron.down`). Tapping it opens `CategoryChoiceList` in a sheet with a
  `Cancel` button. This is the "Category chip that opens the full list" from plan task 3.8, and it
  stops a row of giant chips scrolling sideways at large sizes. The duration chips are unchanged.
- **Suggestion chips** (`suggestionChip`) show the glyph of the suggestion's category through the
  catalog. A suggestion whose slug is unknown or archived still shows its stand-in or archived glyph
  and still fills the draft (`ComposerDraft.apply` must stop discarding slugs that
  `BlockCategory(rawValue:)` does not know; it should accept any slug the catalog can resolve). An
  archived suggested category is accepted because it is the owner's own history; the draft then shows
  it as the current value.

### 1.5 `New category…` inside a picker

The last row of the choice list opens the editor in a sheet (Add mode). On Save the sheet closes and
the picker selects the new slug, popping back. If the picker is inside the block sheet, the block sheet
state now holds the new slug and Save on the block sheet still writes it only because it differs from the
original.

### 1.6 Dynamic Type and VoiceOver

- Form row and list rows wrap and grow. Nothing in the list or the row is fixed-height. Tiles scale.
- Composer chips use `.footnote` weight `.medium` (one step up from `.caption`, which is under the
  size the type scale allows for labels). At accessibility sizes the overflow rule (1.4) replaces the
  chip row.
- VoiceOver, Form row: label `Category, Deep work`, hint `Opens the list of categories`. Archived:
  `Category, Errands, archived`. Stand-in: `Category, Errands, not saved as a category`.
- VoiceOver, list row: label is the name, glyph hidden. Value `Selected` on the checked row. Archived
  and stand-in rows append `, archived` and `, not saved as a category`.
- `New category…` row: label `New category`, hint `Opens the category editor`.
- Composer chips: one element each, label = name, `.isSelected` when chosen, container label
  `Category`. The `New` chip reads `New category`. The collapsed chip reads
  `Category, Deep work` with hint `Opens the list of categories`.

---

## 2. Settings, Categories list (task 3.8)

### 2.1 Entry

`SettingsView` gets a new `Section` between `Skip preview` and `Alerts`:

- Row: `Categories`, trailing secondary value = number of **unarchived** categories (`8`), chevron.
  Pushes `CategoriesListView`.
- Footer: `Names, emoji and colours for your blocks. Changing one updates everything that uses it.`

### 2.2 `CategoriesListView`

Title `Categories`, inline. Toolbar trailing: the system `EditButton` (`Edit` / `Done`), which turns on
drag handles for reordering. No other toolbar items.

**Active section** (no header):
- Rows in catalog order. Row = the tile and name from 1.3, no check, a trailing chevron. Tap opens the
  editor in Edit mode as a sheet.
- Last row: `Add category` (symbol `plus`, accent). Tap opens the editor in Add mode.
- Footer, normal case: `Tap Edit to reorder. This order is used wherever you pick a category.`
- Footer, only one unarchived category left: `Blockey needs at least one category. Add another before archiving this one.`

**Archived section** (header `Archived`), **omitted when empty**:
- Same row, subtitle `Archived`. No drag handle. Tap opens the editor in Archived mode (3.7).
- Footer: `Archived categories stay on the blocks that use them. They just aren’t offered for new work.`
- Always visible when non-empty. No disclosure and no toggle: the owner asked to be able to see them,
  and a collapsed group would be one more decision.

### 2.3 Add

`Add category` opens the editor (section 3) as a sheet. On Save the list shows the new row last in the
active section (no animation under Reduce Motion). No "success" banner; the row appearing is the
confirmation, and VoiceOver gets an announcement: `Added “Errands”`.

### 2.4 Reorder

- Drag handles in Edit mode via `.onMove`. VoiceOver and non-edit-mode users get custom actions on
  every active row: `Move up` and `Move down` (omitted at the ends). Do not rely on `EditButton`
  being found by a VoiceOver user.
- A move rewrites `sortIndex` to `0..<n` for **every unarchived category in the new order** in one
  save. Built-ins that have no row get one (an override row copying the built-in's defaults), because
  ordering is stored on the row. Archived rows keep their old `sortIndex`.
- Footnote for the engineer, not the owner: this means a reordered built-in gets a row even though its
  name, emoji and colour are untouched. Reset to default (3.6) writes defaults back and keeps the
  row, so position survives a reset.
- After a move, VoiceOver announces `Moved Errands to position 3 of 8`.

### 2.5 Archive

Entry points, all the same flow: swipe trailing action `Archive` (symbol `archivebox`, default tint,
**not** red, because nothing is destroyed), the `Archive` custom action, and the `Archive category`
button in the editor (3.7).

1. **Rule check first.** `catalog.canArchive(slug)`. When false (the last unarchived category), the
   swipe action and custom action are **absent**, and the editor button is disabled with the footer
   `Blockey needs at least one category. Add another before archiving this one.`
2. **Count what uses it.** N inbox `TaskItem`s and M `TemplateRow`s with `categoryRaw == slug`. Blocks
   already on the calendar are not counted and not asked about: they keep the slug and keep rendering.
3. **N + M == 0:** archive immediately. No dialog. The row moves into `Archived`; VoiceOver announces
   `Archived “Errands”`. This is cheap to reverse (Restore), so asking would be friction.
4. **N + M > 0:** present the **move-to sheet**, `.medium` detent, interactive dismissal allowed
   (dismissing is the same as Cancel).

**Move-to sheet layout**

```
Cancel              Archive “Errands”?
3 inbox tasks and 2 template rows use this category.
Blocks already on your calendar keep this category.

MOVE THEM TO
 [tile] Deep work
 [tile] Meeting
 ...                       (every other unarchived category, radio rows, none preselected)
Choose a category to move them to, or archive without moving.

[        Move 5 and archive        ]   prominent, disabled until a row is chosen
[      Archive without moving      ]   plain
They keep “Errands” and still show it. It just won’t be offered for new work.
```

- The archived category itself is not in the list. Rows are radio-style (`checkmark` on the choice,
  `.isSelected`), min 44 pt.
- **Nothing is preselected.** The owner's rule (ADR 005) is that nothing moves unless they choose. The
  cost is one extra tap for the common case, and that is deliberate.
- **Move 5 and archive** moves all N tasks and M rows to the chosen slug, archives, and saves **in one
  `context.save()`**. Singular: `Move 1 and archive`.
- **Archive without moving** archives only. Template rows that point at it keep stamping with that slug
  and render from the archived definition (ADR 005, "Archived categories and new work").
- **Failure** (the save throws): the sheet stays open, nothing is changed, and an inline warning
  appears above the buttons: `Couldn’t archive “Errands”. Nothing was changed. Try again.` For the
  no-prompt path (step 3) the failure is an alert: title `Couldn’t archive`, message
  `Nothing was changed. Try again.`, button `OK`.
- Usage sentence, by count (pure function, tested):
  - N and M both above zero: `3 inbox tasks and 2 template rows use this category.`
  - Only tasks: `3 inbox tasks use this category.` One: `1 inbox task uses this category.`
  - Only rows: `2 template rows use this category.` One: `1 template row uses this category.`
  - One and one: `1 inbox task and 1 template row use this category.`

### 2.6 Restore

Swipe leading action `Restore` on an archived row (and the `Restore` custom action). Before writing,
run `catalog.validate(name:editing:)`. If it returns `.duplicate`, do **not** restore silently: open
the editor in Archived mode with the name field already showing the duplicate error
(`Another category is already called “Admin”. Choose a different name.`), so the fix is one edit. The
rule exists because two identical names in one picker cannot be told apart.

### 2.7 States

| State | Behaviour |
|---|---|
| Default | Active rows, `Add category`, optional Archived section |
| Empty | **Cannot occur.** The active section always has at least one row. If a bad restore or edit somehow leaves none, `choices` still shows the built-ins and `canArchive` stays false |
| Loading | None. Definitions are local; no spinner |
| Editing (reorder) | Handles shown, swipe actions hidden by the system |
| Only one active | Footer swaps (2.2); no Archive action on that row |
| Error | Archive failure per 2.5; save failures per 3.8 |
| Success | Row moves or appears; VoiceOver announcement only |

---

## 3. The category editor (task 3.8, colour row is 3.8b)

A sheet with its own `NavigationStack`, `.large` detent, used from Settings, from the pickers'
`New category…`, from the composer `New` chip and from the unknown-slug flow. Four modes share one
screen:

| Mode | Title | Initial state |
|---|---|---|
| Add | `New category` | Empty name, empty emoji, default swatch (3.5), unsaved |
| Edit | `Edit category` | The resolved category's name, emoji, colour |
| Archived | `Edit category` | As Edit, plus the restore banner (3.7) |
| Adopt | `Add category` | Name recovered from the slug, tag emoji, the stand-in's FNV swatch, slug fixed to the stand-in's |

Toolbar: `Cancel` leading, `Save` trailing (`confirmationAction`).

Form sections, in order: **Name**, **Emoji**, **Colour**, then actions (Reset, Archive or Restore).

### 3.1 Name

- `TextField`, placeholder `Category name`, accessibility label `Name`. Capitalisation
  `.words`, return key `.next` (moves to nothing; dismisses the keyboard), no autocorrection changes.
  Thai and other keyboards are untouched: the field never filters characters.
- **Cap: 24 characters**, counted as `Character` (grapheme cluster), so a Thai mark is never cut off
  its consonant. Past the cap, input beyond it is dropped, the same way `ComposerTitle` does it.
  Footer appears only at the cap: `Names can be up to 24 characters.` (Q2.)
- **Validation** is live but quiet: nothing shows until the field has been edited. Then:

| Condition (`catalog.validate`) | Message, under the field | Save |
|---|---|---|
| `.empty` (blank, whitespace, or only invisible characters) | `Give this category a name.` | Disabled |
| `.duplicate(ofSlug:)` | `Another category is already called “Admin”. Choose a different name.` | Disabled |
| `nil` | none | Per other fields |

  The duplicate message names the **other** category's display name (`resolve(slug).name`), which can
  differ from what was typed in case or accents. It compares against unarchived categories only, so
  reusing an archived category's name is allowed. Editing a category and leaving its own name alone is
  never a duplicate (`editing:` exempts it).
- Names are trimmed on save with `CategoryCatalog.cleanedName`. Nothing else is altered.
- The slug is minted on first Save from the cleaned name (`CategorySlug.mint` with
  `catalog.takenSlugs`) and checked with `insertIfFree`. It never changes afterwards, so renaming is
  safe for every existing block. The owner never sees a slug.

### 3.2 Emoji (required)

Layout: a header row with the current choice, a suggestion grid, and (on device) a free-entry field.

- **Current choice:** a 56 pt tile showing the chosen glyph (emoji, or its symbol on the simulator).
  Empty: a dashed rounded square with symbol `face.smiling`, VoiceOver `No emoji chosen`.
- **Suggestion grid:** `LazyVGrid`, adaptive columns min 44 pt, spacing 8, 30 cells (list in 3.2.1).
  Each cell is a 44 pt button showing the glyph (`.title2`, `@ScaledMetric`). Selected: 2 pt accent ring
  plus a small `checkmark.circle.fill` badge, `.isSelected`. Not colour alone.
- **Free entry (device only):** a `TextField` row, placeholder `Type your own`. It keeps exactly one
  character: on change, keep the **last** `Character` typed, so typing a new emoji replaces the old one.
  Must pass `CategoryCatalog.isAcceptableEmoji`. When `Emoji.isSupported` is false (the simulator) this
  row is **hidden**, because anything typed would only render as a tofu box. The grid is enough to
  exercise every path on the simulator.
- **Footer:** `Emoji help you tell categories apart without relying on colour. To type your own, switch to the emoji keyboard.` On the simulator, drop the last sentence.
- **Required:** with no emoji, the footer is replaced by
  `Choose an emoji. It keeps this category recognisable without its colour.` and Save is disabled.
  Shown only after the field has been interacted with or Save was attempted (Save is disabled, so
  "interacted" is: the name field has content, or the user left the section).

**Symbol fallback.** `CategoryDefinition` needs a `symbolName`. Rules (a pure function,
`EmojiSuggestions.symbol(for:keeping:)`):
1. If the emoji equals a suggestion's emoji, use that suggestion's symbol.
2. Else if editing and the emoji is unchanged, keep the stored `symbolName`.
3. Else use `star.fill`. Not `tag`: `tag` is the stand-in's glyph and means "not recognised".

On a real phone the symbol is never shown (emoji render). It matters for the simulator and for
screenshots.

#### 3.2.1 Suggestion set

Label is the VoiceOver name. Every symbol name must be confirmed to exist at the deployment target; one
that does not falls back to `star.fill`.

| Emoji | Symbol | Label |
|---|---|---|
| 📚 | `books.vertical.fill` | Books |
| 💼 | `briefcase.fill` | Work |
| 💻 | `laptopcomputer` | Computer |
| ✉️ | `envelope.fill` | Mail |
| 📞 | `phone.fill` | Calls |
| 🛒 | `cart.fill` | Shopping |
| 🧹 | `sparkles` | Cleaning |
| 🍽️ | `fork.knife` | Meals |
| 🚗 | `car.fill` | Travel |
| ✈️ | `airplane` | Flights |
| 🎨 | `paintpalette.fill` | Art |
| 🎵 | `music.note` | Music |
| 🎮 | `gamecontroller.fill` | Games |
| 📖 | `book.fill` | Reading |
| 🏋️ | `dumbbell.fill` | Workout |
| 🧘 | `figure.mind.and.body` | Mindfulness |
| 😴 | `bed.double.fill` | Sleep |
| 🐶 | `pawprint.fill` | Pets |
| 👨‍👩‍👧 | `figure.2.and.child.holdinghands` | Family |
| ❤️ | `heart.fill` | Relationships |
| 💰 | `banknote.fill` | Money |
| 🧾 | `doc.text.fill` | Bills |
| 🛠️ | `wrench.and.screwdriver.fill` | Repairs |
| 🌱 | `leaf.fill` | Garden |
| 💡 | `lightbulb.fill` | Ideas |
| ✍️ | `pencil` | Writing |
| 🎓 | `graduationcap.fill` | Study |
| 💊 | `pills.fill` | Medicine |
| 🎉 | `party.popper.fill` | Social |
| 📅 | `calendar` | Planning |

The six built-in emoji are not in the grid. When editing a built-in, its current emoji shows in the
header tile and nothing in the grid is selected.

### 3.3 Colour

Section header `Colour`. Contents, top to bottom:

**(a) Palette grid.** The twelve swatches in `CategoryPalette.pickerOrder` (Red, Orange, Gold, Lime,
Green, Mint, Teal, Sky, Blue, Violet, Plum, Pink). `LazyVGrid`, adaptive columns min 44 pt, spacing 12.
On a 390 pt phone that is 6 columns by 2 rows. Each swatch is a 44 pt circle filled with the
**light-mode spine** in light appearance and the **dark-mode spine** in dark (from
`CategoryPalette.swatches[i].colors`), so it matches what the blocks will use. Selected: 3 pt accent ring
with a 2 pt gap, and a `checkmark` in the swatch in the mode's `onFill`. Tapping a swatch calls
`choosePalette(index)`, which sets `paletteIndex` and **clears** `customColorHex`.

**(b) The `Other…` row.** One Form row directly below the grid:

- Label `Other…`, leading `paintpalette` symbol.
- Trailing: the system `ColorPicker("Other…", selection:, supportsOpacity: false)` control. It opens
  the system picker; opacity is never offered.
- **Selecting.** The row is selected (a `checkmark` before the label, and the secondary text
  `Custom`) **only after a colour is actually picked**, not when the picker merely opens. On change,
  convert the picked `Color` to sRGB, **clamp each component to 0...1** (a Display P3 pick can fall
  outside), format as uppercase `#RRGGBB`, and call `chooseCustom(hex:)`. It leaves `paletteIndex`
  alone. If it returns false, change nothing.
- **Initial colour in the picker:** the current custom hex if one is set; otherwise the current
  swatch's light-mode spine, so the picker opens near what the owner already has.
- **Tap target:** the engineer must check on a device whether tapping the label opens the picker or
  only the well does. If only the well, the well is the target and must be at least 44 x 44 pt; the
  label is then plain text, and the row's VoiceOver element is the picker control with the label
  below. Do not attach an overlay button that fights the control.
- Choosing a swatch later clears the custom hex and unticks this row. The custom colour is not kept
  for next time. (The owner asked for one custom colour per category, not a history.)

**(c) Previews, in both modes.** Directly under the row, always visible (palette or custom), so a
rename or emoji change is visible too:

```
 Light                      Dark
 +----------------------+   +----------------------+
 | [spine] 🧠 Errands   |   | [spine] 🧠 Errands   |
 +----------------------+   +----------------------+
```

- Two **surface patches**, each filled with the mode's **canvas** (`ColorSurfaces` value for that mode,
  not the system background, so the patch is right even when the phone is in the other mode), 12 pt
  inside padding, radius 12, holding one miniature chip.
- **Miniature chip:** min height 44 pt, radius 8, background = that mode's `fill`, 1 pt `border`, 3 pt
  `spine` bar on the leading edge, glyph, then the category name in `.footnote` in the mode's
  `onFill`. It is the same anatomy as the block chip, drawn from one `CategoryColors` record. It
  uses explicit record colours, **never** semantic ones, so the dark patch is dark even in a light phone.
- Captions above each patch: `Light` and `Dark`, `.caption`, `.secondary`.
- Side by side at standard sizes. At accessibility sizes, stacked vertically.
- Empty name shows `Name` as placeholder text in the chip.
- For a custom colour, the preview chips are drawn from `CustomCategoryColor.derive`; for a swatch,
  from the swatch record. The spine on screen will not equal the picked colour. That is the point of
  the note in (e).

**(d) One warning line, worst problem only.** Computed on every change from
`CustomCategoryColor.assess(colors, surfaces:, others:)`, where `others` is **every other unarchived
category** (not the one being edited, not archived ones; the caller supplies this because `assess`
cannot know). Run for **both** palette and custom choices: a palette swatch can still sit close to a
custom neighbour. Show **one** line, the first concern. Never a list.

- Precedence (already encoded in `assess` order): low contrast, looks like a meeting, close to a
  category. A **grey pick** (`CustomCategoryColor.isGrey`) overrides `looksLikeMeeting` with its own
  line. Custom colours only.
- Modes. `assess` returns one concern per mode. If the same kind (and, for `closeTo`, the same slug)
  appears in both modes, say `light and dark mode`; otherwise name the one mode.
- Style: 0.5 warning, `.footnote`, in its own Form row. **Save stays enabled.**
- Strings (from `category-palette.md` section 5.1):

| Concern | Text |
|---|---|
| `lowContrast` | `Title may be hard to read in light mode` / `…in dark mode` / `…in light and dark mode` |
| `looksLikeMeeting` | `Looks like a meeting in light mode` / `…in dark mode` / `…in light and dark mode` |
| `closeTo(slug)` | `Close to Admin in light mode` / `…in dark mode` / `…in light and dark mode` (the other category's current name) |
| Grey pick | `Too grey to tell apart from a meeting` |

- VoiceOver: label `Warning. Looks like a meeting in dark mode`. The line is a plain element; it is
  not announced on every drag. After the system picker closes, announce the line once if it changed
  (`AccessibilityNotification.Announcement`, debounced one second, none for palette taps).
- No line when `assess` returns `[]`. Do not show a "looks good" message; absence is the good state.

**(e) The derived-brightness note, as the section footer, shown only while Other… is selected:**
`Blockey adjusts brightness for light and dark mode. Your pick sets the hue.`
Exactly this sentence, once. (Owner decision, `category-palette.md`.) Not shown for a swatch, because
a swatch is already the measured colour.

### 3.4 Default colour for a new category

A new category starts with the first swatch in `pickerOrder` that **no unarchived category currently
uses** (compare `colorChoice`; a custom colour uses none). If all twelve are used, start at
`unarchivedCount % 12` in picker order. The owner then needs only a name and an emoji, which removes
the colour decision from the common path. In Adopt mode the colour is the stand-in's FNV swatch, so
nothing changes on screen (ADR 005).

### 3.5 Save, Cancel, dirty state

- **Save enabled** when: the name has no problem, an emoji is set, and (Edit modes) the draft differs
  from the stored value. Add mode needs no "different" check.
- **Save writes:**
  - Add: mint the slug, `insertIfFree`, `sortIndex` = last unarchived `sortIndex` + 1. If `insertIfFree`
    returns false, show the error below and write nothing.
  - Edit on a category that has a row: mutate the row in place, never insert.
  - Edit on an untouched built-in: create its override row via `insertIfFree`, copying the built-in's
    defaults for fields the owner did not change.
  - Then `try context.save()`.
- **On success:** dismiss. Return the saved slug to the caller (the pickers use it).
- **On failure:** stay open, nothing half-written, inline error row above the Save-affecting content:
  `Couldn’t save this category. Nothing was changed. Try again.`
- **Cancel, not dirty:** dismiss immediately.
- **Cancel, dirty:** `confirmationDialog`, title `Discard your changes?`, buttons `Discard changes`
  (destructive) and `Keep editing` (cancel). While dirty, `interactiveDismissDisabled(true)`, so a
  swipe-down cannot drop work. When not dirty a swipe-down just dismisses.
- Dirty is "draft differs from where the editor started". In Add mode, dirty once any field has
  content.
- No loading state and no spinner. Save is a local write.

### 3.6 Edit mode extras

- **Past-blocks note**, as the footer of the last section in Edit and Archived modes:
  `Changes apply to every block, task and template row that uses this category, including past ones. Nothing in your calendar is rewritten.`
  This is true by construction: blocks carry only the slug (ADR 005) and resolve on read. Not shown in
  Add mode.
- **`Reset to default`**, built-ins only, shown only when the draft differs from the built-in's default
  name, emoji, symbol or colour. Not destructive style. It **loads the defaults into the draft**; Save
  commits. It does not delete the row (ADR 005 describes deletion; the pixels are the same and keeping
  the row preserves the category's position and archive state). A reset name that collides with
  another category fails validation like any other name, which is the right outcome.
- **`Archive category`**, section of its own at the bottom, symbol `archivebox`, not red. Enabled
  when `canArchive(slug)` **and** the draft would be savable. It saves the draft and archives in one
  write, going through the move-to flow (2.5) first when anything uses the category. Disabled with the
  footer `Blockey needs at least one category. Add another before archiving this one.` when it is the
  last one. Not shown in Add or Adopt mode.

### 3.7 Archived mode

Same form, with a banner row at the top: symbol `archivebox`, text
`This category is archived. Blocks that use it still show it, but it isn’t offered for new work.`
The first action button is `Restore category` (prominent in its section). It saves the draft and clears
`archivedAt`. If the name now duplicates an active category, the name error shows and Restore and Save
are disabled until it is changed. `Archive category` is hidden. `Reset to default` is hidden.

### 3.8 What happens to past blocks

Nothing is rewritten, ever. Every block, task and template row stores the slug only; name, emoji and
colour are looked up when drawn. So rename, re-emoji, recolour, archive and restore all show on past
blocks immediately, with no calendar writes (CLAUDE.md invariants hold: `EKEvent` stays in
`Calendar/`). The footer in 3.6 says so.

### 3.9 Editor state matrix

| State | Behaviour |
|---|---|
| Default (Add) | Empty name and emoji, default swatch, Save disabled, no messages |
| Default (Edit) | Stored values, Save disabled until something changes |
| Name empty after typing | `Give this category a name.`, Save disabled |
| Name duplicate | The `Another category is already called…` message, Save disabled |
| Emoji missing | Footer swaps to the required message, Save disabled |
| Custom colour with a concern | One warning line, Save enabled |
| Custom colour grey | `Too grey to tell apart from a meeting`, Save enabled |
| Saving | Instant. Buttons disabled for the duration of the call only |
| Save error | Inline `Couldn’t save this category…`, editor stays open |
| Success | Sheet dismisses |
| Dirty cancel | Discard dialog |
| Simulator (`!Emoji.isSupported`) | Free-entry row hidden, grid shows symbols |

---

## 4. The unknown-slug block

### 4.1 What the stand-in looks like

An unknown slug is one with no built-in and no definition (`origin == .standIn`). Everywhere it is
drawn, it uses what `resolve` already returns:

- **Name:** recovered from the slug (`u-` dropped, `-` as space). Best effort.
- **Glyph:** the tag. Emoji `🏷️` on a device, `tag` symbol where emoji are unavailable. This is
  deliberately different from every real category so the owner can see "not recognised".
- **Colour:** the FNV-1a swatch for the slug, stable across launches and devices. Never a custom colour.
- **No special badge on the timeline.** The timeline chip shows the tag glyph, the recovered colour,
  the block's own title and the name in its VoiceOver label. Marking it further is Story 3's call.
  The explanation and the fix live in the block sheet, where the owner can act.

### 4.2 The one-tap adopt flow

Location: `BlockDetailSheet` and `TemplateRowEditor`, as the footer of the `Category` section (1.2),
and inside the `Current` section of the choice list (1.3). Same button, same behaviour, wherever it
appears.

1. The footer reads `“Errands” isn’t saved as a category on this phone.`
2. Under it, a full-width row button, 44 pt minimum: symbol `plus.circle`, label `Add as category`,
   accent colour. VoiceOver hint: `Adds it with this name. Every block that uses it updates. Nothing in your calendar changes.`
3. **One tap.** No confirmation. It inserts `catalog.definitionAdopting(standIn: slug, sortIndex:)` via
   `insertIfFree` and saves. The definition keeps the stand-in's FNV swatch and the tag emoji, so
   **nothing on screen changes colour or glyph**; the name is the recovered one. No calendar write.
4. The row immediately renders as a normal category. The footer becomes
   `Added “Errands”. Change its emoji and colour in Settings.` and stays until the sheet closes.
   VoiceOver announces `Added as category`.
5. The item is **not** modified: the slug is the same, so Save on the block sheet still writes no
   category (0.3).

**Edge: the recovered name collides.** If `validate(name:editing: nil)` returns `.duplicate` (say the
recovered name is "admin" and `Admin` is active), a one-tap add would create two identical names. In
that case the button still reads `Add as category`, but it opens the editor in Adopt mode with the
name field already showing the duplicate message, so the fix is a rename and Save. The slug is fixed to
the stand-in's.

**Failure:** the write throws, or `insertIfFree` returns false. Nothing changes. Footer:
`Couldn’t add this category. Nothing was changed. Try again.`

### 4.3 Where adoption is not offered

An unknown slug on an **inbox task** (after a restore, say) renders as a stand-in glyph, but there is
no per-task editor, so there is no button. It becomes adoptable once the task is placed (it becomes a
block) or if the owner opens a template row with the same slug. This is a known limit, not a bug to fix
in this issue (Q4 asks whether to close it).

---

## 5. Every string

Grouped by place. Curly quotes and apostrophes throughout. `{x}` marks a runtime value.

**Picker, Form row and list**

| Where | String |
|---|---|
| Section title | `Category` |
| Row label | `Category` |
| List title | `Category` |
| `Current` section header | `Current` |
| Archived subtitle | `Archived` |
| Stand-in subtitle | `Not saved as a category` |
| Archived footer | `“{name}” is archived. It still shows here, but it won’t be offered for new work.` |
| Stand-in footer | `“{name}” isn’t saved as a category on this phone.` |
| Action row | `New category…` |
| Adopt button | `Add as category` |
| Adopt success | `Added “{name}”. Change its emoji and colour in Settings.` |
| Adopt failure | `Couldn’t add this category. Nothing was changed. Try again.` |
| Composer new chip | `New` (VoiceOver `New category`) |
| Composer collapsed chip VO | `Category, {name}` |
| Composer sheet cancel | `Cancel` |

**Settings list**

| Where | String |
|---|---|
| Row | `Categories` |
| Row section footer | `Names, emoji and colours for your blocks. Changing one updates everything that uses it.` |
| Screen title | `Categories` |
| Add row | `Add category` |
| Active footer | `Tap Edit to reorder. This order is used wherever you pick a category.` |
| Last-one footer | `Blockey needs at least one category. Add another before archiving this one.` |
| Archived header | `Archived` |
| Archived footer | `Archived categories stay on the blocks that use them. They just aren’t offered for new work.` |
| Swipe / action | `Archive`, `Restore`, `Move up`, `Move down` |
| Announcements | `Added “{name}”`, `Archived “{name}”`, `Restored “{name}”`, `Moved {name} to position {n} of {total}` |

**Archive sheet**

| Where | String |
|---|---|
| Title | `Archive “{name}”?` |
| Usage | `3 inbox tasks and 2 template rows use this category.` (variants in 2.5) |
| Calendar note | `Blocks already on your calendar keep this category.` |
| List header | `Move them to` |
| Helper | `Choose a category to move them to, or archive without moving.` |
| Primary | `Move {n} and archive` |
| Secondary | `Archive without moving` |
| Secondary note | `They keep “{name}” and still show it. It just won’t be offered for new work.` |
| Cancel | `Cancel` |
| Inline failure | `Couldn’t archive “{name}”. Nothing was changed. Try again.` |
| Alert (no-prompt path) | title `Couldn’t archive`, message `Nothing was changed. Try again.`, button `OK` |

**Editor**

| Where | String |
|---|---|
| Titles | `New category`, `Edit category`, `Add category` (Adopt) |
| Toolbar | `Cancel`, `Save` |
| Name header, field | `Name`, placeholder `Category name` |
| Name empty | `Give this category a name.` |
| Name duplicate | `Another category is already called “{other}”. Choose a different name.` |
| Name cap | `Names can be up to 24 characters.` |
| Emoji header | `Emoji` |
| Emoji free entry | `Type your own` |
| Emoji footer | `Emoji help you tell categories apart without relying on colour. To type your own, switch to the emoji keyboard.` |
| Emoji required | `Choose an emoji. It keeps this category recognisable without its colour.` |
| Empty tile VO | `No emoji chosen` |
| Colour header | `Colour` |
| Other row | `Other…` (secondary when active: `Custom`) |
| Preview captions | `Light`, `Dark` |
| Preview placeholder | `Name` |
| Concern lines | see 3.3 (d) |
| Derived note | `Blockey adjusts brightness for light and dark mode. Your pick sets the hue.` |
| Past blocks footer | `Changes apply to every block, task and template row that uses this category, including past ones. Nothing in your calendar is rewritten.` |
| Adopt banner | `Blocks already use this category. Saving it gives them this name, emoji and colour.` |
| Archived banner | `This category is archived. Blocks that use it still show it, but it isn’t offered for new work.` |
| Actions | `Reset to default`, `Archive category`, `Restore category` |
| Save failure | `Couldn’t save this category. Nothing was changed. Try again.` |
| Discard dialog | title `Discard your changes?`, buttons `Discard changes`, `Keep editing` |

---

## 6. Accessibility

**Targets (44 x 44 pt minimum, visible shape may be smaller).**
- Picker rows, list rows, archive-sheet rows: 44 pt min height, whole row tappable.
- Composer category chips and the `New` chip: 44 pt hit area (today's chips are about 28 pt).
- Palette swatches: 44 pt circles. Emoji cells: 44 pt. The colour well: 44 pt.
- Adopt button: 44 pt.

**VoiceOver.**
- Swatch: `{Name}, colour {n} of 12`, plus `Selected` when chosen. `{n}` is the **picker position**
  (1 to 12 in `pickerOrder`), `{Name}` is `CategoryPalette.swatches[i].name`.
- `Other…` row: label `Other colour`, value `Selected` when custom, hint `Opens the colour picker`.
- Previews: label `Preview in light mode` and `Preview in dark mode`, value = the category name.
- Emoji cells: the label from 3.2.1, `Selected` when chosen. The header tile reads the chosen label, or
  `No emoji chosen`.
- Warning line: `Warning. {text}`.
- Reorder: `Move up` and `Move down` custom actions, with the position announcement in 2.4.
- Decorative glyphs and tiles in list rows are hidden; the name and status are what is read.
- Every sheet's first focus is its title or first field; the editor puts focus on the Name field in
  Add mode only.

**Dynamic Type.** Nothing in the picker, list, archive sheet or editor is fixed-height. Tiles and
swatches scale with `@ScaledMetric`; grids use adaptive columns so they reflow. The chip previews stack
at accessibility sizes. The timeline's own cap at `accessibility1` is unchanged (out of scope).
**Thai names:** test one with stacked tone marks at `accessibility3` in every place a name appears. Use
`minHeight` and never a fixed frame around name text, or the marks are clipped.

**Reduce Motion.** No new animation is required. Where the list animates rows into `Archived`, the
composer scrolls to a new chip, or the warning line appears, gate it with
`accessibilityReduceMotion` and use no animation (matching `InboxTray`'s existing `reduceMotion ? nil`
pattern). Selection changes are an instant ring or check, never a slide.

**Colour is never the only signal.**
- Identity: glyph and name, in every row, chip and preview.
- Selection: ring plus `checkmark`, plus `.isSelected`.
- Archived and unknown: written subtitles (`Archived`, `Not saved as a category`), not dimming.
- Warnings and errors: symbol plus text.
- The required emoji exists for this reason (ADR 005).

**Contrast.** Row, chip and sheet text is `.primary` on system backgrounds. Preview chips use
`onFill` on `fill`, which `assess` already guarantees at 4.5:1 or flags. The warning symbol is orange
but the text is `.primary`.

---

## 7. State matrix for QA

| Surface | States to cover |
|---|---|
| Form row | active, archived, unknown, each at default and `accessibility3` |
| Choice list | no `Current` section; archived `Current`; unknown `Current` with button; 1 category; 15 categories; long Thai name |
| Composer | 6 chips; 9 chips (collapsed); accessibility size (collapsed); new category created from `New`; draft category archived while the tray is open |
| Categories list | default; one active left; archived section present and absent; edit mode; Move up/down |
| Archive | 0 uses (no prompt); tasks only; rows only; both; singular and plural strings; move; decline; failure |
| Editor | every row of 3.9, in light and dark, with a built-in and a custom, with and without emoji support |
| Colour | each of 12 swatches; custom bright yellow; custom grey; custom near an existing category; custom meeting-like pastel; Display P3 pick clamped |
| Unknown slug | block sheet; template row; collision name; failure; timeline chip unchanged by adoption |

Seed on the **simulator only**. Never touch the real Calendar. For an unknown-slug block, seed an
event with a `c=` the catalog does not know. Emoji will show as symbols in the simulator; that is
expected (CLAUDE.md), so verify glyphs on the phone.

Tests the engineer should add with the pure code (section 9): usage sentence for every count, reorder
output, default-swatch choice, symbol fallback, concern sentence for each kind and mode combination,
name cap by grapheme cluster, and "archived and unknown values appear in the `Current` section".

---

## 8. Out of scope (Story 3 and others)

- **The timeline restyle is Story 3.** In this issue the current chips only **swap their colour
  source**. Replace `block.category.tint` with `CategoryStyle(resolved).spine` at
  `TimelineCanvas.swift:314`, `:381` and the sites that follow it (and `Emoji.swift:76`,
  `RootView.swift:40`), and keep **every opacity, border width and layout constant exactly as it is**.
  The chip's VoiceOver label reads the resolved name. Expected visible changes, all intended:
  `admin` turns teal (finding M9, `category-palette.md`), and dark-mode spines are the lifted values.
  Nothing else changes: no opaque fills, no new density rules, no fixed-event chip work.
- `CategoryGlyph` takes a `CategoryStyle` (or a resolved category) instead of a `BlockCategory`. Its
  symbol fallback behaviour is unchanged.
- Chip anatomy, density rules, the meeting `lock` mark and opaque fills are Story 2 and Story 3.
- Composer chip *paint* is Story 7 (1.4). This spec fixes behaviour, targets and data only.
- Backup v2 UI and copy (task 3.9). The restore warning's category count is that task's.
- Reconciliation, completion and every other known gap in CLAUDE.md.
- Per-task category editing in the inbox (4.3).
- A "use my exact colour" override. Rejected in `category-palette.md` section 5.
- Colour-blind simulation in the editor.
- Removing `BlockCategory`. It may survive as a shim until the last caller takes slugs.
- Importing or sharing categories.

---

## 9. Pure code this UI needs first (tests before views)

None of these exist (checked). Put them in `Catalog/` (Foundation only) unless noted. Each gets tests.

1. `CategoryCatalog.archived()` and `CategoryCatalog.activeInOrder()`: the lists the Settings screen
   shows. (`choices` only returns unarchived plus `current`.)
2. `CategoryOrdering.reordered(...)`: returns the new `sortIndex` for every unarchived category after
   a move, plus the rows that must be created for built-ins.
3. `CategoryUsage.sentence(tasks:rows:)` and `moveButtonTitle(count:)`.
4. `CategoryPalette.defaultIndex(avoiding:)` for 3.4.
5. `EmojiSuggestions` (the table in 3.2.1) and `symbol(for:keeping:)`.
6. `ColorConcernCopy.line(for: [ColorConcern], isGrey:, nameFor:)`, folding the two modes into
   `light and dark mode`.
7. `CategoryNameField.clamped(_:)` for the 24-character cap by `Character`.
8. A planning-style function (home is the engineer's call; it touches `TaskItem` and `TemplateRow`,
   so not `Catalog/`) that counts and moves by slug and archives in one save.
9. `ComposerDraft.category` becomes a slug and `apply(_:)` accepts any resolvable slug.

**Compare against `gh issue view 1` before building:** the issue's acceptance list, in particular
anything about inbox-task categories (4.3), the composer, and Backup.

---

## 10. Open questions, with recommendations

The owner is answering quickly, so these are the only four.

- **Q1. Composer category chips.** Plan task 3.8 says "a Category chip in the composer that opens the
  full list". The redesign plan calls it "the new-category chip". This spec reads both as: keep the
  inline chips, add a trailing `New` chip, and collapse to one chip that opens the full list when there
  are more than 8 categories or at accessibility sizes (1.4). **Recommend: as specified.** The six
  chips the owner uses daily stay one tap.
- **Q2. Name length.** ADR 005 sets no cap on names, only on the slug body (32 clusters). Long names
  break chips and the timeline. **Recommend: cap at 24 characters** (3.1). The slug cap is independent.
- **Q3. Does Reset to default delete the override row (ADR 005) or write defaults into it?**
  **Recommend: write defaults and keep the row** (3.6), so a reset category keeps its position and
  archive state. Pixels are identical.
- **Q4. Adopting from an inbox task.** Stand-in tasks have no editor and no button (4.3).
  **Recommend: leave it.** It only arises after a restore into a fresh install, and placing the task
  makes it a block that can be adopted. Revisit if it bites.

Files the engineer will touch: `Views/BlockDetailSheet.swift`, `Views/TemplatesView.swift`
(`TemplateEditor`, `TemplateRowEditor`), `Views/InboxTray.swift`, `Views/SettingsView.swift`,
`Views/Emoji.swift` (`CategoryGlyph`), `Views/TimelineCanvas.swift` (colour source only),
`Views/RootView.swift`, `Catalog/ComposerSuggestionRow.swift`, new `Views/CategoryPicker.swift`,
`Views/CategoriesListView.swift`, `Views/CategoryEditor.swift`, and the new pure files in section 9.
Never edit `project.pbxproj`.

**Status 2026-11-04:** Q1 to Q4 adopted on their recommendations so the build can proceed; the owner can reverse any of them.
