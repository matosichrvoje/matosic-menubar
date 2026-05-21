import Foundation

struct Profile: Codable, Hashable, Identifiable {
    var id: String { name }
    var name: String
    var hint: String?
}

struct ProfileBinding: Codable, Hashable {
    var bundleID: String
    var appName: String
    var profileName: String
}
