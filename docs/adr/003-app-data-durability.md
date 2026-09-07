# ADR 003: App data durability under free-provisioned sideloading

Status: accepted
Date: 2026-09-07

## Context

ADR 002 was written against a premise supplied in its brief: that free-provisioned
sideloading means "the app is reinstalled roughly weekly (7-day cert expiry), which wipes
the sandbox." On that premise the architect concluded that tasks, templates and settings
are destroyed every seven days, that the one-tap morning pass therefore cannot survive,
and that JSON export/import was required *before* templates were worth building at all.

That premise was asserted, not measured. It is load-bearing enough — it decides whether
the app's headline feature is viable — that it was worth an experiment rather than an
argument.

## The experiment

On the iOS 26.3 simulator, with the app installed and populated (4 inbox tasks, 2 seeded
templates):

1. Record the data container path and the SwiftData store file sizes.
2. Terminate the app.
3. `xcrun simctl install` the same build **over the top**, with no uninstall — this is
   exactly what re-running from Xcode does when a certificate has expired.
4. Relaunch with no seeding arguments.
5. Query the store directly.

Result:

```
4 tasks
2 templates
```

The store files were byte-identical in size and timestamp. The data container's UUID
*does* change across the reinstall, but the contents are migrated into the new container
rather than discarded.

## Decision

Treat app data as **durable across re-signing**, and export/import as insurance rather
than a prerequisite.

The distinction that actually matters is not "reinstall" but **deletion**:

| Event | Tasks, templates, settings |
|---|---|
| Certificate expires, app refuses to launch | Kept |
| Re-run from Xcode over the expired app | **Kept** (measured above) |
| User deletes the app from the Home Screen | **Lost** |
| New Mac, or a changed bundle identifier | **Lost** |

Blocks are unaffected in every row: they live in the calendar database, outside the app
sandbox entirely.

## Consequences

**What this makes easy.** Templates are worth building, and Phase 4 stands as planned.
The weekly re-sign is an inconvenience — the app stops launching until redeployed — not a
data-loss event. No restore-on-first-launch prompt is needed.

**What stays true from ADR 002.** Everything about block identity is unchanged: no
EventKit identifier is persisted, the token still rides in `event.url`, and losing the
token is still cosmetic. Those conclusions did not depend on the wipe premise.

**What we still owe.** Deleting the app *does* lose tasks and templates, and there is no
iCloud sync to fall back on (CloudKit needs a paid account). JSON export/import remains
worth building — it needs no entitlement and no App Group — but as a backup feature the
user reaches for deliberately, not as scaffolding the app cannot open without.

**The general lesson, recorded because it will recur.** ADR 002's reasoning was sound and
its EventKit research was verified against the SDK headers. It went wrong only where it
accepted an environmental claim from its brief without testing it. Claims about what the
platform does to your data are cheap to measure and expensive to get wrong.
