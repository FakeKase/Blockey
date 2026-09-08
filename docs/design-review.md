# Blockey — design review

Date: 2026-09-07
Reviewed: `/tmp/blockey-01.png` (first run), `/tmp/blockey-07.png` (populated Today),
`/tmp/blockey-04.png` (Templates), and `Blockey/Views/*`, `Blockey/Models/BlockCategory.swift`,
`Blockey/Scheduling/*`, `Blockey/Calendar/CalendarService.swift`, `Blockey/Models/Backup.swift`.

The bet in the plan is sound and the screen mostly delivers it: one day, meetings you can't move,
blocks you can, two actions at the bottom. The stamped day in `blockey-07.png` reads as a real plan.
Almost everything below is about the two minutes around that screen — the taps to get there, what
happens when it goes wrong, and what the screen looks like before it has anything on it.

Findings are graded for *this* app: one user, sideloaded, a two-minute morning pass.
**Must-fix** means it will bite on a real morning or lose data. **Should-fix** means it costs taps,
clarity or legibility. **Polish** is everything else.

---

## Priority index

**Must-fix**

| | Finding | Where |
|---|---|---|
| M1 | Arming a task dismisses the inbox — 2 wasted taps and 4 extra sheet animations per morning | `TodayView.onArm` |
| M2 | Tap-to-place offers gaps that have already passed; Fill day doesn't. Same app, two rules | `TodayView.candidateGaps` |
| M3 | No undo and no "clear this day" — unstamping costs 10+ taps | `TodayView` |
| M4 | The restamp dialog's message describes the button the user *didn't* press, and says "Today" on any date | `TodayView.confirmationDialog` |
| M5 | Errors are 2.6-second capsules at 2.08:1 contrast, and a success banner overwrites them | `TodayView.bannerView`, `fillDay`, `applyTemplate` |
| M6 | "Restore from a backup" deletes every task and template with no warning and no confirmation | `SettingsView.importBackup`, `Backup.restore` |
| M7 | The bottom bar floats over live timeline content with no scrim — a meeting title is unreadable in the shipped screenshot | `TodayView.bottomBar` |
| M8 | The first-run screen is a blank ruler that says nothing | `blockey-01.png` |
| M9 | Admin blocks are visually indistinguishable from meetings (ΔE 3.4) | `BlockCategory.admin`, `BlockChip` |
| M10 | Dark mode: block fills land at 1.17–1.27:1 and meetings end up *more* prominent than your own blocks | `BlockChip`, `FixedEventChip` |

**Should-fix**

S1 Dynamic Type breaks the timeline · S2 VoiceOver: meetings are invisible, tap-to-place is unusable ·
S3 Tap targets: day chevrons ~20pt, resize grabber 23pt tall · S4 Category tints as text fail contrast in
both modes · S5 "free" hours count time that has already passed · S6 Type scale: 8 of 11 iOS styles,
1pt doing semantic work · S7 Spacing and left edges: three different page margins on one screen ·
S8 "Apply template" doesn't apply a template · S9 "Fill day" sits in the Cancel slot · S10 Changing a
block from 30 to 90 min is 12 taps · S11 Auto-scroll yanks the timeline back to now once an hour ·
S12 No way to create a block by touching the timeline · S13 The inbox pill shows "0" next to a "full
tray" icon · S14 Nav title duplicates the day header · S15 Permission copy misses the write-only case
and points at the wrong Settings path

**Polish**

P1 `15.0h` · P2 The resize grabber reads as a stray mark · P3 The now-line has no time · P4 Abutting
chips double their borders · P5 First-run flash of "Apply template" · P6 Tasks can't be edited or
completed · P7 No "save today as a template" · P8 Weekday menus have no disclosure affordance ·
P9 No haptics (plan phase 5) · P10 Alert toggle label contradicts its own stepper · P11 An inverted
day window silently produces a day with no free time

---

## 1. The morning pass

### The count, as built

Cold launch on a Monday. Access granted, meetings present, "Workday" assigned, four tasks in the
inbox. The user stamps and places three tasks.

| # | Tap | Result |
|---|---|---|
| 1 | Stamp "Workday" | 5 blocks appear |
| 2 | Inbox pill | Sheet up (medium) |
| 3 | Task | Sheet **dismisses**, task armed |
| 4 | Gap | Placed |
| 5 | Inbox pill | Sheet up again |
| 6 | Task | Sheet dismisses |
| 7 | Gap | Placed |
| 8 | Inbox pill | Sheet up again |
| 9 | Task | Sheet dismisses |
| 10 | Gap | Placed |

**10 taps and 6 sheet transitions.** The tap count is defensible. The transitions are not — four of
them are pure overhead, and each one is a ~0.4s animation that also re-scrolls nothing but re-lays
out the whole timeline behind a moving sheet.

### M1 — Arming a task should not close the inbox · Must-fix

