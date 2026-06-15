import Foundation

/// The persisted application configuration: the reusable profile aliases, the
/// ordered rule list, plus the fallback policy for unmatched links.
///
/// This is the root object written to `config.json`. Its coding keys are part
/// of the on-disk JSON format and must remain stable; `schemaVersion` exists to
/// support forward migration if the shape ever changes.
///
/// ## Migration (schema v1 → v2)
///
/// v1 documents have no `aliases` key, store each `Rule` with a bare `target`,
/// and store `.defaultBrowser` with a bare `target`. `init(from:)` defaults
/// `aliases` to `[]` when the key is absent; `Rule` and `FallbackPolicy` migrate
/// their own legacy shapes. New writes always use schema v2 (with `aliases` and
/// `RoutingDestination` payloads), so a load-then-save migrates the file forward
/// with no data loss.
public struct AppConfig: Codable, Equatable, Sendable {
    /// Current on-disk schema version written by this build.
    public static let currentSchemaVersion = 2

    /// Schema version of this configuration document.
    public var schemaVersion: Int
    /// Reusable, named profile aliases referenced by `RoutingDestination.alias`.
    public var aliases: [ProfileAlias]
    /// Ordered routing rules (first match wins).
    public var rules: [Rule]
    /// Policy applied to links that match no enabled rule.
    public var fallback: FallbackPolicy

    /// Stable on-disk coding keys. Do not rename without a schema migration.
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case aliases
        case rules
        case fallback
    }

    public init(
        schemaVersion: Int = AppConfig.currentSchemaVersion,
        aliases: [ProfileAlias] = [],
        rules: [Rule],
        fallback: FallbackPolicy
    ) {
        self.schemaVersion = schemaVersion
        self.aliases = aliases
        self.rules = rules
        self.fallback = fallback
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        // v1 documents have no `aliases` key — default to an empty list.
        self.aliases = try container.decodeIfPresent([ProfileAlias].self, forKey: .aliases) ?? []
        self.rules = try container.decode([Rule].self, forKey: .rules)
        self.fallback = try container.decode(FallbackPolicy.self, forKey: .fallback)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(aliases, forKey: .aliases)
        try container.encode(rules, forKey: .rules)
        try container.encode(fallback, forKey: .fallback)
    }

    /// Built-in default used when no config file exists: no aliases, no rules,
    /// picker fallback.
    public static let `default` = AppConfig(
        schemaVersion: currentSchemaVersion,
        aliases: [],
        rules: [],
        fallback: .picker
    )

    /// Returns a new config with `rule` inserted-or-updated by its `pattern`.
    ///
    /// The `pattern` string is the deduplication key, **matched
    /// case-insensitively** to mirror `GlobPattern` (rule matching is
    /// case-insensitive). If an existing rule shares the incoming rule's pattern
    /// (ignoring case), that rule's `destination` is replaced and it is re-enabled
    /// (`isEnabled = true`), keeping its position, `id`, and its original pattern
    /// string; every other rule keeps its order. If no rule has that pattern, the
    /// incoming rule is appended. This is pure: the receiver is not mutated.
    ///
    /// Because the whole `destination` is replaced, upserting a concrete
    /// `.browser` rule over an existing `.alias`-backed rule for the same pattern
    /// *demotes* it to the concrete destination — the intended "remember this
    /// site" behavior (see plan design decision #4).
    public func upserting(_ rule: Rule) -> AppConfig {
        var updated = self
        if let index = updated.rules.firstIndex(where: {
            $0.pattern.caseInsensitiveCompare(rule.pattern) == .orderedSame
        }) {
            updated.rules[index].destination = rule.destination
            updated.rules[index].isEnabled = true
        } else {
            updated.rules.append(rule)
        }
        return updated
    }
}
