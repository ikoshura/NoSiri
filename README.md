<div align="center">

<img width="128" height="128" alt="nosiri" src="https://github.com/user-attachments/assets/3a4f44f5-696b-45d8-aac3-6bca927cd6e4" />

# NoSiri

[![macOS](https://img.shields.io/badge/macOS-14%2B-9cf2ff?logo=apple&logoColor=white)](https://www.apple.com/macos/)

</div>

A small macOS app that hides or restores the "Ask Siri" item in context menus, so you don't have to remember the terminal command.

| Before patch | After patch |
| :---: | :---: |
| <img width="1588" height="1050" alt="Before patch" src="https://github.com/user-attachments/assets/2ef31edf-dba5-4a54-b340-02a0774032cd" /> | <img width="1588" height="1050" alt="After patch" src="https://github.com/user-attachments/assets/7121c882-356c-46b6-ae1d-8e0530252c5a" /> |

## Install

**Build from source (Recommended)**

```bash
git clone https://github.com/ikoshura/NoSiri.git
cd NoSiri && ./build.sh
open build/NoSiri.app
```

## What it does

NoSiri manages the `NSAppleMenuAllowedItems` preference and then relaunches Finder so the change applies right away. No reboot or admin rights needed.

| Status | Meaning | Button |
| --- | --- | --- |
| Default | Key is absent, "Ask Siri" is shown | Apply Patch |
| Patched | Key matches the allowlist, "Ask Siri" is hidden | Restore Default |
| Custom | Key is set but doesn't match, likely hand-edited | Restore Default |

Restore Default deletes the key, which returns macOS to stock behavior.

It only affects the context-menu item. It does not disable Siri itself.

A terminal panel at the bottom shows the exact commands that ran and their output.

## Requirements

- macOS 14 or later
- Swift toolchain or Command Line Tools (to build)