`TodayView` already sets `.presentationBackgroundInteraction(.enabled(upThrough: .medium))`, which
exists precisely so the user can touch the timeline while the sheet is up. Then `onArm` throws it
away with `sheet = nil`.

Keep the sheet. On arm, drop it to a short detent so the day is visible:

```
.presentationDetents([.height(120), .medium, .large], selection: $inboxDetent)
```

`onArm` sets `inboxDetent = .height(120)` instead of `sheet = nil`. The armed banner already exists —
render it inside the tray at the short detent rather than in the bottom bar, so there is one
armed-state surface, not two.

New count: **1 (stamp) + 1 (open inbox) + 6 (three × task, gap) = 8 taps, 1 transition.**

If the stamp also opened the inbox automatically — the stamp is finished, the remaining work is
the inbox, that is genuinely the next step — it is **7 taps and 1 transition**. I would do that too:
it is the "reduce the number of decisions" rule applied to the one flow the app exists for.

### M2 — Tap-to-place offers gaps in the past · Must-fix

`fillDay` passes `notBefore: isToday ? now : nil` and is careful not to schedule into hours that have
gone. `candidateGaps` does not:

```swift
private var candidateGaps: [TimeRange] {
    guard let armedTask else { return [] }
    return DaySchedule.gaps(busy: contents.busy,
                            within: window,          // <- no notBefore
                            minimumDuration: armedTask.duration)
}
```

In `blockey-07.png` the demo clock is 10:15 and the 07:00–09:30 stretch is free. Arm a task there and
the app lights that stretch up as a valid slot with "Tap to place" on it. Two rules for the same
question in the same screen, and one of them creates a block in the past.

Fix: clamp `window` to `max(window.start, now)` when `isToday`, for `candidateGaps` and for the
summary line (S5). The past should still be *drawn* — it's the day — but it should not be offered.

### M3 — There is no undo and no way to clear a day · Must-fix

`CalendarService.deleteAllBlocks(on:)` exists, but the only path to it is "Replace them" inside the
restamp dialog. If a stamp lands wrong — the wrong template, the wrong day, a meeting you forgot to
accept — the recovery is: tap block, "Delete block", repeat. Five blocks is ten taps, and one of them
is a destructive button with no confirmation.

Two additions, both cheap:

1. An **Undo** affordance on the stamp banner, live for its 2.6 seconds. The stamper already knows
   exactly which events it created.
2. **"Clear this day"** in the `⋯` menu, destructive, with a confirmation that names the count:

   > **Delete 5 blocks from Monday, 7 September?**
   > Your meetings aren't touched. This also removes them from Calendar.
   > `Delete 5 blocks` · `Cancel`

### S8 — "Apply template" does not apply a template · Should-fix

```swift
Label(templateForToday.map { "Stamp “\($0.name)”" } ?? "Apply template", ...)
```

With no template assigned, that button opens the Templates sheet. The label promises the outcome and
delivers a settings screen. Then the user must open a weekday menu, pick, tap Done, and tap the
button again — four extra taps behind a label that said one.

> Replacement: **`Set up a template`**

### S9 — "Fill day" is in the Cancel slot · Should-fix

```swift
ToolbarItem(placement: .topBarLeading) { Button("Fill day") { onFillDay(); dismiss() } }
```

`topBarLeading` on a sheet is where Cancel lives. This is a one-tap, unconfirmed, multi-event write
sitting exactly where the platform has trained the user to tap to back out. It is the fastest
possible way to plan a day (3 taps total) and it is hidden in the most dangerous place on the screen.

Move it to a prominent button below the list, labelled with what it will do:

> **`Fill the day with 4 tasks`**

and when it can't, the disabled state should say why rather than just greying out (see M5 copy).

### S12 — You cannot create a block by touching the timeline · Should-fix

Build order phase 2 called for "create by dragging on empty space". There is no gesture on empty
canvas in `TimelineCanvas` — `gapLayer` only exists while a task is armed. So "block 2–4pm right now"
costs: open inbox, type a title, tap a duration chip, tap add, tap the task, tap the gap. Six-plus
taps and a keyboard, for the single most obvious gesture on a day timeline.

A long-press on empty space that creates a 30-minute block at the snapped time and opens the detail
sheet for the title would cover it, and reuses `date(atY:)` and `DaySchedule.snap` which already exist.

### S11 — The timeline scrolls itself back to now, once an hour · Should-fix

```swift
.onChange(of: visible) { _, _ in scrollToNow(proxy, animated: true) }
```

`visibleRange` extends to `now + 1800`, ceiled to the hour. So `visible` changes on every hour
boundary, and when it does the canvas animates back to the current hour under the user's finger. If
they are looking at 4pm at 10:59, they are looking at 11am at 11:00.

Auto-scroll on appear and on date change. Not on `visible`.

---

## 2. Empty and error states

### M8 — The first-run screen · Must-fix

