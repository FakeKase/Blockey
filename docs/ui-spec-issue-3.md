# UI spec: issue #3, tasks 2.3 to 2.7

Date: 2026-11-03
Author: `designer` agent (read-only spec, no code)
Status: **DRAFT.** Open questions Q1 to Q11 (section 7) need the owner's answers before the build.
Builds on: `docs/feedback-plan-2026-11.md` §3.1 and §7, ADR 007, and the logic already built in
tasks 2.0 to 2.2 (`DayPlanner`, `StampPreview`, `UndoRecord`, `UndoOutcome`).

The designer had no shell access, so this was written from the source and the plan, not from the
issue comments. Skim `gh issue view 3 --comments` for any changes before building.

---

## 0. Shared decisions

- **0.1 Day phrase.** Add a pure, tested `StampPreview.dayPhrase(for:now:calendar:)` that returns
  "today", "tomorrow" or the weekday name. Always use it after "for" or in "Plan ...":
  "Plan today", "Add 4 blocks for Monday", "Place all 4 for Thursday". This avoids "to today" and
  "on today", which read badly (Q8).
- **0.2 Symbols only.** Every status mark in the banner, card and sheet is an SF Symbol. Nothing
  depends on judging emoji from a simulator screenshot.
- **0.3 Warning style.** Warnings get an orange `exclamationmark.triangle.fill` symbol with
  `.primary` text. Successes get `checkmark.circle.fill`. No orange text, because it fails
  contrast (design review M5/S4), and colour is never the only signal.
- **0.4 Safe first.** The restamp `confirmationDialog` is deleted. The safe-first rule now lives in
  the Keep / Start over control, where Keep is first and is the default every time the sheet opens.

## 1. Task 2.3: copy pass

"Stamp" must not appear in any UI string. Identifiers may keep the name. Update the code comments
that quote UI text (`TemplatesView.swift:7-8`, `TodayView.swift:5`, `StarterData.swift:6`).

| # | Where | Now | Should say |
|---|---|---|---|
| 1 | `TodayView.defaultBar` | `Stamp “Workday”` | `Add my Workday` (`lineLimit(1)`, `minimumScaleFactor(0.8)`). With no template: `Set up a template`, unchanged |
| 2 | `summaryLine`, when meetings are in | `…Stamp “Workday” to fill the rest.` | `Your meetings are in. Add your Workday to fill the rest.` |
| 3 | `emptyDayCard` body | `Stamp “Workday” to lay down your usual day…` | `Add your Workday for a ready-made day, then drop anything else into the gaps.` |
| 4 | `emptyDayCard`, new | none | `See what’s in Workday` (bordered, small). Opens Templates. Hit testing must be enabled in this case |
| 5 | Restamp dialog and its state | dialog | Delete it, replaced by the preview sheet (2.4) |
| 6 | `untaggedLossSentence` | `…cannot be returned — this deletes it for good.` | `One block has lost its Blockey tag, so it cannot be returned to the inbox. It will be deleted for good.` (plural form likewise). Count only `isEditable && token == nil` |
| 7 | `StampResult.message` | `Stamped 5 blocks · …` | Becomes `message(day:)`. Strings are in 3.5 |
| 8 | `FillResult.message` | `Placed 3 tasks`, etc. | Keep as is |
| 9 | InboxTray toolbar `Fill day` | toolbar button | Remove it (see 2.6) |
| 10 | InboxTray row note | `· didn’t fit` | `· from Workday, no room` (Q1). Fallback: `· from your template, no room`. Add an `exclamationmark.circle` symbol |
| 11 | TemplatesView "Templates" footer | none | `Workday and Weekend are examples. Edit them or make your own.` Shown while either one exists |
| 12 | `TemplateEditor` footer | `When you stamp this template…` | `When you add this template to a day, anything that clashes with a meeting moves to the next free slot. If nothing fits, it goes to your inbox instead of being dropped.` |
| 13 | SettingsView | none | The `Skip preview` toggle (2.4.7) |

