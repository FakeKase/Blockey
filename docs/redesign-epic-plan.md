# Redesign epic: plan

Date: 2026-11-04
Author: `designer` agent. Read-only planning pass, no app code touched, no issues created.
Status: **DRAFT.** Open questions are in section 5. Nothing here is a decision until the owner answers or says to proceed on the recommendations.

The epic has two goals, both from the owner:

- **(a) Visual refresh.** "Looks plain or generic, like a default SwiftUI app", and "the timeline is hard to read": blocks, meetings and free time do not stand apart, especially in dark mode.
- **(b) Flow and usability.** Finish what `docs/design-review.md` found and sprint 1 did not land.

Everything in section 1 was checked against the source on branch `sprint-1`, not against other docs.

---

## 1. Findings status (design review, verified against code)

Counts: **36 findings. 12 fixed, 9 partly fixed, 15 open.**
By tier: Must-fix 6 fixed, 4 partly, 0 open. Should-fix 5 fixed, 4 partly, 6 open. Polish 1 fixed, 1 partly, 9 open.

Paths are under `Blockey/Views/` unless stated. "Residual" is what is left to do.

### Must-fix

| ID | Status | Evidence | Residual |
|---|---|---|---|
| M1 arming closes inbox | Fixed | `TodayView.swift:202` shrinks to `armedDetent`; `:214-215` detents and background interaction | Optional: open inbox after Add my Workday |
| M2 past gaps offered | Fixed | `TodayView.swift:124-129` uses `plannableWindow` (`:76`) | none |
| M3 no undo, no clear | Fixed | Undo: `PlanBannerView.swift:83`, `TodayView.swift:707`. Clear: `:628`, `:250` | none |
| M4 restamp dialog | Fixed | Dialog deleted; `PlanSheet.swift` with Keep / Start over (`:216`) | none |
| M5 errors ephemeral, low contrast | Partly | Fixed: material + symbol + primary text (`PlanBannerView.swift:104-121`), warnings 7 s (`:37`), partial-failure copy (`DayPlanner.swift:196,239`). Open: not sticky; `noCalendarAvailable` is still a banner (`CalendarService.swift:30`, `TodayView.swift:683`), no Open Settings alert | Story 8 |
| M6 restore destroys silently | Fixed | `SettingsView.swift:164-172` confirms with counts before `restore` | Label still "Restore from a backup" (`:122`), cosmetic |
| M7 bar floats over content | Fixed | `TodayView.swift:190,508` `safeAreaInset` with `.bar` | none |
| M8 first-run blank | Partly | `emptyDayCard` `:458-490` covers template and no-template; summary line covers meetings-only (`:410`). Missing: access granted but no calendars enabled | Story 8 |
| M9 blocks vs meetings | Partly | Fill raised, glyph on chip (`TimelineCanvas.swift:386,393`). `admin` is still grey-blue (`BlockCategory.swift:72`), the colour family of fixed events | Stories 2, 3 |
| M10 dark mode inversion | Partly | Light/dark tint pairs (`BlockCategory.swift:68-85`), scheme-aware chip fills (`TimelineCanvas.swift:393-394,462-466`). Still `Color.primary` alpha for out-of-window shade (`:139`) and gridlines (`:111`) | Story 3 |

### Should-fix

