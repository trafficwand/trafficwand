import Foundation

/// What to do with a link that matches no enabled rule.
///
/// - `.picker`: present the interactive browser/profile picker.
/// - `.defaultBrowser(destination)`: open in a single configured destination —
///   either a concrete browser/profile or a late-bound `RoutingDestination.alias`
///   reference (a dangling alias resolves to the picker in `Router.decide`).
/// - `.lastUsed`: reuse the most recently used target. With nothing recorded
///   yet, the router falls back to the picker — the picker is always the
///   ultimate fallback, so this case needs no nested default.
///
/// Persisted, so the encoded shape is part of the on-disk JSON format and must
/// remain stable. Encoded as a tagged object: `{ "type": <case>, ... }`. Only
/// `.defaultBrowser` carries a nested `target` payload.
///
/// ## Migration (schema v1 → v2)
///
/// In v1 the `.defaultBrowser` `target` key held a bare `BrowserTarget`. In v2 it
/// holds a `RoutingDestination` (tagged object). `init(from:)` decodes the
/// `target` key by trying `RoutingDestination` first and, on failure, falling
/// back to a legacy `BrowserTarget` wrapped as `.browser(...)`. This ordering is
/// unambiguous: a legacy `BrowserTarget` has no `type` discriminator, so it
/// deliberately fails to decode as `RoutingDestination` (pinned by
/// `RoutingDestination`'s negative-decode test). `encode(to:)` always writes the
/// v2 `RoutingDestination` shape.
public enum FallbackPolicy: Codable, Equatable, Hashable, Sendable {
    case picker
    case defaultBrowser(RoutingDestination)
    case lastUsed

    /// Stable discriminator strings. Do not rename without a schema migration.
    private enum Kind: String, Codable {
        case picker
        case defaultBrowser
        case lastUsed
    }

    /// Stable on-disk coding keys. Do not rename without a schema migration.
    private enum CodingKeys: String, CodingKey {
        case type
        case target
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .picker:
            self = .picker
        case .lastUsed:
            self = .lastUsed
        case .defaultBrowser:
            // Try the v2 RoutingDestination shape first; fall back to a legacy
            // bare BrowserTarget wrapped as `.browser(...)`. Unambiguous because
            // a legacy BrowserTarget has no `type` key and so fails to decode as
            // a RoutingDestination.
            if let destination = try? container.decode(RoutingDestination.self, forKey: .target) {
                self = .defaultBrowser(destination)
            } else {
                let target = try container.decode(BrowserTarget.self, forKey: .target)
                self = .defaultBrowser(.browser(target))
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .picker:
            try container.encode(Kind.picker, forKey: .type)
        case .lastUsed:
            try container.encode(Kind.lastUsed, forKey: .type)
        case .defaultBrowser(let destination):
            try container.encode(Kind.defaultBrowser, forKey: .type)
            try container.encode(destination, forKey: .target)
        }
    }
}
