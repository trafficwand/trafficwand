import Foundation

/// An installed browser discovered on the system, with its known profiles.
///
/// Not persisted — it is derived at runtime from the system browser provider and
/// profile readers — so it is intentionally **not** `Codable`. It conforms to
/// `Equatable`/`Hashable`/`Identifiable`/`Sendable` for SwiftUI lists and tests.
public struct Browser: Equatable, Hashable, Identifiable, Sendable {
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