| ID | Status | Evidence | Residual |
|---|---|---|---|
| S1 Dynamic Type timeline | Partly | `ChipDensity` (`TimelineCanvas.swift:348`), type capped at `accessibility1` (`:399,470`). `hourHeight`, `gutterWidth` still fixed (`:33-35`) | Story 4 |
| S2 VoiceOver | Partly | Meetings are elements (`:471-473`), gap action (`:181`), banners announced (`TodayView.swift:286`). No move/resize actions on blocks | Story 4 |
| S3 tap targets | Partly | Chevrons 44 (`TodayView.swift:361-364`), add button 44 (`InboxTray.swift:124`). Grabber still 26x3 (`TimelineCanvas.swift:315`); no day swipe | Stories 4, 5 |
| S4 tint as text | Open | `InboxTray.swift:233` tints chip text | Story 7 |
| S5 free counts past | Fixed | `TodayView.swift:403` uses `plannableWindow` | none |
| S6 type scale | Open | Chip titles `.footnote` vs `.caption` (`TimelineCanvas.swift:424,495`); eight styles in use | Stories 1, 3 |
| S7 spacing | Open | Header 4/12 (`TodayView.swift:392-393`), bar 12 (`:505`), sheets 16 | Stories 1, 6 |
| S8 "Apply template" | Fixed | `TodayView.swift:553` | none |
| S9 Fill day in Cancel slot | Fixed | `InboxTray.swift:74` bottom button | none |
| S10 30 to 90 min is 12 taps | Open | `BlockDetailSheet.swift:47` stepper step 5 | Story 5 |
| S11 hourly scroll yank | Open | `TimelineCanvas.swift:84` | Story 5 |
| S12 create from timeline | Partly | `+` creates a 30 min block at first fit (`TodayView.swift:619,732`). No gesture on empty canvas | Story 5 |
| S13 inbox pill "0" | Fixed | `TodayView.swift:566-567` | none |
| S14 duplicate nav title | Fixed | `TodayView.swift:184` empty title | Toolbar bar still costs ~44pt for two icons (Story 6) |
| S15 permission copy | Open | `CalendarService.swift:82` maps write-only to denied; `RootView.swift:46-48` old copy and wrong path | Story 8 |

### Polish

| ID | Status | Evidence | Residual |
|---|---|---|---|
| P1 `15.0h` | Fixed | `TodayView.swift:407` | `TemplatesView.swift:90` still `%.1fh` (Story 7) |
| P2 grabber looks stray | Open | `TimelineCanvas.swift:313-317` | Story 3 |
| P3 now-line time | Open | `:258-274` | Story 3 |
| P4 doubled borders | Open | `:251-256` only insets horizontally | Story 3 |
| P5 first-run flash | Open | seeding in `.task`, `TodayView.swift:258` | Story 8 |
| P6 tasks not editable or completable | Open | `completedAt` has no writer (`Models/TaskItem.swift:17,53,91`), CLAUDE.md gap 2 | Story 9 |
| P7 save day as template | Open | no match in source | Story 9 |
| P8 weekday menu affordance | Open | `TemplatesView.swift:29-38` | Story 7 |
| P9 haptics | Partly | only drag pickup (`TimelineCanvas.swift:85`) | Story 5 |
| P10 alert label | Open | `SettingsView.swift:66` | Story 7 |
| P11 inverted window | Open | `DaySchedule.swift:118-124` no clamp, pickers unconstrained | Story 8 |

**Not in this epic (structural, separate):** CLAUDE.md gap 1 (reconciliation), gap 2's completion/rollover machinery, gap 3 (multi-day timed events make a day read busy), gap 4 (subscribed calendars count as busy), gap 5 (no debounce). Gaps 3 and 4 change what "free time" means on the timeline, so see question Q6.

---

## 2. Visual direction (sketch)

Full spec comes later as its own story (Story 2 plus the Story 1 token table).

### Character

A calm printed day-planner, not a dashboard. **Chrome is ink, colour belongs to categories.** The default SwiftUI blue accent is the strongest "generic" signal in the app, and it competes with `deepWork` blue. Make the app chrome monochrome (primary button fill is ink: near-black in light, near-white in dark) so the only saturated colour on screen is the user's own categories. Warmth comes from rounded numerals for times and the day title (`.fontDesign(.rounded)`), generous header space, and a soft off-white / deep-charcoal canvas. No gradients, no illustration. Dark mode is a first-class design, not an inversion.

### Three surfaces, three materials

The timeline must answer one question at a glance: what is mine, what is booked, what is open.

| Thing | Treatment | Why it reads |
|---|---|---|
| **Free time** | The canvas itself. Inside the planning window, a very slightly lifted surface; outside it, dimmed with black alpha (never `primary`, which brightens in dark). Hairline hour rules. | Open space should look like paper, not like a component |
| **Fixed meetings** | Neutral, low chroma, *never a hue*. Flat tertiary-fill surface, dashed 1pt edge, `.secondary` text, no glyph tint, small `lock` mark at the trailing edge when height allows. Smaller visual weight than blocks in both modes. | "Not yours, not movable" is a texture, not a colour |
| **Your blocks** | Opaque tinted fill (precomputed per mode, so gridlines never show through), solid 1pt border, 4pt leading spine in the full category colour, category glyph, `.primary` title. Heaviest object on the screen. | "Mine and movable" is the loudest thing, which is the product's point |

