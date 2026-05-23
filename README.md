# Matosic Macropad — menubar app

A tiny macOS menubar utility that shows which **macropad profile** is active for the app you're currently using.

It watches whichever app is in focus, looks up a profile binding (e.g. *Cursor → VS Code profile*, *Photoshop → Photoshop profile*), and surfaces the active profile in your menubar with one click to switch.

This is the companion app to the [Matosic Macropad](https://macropad.hrvojematosic.com) — an open-source 9-key + encoder mechanical macropad. It auto-switches the macropad's active layer to match whichever app is in focus, and works as a profile-tracker HUD when the device is unplugged.

## Install

> v0.3.0 is a developer preview — unsigned. Gatekeeper will warn the first time you open it. Right-click → Open the first time to bypass.

1. Go to the [Releases page](https://github.com/matosichrvoje/matosic-menubar/releases/latest).
2. Download `MatosicMenubar.zip`.
3. Unzip → drag `MatosicMenubar.app` into `/Applications`.
4. Right-click the app → **Open** → confirm "Open" in the Gatekeeper dialog.

A small bird icon appears in your menubar. Click it to open the popover.

If you can't see the bird in your menubar (common on notched MacBooks), it's hiding behind the notch. Hold **⌘** and drag any menubar item to reorder, or use [Ice](https://github.com/jordanbaird/Ice) to manage overflow.

## What it does today

- **Auto-switches the macropad's active layer to match the focused app** *(once a v0.3-compatible firmware is flashed)*. Bring VS Code to the front → the macropad jumps to your VS Code layer. Switch to Photoshop → it follows. The connection uses QMK's Raw HID interface and piggybacks on VIA's custom-channel framing, so the [web configurator](https://macropad.hrvojematosic.com/configure) keeps working unchanged. The Mac side ships today; the matching firmware handler (channel `0x10` in `via_custom_value_command_kb`) is landing in the sibling firmware repo. Without it, the menubar app still runs cleanly — bird state and HUD work — but the device ignores the layer-switch commands.
- **Live menubar HUD.** Bird icon in the menubar; tooltip + popover show the active app and its bound profile. Bird dims and the popover shows "Device offline" when the macropad is unplugged — the HUD stays honest about what it can and can't do.
- **Per-app profile bindings.** Click the active-profile row → pick a profile → that app is now bound. The macropad switches layers automatically next time you focus the app.
- **Profile library.** Ships with Default / Photoshop / VS Code / Final Cut, each mapped to a device layer (Default→BASE, Photoshop→USER1, VS Code→USER2, Final Cut→USER3). Edit `~/Library/Application Support/Matosic Macropad/profiles.json` to add your own — unused layers will be assigned automatically.
- **Save screenshots** *(opt-in, off by default)*. Toggle in the popover. When enabled, every image you copy to the clipboard (e.g. `Cmd-Ctrl-Shift-4`) is saved as PNG under `YYYY-MM-DD/HHMMSS.png` inside a folder you pick. Default save folder is `~/Pictures/matosic-blog/`; click **Change folder…** in the popover to point it at any directory — e.g. an iCloud Drive subfolder, so screenshots sync to your other Mac automatically. Toggle off and clipboard polling stops entirely.
- **Stays out of your way.** No dock icon, no notifications, no telemetry, no network.

## What it doesn't do *yet*

- **In-app profile editor.** You can bind apps to existing profiles via the popover; adding/renaming/deleting profiles or reassigning layer indices requires hand-editing the JSON. UI editor coming in v0.4.
- **Visual keymap preview.** The popover shows the profile *name* but not what each macropad key does on that layer. Live 3×3 + encoder preview coming in v0.4 (it reads the current keymap from the device over the same HID channel).
- **Auto-launch at login.** Coming in v0.4 via `SMAppService`.
- **App picker.** Currently you can only bind the currently-focused app; v0.4 adds a `/Applications`-wide picker.

## Privacy

The app reads:
- The bundle identifier and localized name of the frontmost macOS app (via `NSWorkspace`).
- **The clipboard — only when "Save screenshots" is toggled on** (off by default). When enabled, the app polls `NSPasteboard.general` every ~1.5s; if the clipboard contains a new image, the image is written to `YYYY-MM-DD/HHMMSS.png` under the user-picked save folder (default `~/Pictures/matosic-blog/`). macOS may show a "MatosicMenubar pasted from <app>" banner when this happens — that's the standard pasteboard-access notification, not a separate transmission. Toggle off and the polling stops entirely.

It does not read:
- Window contents, keystrokes, browser history, file contents, or anything else.

It does not send any data anywhere. Profile bindings live in `~/Library/Application Support/Matosic Macropad/profiles.json`; when enabled, clipboard images live in `~/Pictures/matosic-blog/` — both on your machine, never transmitted.

## Build from source

Requires Xcode 15+ / Swift 5.10+ and macOS 14+.

```bash
git clone https://github.com/matosichrvoje/matosic-menubar.git
cd matosic-menubar
swift run MatosicMenubar
```

To produce a distributable `.app` bundle:

```bash
./build.sh
# → dist/MatosicMenubar.app  (and dist/MatosicMenubar.zip)
```

## Project layout

```
matosic-menubar/
├── Package.swift                 # SPM manifest
├── Sources/MatosicMenubar/
│   ├── main.swift                # Entry point
│   ├── AppDelegate.swift         # NSStatusItem + NSPopover wiring, focus→device bridge
│   ├── FocusObserver.swift       # NSWorkspace focus notification subscriber
│   ├── ClipboardWatcher.swift    # Opt-in pasteboard-image logger
│   ├── DeviceController.swift    # IOKit HID transport to the macropad
│   ├── MacropadProtocol.swift    # VIA custom-channel byte layouts
│   ├── Profile.swift             # Profile + binding data model (layer index lives here)
│   ├── ProfileStore.swift        # JSON persistence + layer-index migration
│   └── PopoverView.swift         # SwiftUI popover content
├── Resources/
│   └── Info.plist                # App bundle metadata (LSUIElement = true)
├── build.sh                      # Build + bundle into MatosicMenubar.app
├── LICENSE                       # MIT
└── README.md                     # You are here
```

## Roadmap

| Version | What |
|---|---|
| **v0.1.0** | Menubar HUD, per-app profile binding, JSON profile store |
| **v0.1.1** | Opt-in clipboard-image saver (`Save screenshots` toggle) |
| **v0.3.0** *(current)* | macropad-firmware roundtrip: auto-switch the device's active layer to match the focused app, via QMK Raw HID + VIA custom-channel framing |
| **v0.4.0** | In-app profile editor (add / rename / set layer), app-picker for pre-binding, per-profile visual key map preview, auto-launch at login, .app code signing + notarization |
| **v1.0** | Homebrew Cask distribution, signed + notarized |

## Companion projects

- **Macropad PCB** (KiCad source, BOM, case): `github.com/matosichrvoje/matosic-macropad-pcb`
- **Macropad firmware** (QMK): `github.com/matosichrvoje/emisha-macropad`
- **Web landing + browser configurator**: `github.com/matosichrvoje/matosic-macropad-web`
- **This menubar app**: you're here.

## License

MIT — see [LICENSE](LICENSE). Do what you want with this code.

The macropad hardware design itself is under CC-BY-SA-4.0 (forked from [ANAVI Macro Pad 10](https://github.com/AnaviTechnology/anavi-macro-pad-10)), but this menubar app is an independent piece of software that talks to the device — not a derivative of the hardware design — and is freely MIT-licensed.

— Hrvoje Matosic
