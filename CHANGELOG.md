# Changelog

All notable changes to this project will be documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned for v0.4.0

- In-app profile editor (add / rename / delete profiles, set layer index, set hints)
- App picker so apps that aren't currently focused can be pre-bound
- Per-profile visual key map preview in the popover (3×3 + encoder; reads live keymap from the device over HID)
- Auto-launch at login via `SMAppService.mainApp.register()`
- Developer ID code-signing + notarization (removes the Gatekeeper warning on first open)

## [0.3.0] — 2026-05-22

> **Status: Mac side staged, firmware side pending.** The host code shipped in this release talks to the device over Raw HID using a custom VIA channel (id `0x10`). The matching firmware handler (`via_custom_value_command_kb` for channel `0x10`) is being landed separately in the sibling firmware repo. Until that firmware is flashed (`device_version` ≥ `0.1.0`), the menubar app still runs cleanly — bird dims/brightens on plug/unplug, popover shows "Device offline" when no device is found — but the actual layer-switch commands are sent into the void and the device ignores them (`id_unhandled = 0xFF`). All the visible v0.1.x behavior is unchanged.

### Added

- **Auto-switching device layers on macOS focus changes** (Mac side). Bring an app to the front → the Mac app sends a "switch to layer N" command over Raw HID. Implemented as a conversation over QMK's existing VIA interface using the "custom channel" command framing (channel id `0x10`), so VIA's own protocol stays untouched and the web configurator keeps working against the same device. New files: `DeviceController.swift` (IOKit HID transport using `IOHIDManagerScheduleWithRunLoop` on the main runloop, connect/disconnect lifecycle, fire-and-forget SETs, async GET replies that update the published `deviceLayer`) and `MacropadProtocol.swift` (byte-level encode/decode for `id_custom_set_value` / `id_custom_get_value` over the menubar channel).
- **Profile-to-layer mapping.** `Profile` gains `layerIndex: Int`. Seeds: Default→0 (BASE), Photoshop→2 (USER1), VS Code→3 (USER2), Final Cut→4 (USER3). Layer 1 is the FN momentary overlay — reserved forever; the Mac app never SETs it. Profiles loaded from a pre-v0.3 `profiles.json` get migrated: known names get their seed indices, unknown names get the next free non-reserved slot.
- **"Device offline" subtle cue.** Bird icon dims (`appearsDisabled = true` on the menubar button, which works in both light and dark menubars without a second asset) and the popover shows a one-line "Device offline — not switching layers" row when the macropad is missing. Keeps the HUD honest. Auto-recovers silently on reconnect (sends a fresh SET for the currently focused app).

### Changed

- Strict focus-follows-layer model: every focus change issues a SET, including focus on apps with no explicit binding (those route to the Default profile's layer). Predictable: the HUD's claim and the device's actual state never drift.

### Pending

- Matching firmware-side `via_custom_value_command_kb` handler (channel id `0x10`, value id `0x00` = active layer) — was prototyped during v0.3 design but reverted to keep firmware changes out of this release; lands in a follow-up alongside `DYNAMIC_KEYMAP_LAYER_COUNT 6` + the `KC_TRNS`-on-user-layers fix that lets `MO(_FN)` keep working from any active layer.

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

[Unreleased]: https://github.com/matosichrvoje/matosic-menubar/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/matosichrvoje/matosic-menubar/releases/tag/v0.3.0
[0.1.1]: https://github.com/matosichrvoje/matosic-menubar/releases/tag/v0.1.1
[0.1.0]: https://github.com/matosichrvoje/matosic-menubar/releases/tag/v0.1.0
