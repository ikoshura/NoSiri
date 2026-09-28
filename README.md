# NoSiri

[![macOS](https://img.shields.io/badge/macOS-14%2B-9cf2ff?logo=apple&logoColor=white)](https://www.apple.com/macos/)
![Latest release](https://img.shields.io/github/v/release/ikoshura/NoSiri?label=download)

A tiny macOS app that toggles the "Ask Siri" context-menu item, so you never
have to remember the terminal incantation again.

## Install

### Recommended: build it yourself

This is the best option, and it takes seconds. The app is one Swift file with no
dependencies, so `swiftc` compiles it from source faster than you can download a
disk image — and you get a binary you know the provenance of, since you watched
it get built from the 505 lines sitting in this repo.

```bash
git clone https://github.com/ikoshura/NoSiri.git
cd NoSiri && ./build.sh
open build/NoSiri.app
```

That's the whole thing. If you don't have the Swift toolchain yet, install the
Command Line Tools with `xcode-select --install` and the first build takes a
minute; every build after that is instant.

### Or download the DMG

Grab the latest `.dmg` from [releases](https://github.com/ikoshura/NoSiri/releases),
drag **NoSiri** into Applications, and launch it.

## First launch: "cannot be opened because it is not notarized"

Expected, and harmless to fix. NoSiri has no Apple Developer account behind it,
so `build.sh` signs it **ad-hoc** (`codesign --sign -`) instead of with a
notarized Developer ID. Gatekeeper only trusts notarized apps by default, so on
first open macOS will refuse it. Pick whichever of these suits you:

**1. Right-click → Open** (easiest, no terminal)
Open Finder, right-click `NoSiri.app` in Applications, choose **Open**, then
**Open** again in the dialog. The exception is remembered for that copy only.

**2. Clear the quarantine flag** (once, in Terminal)

```bash
xattr -dr com.apple.quarantine /Applications/NoSiri.app
open /Applications/NoSiri.app
```

**3. Allow it system-wide**, if you'd rather not do it per copy:
System Settings → Privacy & Security → scroll to the blocked section →
**Open Anyway**. This appears only the first time, and only after you try to
launch the app.

Note that building it yourself (option 1 above) sidesteps all of this: an app you
compile locally is never quarantined, since the flag is set only on files
*downloaded* by a browser. No `xattr` gymnastics needed.

## What it does

It manages the global `NSAppleMenuAllowedItems` preference:

| Status | Meaning | Button |
| --- | --- | --- |
| **Default** | key absent, "Ask Siri" is in every context menu | Apply Patch |
| **Patched** | key matches the exact allowlist, "Ask Siri" hidden | Restore Default |
| **Custom** | key is set but doesn't match — likely hand-edited | Restore Default |

Each button also relaunches Finder, which is the process that builds the context
menus and caches the filter, so the change takes effect immediately:

```bash
killall Finder
```

No reboot, Automation consent or admin rights are needed — Finder is an ordinary
per-user process that relaunches itself and restores the windows that were open.

`Apply Patch` writes the same 15 system menu codes (plus the leading `-int 0`)
as the original command. `abtm` (About This Mac) is intentionally left out, as
in the original. `Restore Default` deletes the key, which is the supported way
to get back to stock behavior.

## Notes

- The change applies to the  **menu** filter; it does not disable Siri AI, only
  the context-menu item.
- Reloading needs no Automation access or admin rights: `killall` on your own
  Finder process is always permitted, and the preference lives in your own
  ~/Library/Preferences.
- "Custom" state is detected by exact comparison against the value the app
  writes, so a partially-edited array is reported honestly rather than
  misreported as patched.

## The terminal panel

The readout at the bottom is not decoration: it shows the exact `defaults`
invocation that ran, the wrapped command as issued, the output and exit status,
then `Reloading Finder…`. Each button press resets the transcript, so it always
describes the action you just took and nothing older. Long commands wrap at word
boundaries and the transcript opens at its heading, not at its tail.

## Layout

```
Sources/NoSiri/App.swift   all app code (Prefs, state model, SwiftUI views)
Resources/Info.plist       bundle metadata
Resources/AppIcon.appiconset  macOS icon catalog -> .icns at build time
build.sh                   swiftc build script -> build/NoSiri.app + dist/*.dmg
```

## Requirements

- macOS 14 or later (built and tested on macOS 27)
- Swift toolchain / Command Line Tools for building
