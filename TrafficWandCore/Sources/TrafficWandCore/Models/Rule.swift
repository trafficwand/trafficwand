import Foundation

/// What part of a URL a glob pattern is matched against.
///
/// v1 matches the **host** only; full-URL (path) scope is a documented future
/// extension. Defined here so a `scope` field can be added to `Rule` later
/// without reshaping the type.
public enum GlobScope: String, Codable, Equatable, Hashable, Sendable {
    case host
}

/// A user-defined routing rule: a glob pattern paired with the browser/profile
/// target to use when it matches.
///
/// Rules are evaluated in order (first match wins). Persisted, so its coding
/// keys are part of the on-disk JSON format and must remain stable.
public struct Rule: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// Stable unique identifier (also used for SwiftUI list identity).
    public let id: UUID
    /// Glob pattern matched against the URL host (see `GlobScope`).
    public var pattern: String
    /// Destination browser/profile when this rule matches.
    public var target: BrowserTarget
    /// Whether this rule participates in matching. Disabled rules are skipped.
    public var isEnabled: Bool

    /// Stable on-disk coding keys. Do not rename without a schema migration.
    private enum CodingKeys: String, CodingKey {
        case id
        case pattern
        case target
        case isEnabled
    }

    public init(id: UUID = UUID(), pattern: String, target: BrowserTarget, isEnabled: Bool = true) {
        self.id = id
        self.pattern = pattern
        self.target = target
        self.isEnabled = isEnabled
    }
}
