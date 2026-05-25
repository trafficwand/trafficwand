import Foundation

/// A discovered profile within a browser.
///
/// `id` is the family-native identifier used to launch into the profile:
/// the Chrome profile **directory name** (e.g. `"Default"`, `"Profile 1"`) or
/// the Firefox **profile name** (e.g. `"Personal"`). `name` is the display
/// label shown to the user.
public struct BrowserProfile: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// Family-native profile identifier (Chrome dir name / Firefox profile name).
    public let id: String
    /// Human-readable display name.
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
