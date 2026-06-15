import Foundation

/// A named, reusable binding to a concrete browser/profile target.
///
/// Aliases act as live references ("variables"): rules and the fallback policy
/// point at an alias by `id` (via `RoutingDestination.alias`), and re-pointing
/// the alias at a different `target` updates every referencing rule at once.
///
/// Persisted inside `AppConfig.aliases`, so its coding keys are part of the
/// on-disk JSON format and must remain stable. Do not rename without a schema
/// migration.
public struct ProfileAlias: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// Stable unique identifier referenced by `RoutingDestination.alias`.
    public let id: UUID
    /// User-facing display name (e.g. "Personal", "Work").
    public var name: String
    /// The concrete browser/profile this alias currently resolves to.
    public var target: BrowserTarget

    /// Stable on-disk coding keys. Do not rename without a schema migration.
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case target
    }

    public init(id: UUID = UUID(), name: String, target: BrowserTarget) {
        self.id = id
        self.name = name
        self.target = target
    }
}
