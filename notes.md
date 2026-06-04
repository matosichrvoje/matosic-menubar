# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & run

This is a Swift Package Manager executable targeting macOS 14+. There is no test suite.

```bash
swift run MatosicMenubar      # dev mode — Bundle.module finds bird PDF in .build/.../*.bundle
swift build -c release        # release-mode SPM build
./build.sh                    # lipo universal .app bundle → dist/MatosicMenubar.app + dist/MatosicMenubar.zip
```

`build.sh` builds the arm64 and x86_64 slices separately and `lipo`s them — `swift build --arch arm64 --arch x86_64` works but the output path shifts between toolchains. It also ad-hoc codesigns the bundle (Gatekeeper on macOS 14+ silently fails on completely-unsigned `.app`s on first launch) and copies the SPM-generated `MatosicMenubar_MatosicMenubar.bundle` into `Contents/Resources/` so `Bundle.module` works inside the `.app` too.

The menubar bird PDF lives in [Sources/MatosicMenubar/Resources/](Sources/MatosicMenubar/Resources/) (inside the SPM target, declared via `resources: [.process("Resources")]` in [Package.swift](Package.swift)). AppDelegate loads it via `Bundle.module` — the same code path works in both `swift run` and the `.app`. There is no SF Symbol fallback; if the PDF is missing, [AppDelegate.swift](Sources/MatosicMenubar/AppDelegate.swift) `fatalError`s at launch. That's intentional — a silent fallback would hide a packaging regression.

(Top-level [Resources/](Resources/) still holds [Info.plist](Resources/Info.plist) and [bird-template.svg](Resources/bird-template.svg) — neither is consumed by the running app; `Info.plist` is read by `build.sh` only, and the SVG is just the design source for the PDF.)

## Architecture

Single-process AppKit menubar utility. `LSUIElement=true` in [Info.plist](Resources/Info.plist) → no Dock icon. Entry point [main.swift](Sources/MatosicMenubar/main.swift) wires `NSApplication` to [AppDelegate](Sources/MatosicMenubar/AppDelegate.swift); everything is `@MainActor`.

The whole app is held together by **four `ObservableObject`s wired through Combine sinks in `AppDelegate.applicationDidFinishLaunching`**:

- [FocusObserver](Sources/MatosicMenubar/FocusObserver.swift) — `NSWorkspace.didActivateApplicationNotification` → publishes `bundleID` / `appName` of the frontmost app.
- [ProfileStore](Sources/MatosicMenubar/ProfileStore.swift) — owns the profile list and `bundleID → profileName` bindings, persisted to `~/Library/Application Support/Matosic Macropad/profiles.json`.
- [DeviceController](Sources/MatosicMenubar/DeviceController.swift) — `IOHIDManager` that opens the macropad's Raw HID interface and sends layer-switch commands.
- [ClipboardWatcher](Sources/MatosicMenubar/ClipboardWatcher.swift) — opt-in `NSPasteboard` poller that writes copied images to disk.

The **focus → device bridge** in [AppDelegate.swift:62-69](Sources/MatosicMenubar/AppDelegate.swift#L62-L69) is the core of the app: it `combineLatest`s focus changes, binding edits, profile edits, *and* `device.$isConnected`. The sink re-fires when the device reconnects, so a SET that was dropped while the macropad was unplugged is re-issued automatically. `DeviceController.setLayer()` is a no-op when disconnected — the bridge owns recovery, not the transport.

### Device protocol (critical)

[MacropadProtocol](Sources/MatosicMenubar/MacropadProtocol.swift) defines a tiny wire format that **piggybacks on VIA's custom-channel framing** (cmd `0x07` = `id_custom_set_value`, `0x08` = `id_custom_get_value`) so VIA's own protocol stays untouched and the [web configurator](https://macropad.hrvojematosic.com/configure) keeps working against the same Raw HID interface concurrently. Channel ID `0x10` identifies *our* "menubar" channel inside that framing — the matching handler lives in the [companion firmware repo](https://github.com/matosichrvoje/emisha-macropad)'s `via_custom_value_command_kb`.

- 32-byte Raw HID report, no report ID prefix → `IOHIDDeviceSetReport(... CFIndex(0), ...)`.
- Vendor/product `0xFEED:0x0001`, usage page `0xFF60`, usage `0x61`. The macOS composite device exposes keyboard / consumer / raw-HID as separate `IOHIDDevice` instances; the usage page+usage selects the right one.
- **Layer 1 is the FN overlay and is never a SET destination.** `encodeSetActiveLayer` returns `nil` for layer 1 or anything outside `0...maxLayerIndex` (=5) — the SET never hits the wire. `ProfileStore.nextFreeLayerIndex` skips it when assigning indices to new profiles.
- Unknown input reports (`.unknown` from `parseResponse`) are silently ignored — they're usually VIA replies destined for the web configurator running in another tab.

All IOKit callbacks are scheduled on `CFRunLoopGetMain()` and use `MainActor.assumeIsolated` to bounce back into Swift concurrency. Don't refactor to a dispatch queue: the dispatch-queue IOKit API has ordering pitfalls that the runloop API doesn't (per the comment at [DeviceController.swift:12-22](Sources/MatosicMenubar/DeviceController.swift#L12-L22)).

### Profile model & migration

[Profile.layerIndex](Sources/MatosicMenubar/Profile.swift#L12) uses `-1` as a **migration sentinel** for profiles loaded from pre-v0.3 `profiles.json` (which had no `layerIndex` field). `ProfileStore.load()` calls `migrateLayerIndices`, which:
1. Applies known seed indices for the four ship-with profiles (Default=0, Photoshop=2, VS Code=3, Final Cut=4),
2. Assigns the next free non-FN index to anything still `-1`,
3. Re-saves only if migration changed anything (preserves mtime otherwise).

So: any code reading `layerIndex` after `load()` returns can assume it's `>= 0`. The defensive fallback in `layerIndex(forBundleID:)` exists just in case.

### Popover

[PopoverView](Sources/MatosicMenubar/PopoverView.swift) is SwiftUI hosted in `NSPopover` via `NSHostingController` with `sizingOptions = [.preferredContentSize]` — fixed `contentSize` clips the bottom of the view. The active-profile row is itself the binding `Menu` (not a small adjacent "Bind…" button) — bigger hit area, matches System Settings idioms.

Don't call `NSApp.activate(ignoringOtherApps: true)` when showing the popover — doing so makes MatosicMenubar the frontmost app, which then becomes the focused app the HUD reports, defeating the whole point ([AppDelegate.swift:109-112](Sources/MatosicMenubar/AppDelegate.swift#L109-L112)).

## Companion projects (relevant when changing the device protocol)

The firmware-side `via_custom_value_command_kb` handler lives in `github.com/matosichrvoje/emisha-macropad`. Any change to channel ID `0x10`, value IDs, or report layout in [MacropadProtocol](Sources/MatosicMenubar/MacropadProtocol.swift) must be matched there. The web configurator (`github.com/matosichrvoje/matosic-macropad-web`) speaks VIA's standard protocol on the same Raw HID interface and must not be broken — that's why we use a custom *channel* inside VIA's framing rather than inventing fresh command IDs.
