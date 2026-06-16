import Foundation

/// Where a rule (or the fallback policy) sends a link: either a concrete
/// browser/profile, or a late-bound reference to a `ProfileAlias`.
///
/// - `.browser(target)`: a concrete `BrowserTarget`.
/// - `.alias(id)`: a reference resolved against `AppConfig.aliases` at decision
///   time. A dangling reference (`id` not present in the aliases) resolves to
///   `nil`, which the router treats as "show the picker" — never a dropped or
///   mis-routed link.
///
/// Persisted inside `Rule` and `FallbackPolicy`, so the encoded shape is part of
/// the on-disk JSON format and must remain stable. Encoded as a tagged object,
/// mirroring `FallbackPolicy`:
/// - `.browser` → `{ "type": "browser", "target": { bundleID, profileID? } }`
/// - `.alias`   → `{ "type": "alias", "id": "<uuid>" }`
///
/// `init(from:)` requires the `type` discriminator: a legacy bare `BrowserTarget`
/// JSON (which has no `type` key) deliberately **fails** to decode. This lets the
/// `Rule` / `FallbackPolicy` migration decoders try `RoutingDestination` first and
/// fall back to a legacy `BrowserTarget` on failure without ambiguity.
public enum RoutingDestination: Codable, Equatable, Hashable, Sendable {
    case browser(BrowserTarget)
    case alias(UUID)

    /// Stable discriminator strings. Do not rename without a schema migration.
    private enum Kind: String, Codable {
        case browser
        case alias
    }

    /// Stable on-disk coding keys. Do not rename without a schema migration.
    private enum CodingKeys: String, CodingKey {
        case type
        case target
        case id
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // No default/leniency: a missing `type` key throws `keyNotFound(.type)`.
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .browser:
            let target = try container.decode(BrowserTarget.self, forKey: .target)
            self = .browser(target)
        case .alias:
            let id = try container.decode(UUID.self, forKey: .id)
            self = .alias(id)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .browser(let target):
            try container.encode(Kind.browser, forKey: .type)
            try container.encode(target, forKey: .target)
        case .alias(let id):
            try container.encode(Kind.alias, forKey: .type)
            try container.encode(id, forKey: .id)
        }
    }

    /// Resolve to a concrete target given the config's aliases.
    /// Returns `nil` for a dangling `.alias` reference (alias deleted/missing).
    public func resolved(in aliases: [ProfileAlias]) -> BrowserTarget? {
        switch self {
        case .browser(let target):
            return target
        case .alias(let id):
            return aliases.first { $0.id == id }?.target
        }
    }
}
