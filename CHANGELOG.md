# Changelog

All notable changes to this project will be documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned for v0.2.0

- In-app profile editor (add / rename / delete profiles, set hints)
- App picker so apps that aren't currently focused can be pre-bound
- Auto-launch at login via `SMAppService.mainApp.register()`
- Developer ID code-signing + notarization (removes the Gatekeeper warning on first open)

### Planned for v0.3.0

- USB HID roundtrip to the macropad: focus change → host sends layer-switch command → macropad physical layer follows the active app. Blocked on the macropad firmware migrating from CircuitPython to QMK so a Raw HID channel exists.

## [0.1.1] — 2026-05-22

### Added

- **"Save screenshots" toggle** in the popover. Opt-in clipboard-image logger (off by default). When enabled, the app polls `NSPasteboard.general` every ~1.5s; new pasteboard images are saved to `YYYY-MM-DD/HHMMSS.png` under a user-picked folder (default `~/Pictures/matosic-blog/`). Designed for documentation / blog workflows where you screenshot heavily and want them organized by day without manual filing. New file: `ClipboardWatcher.swift`.
- **"Change folder…" picker** in the popover (`NSOpenPanel`-based) so the save folder is configurable — e.g. point at an iCloud Drive folder so screenshots sync across your Macs. Selection persists in `UserDefaults` (`ClipboardWatcher.saveDirectoryPath`). Show-in-Finder button reveals the current folder. Toggle off and clipboard polling stops entirely — no background access otherwise.

## [0.1.0] — 2026-05-21

Initial public release.

### Added

- Menubar status item (`NSStatusItem`) with bird icon; click opens a SwiftUI popover via `NSPopover`.
- Focus observer (`FocusObserver`) subscribing to `NSWorkspace.didActivateApplicationNotification` to track the frontmost app's bundle identifier and localized name.
- JSON profile store at `~/Library/Application Support/Matosic Macropad/profiles.json`, seeded with Default / Photoshop / VS Code / Final Cut profiles.
- One-click per-app profile binding via the popover (entire active-profile row is a button — bigger hit target than a small dropdown).
- `build.sh` that produces a universal-binary (`arm64` + `x86_64`) `.app` bundle, ad-hoc codesigned with `codesign --force --deep --sign -`, zipped via `ditto` for distribution. Runs on every Mac sold since 2006.
- MIT license — independent software, no derivative obligations from the macropad's CC-BY-SA-4.0 hardware lineage.

### Known limitations

- Unsigned (ad-hoc only). First-time open requires right-click → Open to bypass Gatekeeper.
- Profile add/rename/delete requires hand-editing the JSON store (UI editor in v0.2).
- No auto-launch at login.
- No USB communication to the physical macropad yet.

[Unreleased]: https://github.com/matosichrvoje/matosic-menubar/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/matosichrvoje/matosic-menubar/releases/tag/v0.1.1
[0.1.0]: https://github.com/matosichrvoje/matosic-menubar/releases/tag/v0.1.0