Out of scope: the `Nothing blocked · 15.0h free` wording.

## 2. Task 2.4: the preview sheet "Plan <day>"

### 2.4.1 Flow

1. The user taps `Add my Workday`.
2. If **Skip preview** is on, the day has no own editable blocks, and `confirmCount > 0`, write
   straight away with `stamp(expecting:mode: .keep)`. If that returns `.stale`, open the sheet with
   the fresh plan instead. In every other case, open the sheet.
3. Confirm. `.written` dismisses the sheet and shows the Undo banner. `.stale(fresh)` keeps the sheet
   open, updates it in place with a note, writes nothing, and waits for a second confirm.

The blank-day morning pass is 2 taps, or 1 with Skip preview on. Add `case plan` to `TodayView.Sheet`.
Changing the mode recomputes with `planner.preview(...)`, which is pure and synchronous.

### 2.4.2 Layout

```
| Cancel            Plan Monday                |
| Your Workday template. Meetings stay where   |
| they are.                                    |
| ON YOUR DAY                                  |
| (clock) Deep work        9:00 AM to 11:00 AM |
| (shift) Admin & email   11:45 AM to 12:30 PM |
|         moved from 11:30 AM                  |
| GOES TO YOUR INBOX                           |
| (tray)  Lunch            no room today       |
|----------------------------------------------|
| 3 blocks · 1 moved to fit · 1 to your inbox  |
| [      Add 3 blocks for Monday           ]   |
```

- **Title:** `Plan \(dayPhrase)`, inline, with the heading trait.
- **Subtitle:** `Your \(name) template. Meetings stay where they are.`
- **The list:** an inset-grouped `List` of non-tappable rows. Each row is a VStack (title, time,
  optional note), so it wraps at large type.
- **Row symbols:** `clock` for placed, `clock.arrow.circlepath` for moved, `tray` for the inbox.
- **Sections:** "On your day" is sorted by start time. "Goes to your inbox" is in template order.
  Empty sections are omitted. Times use `.formatted(date: .omitted, time: .shortened)`.
- **Notes** come from `Row.noteText` and are not reworded in the view.
- **Zero-length rows:** `1 row has no length and was skipped.`
- **Buttons:** Cancel goes in the leading toolbar slot. Confirm is pinned at the bottom in a
  `safeAreaInset` with a `.bar` background.

### 2.4.3 Footer and confirm states

| State | Footer | Button |
|---|---|---|
| Keep | count line | `Add 3 blocks for Monday` (singular `Add 1 block…`) |
| Start over | count line | `Delete 3 and add 5 blocks`, red tint |
| Nothing fits | Today: `Your day is full from now on. Try tomorrow.` Other day: `Your meetings fill this day. Nothing fits.` | Disabled `Nothing fits`. Today also gets a `Try tomorrow` text button |
| Empty template | none | Empty state `This template is empty` / `Add a few rows to \(name), then come back.` and an `Edit \(name)` button |
| Writing | unchanged | Disabled until the call returns |
| Error (the clear failed) | unchanged | Inline warning `Couldn’t clear Monday. Nothing was changed. Try again.` |

There is no loading state and no spinner.

### 2.4.4 Keep / Start over

- **When it shows:** only when the day has own editable blocks.
- **Control:** a segmented picker, `Keep my 3 blocks` (the default, counting all own blocks) /
  `Start over`. At accessibility text sizes it becomes `.inline`.
- **Accessibility label:** `What to do with the blocks already on Monday`.
- **When Start over is selected**, a warning footnote appears:
  - `Deletes 3 blocks on Monday, including any you placed by hand. Blocks that came from your inbox go back to your inbox. Your meetings are not touched.`
  - The untagged-loss sentence, when it applies.
  - When `kept > 0`: `2 repeating or multi-day blocks stay where they are.` `kept` is computed in
    the view from `contents` (`!isEditable`) before the clear.
