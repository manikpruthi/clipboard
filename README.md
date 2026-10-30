# Clipboard Win

Native macOS menu bar app that brings Windows 11-style clipboard history (`Win+V`) to the Mac. Press **Shift+⌘+V** anywhere to open a searchable popup, then pick a text snippet or image to paste into the app you were using.

![Clipboard Win history panel](docs/screenshots/clipboard-panel.png)

Pinned items stay at the top, image entries get thumbnails, and long text truncates cleanly.

![Searching clipboard history](docs/screenshots/clipboard-search.png)

## Features

- **Global hotkey** — `Shift+⌘+V`, swallowed so it never types a stray `V` into your document
- **Text and image history** with thumbnails, capped at 50 unpinned entries to keep memory low
- **Live search** — filter as you type, across both the preview and the full text
- **Pinning** — `⌘P` or the right-click menu keeps an entry at the top permanently
- **No duplicates** — re-copying something moves the existing entry instead of cloning it
- **Hover and selection feedback** with a native accent highlight
- **Menu bar only** — runs as an `LSUIElement`, no Dock icon
- **Universal binary** — Apple Silicon and Intel
- **Native AppKit** — no web views, no third-party dependencies

## Install

### Option 1: DMG (easiest)

1. Open `release/Clipboard-Win-1.1.0.dmg`
2. Drag **Clipboard Win.app** into `Applications`
3. Open it from Applications (right-click → **Open** the first time, since the build is ad-hoc signed)
4. Grant **Accessibility** access — see below

### Option 2: Build from source

```bash
./build.sh release
cp -R "$HOME/Library/Caches/ClipboardWinBuild/Clipboard Win.app" /Applications/
open "/Applications/Clipboard Win.app"
```

### Option 3: Build and package a DMG

```bash
./package.sh          # builds universal app, writes release/Clipboard-Win-<version>.dmg
```

## Permissions

Clipboard Win installs a session-wide event tap to catch `Shift+⌘+V` and posts a synthetic `⌘V` when you pick an item. Both need **Accessibility**:

1. Open the menu bar clipboard icon → **Grant Accessibility Access…** (jumps straight to the right pane)
2. Enable **Clipboard Win** under **System Settings → Privacy & Security → Accessibility**
3. No relaunch needed — the app notices the grant and starts the hotkey automatically

> **Why Accessibility and not Input Monitoring?** A tap that *swallows* the hotkey requires Accessibility. The app listens for both, but only Accessibility lets it prevent `V` from reaching your app.

If the menu bar item still says *Grant Accessibility Access…* after you toggle it, quit and reopen the app once using **Quit Clipboard Win** in the menu.

## Usage

| Action | Shortcut |
|---|---|
| Open history | `Shift+⌘+V` |
| Move selection | `↑` / `↓` |
| Paste selected item | `Return` or click |
| Pin / unpin selected item | `⌘P` (or right-click) |
| Delete selected item | `Delete` (or right-click) |
| Dismiss | `Esc` (or click away) |

The panel opens on whichever display your pointer is on, and dismisses as soon as another app takes focus. The menu bar icon also offers **Clear Unpinned** and **Quit**.

Pasting needs Accessibility too. Without it the item is still placed on the clipboard, so you can press `⌘V` yourself.

## How it works

- `HistoryService` polls `NSPasteboard.general.changeCount` every 250 ms, dedupes by content, and keeps pinned entries above unpinned ones.
- `HotkeyService` creates an `CGEvent` tap, re-enables itself when macOS disables the tap on timeout, and retries every few seconds until Accessibility is granted.
- `ClipboardPanel` is a borderless `NSPanel` with vibrancy, a reusable row view, and a local key monitor for navigation.

Pasting writes to the pasteboard, reactivates the previous frontmost app, then posts a synthetic `⌘V` — so history itself never pollutes the history.

## Requirements

- macOS 14 or later
- Xcode Command Line Tools (`xcode-select --install`) to build; Xcode 16+ also works
- Ad-hoc signed (not notarized), so the first launch needs right-click → **Open**

## Project layout

```
clipboard-win/
├── Sources/
│   ├── App/         AppDelegate (status item, permissions), main.swift
│   ├── Models/      ClipboardItem — pasteboard capture and paste
│   ├── Services/    HistoryService, HotkeyService
│   └── UI/          ClipboardPanel — popup, rows, search, keyboard
├── Resources/       Info.plist
├── docs/screenshots/
├── build.sh         builds a universal .app into ~/Library/Caches/ClipboardWinBuild
└── package.sh       builds + wraps it in a DMG under release/
```
