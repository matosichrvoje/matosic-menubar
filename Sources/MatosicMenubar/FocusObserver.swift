import AppKit
import Combine

@MainActor
final class FocusObserver: ObservableObject {
    @Published private(set) var bundleID: String = ""
    @Published private(set) var appName: String = "—"

    private var observer: NSObjectProtocol?

    init() {
        publishCurrent()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                self?.publish(app: app)
            }
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private func publishCurrent() {
        if let app = NSWorkspace.shared.frontmostApplication {
            publish(app: app)
        }
    }

    private func publish(app: NSRunningApplication) {
        self.bundleID = app.bundleIdentifier ?? ""
        self.appName = app.localizedName ?? bundleID
    }
}
