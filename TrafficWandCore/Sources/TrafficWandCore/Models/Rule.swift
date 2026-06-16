import Foundation

/// A user-defined routing rule: a glob pattern paired with the destination
/// (a concrete browser/profile, or a late-bound alias reference) to use when it
/// matches.
///
/// Rules are evaluated in order (first match wins). Persisted, so its coding
/// keys are part of the on-disk JSON format and must remain stable.
///
/// ## Migration (schema v1 → v2)
///
/// In v1 a rule stored a bare `target: BrowserTarget`. In v2 it stores a
/// `destination: RoutingDestination` (which can wrap either a concrete browser
/// or an alias reference). `init(from:)` is backward-compatible: it prefers the
/// v2 `destination` key, and if it is absent decodes the legacy `target`
/// (`BrowserTarget`) and wraps it as `.browser(...)`. `encode(to:)` always writes
/// the v2 `destination` shape, so a load-then-save migrates the file forward with
/// no data loss.
public struct Rule: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// Stable unique identifier (also used for SwiftUI list identity).
    public let id: UUID
    /// Glob pattern matched against the URL host (host scope only in v1).
    public var pattern: String
    /// Destination (browser/profile or alias reference) when this rule matches.
    public var destination: RoutingDestination
    /// Whether this rule participates in matching. Disabled rules are skipped.
    public var isEnabled: Bool

    /// Stable on-disk coding keys. Do not rename without a schema migration.
    /// `target` is the legacy (v1) key, decoded only for backward compatibility.
    private enum CodingKeys: String, CodingKey {
        case id
        case pattern
        case destination
        case target
        case isEnabled
    }

    public init(
        id: UUID = UUID(),
        pattern: String,
        destination: RoutingDestination,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.pattern = pattern
        self.destination = destination
        self.isEnabled = isEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.pattern = try container.decode(String.self, forKey: .pattern)
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        // Prefer the v2 `destination` key; fall back to the legacy `target`
        // (a bare BrowserTarget) wrapped as `.browser(...)`.
        if let destination = try container.decodeIfPresent(RoutingDestination.self, forKey: .destination) {
            self.destination = destination
        } else {
            let target = try container.decode(BrowserTarget.self, forKey: .target)
            self.destination = .browser(target)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(pattern, forKey: .pattern)
        try container.encode(destination, forKey: .destination)
        try container.encode(isEnabled, forKey: .isEnabled)
    }
}
