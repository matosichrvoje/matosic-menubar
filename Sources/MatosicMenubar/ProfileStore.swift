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
            ?? Profile(name: defaultProfileName, hint: nil, layerIndex: 0)
    }

    /// The layer index the device should be on for the given focused-app bundle ID.
    /// Falls back to the Default profile's layer when no binding matches or the
    /// matched profile somehow lacks a valid layer (defensive — shouldn't happen
    /// after migration).
    func layerIndex(forBundleID bundleID: String) -> Int {
        let p = profile(forBundleID: bundleID)
        return p.layerIndex >= 0 ? p.layerIndex : 0
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
        var p = profile
        if p.layerIndex < 0 {
            p.layerIndex = nextFreeLayerIndex(excluding: profiles.map(\.layerIndex))
        }
        profiles.append(p)
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
        self.profiles = migrateLayerIndices(onDisk.profiles)
        self.bindings = Dictionary(uniqueKeysWithValues: onDisk.bindings.map { ($0.bundleID, $0) })
        // Re-save only if migration changed anything — keeps mtime stable otherwise.
        if onDisk.profiles != self.profiles {
            save()
        }
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
        // Seed assigns each profile its firmware layer index. Index 1 is
        // reserved for the FN overlay and never used by Mac-driven SETs.
        profiles = [
            Profile(name: "Default",   hint: "Generic macros",                                       layerIndex: 0),
            Profile(name: "Photoshop", hint: "Brush size on encoder, undo / step back / layers",     layerIndex: 2),
            Profile(name: "VS Code",   hint: "Git shortcuts, jump-to-symbol, file switcher",         layerIndex: 3),
            Profile(name: "Final Cut", hint: "Scrub on encoder, in/out/blade keys",                  layerIndex: 4),
        ]
        defaultProfileName = "Default"
    }

    /// Assigns layer indices to any profile loaded from disk that lacks one
    /// (i.e. a profiles.json written by v0.1.x). Known names get their seed
    /// indices; unknown names get the next free index outside the FN slot.
    private func migrateLayerIndices(_ loaded: [Profile]) -> [Profile] {
        let seedByName: [String: Int] = [
            "Default":   0,
            "Photoshop": 2,
            "VS Code":   3,
            "Final Cut": 4,
        ]
        // First pass: keep already-assigned indices; apply seed for known names.
        var used = Set<Int>()
        var result: [Profile] = loaded.map { profile in
            var p = profile
            if p.layerIndex < 0 {
                if let seed = seedByName[p.name] {
                    p.layerIndex = seed
                }
            }
            if p.layerIndex >= 0 { used.insert(p.layerIndex) }
            return p
        }
        // Second pass: assign next-free indices to anything still unassigned.
        for i in result.indices where result[i].layerIndex < 0 {
            let next = nextFreeLayerIndex(excluding: Array(used))
            result[i].layerIndex = next
            used.insert(next)
        }
        return result
    }

    private func nextFreeLayerIndex(excluding taken: [Int]) -> Int {
        let usedSet = Set(taken)
        for candidate in 0...MacropadProtocol.maxLayerIndex {
            if candidate == MacropadProtocol.reservedFnLayerIndex { continue }
            if !usedSet.contains(candidate) { return candidate }
        }
        // All slots full — overflow to maxLayerIndex (clamped). The device
        // will reject a SET to an out-of-range layer, which the UI can
        // surface later. For v0.3 we have headroom (4 user slots) for the
        // 3 seeded user profiles plus growth.
        return MacropadProtocol.maxLayerIndex
    }
}