`blockey-01.png` is fifteen hours of ruled lines, a header reading "Nothing blocked · 15.0h free",
and two floating buttons. There is nothing that says what the app does, what "stamp" means, or what
the "0" pill is. `StarterData` has already seeded "Workday" and wired it to Monday–Friday — the app
knows the user is one tap from a planned day and doesn't say so.

Three distinct states here, and they want different treatments.

**(a) No meetings, no blocks, template assigned** — the true first run. A card centred in the
timeline area, not a takeover; the ruler behind it is doing useful work.

> **Nothing planned yet**
> Stamp "Workday" to lay down your usual day, then drop anything else into the gaps.

**(b) Meetings, no blocks** — do not show a takeover. The meetings *are* the content, and the point of
the screen is that they define where you can't plan. A single line under the last meeting is enough:

> Your meetings are in. Stamp "Workday" to fill the rest.

**(c) No template assigned** — point at the missing thing, with the action inline:

> **No template for Mondays yet**
> A template is your usual day. Set one up and every Monday takes one tap.
> `Set up a template`

**(d) Access granted, no calendars enabled** — currently produces (a) with no explanation, and the
first write throws `noCalendarAvailable` into a 2.6s capsule. Worth its own state.

### The inbox empty state — keep it, tighten it

Current copy is already good:

> **Inbox is empty**
> Add what needs doing, then tap it to drop it on the day.

Two notes. The body is `.caption` (12pt) — the smallest type in the app is carrying the only
instruction a new user gets; make it `.footnote`. And the composer sits directly above, so point at
it: **"Type what needs doing above, then tap it to drop it on the day."**

### The armed-but-nothing-fits state — a dead end

```swift
Text(candidateGaps.isEmpty ? "No gap is long enough today" : "...")
```

The only control on that bar is **Cancel**. The app has told the user the day is full and offered them
nothing but retreat. It also knows exactly *how* short the day is.

> **`Nowhere to put "Write the launch post"`**
> `The longest free stretch today is 45 min.`
> `Try tomorrow` · `Cancel`

"Try tomorrow" advances `selectedDate` and keeps the task armed — it's one line and it turns a dead
end into a decision.

### M5 — Errors are ephemeral, low-contrast, and get overwritten · Must-fix

Three separate problems in `bannerView` and its callers.

**Contrast.** White text on `Color.orange.opacity(0.92)` measures **2.08:1** in light mode and 2.37:1
in dark. The success variant, white on `accentColor.opacity(0.92)`, is 3.61:1. Both fail 4.5:1 for
footnote-sized text; the error variant fails badly enough to be hard to read at a glance, which is
the only kind of glance a 2.6-second banner gets.

Fix: don't invert. Use a filled capsule with a semantic foreground —
`.background(.regularMaterial)` + `.foregroundStyle(Color.orange)` for warnings and `.primary` for
success, with an SF Symbol (`exclamationmark.triangle.fill` / `checkmark`) so the state isn't
carried by hue alone. That also fixes it in dark mode for free.

**Duration.** A real failure — `noCalendarAvailable`, a write that threw — is a setup problem the user
must act on. It gets 2.6 seconds and then no trace. Warnings should not auto-dismiss; give them a
tap-to-dismiss and no timer. `noCalendarAvailable` specifically deserves an alert with an **Open
Settings** button, not a capsule.

**Overwriting.** Both batch operations swallow their own error:

```swift
} catch {
    show(error.localizedDescription, warning: true)
    break
}
...
show(placed == 0 ? "..." : "Placed \(placed) task\(...)", warning: placed == 0)
```

If task 3 of 4 fails, the error banner is shown, the loop breaks, and then "Placed 2 tasks" replaces
it immediately. The user sees a success message for a partial failure. Same shape in
`applyTemplate`. Track a `failed` flag and report it:

> `Placed 2 of 4 — the rest couldn't be saved to Calendar. Try again.`

### The permission states

`PermissionPrompt` is the best-written screen in the app. Three gaps.

**S15a — write-only is reported as "off".** `refreshAccessStatus` maps `.writeOnly` to `.denied`, so a
user who granted access — just not full access — is told "Calendar access is off". That's false, and
it sends them looking for a switch that is already on.

> New third state: **"Blockey can save blocks but can't see your meetings"**
> "It needs full access to plan around them. In Settings, switch Calendars from Add Only to Full Access."

**S15b — the copy and the button point at different places.** The text says
"Settings › Privacy & Security › Calendars › Blockey"; the button opens
`UIApplication.openSettingsURLString`, which lands on Blockey's own settings page. Match the button:

> **"Blockey can't see your calendar. Open Settings and turn on Calendars."**

**S15c — the asking copy.** "It needs access…" — the subject is the app, so name it, and say what the
user gets rather than what the app requires:

> **"Blockey reads your calendar to see where your meetings are, and writes your blocks back to it —
> so your plan shows up on your Lock Screen, Watch and CarPlay without opening this app."**
> Button: **`Allow calendar access`**

