import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let focus = FocusObserver()
    private let store = ProfileStore()
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Custom matosic bird (bundled in .app/Contents/Resources/) takes priority.
            // SF Symbol fallback covers `swift run` dev mode where there's no .app bundle.
            let image: NSImage? = NSImage(named: "bird-template")
                ?? NSImage(systemSymbolName: "bird.fill", accessibilityDescription: "Matosic Macropad")
                ?? NSImage(systemSymbolName: "bird", accessibilityDescription: "Matosic Macropad")
            if let image {
                // Apple HIG: menubar icons are 18×18pt within the 22pt menubar height.
                // PDFs come in at their viewBox size (64pt here) by default — force resize.
                image.size = NSSize(width: 22, height: 22)
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageOnly
            }
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.behavior = .transient
        let hosting = NSHostingController(
            rootView: PopoverView(focus: focus, store: store)
        )
        // Let SwiftUI's intrinsic size drive the popover; otherwise a fixed
        // contentSize clips the bottom (Quit button) when content grows.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        // Republish status item title when focus or bindings change.
        focus.$appName
            .combineLatest(focus.$bundleID, store.$bindings, store.$profiles)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _, _ in
                self?.refreshStatusTitle()
            }
            .store(in: &cancellables)

        refreshStatusTitle()

        let visible = statusItem.isVisible
        let hasButton = statusItem.button != nil
        FileHandle.standardError.write(Data("""
            [matosic-menubar] launched. status_item_visible=\(visible) button_attached=\(hasButton)
              if you can't see the icon in the menubar, it's almost certainly hidden behind the notch.
              switch to Finder to free up menubar space, or install Ice (brew install --cask jordanbaird-ice).
            \n
            """.utf8))

    }

    func applicationWillTerminate(_ notification: Notification) {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            removeOutsideClickMonitor()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            installOutsideClickMonitor()
            // Do NOT call NSApp.activate(ignoringOtherApps: true): doing so makes
            // MatosicMenubar the frontmost app, which then becomes the focused app
            // the popover reports — defeating the whole point of the HUD.
        }
    }

    private func installOutsideClickMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.popover.performClose(nil)
                self?.removeOutsideClickMonitor()
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func refreshStatusTitle() {
        let profile = store.profile(forBundleID: focus.bundleID)
        statusItem.button?.title = ""
        statusItem.button?.toolTip = focus.appName.isEmpty
            ? "Matosic Macropad — \(profile.name)"
            : "\(focus.appName) → \(profile.name)"
    }
}
