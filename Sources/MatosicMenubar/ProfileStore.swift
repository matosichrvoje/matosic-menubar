import Foundation
import Combine

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var bindings: [String: ProfileBinding] = [:]
    @Published private(set) var defaultProfileName: String = "Default"

    private let storeURL: URL

    init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Matosic Macropad", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storeURL = dir.appendingPathComponent("profiles.json")
        load()
    }

    func profile(forBundleID bundleID: String) -> Profile {
        let name = bindings[bundleID]?.profileName ?? defaultProfileName
        return profiles.first(where: { $0.name == name })
            ?? Profile(name: defaultProfileName, hint: nil)
    }

    func bind(bundleID: String, appName: String, to profileName: String) {
        bindings[bundleID] = ProfileBinding(
            bundleID: bundleID,
            appName: appName,
            profileName: profileName
        )
        save()
    }

    func unbind(bundleID: String) {
        bindings.removeValue(forKey: bundleID)
        save()
    }

    func addProfile(_ profile: Profile) {
        guard !profiles.contains(where: { $0.name == profile.name }) else { return }
        profiles.append(profile)
        save()
    }

    // MARK: persistence

    private struct OnDisk: Codable {
        var defaultProfileName: String
        var profiles: [Profile]
        var bindings: [ProfileBinding]
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let onDisk = try? JSONDecoder().decode(OnDisk.self, from: data) else {
            seedDefaults()
            save()
            return
        }
        self.defaultProfileName = onDisk.defaultProfileName
        self.profiles = onDisk.profiles
        self.bindings = Dictionary(uniqueKeysWithValues: onDisk.bindings.map { ($0.bundleID, $0) })
    }

    private func save() {
        let onDisk = OnDisk(
            defaultProfileName: defaultProfileName,
            profiles: profiles,
            bindings: Array(bindings.values).sorted { $0.appName < $1.appName }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(onDisk) else { return }
        try? data.write(to: storeURL, options: [.atomic])
    }

    private func seedDefaults() {
        profiles = [
            Profile(name: "Default", hint: "Generic macros"),
            Profile(name: "Photoshop", hint: "Brush size on encoder, undo / step back / layers"),
            Profile(name: "VS Code", hint: "Git shortcuts, jump-to-symbol, file switcher"),
            Profile(name: "Final Cut", hint: "Scrub on encoder, in/out/blade keys"),
        ]
        defaultProfileName = "Default"
    }
}
