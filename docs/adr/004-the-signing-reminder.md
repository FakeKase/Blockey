# ADR 004 — The app schedules its own resurrection

**Status:** accepted · 2026-10-03

## Context

Blockey is signed with a free Apple ID. The provisioning profile lasts **seven days**, after which
the app stops launching. There is no warning, no prompt and no grace period: one ordinary morning the
icon simply refuses.

This already happened. The profile minted on 2026-09-18 expired on 2026-09-25, and the lapse was
noticed on 2026-10-03 — eight days during which the app was installed, looked fine, and did nothing.

That is worse than an outage. A planning habit takes roughly three weeks to set and the certificate
grants one, so the treadmill is not an inconvenience around the product, it is the single most likely
cause of the product being abandoned. Worse, the architecture makes abandonment easy: ADR 001 put
every block in the user's calendar precisely so the schedule survives the app, which means when the
app dies the plan is still on the Lock Screen and the Watch. Three days expired and Calendar.app
covers most of the value.

So the app has to ask to be rescued, and it has to do the asking **after it can no longer run**.

## Options

### A. Do nothing; rely on the user remembering

What was happening. It failed on the first cycle.

### B. A local notification scheduled by the app

The obvious answer, and wrong. A `UNNotificationRequest` is owned by the app, and the reminder must
fire during exactly the window when the app cannot launch. It also costs a second permission prompt
(notifications are separate from calendar access), which is a prompt asked for the app's own
convenience rather than for anything the user wanted.

### C. A calendar event with an alarm — **chosen**

Write an `EKEvent` into the Blockey calendar, dated two days before expiry, carrying an `EKAlarm`.

The alarm lives in the calendar store, not in the app's sandbox. It fires on the Lock Screen, the
Watch and every synced device with the app uninstallable and the certificate long dead. It needs no
notification permission, because calendar access is already granted. And it costs about twenty lines,
because `createBlock` already knew how to attach an `EKAlarm`.

This is the architecture of ADR 001 paying a dividend nobody designed it for: the same property that
makes blocks outlive the app — they are not the app's data — makes the app's own distress signal
outlive it too.

## Decision

The reminder is an **all-day** event in the Blockey calendar titled `Re-sign Blockey`.

- **All-day, not timed.** A timed event would land in `busy` and eat a gap the user could have planned
  into. All-day events are routed to `contents.allDay` and consume no time. It also makes the event
  non-editable (`Block.isEditable` excludes all-day), so it cannot be dragged around like a block.
- **A stable title** is how the event is found again. Anything date-dependent would break the match
  and produce one reminder per launch.
- **Two days' lead time**, clamped so the reminder is never dated in the past — if less than two days
  remain, it is for today.
- **Only for profiles expiring within 30 days.** A paid account's profile lasts a year; a reminder
  eleven months out is noise. This also means the feature switches itself off the day the $99 is paid.
- The expiry is read from `embedded.mobileprovision` in the app bundle, which is the only thing in the
  runtime that knows. There is no such file in a simulator build, so the whole feature is inert there.

Date arithmetic lives in `Scheduling/SigningReminder.swift` as pure functions with tests. Only
`CalendarService.ensureSigningReminder` touches EventKit, per the layering rule.

## Consequences

**Good.** The failure that already cost eight days is now announced before it happens, through a
channel that survives the failure. No new permission. No new entitlement — it works under free
signing, unlike every other notification-shaped answer.

**The cost.** `deleteAllBlocks` had to stop deleting all-day events, or "Clear the day" would remove
the reminder. This is the correct behaviour independently — an all-day event is not a block anywhere
else in the app — but it is a behaviour change made to accommodate this feature, and it is recorded
here rather than discovered later.

**Accepted limits.** Re-signing creates a new expiry and therefore a new reminder day; the old pending
reminder is deleted when the new one is written, so at most one is outstanding, but past reminders
accumulate in the calendar as history.

Inside the final two days the reminder day becomes "today" and moves forward with it, so opening the
app on each of the last days produces a fresh alarm. That is deliberate — the thing being warned about
gets more urgent, not less — but it means up to three alarms per cycle rather than one. Likewise,
launching after 7pm on a day a reminder is due fires it within the minute instead of silently waiting
for an evening that has gone. If the user deletes the event, it is rewritten on next launch —
which only helps while the app still launches. And the reminder cannot help someone who has already
let it lapse; it is a fence at the top of the cliff, not an ambulance.

**Unverified.** The reminder has not yet fired on the real device — that takes a full seven-day cycle.
The date logic is tested, the write is not observable in the simulator (no profile), so the first real
proof arrives with the next expiry.

## Amendment, 2026-11-03 (issue #5)

The reminder was found again by title alone, so cleanup could delete a user's own timed block named
`Re-sign Blockey`. It now carries the marker url `blockey://signing-reminder` and is matched by
`SigningReminder.isReminder`: the marker first, with all-day plus the exact title kept as a fallback
for reminders written before the marker. The marker's host is not `block`, so `BlockToken` ignores it.

The fallback requires no url at all, so an all-day event with this title and a foreign url (a meeting
link, say) is left alone. Legacy reminders are upgraded on the next launch: one on the right day is
replaced once with a marked copy instead of being left as it was.

Accepted residual risk: an unmarked all-day event with exactly this title and no url, in the Blockey
calendar and within 60 days, is indistinguishable from a legacy reminder and will be replaced.
