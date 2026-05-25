import Foundation

/// A routing destination: a specific browser, and optionally a specific profile
/// within it.
///
/// Persisted inside `Rule` and `FallbackPolicy`, so its coding keys are part of
/// the on-disk JSON format and must remain stable. `profileID` encodes to an
/// absent key when `nil` (rather than an explicit `null`), keeping the on-disk
/// shape minimal for browsers without profile support.
public struct BrowserTarget: Codable, Equatable, Hashable, Sendable {
    /// Bundle identifier of the target browser.
    public let bundleID: String
    /// Family-native profile identifier, or `nil` to launch the default profile.
    public let profileID: String?

    /// Stable on-disk coding keys. Do not rename without a schema migration.
    private enum CodingKeys: String, CodingKey {
        case bundleID
        case profileID
    }

    public init(bundleID: String, profileID: String?) {
        self.bundleID = bundleID
        self.profileID = profileID
    }
}