### M6 — Restore silently destroys everything · Must-fix

`BlockeyBackup.restore` opens with:

```swift
for task in try context.fetch(FetchDescriptor<TaskItem>()) { context.delete(task) }
for template in try context.fetch(FetchDescriptor<DayTemplate>()) { context.delete(template) }
for assignment in try context.fetch(FetchDescriptor<TemplateAssignment>()) { context.delete(assignment) }
```

The button that triggers this says **"Restore from a backup"** and there is no confirmation. A user
tapping it to *look* at a backup file loses every task and template on the phone, and the tasks were
never in Calendar so there is nothing to recover from. This is the only irreversible data loss in the
app and it is one tap deep in Settings.

> Label: **`Replace tasks & templates…`** (the ellipsis promises a further step)
> Confirmation alert:
> **"Replace everything on this phone?"**
> "Restoring deletes the 4 tasks and 2 templates here and puts the backup's in their place. Your
> blocks in Calendar aren't touched."
> `Replace` (destructive) · `Cancel`

The alert must come *before* the file picker or immediately after a successful decode — decode first
so an invalid file fails without destroying anything, which the current ordering already gets right.

---

## 3. Interface copy

Everything user-facing, audited. Only rows that need a change are listed; the rest —
`"Return to inbox"`, `"Delete block"`, `"What needs a slot?"`, `"Plan around these calendars"`,
`"Turn one off and its events stop blocking out time."`, the `TemplateEditor` footer,
`"That file isn't a Blockey backup."` — are good and should be left alone.

### M4 — The restamp dialog contradicts itself · Must-fix

```swift
.confirmationDialog("Today already has \(contents.blocks.count) block(s)", ...) {
    Button("Replace them", role: .destructive) { deleteAllBlocks; applyTemplate() }
    Button("Add on top") { applyTemplate() }
    Button("Cancel", role: .cancel) { }
} message: {
    Text("Stamping again will plan around the blocks that are already there.")
}
```

Four problems in eleven words of message text.

1. **The message describes the wrong button.** "will plan around the blocks that are already there"
   is what **Add on top** does. **Replace them** deletes them. The one explanatory sentence in the
   dialog explains only the non-destructive option, sitting directly under the destructive one.
2. **"Today" is wrong on any other date.** The dialog fires for `selectedDate`, not today. Navigate to
   Wednesday, stamp, and it says "Today already has 3 blocks".
3. **"Replace them" understates the blast radius.** It calls `deleteAllBlocks(on:)` — every block on
   the day, including ones placed by hand from the inbox thirty seconds earlier. "Them" reads as "the
   ones from the last stamp".
4. **It fires too eagerly.** Any non-empty `contents.blocks` triggers it. Place one task from the
   inbox, then stamp, and the morning pass hits a destructive three-way dialog for no reason.

Replacement, safe option first:

```swift
.confirmationDialog(
    contents.blocks.count == 1
        ? "This day already has 1 block"
        : "This day already has \(contents.blocks.count) blocks",
    isPresented: $isConfirmingRestamp,
    titleVisibility: .visible
) {
    Button("Keep them and stamp around") { applyTemplate() }
    Button("Delete \(contents.blocks.count) and start over", role: .destructive) { ... }
    Button("Cancel", role: .cancel) { }
} message: {
    Text("Deleting removes every block on this day, including any you placed by hand. Your meetings aren't touched.")
}
```

And gate it: skip the dialog entirely when the existing blocks are few and none came from a stamp —
or simplest, when `contents.blocks.count <= 1`.

### The rest, in full

