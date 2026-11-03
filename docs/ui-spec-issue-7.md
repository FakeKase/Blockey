# UI spec: daily streak (issue #7)

Caveat: `gh` was not available to me, so this follows the brief, not the issue thread. Re-check the thread for anything it adds. Rule: a day counts if the user ADDED a block that day (day of the action). No freeze. Undo and delete never remove a day.

## 1. Placement on Today

One inline label in `TodayView.dayHeader`, in the existing `VStack(alignment: .leading, spacing: 1)`. Change the first line, `Text("Today")`, into `HStack(alignment: .firstTextBaseline, spacing: 8) { Text("Today").font(.headline); streakLabel }`. The summary line below is untouched, and nothing goes near the action area, so "Add my Workday" is not crowded.

- Shown only when `isToday`. Hidden when browsing other days (the streak is about today).
- `streakLabel` = `Label { Text(copy) } icon: { Image(systemName: ...) }`, font `.caption.weight(.medium)`, `.lineLimit(1)`, `.fixedSize(horizontal: false, vertical: true)`.
- Symbol: SF Symbol, not emoji. Active: `flame.fill`, `.orange`. At risk: `flame` (outline), `.secondary`, text `.secondary`. Text colour when active is `.primary`, so the orange is a small accent only.
- Emoji is never needed, so `Emoji.isSupported` is not consulted. This sidesteps the simulator tofu problem and keeps screenshots honest.
- Not a Button. No tap target is added to the header.

## 2. Copy by state

| State | Condition | Shown (Today only) |
|---|---|---|
| No streak yet | never added, or streak is 0 | nothing |
| Active | added today, n >= 1 | `1-day streak` / `n-day streak` (n = 2, 3, ...) |
| At risk | nothing today, alive from yesterday (n >= 1) | `Keep your 1-day streak` / `Keep your n-day streak` |
| Just broken | missed a full day, nothing today | nothing (same as no streak) |
| Restart | first add after a break | `1-day streak` |

Q5 answer: plain restart, with no "welcome back" line. A broken streak is shown nowhere on Today; the best is in Settings (3). Reason: a personal tool should not scold or celebrate at the moment of failure, and "your best was N" is exactly the line that makes someone abandon an app (CLAUDE.md gap 2 says abandonment is the live risk). The pull comes from the at-risk line, which is the only state that asks for action.

## 3. Longest streak

Settings gets one row in the section that holds the other personal info (read `SettingsView` for the right section; I did not). Row: title `Streak`, trailing secondary value `Best: 12 days` (`Best: 1 day`; `Best: none yet` when 0). Footer: `Counts each day you add a block. Undo and delete do not remove a day.` The badge is not tappable, to keep the header quiet.

## 4. At the moment it increments

Nothing extra. No banner, no Undo-banner text (the banner's Undo is about blocks and must not mention the streak, since Undo does not touch it). The label changes from `Keep your 3-day streak` to `4-day streak` when the add succeeds; animate it with `.contentTransition(.opacity)` inside the existing `withAnimation`, 0.25s. No confetti, haptic or sound. Under Reduce Motion (`@Environment(\.accessibilityReduceMotion)`), no animation: swap instantly.

## 5. Accessibility

- Group the label as one element: `.accessibilityElement(children: .ignore)` plus a label.
  - Active: `Streak: 3 days. You have added blocks today.` Singular: `Streak: 1 day. You have added blocks today.`
  - At risk: `Streak: 3 days. Add a block today to keep it.`
- Announce on increment only if VoiceOver is on: reuse the existing `AccessibilityNotification.Announcement`, text `Streak is now 4 days.` Not on launch.
- Colour is never the only signal: active vs at risk differ by symbol (`flame.fill` vs `flame`) and by words (`3-day streak` vs `Keep your 3-day streak`). Orange on the bar material is decoration, not information.
- Dynamic Type: `.caption` scales. At `typeSize.isAccessibilitySize`, drop the HStack for a VStack so the label sits on its own line under `Today`, with `lineLimit(nil)`, matching how the summary line already behaves.
- Contrast: use `.orange` only for the symbol; the text is `.primary` or `.secondary`, which meet contrast on `.bar`.

## 6. Open questions

1. When does "at risk" start? Recommend all day (no clock logic, no nagging). Alternative: only after the day-end setting. Not recommended, it adds a rule to explain.
2. Day boundary: calendar day in `Calendar.current`. CLAUDE.md warns this Mac's `Calendar.current` is Buddhist, so tests must build dates from `Calendar.current` and compare days, never year numbers.
3. Where the days are stored: SwiftData or `@AppStorage`? Recommend SwiftData (a small `ActivityDay` set of day starts), because a streak is derived from days, not a counter, and survives time-zone changes. Note ADR 003: it is not in iCloud, and CLAUDE.md gap 6 says backup omits `@AppStorage`, so `@AppStorage` would lose the streak on restore.
4. Do `Add my Workday`, Place all, drag-to-place and `New block` all count? Recommend yes, anything that creates a block. Moving or editing does not.
5. Does viewing a past or future day change the label? Recommend no: hidden off today, so no "streak on Tuesday" confusion.
