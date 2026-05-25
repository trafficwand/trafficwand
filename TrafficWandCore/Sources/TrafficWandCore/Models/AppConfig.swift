import Foundation

/// The persisted application configuration: the ordered rule list plus the
/// fallback policy for unmatched links.
///
/// This is the root object written to `config.json`. Its coding keys are part
/// of the on-disk JSON format and must remain stable; `schemaVersion` exists to
/// support forward migration if the shape ever changes.
public struct AppConfig: Codable, Equatable, Sendable {
    /// Current on-disk schema version written by this build.
    public static let currentSchemaVersion = 1

    /// Schema version of this configuration document.
    public var schemaVersion: Int
    /// Ordered routing rules (first match wins).
    public var rules: [Rule]
    /// Policy applied to links that match no enabled rule.
    public var fallback: FallbackPolicy

    /// Stable on-disk coding keys. Do not rename without a schema migration.
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case rules
        case fallback
    }

    public init(schemaVersion: Int = AppConfig.currentSchemaVersion, rules: [Rule], fallback: FallbackPolicy) {
        self.schemaVersion = schemaVersion
        self.rules = rules
        self.fallback = fallback
    }

    /// Built-in default used when no config file exists: no rules, picker fallback.
    public static let `default` = AppConfig(
        schemaVersion: currentSchemaVersion,
        rules: [],
        fallback: .picker
    )
}