| Where | Now | Replacement | Why |
|---|---|---|---|
| `summaryLine` | `Nothing blocked · 15.0h free` | `No blocks yet · 15h free` | "Nothing blocked" parses as "nothing was prevented". And drop the `.0` (P1) |
| `summaryLine` | `5 blocks · 7.0h free` | `5 blocks · 4h free left` | Counts past hours as free (S5). On today, measure from `now`; add "left" so the number is honest |
| `place()` | `Blocked 2:30 PM` | `"Write the launch post" at 2:30 PM` | Reads as "2:30 PM was blocked". Name the thing that moved |
| `fillDay()` | `Nothing fits in the day's free time` | `Nothing fits — the longest free slot is 20 min` | Names the cause with the number. The app already computes the gaps |
| `fillDay()` | `Placed 3 tasks` | `Placed 3 tasks · Undo` | See M3 |
| `applyTemplate()` | `Stamped 5 blocks · 2 moved to fit · 1 to inbox` | `Stamped 5 blocks · 2 moved to fit` / and for the miss: `"Lunch" didn't fit — it's in your Inbox` | "1 to inbox" is telegraphic and the banner isn't tappable. Name the item when there's one, count when there are more, and make the banner open the Inbox |
| `bottomBar` | `Apply template` | `Set up a template` | S8 — it opens Templates |
| `bottomBar` | `No gap is long enough today` | `The longest free stretch today is 45 min` | Dead end; give the number and a `Try tomorrow` |
| `InboxTray` | `Fill day` | `Fill the day with 4 tasks` | S9 — and out of the Cancel slot |
| `InboxTray` | `· didn't fit` | `· from Workday, didn't fit` | It's the only trace of what the stamp did |
| `InboxTray` empty | `Add what needs doing…` | `Type what needs doing above, then tap it to drop it on the day.` | The field is right there |
| Inbox pill | `4` / `0` | `4` with `tray.full.fill`; icon only (`tray`) at zero | S13 — "0" beside a *full* tray is a contradiction, and a zero badge is noise |
| `BlockDetailSheet` | title `Block` | the block's own title | "Block" names the type, not the thing |
| `SettingsView` | `Alert at block start` | `Remind me about blocks` | P10 — the stepper underneath offers "5 min before", contradicting "at block start" |
| `SettingsView` | `Restore from a backup` | `Replace tasks & templates…` | M6 |
| `SettingsView` | `Could not read your tasks and templates to export.` | `Couldn't build the backup. Try again.` | Names no fix; the cause isn't actionable |
| `Failure.notPermitted` | `Blockey needs full access to your calendar to plan your day.` | `Blockey needs full calendar access to plan your day. Turn it on in Settings › Blockey › Calendars.` | States a need, not a fix |
| `Failure.noCalendarAvailable` | `Blockey could not create its calendar. Check that at least one calendar account is enabled in Settings.` | `Blockey couldn't create its calendar because no account is available. Add one in Settings › Calendar › Accounts, then try again.` | "Check that…" asks the user to diagnose; say what to do |
| `PermissionPrompt` | see S15a–c above | | |

One thing the copy gets right and should be defended: **`Stamp "Workday"`**. The button names the
specific template it will apply. That is exactly the "buttons say what happens" rule, and it is the
reason the primary action needs no explanation at all.

---

## 4. Visual system

### S6 — The type scale is eight styles doing five jobs

In use: `.title2`, `.headline`, `.callout`, `.body`, `.subheadline`, `.footnote`, `.caption`,
`.caption2` — eight of the eleven iOS text styles, across four screens.

The costly one is on the timeline itself:

```swift
BlockChip:      Text(block.title).font(.footnote.weight(.semibold))   // 13pt
FixedEventChip: Text(block.title).font(.caption.weight(.medium))      // 12pt
```

**One point of size is carrying the app's central distinction** — this is yours and movable, that
isn't. Nobody perceives a 1pt difference between two chips 40pt apart vertically. The distinction is
actually being carried by colour and border style, and (see M9) those fail too.

A five-step scale, held everywhere:

| Role | Style | Used for |
|---|---|---|
| Screen title | `.headline` | day date, sheet titles |
| Row title | `.body` | inbox tasks, form rows |
| Chip title | `.subheadline.weight(.semibold)` | **both** blocks and meetings |
| Supporting | `.footnote` | summary line, chip times, empty-state body, task meta |
| Micro | `.caption2.monospacedDigit()` | hour gutter only |

Bumping chip titles from 12/13pt to 15pt also buys real legibility on a screen you glance at while
holding coffee — and it forces the block/meeting distinction onto channels that actually work.

### S7 — Spacing is a spread, not a scale

Values currently in the view layer: `1, 2, 3, 4, 5, 6, 8, 9, 10, 12, 14, 16, 18, 20, 32`. Corner radii:
`8, 10, 14`, plus `Capsule`.

Pick **4 / 8 / 12 / 16 / 24 / 32** and **10 / 14 / Capsule**, and hold them. The 1pt, 2pt, 3pt, 5pt,
9pt and 18pt values are all doing work that 4 or 8 would do identically.

The visible symptom is horizontal alignment. On Today there are three page margins on one screen:

- Day header content: `.padding(.horizontal, 16)`
- Timeline chips: `gutterWidth 52 + inset 4` = 56
- Bottom bar: `.padding(.horizontal, 12)`

In `blockey-07.png` the date, the block titles and the blue button all start at different x. Set one
page margin of 16 for the header and the bottom bar; the gutter can stay where it is, because a ruler
is allowed its own edge.

### M9 — Blocks and meetings are not distinct enough, and Admin is the worst case · Must-fix

Measured, sRGB, light mode. Block fill is `tint.opacity(0.16)`; fixed-event fill is
`Color.primary.opacity(0.05)`:

| Pair | ΔE (CIE76) |
|---|---|
| **Admin block vs fixed event** | **3.4** |
| Rest block vs fixed event | 6.7 |
| Deep work block vs fixed event | 15.6 (at 0.22 alpha) |

ΔE 3.4 is "the same colour under different lighting". `blockey-07.png` shows it directly: the
"1:1 with Sam" meeting and the "Admin & email" block sit against each other and differ only by a
dashed vs solid border and a slightly darker title. The `admin` tint is *literally grey*
`(0.45, 0.48, 0.56)` — the same semantic grey the app uses to mean "not yours".