Rules that hold the hierarchy:

- Block chroma > meeting chroma by a wide margin. A meeting has **no** hue, so the admin-looks-like-a-meeting problem (M9) ends by giving every category a real hue (admin moves to teal, per the review's measurement).
- Colour is never the only channel: glyph at the leading edge, spine, and the dashed vs solid edge carry the same information.
- The armed-slot overlay uses the ink accent dashed, not blue, with `.primary` text on a tinted fill (fixes the 3.44:1 "Tap to place").
- Now-line: red stays (it is a convention), plus a time pill in the gutter (P3).

### Colour system: roles, pairs and targets

Each category is **one record** of hand-authored light and dark values, not alpha math: `spine`, `fill` (opaque), `border`, `onFill` (text, almost always `.primary`). Surfaces: `canvas`, `canvasLifted`, `canvasDimmed`, `rule`, `meetingFill`, `meetingEdge`.

Targets (WCAG-style, measured with the same method as the review, light and dark, against the real canvas colour):

| Pair | Target |
|---|---|
| Title / time text on any chip fill | at least 4.5:1, aim 7:1 for titles |
| Hour labels on canvas | at least 4.5:1 (use `.secondary`, not `.tertiary`) |
| Block border and spine vs canvas (non-text UI) | at least 3:1 |
| Block fill vs canvas | visible: deltaE at least 8 and at least 1.3:1 luminance |
| Block fill vs meeting fill | deltaE at least 15, plus a chroma gap |
| Category fill vs category fill | deltaE at least 10 normally; best-effort 6 under deuteranopia and protanopia, backed by the glyph |
| Hour rule vs canvas | at least 1.2:1 light, at least 1.5:1 dark |
| Banner and chip text outside fills | never a category tint as text (S4); tints are for shapes and symbols |
| Now-line | at least 3:1 |

The six current built-ins (`BlockCategory.swift:68-77`) are the starting candidates. Likely changes: `admin` to teal, `fill` and `border` become explicit values, dark pair `spine` lifted for the 3:1 border target.

### Type and spacing (one scale, held everywhere)

- **Type** (review S6): Screen title `.headline` (day title may go `.title3.weight(.semibold)` rounded), Row title `.body`, Chip title `.subheadline.weight(.semibold)` for **both** blocks and meetings, Supporting `.footnote`, Micro `.caption2.monospacedDigit()` for the gutter only. No `.caption`, no 1pt differences doing semantic work.
- **Spacing:** 4 / 8 / 12 / 16 / 24 / 32. One 16pt page margin for header, bar and sheets. The gutter keeps its own edge.
- **Radius:** 10 chip and card, 14 sheet-level card, Capsule for pills.
- **Motion:** `.snappy`, off under Reduce Motion (existing pattern in `TodayView.swift:348`).
- **Dynamic Type:** gutter and hour height scale with `@ScaledMetric`; canvas text stays capped at `accessibility1` as a recorded decision, all other screens scale fully.

### The seam with custom categories

Views must stop reading `BlockCategory` directly. Story 2 introduces a small value, `CategoryStyle` (title, emoji, symbolName, spine, fill, border), built today from `BlockCategory` and later from #1's `ResolvedCategory`. Every chip, picker row and glyph consumes `CategoryStyle` only. That keeps #1 phase 3 task 3.7 (which replaces the three `allCases` pickers and the glyph/tint sites) a swap of the producer, not a rewrite of the views.

---

## 3. Stories

Sizes: **S** under 2 hours, **M** half a day, **L** 1 to 2 days, **XL** 3 or more days. Agents: `designer`, `frontend-engineer`, `qa-engineer`, `architect`. SDLC order inside every story: design, build, test, review. Each story ends with the standing review loop (a different agent than the author). No story edits `project.pbxproj`. Simulator screenshots are not truth for emoji, so any story that shows glyphs ends with an on-device check by the owner.

Order and dependencies:

| # | Story | Size | Depends on |
|---|---|---|---|
| 1 | Design tokens and scales | M | none |
| 2 | Category colour records and chip anatomy | M | 1 |
| 3 | Timeline visual hierarchy | L | 1, 2 |
| 4 | Timeline accessibility and Dynamic Type | L | 3 |
| 5 | Timeline touch and flow | L | 3 |
| 6 | Today chrome, banner and empty states | L | 1 |
| 7 | Sheets and Settings restyle | L | 1, 2 |
| 8 | Permission, setup and error states | M | 6 |
| 9 | Task and template upkeep | L | 7 |

Stories 4 and 5 can run in parallel; 6 can start once 1 lands.

### Story 1: Design tokens and scales

As the owner, I want one set of type, spacing, radius and surface tokens, so that every screen looks like the same app and later stories do not each invent values.

**Acceptance**
- [ ] A token table (type roles, spacing 4/8/12/16/24/32, radii, surface colours with light/dark values) exists in `docs/` and is the only source the code follows.
- [ ] `Views/DesignSystem/` (new folder, auto-included) holds `Tokens` (spacing, radius), `Surface` colours (as asset-catalog or `UIColor` dynamic pairs) and the type-role modifiers.
- [ ] `AccentColor` is set to the decision from Q2; buttons use it consistently.
- [ ] No screen is restyled yet and the app looks the same except where a token replaced a stray value; the suite is green.
- [ ] Every surface colour meets the section 2 targets, measured and recorded in light and dark.

**Tasks**
- [ ] designer: token table and measurements, rounded-design decision (M)
- [ ] frontend-engineer: token types and surface colours, no view changes (S)
- [ ] qa-engineer: contrast check script or test over the surface pairs; build and test run (S)
- [ ] architect: confirm `Views/DesignSystem/` stays out of `Scheduling/`, `Planning/`, `Calendar/` rules (S)

**Collision with #1 phase 3:** none. Do not create `CategoryPalette` here.

### Story 2: Category colour records and chip anatomy

As the owner, I want every category to have a distinct, readable colour in light and dark, so that I can tell my blocks apart from each other and from meetings.

**Acceptance**
- [ ] Six records (`spine`, `fill`, `border`, `onFill`) in light and dark, measured against section 2 targets; `admin` has a real hue.
- [ ] Block-vs-meeting and category-vs-category deltaE reported for normal, deuteranopia and protanopia, with the weak pairs named.
- [ ] `CategoryStyle` exists and `BlockChip`, `CategoryGlyph`, `InboxTray` chips and the pickers read it instead of `BlockCategory` directly.
- [ ] Chip anatomy is specified for three densities (`full`, `single`, `titleOnly`), including glyph size and the meeting `lock` mark.
- [ ] Existing tint call sites compile and look right; tests pin the record shape.

**Tasks**
- [ ] designer: measure and pick the six records; write the anatomy spec (M)
- [ ] frontend-engineer: `CategoryStyle`, rewire call sites (M)
- [ ] qa-engineer: tests that every record meets the floors (S)
- [ ] architect: confirm `CategoryStyle` is the right seam against ADR 005's `ResolvedCategory` (S)

**Collision with #1 phase 3:** this story **is** the designer deliverable for task 3.3 ("designer supplies measured light/dark pairs"), extended with `fill` and `border`. Record the pairs in the form 3.3 needs and tell #1 that the palette slots 7 to 12 are still to be measured there. `CategoryPalette` itself, `paletteIndex`, and the pure `Catalog/` code stay in #1. Land this story before 3.7.

### Story 3: Timeline visual hierarchy

As the owner, I want blocks, meetings and free time to look clearly different at a glance in light and dark, so that I can read my day without studying it.

**Acceptance**
- [ ] Blocks use opaque fills; no hour rule shows through a block (M9).
- [ ] Meetings are neutral with a dashed edge and are visibly quieter than blocks in both modes (M10).
- [ ] Out-of-window shading dims in dark mode (black alpha) and gridlines are scheme-aware (M10).
- [ ] In-window versus out-of-window canvas is distinguishable; hour labels use `.secondary`.
- [ ] Chip titles are `.subheadline.weight(.semibold)` for blocks and meetings (S6); `titleOnly` density still fits a 15 min block.
- [ ] Now-line carries a time pill in the gutter (P3). Abutting chips do not double their borders (P4). The resize handle sits at the bottom-right and only on a selected or long-pressed block (P2).
- [ ] "Tap to place" text meets 4.5:1 on the armed fill, in both modes.
- [ ] Before/after screenshots in both modes at default and `accessibility1` size are attached; the owner confirms on device.

**Tasks**
- [ ] designer: timeline spec with annotated screenshots of the five states (empty day, meetings only, planned day, armed, drag) (M)
- [ ] frontend-engineer: `TimelineCanvas` surfaces, chips, now-line, grabber (L)
- [ ] qa-engineer: state matrix at default and large sizes, light and dark, plus 15 min block clipping (M)
- [ ] designer: review against the spec (S)

**Collision with #1 phase 3:** edits `BlockChip` and `CategoryGlyph`, which 3.7 also touches. Consume `CategoryStyle` only, so 3.7 does not conflict.

### Story 4: Timeline accessibility and Dynamic Type

As the owner, I want the timeline to stay usable with larger text and with VoiceOver, so that it never clips or hides a meeting.

**Acceptance**
- [ ] `hourHeight` and `gutterWidth` use `@ScaledMetric`; at the largest sizes the gutter hour label does not truncate.
- [ ] The decision to cap canvas text at `accessibility1` is written in a code comment and the design token table.
- [ ] Each block exposes actions: move 15 minutes earlier or later, longer or shorter, with spoken results (S2).
- [ ] Labels read like "Standup, meeting, 9:30 to 10 AM, not movable" and "Deep work block, 2 to 3 PM".
- [ ] Resize handle hit area is at least 44x44 without covering short blocks; short blocks get no resize gesture (S3).
- [ ] Reading order matches the day.
- [ ] VoiceOver walkthrough of Today (header, a meeting, a block, a free slot, inbox, plan sheet) is recorded as passing.

**Tasks**
- [ ] designer: VoiceOver reading script and labels (S)
- [ ] frontend-engineer: `ScaledMetric`, actions, handle hit area (L)
- [ ] qa-engineer: Dynamic Type matrix to AX5, VoiceOver pass on device (M)

**Collision with #1 phase 3:** labels use `CategoryStyle.title` so custom names read correctly.

### Story 5: Timeline touch and flow

As the owner, I want to move between days and create or resize a block by touching the timeline, so that small plan changes cost one or two gestures.

**Acceptance**
- [ ] Horizontal swipe on the timeline changes day; it does not fight vertical scroll or block drag (S3).
- [ ] The timeline scrolls to now on appear and on date change only, never when `visible` changes at the hour (S11).
- [ ] Long-press on empty space creates a 30 min block at the snapped time and opens the detail sheet; it never lands on a fixed event or in the past on today (S12, "fixed events win").
- [ ] Changing a block's length takes at most two taps from the detail sheet, for example preset chips 15 / 30 / 45 / 60 / 90 beside the stepper (S10).
- [ ] Haptics on place, Add my Workday, Place all and drag snap, off under the system setting (P9).
- [ ] Reduce Motion respected.

**Tasks**
- [ ] designer: gesture map (swipe, long-press empty, long-press block, tap) and conflicts (S)
- [ ] frontend-engineer: gestures, scroll rule, duration presets, haptics (L)
- [ ] qa-engineer: gesture conflict matrix, create-over-meeting case, DST day, VoiceOver alternative for create (M)

**Collision with #1 phase 3:** the detail sheet's category picker is replaced in 3.7; keep the duration change in its own `Section`.

### Story 6: Today chrome, banner and empty states

As the owner, I want the Today screen to feel designed and calm, so that the two-minute morning pass starts from a screen that tells me what to do.

**Acceptance**
- [ ] Header, action area and banner use the Story 1 tokens; one 16pt page margin (S7).
- [ ] The toolbar bar and the day header are merged or reduced so the timeline gains the ~44pt back (S14 residual).
- [ ] Streak label, summary line and day title have a defined hierarchy that survives `accessibility3`.
- [ ] Empty-day card, starter card, armed bar and banner are restyled; the empty card copy is unchanged unless Story 8 changes it.
- [ ] After "Add my Workday" with tasks waiting, the inbox opens at the armed detent (decision Q7).
- [ ] Every state in `docs/ui-spec-issue-3.md` section 6 still behaves as specified (regression matrix).

**Tasks**
- [ ] designer: Today layout spec and the state matrix (default, empty, meetings only, armed, armed with no gap, banner with Undo, banner warning, streak states) (M)
- [ ] frontend-engineer: restyle `dayHeader`, `actionArea`, `emptyDayCard`, `PlanBannerView` (L)
- [ ] qa-engineer: regression of the sprint 1 flows (plan sheet, Undo, Place all, streak) (M)

**Collision with #1 phase 3:** none directly; the new-category chip in the composer (3.8) is in the inbox, Story 7.

### Story 7: Sheets and Settings restyle

As the owner, I want the inbox, plan sheet, block detail, templates and settings to share the Today look, so that the app reads as one product.

**Acceptance**
- [ ] Category chips in the composer use fill, border and glyph, with `.primary` text, never a tint as text (S4).
- [ ] The plan sheet, block detail, Templates and Settings use the type and spacing scales; no `.caption` for instruction text.
- [ ] Weekday assignment rows show the standard picker chevron (P8). `15.0h` becomes `15h` (P1).
- [ ] Copy changes: "Alert at block start" to "Remind me about blocks" (P10); "Restore from a backup" to "Replace tasks & templates..." (M6 label); empty inbox body is `.footnote` and reads "Type what needs doing above, then tap it to drop it on the day."
- [ ] Block detail title is the block's own title, not "Block".
- [ ] Contrast of every sheet text pair is at least 4.5:1 in both modes.

**Tasks**
- [ ] designer: per-sheet restyle notes and copy table (M)
- [ ] frontend-engineer: `InboxTray`, `PlanSheet`, `BlockDetailSheet`, `TemplatesView`, `SettingsView` (L)
- [ ] qa-engineer: light/dark/AX3 pass on each sheet; confirm restore and plan-sheet behaviour unchanged (M)

**Collision with #1 phase 3:** **highest overlap.** 3.7 replaces the pickers in `InboxTray`, `BlockDetailSheet` and `TemplateRowEditor`, and 3.8 adds a Settings category editor and a composer category chip. Sequence: this story's category-chip restyle ships first, on `CategoryStyle`; 3.7 and 3.8 then swap the data source. If both are in flight, the later one rebases and the owner is told.

### Story 8: Permission, setup and error states

As the owner, I want the screens I meet when something is not working to say what happened and what to do, so that a setup problem never looks like a bug.

**Acceptance**
- [ ] Permission prompt has three states: asking, off, and write-only ("Blockey can save blocks but can't see your meetings. In Settings, switch Calendars from Add Only to Full Access."). `CalendarService` reports write-only separately (S15).
- [ ] Copy names the real Settings path the button opens; the asking copy says what the owner gets (S15b, S15c).
- [ ] `noCalendarAvailable` shows an alert with an **Open Settings** button, not a banner (M5).
- [ ] Warnings are tap-to-dismiss with no timer (decision Q4).
- [ ] Access granted but no calendar enabled shows its own empty state (M8d).
- [ ] An inverted planning window is prevented in Settings, or shown as "Your day ends before it starts. Check the planning window in Settings." (P11).
- [ ] Starter templates seed before the first frame so "Set up a template" never flashes (P5).

**Tasks**
- [ ] designer: copy and layout for the five states (S)
- [ ] architect: write-only access state, and `DaySchedule.window` clamp location (S)
- [ ] frontend-engineer: `RootView`, banner stickiness, alert, seeding in `BlockeyApp` (M)
- [ ] qa-engineer: tests for the access mapping and window clamp; simulator states by seeding only. Never touch the real Calendar. (M)

**Collision with #1 phase 3:** none.

### Story 9: Task and template upkeep

As the owner, I want to edit a task and save a good day as a template, so that I stop retyping.

**Acceptance**
- [ ] Tapping a task's duration or a long-press opens a small editor for title, length and category (P6).
- [ ] "Save today as a template" in the `...` menu creates a template from the day's own blocks, names it, and refuses to include meetings (P7).
- [ ] Marking a task done is **out of this story**; it needs the ADR in Q8.
- [ ] Undo or a confirmation covers any destructive path.

**Tasks**
- [ ] designer: editor and save-as-template flow with copy (M)
- [ ] architect: confirm template creation goes through `Planning/` and `BlockWriting`; draft the completion ADR (M)
- [ ] frontend-engineer: editor, menu item (L)
- [ ] qa-engineer: tests for template-from-day (drops meetings, keeps order, handles overlaps) (M)

**Collision with #1 phase 3:** the editor's category picker and the saved template rows both use slugs. Use `CategoryStyle` and write slugs verbatim, as phase 1 already requires.

---

## 4. Risks

- **Screenshots lie about emoji.** The simulator draws tofu, so glyph and chip sign-off needs the owner on a device. Chips already fall back to symbols (`Views/Emoji.swift`); design for both.
- **Two stories on the same files.** Stories 3 and 7 against #1 phase 3. Mitigated by the `CategoryStyle` seam and the sequencing above.
- **Gesture conflicts.** Swipe-for-day, long-press-to-create and long-press-to-move share one ScrollView. Story 5 starts with a conflict matrix.
- **Colour measured, not eyeballed.** Story 2 measures; the repo already has a test habit for that. Do not ship palette changes unmeasured.
- **Scope creep into gaps 1 to 5.** Listed as out of scope in section 1.

---

## 5. Open questions for the owner

Each has a recommendation; if you say nothing, the epic proceeds on them.

- **Q1. Dark mode as a first-class design?** Recommendation: yes, designed and tested alongside light in every story; follow the system setting, no in-app toggle.
- **Q2. Chrome accent: keep default blue, or go monochrome ink?** Recommendation: ink (near-black in light, near-white in dark) for buttons and armed states, so category colours are the only colour on screen. Cost: less obvious tappable text, offset by filled buttons and symbols. This is the single biggest "not generic" lever.
- **Q3. Rounded type for the day title and times?** Recommendation: yes, those two places only (`.fontDesign(.rounded)`). Everything else stays standard SF.
- **Q4. Warnings sticky (tap to dismiss) for everyone?** Recommendation: yes. Sprint 1 chose 7 s (ui-spec-issue-3 Q10); an error you can lose before reading is still a problem, and success banners keep their timers.
- **Q5. Emoji or symbol on timeline chips?** Recommendation: keep the emoji (your earlier decision, ADR 005 requires it) with the symbol fallback, and you sign off Story 3 from a device screenshot, since the simulator cannot show it.
- **Q6. Fold CLAUDE.md gaps 3 and 4 (multi-day timed events, subscribed calendars counting as busy) into this epic?** They make a day look fully booked or free wrongly, which undercuts the timeline refresh. Recommendation: no, a separate small scheduling story (architect-led, `Scheduling/` with tests) right after Story 3, since neither is a visual problem.
- **Q7. Open the inbox automatically after "Add my Workday" when tasks are waiting?** Recommendation: yes, at the armed detent, one fewer tap. The review suggested it; sprint 1 did not do it.
- **Q8. Task completion (gap 2, P6) belongs in this epic?** Recommendation: no. It needs an ADR (where does "done" live, how does rollover work, what does Calendar show), and gap 1 interacts with it. Story 9 does edit only and the architect drafts the ADR.
- **Q9. Order against #1 phase 3?** Recommendation: Stories 1 and 2 first (they feed 3.3), then #1 tasks 3.1 to 3.6 can run in parallel with Story 3, and 3.7 and 3.8 after Stories 3 and 7. If phase 3 is still gated on the Thai slug experiment (task 0.3, the probe just landed), nothing here waits on it.
- **Q10. App icon?** Recommendation: leave it for a later, separate pass. It does not affect the readability complaints, and a free-account weekly reinstall makes icon churn cheap to defer.
