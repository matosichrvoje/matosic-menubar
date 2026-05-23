import Foundation

struct Profile: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var hint: String?
    // Device-layer index this profile maps to. 0 = BASE, 1 = FN
    // (reserved overlay — never assigned), 2..5 = USER1..USER4.
    // -1 is a migration sentinel: profiles loaded from a pre-v0.3
    // profiles.json have no layer field, and ProfileStore.load()
    // assigns one before publishing.
    var layerIndex: Int

    init(name: String, hint: String? = nil, layerIndex: Int = -1) {
        self.name = name
        self.hint = hint
        self.layerIndex = layerIndex
    }

    private enum CodingKeys: String, CodingKey {
        case name, hint, layerIndex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decode(String.self, forKey: .name)
        self.hint = try c.decodeIfPresent(String.self, forKey: .hint)
        self.layerIndex = try c.decodeIfPresent(Int.self, forKey: .layerIndex) ?? -1
    }
}

struct ProfileBinding: Codable, Hashable {
    var bundleID: String
    var appName: String
    var profileName: String
}