The crop also shows a second symptom: **the hour gridlines read straight through the blocks.** The
3 PM line crosses the "Admin & email" chip and the 4 PM line crosses "Sprint planning", because a
16% fill isn't opaque enough to sit on top of anything.

Three changes, all small:

1. **Raise the fill** to `0.22` light / `0.30` dark. Admin-block-vs-meeting goes from ΔE 3.4 → 10.2
   (light) and 2.8 → 14.4 (dark), and the gridlines stop showing through.
2. **Give `admin` a hue.** Grey is the app's word for "fixed, not yours" — no category should speak it.
   `Color(red: 0.13, green: 0.55, blue: 0.60)` (teal) measures 3.97:1 on white and 4.30:1 on dark,
   in the same band as the other five.
3. **Draw the category symbol on the chip.** `BlockCategory.symbolName` already exists and is used in
   the inbox and the template editor, but *not* on the timeline — the one place it would earn its
   keep. See below for why this is not optional.

### The six colours, and colour-blindness

As solid colours the palette holds together — one hue family per bucket, similar lightness
(luminance 0.16–0.30), and under deuteranopia the worst solid pair is personal/health at ΔE 14.7,
which is distinguishable. Contrast on white runs 3.04–4.95:1.

**At the alphas the timeline actually uses, they collapse.** Pairwise ΔE between the six block fills:

| | normal | deuteranopia | protanopia |
|---|---|---|---|
| current 0.16 fill, worst pair | 4.5 (admin/rest) | **1.5** (admin/health) | **1.5** (admin/health) |
| proposed 0.22 fill, worst pair | 6.7 (deepWork/rest) | **2.4** (admin/rest) | **2.4** (admin/health) |
| proposed 0.30 fill, dark, worst | 10.9 | 5.3 | 3.8 |

Raising the alpha fixes *block vs meeting* but does **not** fix *category vs category* — at these
tints, six categories cannot be encoded by hue for a red-green colour-blind viewer, and only barely
for anyone else. ΔE 1.5–2.4 is below the threshold of noticing.

So the conclusion is not "adjust the colours". It is: **colour cannot be the only category channel.**
Put `BlockCategory.symbolName` at the chip's leading edge — where the 3pt spine currently is, or
above it. A 12pt symbol is a redundant, colour-independent, instantly-scannable channel, it costs
nothing, and the data is already on the model. Then the colour becomes a pleasant reinforcement
rather than the load-bearing element, which is the right job for it.

### P2, P4 — two smaller marks

The **resize grabber** (`Capsule 26×3`, `tint.opacity(0.55)`, bottom-centre) reads in the screenshots
as a stray dash floating in the middle of each block — an artefact, not a handle. Either move it to
the bottom-right corner where a resize handle is conventionally expected, or make it appear only on
long-press/selection.

**Abutting chips double their borders.** Deep work ends at 2:00 and "1:1 with Sam" starts at 2:00; both
draw a 1pt border, producing a 2pt line that is heavier than any other rule on the screen. Inset chips
by 1pt at the bottom, or drop the border on the bottom edge.

---

## 5. Dark mode

Nothing in the codebase references `colorScheme`, and the six tints are fixed sRGB literals. Measured
against `#1C1C1E`:

### M10 — The hierarchy inverts · Must-fix

| Element | Light contrast vs bg | Dark contrast vs bg |
|---|---|---|
| Block fill `tint.opacity(0.16)` | 1.17–1.24 | **1.17–1.27** |
| Block border `tint.opacity(0.35)` | — | **1.46–1.79** |
| Fixed-event fill `primary.opacity(0.05)` | 1.12 | **1.15, and 1.78× the background's luminance** |

In light mode `primary` is black, so a meeting is a slightly *darker* card than white — recessive,
which is correct. In dark mode `primary` is white, so a meeting becomes a slightly *lighter* card,
while your blocks stay near-black with a barely-visible outline. **Meetings become the most prominent
thing on the screen and your own plan disappears.** That is the exact opposite of the intent stated
in the plan ("Fixed events — muted, hatched, immovable").

Fix: raise block fills to ~0.30 and borders to ~0.55 in dark, and make the fixed-event chip use an
explicitly dark neutral rather than `Color.primary` — a `secondarySystemFill`-style token, or
`colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.05)` with the border
similarly asymmetric.

### The same inversion, three more times

- **`outOfWindowShading`** — `Color.primary.opacity(0.04)`. In dark mode "outside your planning window"
  is rendered *brighter* than inside it. Dimming should dim in both modes: use black at low alpha, or
  invert the whole treatment and tint the in-window band instead.
- **Hour gridlines** — `Color.primary.opacity(0.07)` gives 1.22:1 on dark. Combined with `.tertiary`
  hour labels, the dark timeline is a near-featureless black field with no ruler. Push to ~0.12 in dark.
