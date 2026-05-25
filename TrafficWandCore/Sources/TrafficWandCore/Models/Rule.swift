import Foundation

// Future extension: a `GlobScope` (e.g. `.host` / `.fullURL`) plus a `Rule.scope`
// field can be added with a schema bump when full-URL matching lands. v1 matches
// the host only, so no scope type is needed yet.

/// A user-defined routing rule: a glob pattern paired with the browser/profile
/// target to use when it matches.
///
/// Rules are evaluated in order (first match wins). Persisted, so its coding
/// keys are part of the on-disk JSON format and must remain stable.
public struct Rule: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// Stable unique identifier (also used for SwiftUI list identity).
    public let id: UUID
    /// Glob pattern matched against the URL host (host scope only in v1).
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
