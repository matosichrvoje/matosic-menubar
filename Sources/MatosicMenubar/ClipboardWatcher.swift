import AppKit
import Combine

/// Optional clipboard-image logger. OFF by default — only polls the pasteboard
/// when the user explicitly toggles it on from the popover.
///
/// When enabled, polls `NSPasteboard.general` every ~1.5s. Detects new clipboard
/// contents via `changeCount`; if the new content includes an image (PNG or TIFF),
/// saves a PNG copy under `~/Pictures/matosic-blog/YYYY-MM-DD/HHMMSS.png`.
///
/// Setting is persisted in `UserDefaults` so it survives relaunches.
@MainActor
final class ClipboardWatcher: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            isEnabled ? start() : stop()
        }
    }
    @Published private(set) var savedCount: Int = 0
    @Published private(set) var lastError: String?
    /// Absolute path of the save directory. Persisted in UserDefaults so a user's
    /// custom pick (e.g. an iCloud-synced folder) survives relaunches and works
    /// the same on both their Macs when the same path exists there.
    @Published private(set) var saveDirectoryPath: String

    private var timer: Timer?
    private var lastChangeCount: Int = 0

    private static let enabledKey = "ClipboardWatcher.enabled"
    private static let saveDirKey = "ClipboardWatcher.saveDirectoryPath"
    private static let pollInterval: TimeInterval = 1.5

    /// Fallback save dir when the user hasn't picked one yet. `~/Pictures/matosic-blog/`.
    private static var defaultSaveBaseDirectory: URL {
        FileManager.default
            .urls(for: .picturesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("matosic-blog")
    }

    init() {
        let enabledStored = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let pathStored = UserDefaults.standard.string(forKey: Self.saveDirKey)
        self.isEnabled = enabledStored
        self.saveDirectoryPath = pathStored ?? Self.defaultSaveBaseDirectory.path
        self.lastChangeCount = NSPasteboard.general.changeCount
        if enabledStored {
            start()
        }
    }

    deinit {
        timer?.invalidate()
    }

    /// Tilde-abbreviated path shown in the popover.
    /// `/Users/me/Desktop/Foo` → `~/Desktop/Foo`.
    var displayPath: String {
        (saveDirectoryPath as NSString).abbreviatingWithTildeInPath
    }

    var saveBaseDirectory: URL {
        URL(fileURLWithPath: saveDirectoryPath)
    }

    func setSaveDirectory(_ url: URL) {
        saveDirectoryPath = url.path
        UserDefaults.standard.set(url.path, forKey: Self.saveDirKey)
    }

    /// Opens an NSOpenPanel for folder selection. The popover will close when
    /// the panel becomes key — that's standard macOS behavior. Reopen after.
    func pickSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = saveBaseDirectory
        panel.message = "Choose where clipboard images get saved"
        panel.prompt = "Use this folder"

        if panel.runModal() == .OK, let url = panel.url {
            setSaveDirectory(url)
        }
    }

    func revealInFinder() {
        try? FileManager.default.createDirectory(
            at: saveBaseDirectory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(saveBaseDirectory)
    }

    private func start() {
        stop()
        lastChangeCount = NSPasteboard.general.changeCount
        let t = Timer.scheduledTimer(
            withTimeInterval: Self.pollInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
        timer = t
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pb = NSPasteboard.general
        let cur = pb.changeCount
        guard cur != lastChangeCount else { return }
        lastChangeCount = cur

        // Prefer PNG; fall back to TIFF re-encoded to PNG. Skip if neither.
        let pngData: Data?
        if let direct = pb.data(forType: .png) {
            pngData = direct
        } else if let tiff = pb.data(forType: .tiff),
                  let rep = NSBitmapImageRep(data: tiff) {
            pngData = rep.representation(using: .png, properties: [:])
        } else {
            pngData = nil
        }
        guard let data = pngData else { return }
        save(pngData: data)
    }

    private func save(pngData: Data) {
        let now = Date()
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HHmmss"

        let dayDir = saveBaseDirectory
            .appendingPathComponent(dayFmt.string(from: now))

        do {
            try FileManager.default.createDirectory(
                at: dayDir,
                withIntermediateDirectories: true
            )
            let base = timeFmt.string(from: now)
            var url = dayDir.appendingPathComponent("\(base).png")
            // Two screenshots in the same second get suffixed _1, _2, ...
            var counter = 1
            while FileManager.default.fileExists(atPath: url.path) {
                url = dayDir.appendingPathComponent("\(base)_\(counter).png")
                counter += 1
            }
            try pngData.write(to: url)
            savedCount += 1
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