- **No second dialog.** The red button and Undo are the confirmation.

### 2.4.5 Stale

When confirm returns `.stale(fresh)`:
- Swap in the fresh plan with animation, keeping the mode.
- Show the note `Your day changed, here’s the new plan.` (`arrow.triangle.2.circlepath`, material
  background). It stays until the user confirms, switches mode, or dismisses.
- Post a VoiceOver announcement and move focus to the note.
- Never auto-confirm.

While the sheet is open, it also recomputes (without writing) on `calendars.revision` and on the 30 s
tick (Q5).

### 2.4.6 Detents and accessibility

- **Detents:** `[.medium, .large]`. It opens at `.large` if there are more than 6 rows or at
  accessibility text sizes. Interactive dismissal is never blocked.
- **VoiceOver:**
  - Row labels like `Admin and email, 11:45 AM to 12:30 PM, moved from 11:30 AM`.
  - Headings get the heading trait.
  - The disabled confirm button has the hint `Nothing fits. Try another day.`

### 2.4.7 Skip preview

- **Where:** SettingsView, a new section between Snap and Alerts.
- **Toggle:** `Skip preview`.
- **Footer:** `Add your template with one tap, without checking the plan first. You can undo it. Days that already have blocks always show the preview.`
- **Storage:** `SettingsKey.skipPlanPreview = "skipPlanPreview"`, default false.
- **It never skips** when the day has own blocks, when nothing fits, or when the result is stale.
- **Backup:** it is not backed up (gap 6). Losing it resets it to off, which is the safe direction.

## 3. Task 2.5: the Undo banner

- **Model:** `Banner` gains `undo: UndoRecord?` (only when `hasEffect`) and `action: BannerAction?`
  (`.openInbox`). The record lives only on the banner, so replacing the banner drops it.
- **When Undo appears:** after Add template (Keep or Start over) and after Fill day. Not after a single
  place, a return to inbox, a clear, an edit, or an undo.
- **How long it stays:**
  - success with Undo: 6 s
  - success without Undo: 2.6 s
  - success after an undo: 4 s
  - any warning: 7 s
  - **while VoiceOver is running:** no timer, and a visible 44 pt `xmark` plus Dismiss and escape actions
- **Timer pauses:** the timer pauses while a sheet other than the inbox, or a block sheet, is open.
  The banner is shown after the preview sheet has finished dismissing. Every banner is announced.
- **Layout:**
  - The `Undo` button is trailing (subheadline, semibold), with a minimum size of 44 x 44 pt. At
    accessibility text sizes it moves to its own line.
  - Children are contained, so Undo is its own VoiceOver element. Its hints are `Reverses what was
    just added` / `Puts the tasks back in your inbox` / `Brings back the blocks you started over`.
- **Strings:**
  - `Added 5 blocks for Monday`, and `· 2 moved to fit` when every row fits.
  - One miss: `Added 4 blocks. “Lunch” is in your inbox.` This is a warning, and tapping it opens the
    inbox (shown with a chevron).
  - Several misses: `Added 3 blocks. 2 didn’t fit and are in your inbox.`
  - Write failures: append `1 couldn’t be saved to your calendar and is in your inbox.`
  - Untagged losses: append `1 block could not be returned and was deleted.`
  - Fill day keeps its current strings.
- **After Undo:** show `UndoOutcome.message` as it is today, with warning style following `isWarning`.
  If undo throws, show `Couldn’t undo. Nothing was changed. Try again.` and **keep the same record**
  so it can be retried.
- **Replacement:** any new banner drops the record. Moving to another day keeps the banner, and Undo
  acts on `UndoRecord.day`.

## 4. Task 2.6: Fill day

- Remove the toolbar's leading `Fill day` button. The tray no longer dismisses after filling.
- Add a full-width bottom button, `Place all 4 for today` (or `for Thursday`; singular
  `Place 1 for today`), shown only when there are tasks and the tray is not at the armed detent.