- **"Tap to place"** — `Color.accentColor` on `accentColor.opacity(0.12)` measures 3.44:1 light and
  4.08:1 dark for `.caption2` text. Below 4.5:1 in both. Use `.primary` text on the tinted fill, or
  raise the fill and use white.

### The banner, again

| | Light | Dark |
|---|---|---|
| White on `accentColor.opacity(0.92)` | 3.61:1 | 4.11:1 |
| White on `orange.opacity(0.92)` | **2.08:1** | **2.37:1** |

Both fail for `.footnote`. The fix in M5 (material background, semantic foreground, plus a symbol)
resolves light and dark at once.

### S4 — The tints are used as text, and fail in both modes

`InboxTray.chip` sets `.foregroundStyle(selected ? tint : Color.primary)` over `tint.opacity(0.2)`.
`TemplateEditor` and the inbox task rows tint SF Symbols the same way.

| Category | selected chip text, light | selected chip text, dark |
|---|---|---|
| deepWork | 3.79 | **2.82** |
| meeting | **2.74** | 3.80 |
| admin | 3.37 | 3.15 |
| personal | **2.50** | 4.13 |
| health | 3.05 | 3.45 |
| rest | 3.31 | 3.20 |

Every cell is under 4.5:1 and several are under 3:1. Each colour fails in *one* mode or the other,
which is what happens when a single literal has to serve both grounds.

Two options: give `BlockCategory.tint` a light and a dark variant (an asset catalog colour set, or a
`@Environment(\.colorScheme)`-aware computed property), or — simpler and probably right for this app —
stop tinting the *text* and let the chip's fill and border carry the colour, with `.primary` text on
top. Symbols can keep the tint; they're shapes, not glyphs to be read.

---

## 6. Accessibility

`grep -rn "accessibility"` over `Blockey/` returns nothing. There are no labels, no traits, no
actions, no `@ScaledMetric`, no announcements. For a single-user sideloaded app I'd normally grade
most of this low, but two of these will bite this user directly.

### S1 — Dynamic Type breaks the timeline · Should-fix (this one is likely to bite)

```swift
private let hourHeight: CGFloat = 64
private let minimumBlockHeight: CGFloat = 24
private let gutterWidth: CGFloat = 52
```

Three fixed constants; the text inside them scales and they don't.

- A 15-minute block is `0.25 × 64 = 16pt`, clamped to 24pt. It holds a title *and* a time. At the
  default size that's already tight (13pt + 11pt + 8pt padding = 32pt in a 24pt box). At AX1 it
  overflows; by AX3 the title alone is taller than the chip. There is no `.minimumScaleFactor`, no
  `.truncationMode`, and `lineLimit(2)` on the title makes it worse.
- The gutter is 52pt wide for a `.caption2` "12 PM". At AX3+ that string is wider than the gutter and
  will truncate to "12…", so the ruler stops being a ruler.
- Nothing else on the timeline is height-constrained, so the failure is silent: text clips inside
  chips rather than pushing anything, which means it looks fine right up until it doesn't.

The right fix is to scale the geometry with the text:

```swift
@ScaledMetric(relativeTo: .subheadline) private var hourHeight: CGFloat = 64
@ScaledMetric(relativeTo: .caption2)    private var gutterWidth: CGFloat = 52
```

and then a **two-tier chip**: above a threshold height, title + time as today; below it, title only at
`.footnote` with `minimumScaleFactor(0.8)` and `lineLimit(1)`. A 15-minute block does not need to
repeat a time that the gutter already gives.

Alternatively, cap it honestly: `.dynamicTypeSize(...DynamicTypeSize.xxLarge)` on the canvas only,
with everything else free to scale. That's a legitimate choice for a dense time canvas — Calendar.app
does something similar — but it should be a decision in the code, not an accident.

### S2 — VoiceOver · Should-fix

Three things are broken, in descending severity:

1. **Meetings are invisible.** `FixedEventChip` carries `.allowsHitTesting(false)`. A VoiceOver user
   gets the blocks and not the meetings — the half of the screen that defines where you *can't* plan.
   Replace with `.accessibilityElement(children: .combine)` + a label, keeping hit-testing off for
   touch. Suggested label: **"Standup, meeting, 9:30 to 10 AM, from Work calendar"**.
2. **Tap-to-place cannot be performed.** `gapLayer` is a `SpatialTapGesture` with no accessibility
   action. VoiceOver's activate gesture produces no spatial location, so the primary interaction in
   the app — the one the plan calls out as "the primary interaction, not drag" — has no accessible
   equivalent. Add an `.accessibilityAction` that places at the gap's start:
   **"Free, 45 minutes, 1:15 to 2 PM. Double-tap to place here."**
3. **Blocks have no combined label or actions.** Each chip currently exposes two separate text
   elements. Combine them, and add `accessibilityActions` for the gestures that are otherwise
   drag-only: **"Move 15 minutes later"**, **"Move 15 minutes earlier"**, **"Add 15 minutes"**,
   **"Remove 15 minutes"**. The detail sheet is reachable by tap, so this is an accelerator rather
   than the only path — but resize and move are currently unreachable without dragging.

