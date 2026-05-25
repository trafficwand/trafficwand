import Foundation

/// An installed browser discovered on the system, with its known profiles.
///
/// Not persisted in the config file — it is derived at runtime from the system
/// browser provider and profile readers — but kept `Codable` so it can travel
/// across boundaries (e.g. into the picker) uniformly.
public struct Browser: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// Bundle identifier of the browser application.
    public let bundleID: String
    /// Human-readable application name.
    public let name: String
    /// Location of the application bundle on disk.
    public let appURL: URL
    /// Profiles discovered for this browser (empty if none / unsupported family).
    public let profiles: [BrowserProfile]

    /// `Identifiable` conformance keyed on the stable bundle identifier.
    public var id: String { bundleID }

    public init(bundleID: String, name: String, appURL: URL, profiles: [BrowserProfile]) {
        self.bundleID = bundleID
        self.name = name
        self.appURL = appURL
        self.profiles = profiles
    }
}
