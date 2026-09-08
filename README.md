# Blockey

A personal time-blocking app for iPhone. Plan the day around the meetings you
already have, in about two minutes.

Blocks are written to a calendar named **Blockey**, so your plan shows up in
Calendar, on your Watch, and on your other devices — and survives reinstalling
the app.

---

## Requirements

- Xcode 26.2 (installed at `/Applications/Xcode.app`)
- An iPhone running **iOS 18 or newer**
- A free Apple ID for signing (no paid developer account needed)

**No `sudo xcode-select` is required.** Every script sets `DEVELOPER_DIR`
itself, so the toolchain works even though the command line still points at
CommandLineTools.

## Running it

```sh
./scripts/build.sh                  # build for the simulator
./scripts/run.sh                    # install, grant calendar access, launch, screenshot
./scripts/test.sh                   # run the unit suite
./scripts/demo.sh /tmp/shot.png     # launch a populated demo day and screenshot
```

`demo.sh` accepts two environment variables:

```sh
BLOCKEY_NOW=14:30 BLOCKEY_STAMP=1 ./scripts/demo.sh /tmp/shot.png
```

`BLOCKEY_NOW` pins the app's idea of "now" so screenshots land on a realistic
hour. `BLOCKEY_STAMP` stamps the weekday's template on launch. Both are
simulator-and-Debug only, behind a compile-time guard.

## Putting it on your phone

Signing is already configured — `DEVELOPMENT_TEAM` is set to the personal team
in `project.pbxproj`, so there is nothing to fill in.

1. Open `Blockey.xcodeproj` in Xcode.
2. Plug the phone in, unlock it, and pick it as the destination.
3. Run.
4. First time only, on the phone: Settings → General → VPN & Device Management
   → trust the developer certificate.

Two prerequisites, both one-time and both on the phone:

- **Developer Mode** must be on: Settings → Privacy & Security → Developer Mode.
  Without it the device cannot be registered and Xcode reports the misleading
  "your team has no devices from which to generate a provisioning profile".
- The Apple ID must be signed in under Xcode → Settings → Accounts.

Updating the app later is the same thing: Run again. Installing over the top
keeps your tasks and templates.

### Only build from this checkout

The signing settings live in this repository. A second clone elsewhere will
build a *different* app — one commit behind, or unsigned — and it is not
obvious from Xcode which one is open. If a change appears to have had no
effect on the phone, check the window title before anything else.

### The seven-day expiry

A free Apple ID signs apps for **7 days**. After that Blockey refuses to launch
until you re-run it from Xcode. That is the only cost — it is not a data-loss
event:

| What happens | Your tasks and templates |
|---|---|
| Certificate expires | Kept |
| Re-run from Xcode over the expired app | **Kept** (measured — see ADR 003) |
| You delete the app from the Home Screen | **Lost** |

Your **blocks are never at risk** either way. They live in the Blockey calendar,
outside the app, and sync through iCloud like any other event.

---

## How it works

A block *is* a calendar event. There is no sync engine, no local mirror of your
schedule, and no conflict resolution — editing a block in Calendar.app *is*
editing the block. See [ADR 001](docs/adr/001-blocks-are-calendar-events.md).

`EKEvent` has no custom fields, so everything else Blockey needs rides in the
event's URL:

```
blockey://block/<uuid>?c=<category>&t=<source task>
```

No EventKit identifier is ever persisted; blocks are always found by fetching
the Blockey calendar over a date range. Apple documents `eventIdentifier` as
changing when an event moves calendar or is re-created by a sync, so the problem
is designed out rather than defended against. If the token is lost, a block
still works — it just falls back to a default colour. See
[ADR 002](docs/adr/002-block-identity-and-metadata.md).

### Layout

```
Blockey/
  Scheduling/    Pure time arithmetic. No EventKit, no SwiftUI, no persistence.
                 Every scheduling rule lives here, which is why it is the only
                 part with heavy unit tests.
  Calendar/      The entire relationship with EventKit. Nothing above this
                 layer ever sees an EKEvent.
  Models/        SwiftData: tasks, templates. Settings are @AppStorage.
  Views/         SwiftUI.
BlockeyTests/    Tests for Scheduling/.
```

The Xcode project uses a **synchronized folder group**, so new Swift files in
`Blockey/` are picked up automatically — `project.pbxproj` never needs editing.

### The stamping rule

When a template is applied, fixed events always win:

1. Try the item's intended time.
2. Otherwise take the next gap that fits, at or after that time.
3. Otherwise take any gap that fits earlier in the day.
4. Otherwise leave it unplaced — it lands in the inbox rather than vanishing.

Items are placed in order and each becomes busy for the ones after it, so a
template cannot double-book itself.
