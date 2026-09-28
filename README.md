# NoSiri

[![macOS](https://img.shields.io/badge/macOS-14%2B-9cf2ff?logo=apple&logoColor=white)](https://www.apple.com/macos/)
![Latest release](https://img.shields.io/github/v/release/ikoshura/NoSiri?label=download)

A tiny macOS app that toggles the "Ask Siri" context-menu item, so you never
have to remember the terminal incantation again.

## Install

Download the latest `.dmg` from [releases](https://github.com/ikoshura/NoSiri/releases),
drag **NoSiri** into Applications, and launch it. The app is ad-hoc signed
(notarization requires an Apple Developer account).

Or build it yourself:

```bash
./build.sh          # -> build/NoSiri.app and dist/NoSiri-<version>.dmg
open build/NoSiri.app
```

No Xcode project and no third-party dependencies — `build.sh` compiles the single
Swift source with `swiftc`, renders the `.icns` from the iconset, ad-hoc signs the
bundle, and packages the disk image.

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