- When disabled, show the reason underneath: `Nothing fits in the time you have left.` (today) or
  `Nothing fits on Thursday.` Whether anything fits is computed in TodayView.
- **The banner inside the tray (Q6):** extract `PlanBannerView` and render it in the tray above the
  button, so Fill day's Undo stays visible while the sheet covers Today. TodayView hides its own copy
  while the inbox is open, so VoiceOver never finds two Undo buttons.

## 5. Task 2.7: the first-launch card

- **Text:** the heading `We added a sample Workday for Mon–Fri.` and the body `Add it to a day with
  one tap. Change it any time.`
- **Buttons:** `Keep` and `Edit`, both bordered, each at least 44 pt tall.
- **Container:** material background, 14 pt corners.
- **Where:** first in `TodayView.actionArea`, within thumb reach.
- **When it shows:** templates were seeded, the note hasn't been seen, Workday still exists, and no task is armed.
- **Keep** sets the flag. **Edit** sets the flag and opens the Templates list (Q4).
- **Persistence:** `SettingsKey.hasSeenStarterTemplatesNote`, which is never reset. It is not backed
  up (gap 6), so a delete and reinstall shows the card again. That is harmless; say so in the commit.

## 6. State matrix for QA

- **Sheet:**
  - Keep
  - Start over
  - Nothing fits, today and another day
  - Empty template
  - Stale note
  - Write error
  - The zero-length footer
- **Banner:**
  - Success with Undo
  - Warning with Undo and the inbox action
  - After an undo, success and warning
  - Undo failed, with retry
  - Sticky under VoiceOver
- **Inbox:**
  - Place all, enabled and disabled
  - Empty
  - At the armed detent

Test the stale case on the simulator by seeding a meeting while the sheet is open. Never use the real
Calendar.

## 7. Open questions, with the designer's recommendations

**Status (2026-11-03):** the owner said to continue without answering individually, so the lead
adopted every recommendation below as a provisional decision. Any of them can be reversed later.

- **Q1.** The inbox note needs the template's name, and `TaskItem` only stores a Bool. Add an optional
  `droppedFromTemplateName: String?` (with an optional Backup field), falling back to "your template".
  **Recommend: add it.**
- **Q2.** Skip preview on days that already have blocks? **Recommend: no.**
- **Q3.** Show the first-launch card on the owner's existing install? **Recommend: yes, once.**
- **Q4.** Should Edit open the Templates list or the Workday editor? **Recommend: the list for now.**
- **Q5.** Live-refresh the open preview on calendar changes and the 30 s tick? **Recommend: yes.** It
  can be dropped; the confirm-time guard is the real protection.
- **Q6.** Host the banner inside the inbox tray? **Recommend: yes.** Without it, Fill day's Undo is
  hidden under the sheet.
- **Q7.** Pause the banner timer while non-inbox sheets are open? **Recommend: yes.**
- **Q8.** Say "for today / for Monday" instead of the plan's "to Monday"? **Recommend: "for".**
- **Q9.** Keep counts all own blocks while the Start over button counts only deletions, with the
  `kept` line explaining the difference. **Recommend: as specified.**
- **Q10.** Make warnings sticky for everyone (design review M5)? **Recommend: no.** Keep 7 s, and
  leave it to an M5 follow-up.
- **Q11.** Changing `StampResult.message` to `message(day:)` breaks tests that check the old strings.
  **Recommend: update them in the same commit, and add string tests.**

**Files the engineer will touch:**
- `Views/TodayView.swift`, `InboxTray.swift`, `SettingsView.swift`, `TemplatesView.swift`
- `BlockeyApp.swift` (two `SettingsKey` entries)
- `Planning/DayPlanner.swift` and `Scheduling/StampPreview.swift`
- a new sheet view and `PlanBannerView`

Never edit `project.pbxproj`.