Also: banners are never announced. `AccessibilityNotification.Announcement(banner.text).post()` in
`show(...)` is one line and covers every message in the app at once.

The canvas ordering is fine, incidentally — `TimelineLayout.columns` sorts by start time, so the
reading order matches the day.

### S3 — Tap targets · Should-fix

| Control | Actual | Minimum |
|---|---|---|
| Day chevrons — `Image(systemName:)`, `.buttonStyle(.plain)`, no frame | ~20×20pt | 44×44 |
| Resize grabber — `26×3` with `.contentShape(Rectangle().inset(by: -10))` | 46×23pt | 44×44 |
| Inbox add button — `.font(.title2)` symbol | ~28×28pt | 44×44 |

The chevrons matter most, because they are the **only** way to change days — the plan's
"swipe left/right for adjacent days" is not implemented anywhere in `TimelineCanvas`. A 20pt target
carrying sole responsibility for navigation, at the top of the screen where a thumb reaches worst.
Add `.frame(width: 44, height: 44)` and `.contentShape(Rectangle())` to all three, and add the
horizontal swipe.

The grabber has a second problem: on a short block (24pt tall) its 23pt hit area covers nearly the
whole chip, so a small drag meant to *move* a 15-minute block will resize it instead. Give the
resize gesture a minimum block height below which it doesn't attach.

---

## Polish

- **P1** `String(format: "%.1fh")` yields `15.0h`. Drop the decimal when whole.
- **P3** The now-line has no time on it. A small `10:15` pill in the gutter, in the same red, is the
  standard treatment and makes the line legible when it lands mid-chip.
- **P5** `StarterData.seedIfNeeded` runs inside `.task` in `TodayView`, so on the very first frame the
  `@Query` hasn't republished and the button reads "Apply template" before flipping to
  `Stamp "Workday"`. Seed earlier — in `BlockeyApp` at container creation.
- **P6** Tasks cannot be edited or completed. `TaskItem.completedAt` is written exactly once, to `nil`,
  and never set anywhere in the app — dead model surface. And changing a 30-minute task to 60 means
  deleting it and retyping the title. A tap-and-hold → edit sheet, or making the row's duration label
  itself a menu, would fix it.
- **P7** The highest-value missing feature for a personal app: **"Save today as a template"** in the
  `⋯` menu. The user builds a good day by hand roughly once, and right now the only way to make that
  repeatable is to retype it row by row in the template editor.
- **P8** In `blockey-04.png`, the weekday assignments render as bare blue text with no chevron. It is a
  `Menu` and reads as tappable, but a `Picker(...).pickerStyle(.menu)` would give the standard
  up-down chevron and match every other iOS settings screen. Same for the `Templates` list, which
  correctly shows disclosure chevrons — so the two halves of one screen use different affordances.
- **P9** No haptics anywhere, though build order phase 5 lists them. `.sensoryFeedback(.success,
  trigger:)` on place, stamp and snap-during-drag is a few lines and is most of what makes
  drag-and-snap feel physical.
- **P11** Nothing prevents `dayEndMinute <= dayStartMinute`. `DaySchedule.window` returns an inverted
  range, `gaps` returns `[]`, and the day silently reports "0h free" with every gap gone and no
  explanation. Either clamp the pickers against each other, or show the state:
  **"Your day ends before it starts — check the planning window in Settings."**
- **S14** `navigationTitle` is `"Today"`, and immediately below it the day header says
  "Monday, 7 September". On any other day the nav title is just the weekday, so the screen reads
  "Monday" over "Monday, 7 September". Two stacked bars consume roughly 200pt — about a quarter of
  the screen — before a single hour is visible. Drop the navigation title and let the day header be
  the title, with the `⋯` menu moving into it. That recovers ~44pt of timeline for free, which on the
  morning pass is roughly one more hour visible without scrolling.

---

## One thing to verify

The now-line is clearly drawn in `blockey-07.png` and absent from `blockey-01.png`, on the same clock.
`nowIndicator` is gated only on `visible.contains(now)`, which should be true in both. It may simply be
that the two captures used different `-blockeyNow` values — but it is worth a look, because the empty
day is exactly the state where the now-line is the only landmark on the screen.

---

## If only three things get done

1. **M1** — keep the inbox open when a task is armed. Three lines, and it is the difference between a
   morning pass and a chore.
2. **M8 + M4 + M5** — the states the user meets when things aren't already working: the blank first
   day, the restamp dialog that argues with itself, and errors that vanish before they're read.
3. **M9 + M10** — raise the block fill and put `symbolName` on the chip. It fixes block-vs-meeting,
   fixes colour-blind legibility that no palette change can fix on its own, and stops the dark-mode
   hierarchy from inverting.
