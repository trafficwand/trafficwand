import Foundation

/// What to do with a link that matches no enabled rule.
///
/// - `.picker`: present the interactive browser/profile picker.
/// - `.defaultBrowser(target)`: open in a single configured browser/profile.
/// - `.lastUsed`: reuse the most recently used target. With nothing recorded
///   yet, the router falls back to the picker — the picker is always the
///   ultimate fallback, so this case needs no nested default.
///
/// Persisted, so the encoded shape is part of the on-disk JSON format and must
/// remain stable. Encoded as a tagged object: `{ "type": <case>, ... }`. Only
/// `.defaultBrowser` carries a nested `target` payload.
public enum FallbackPolicy: Codable, Equatable, Hashable, Sendable {
    case picker
    case defaultBrowser(BrowserTarget)
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
            let target = try container.decode(BrowserTarget.self, forKey: .target)
            self = .defaultBrowser(target)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .picker:
            try container.encode(Kind.picker, forKey: .type)
        case .lastUsed:
            try container.encode(Kind.lastUsed, forKey: .type)
        case .defaultBrowser(let target):
            try container.encode(Kind.defaultBrowser, forKey: .type)
            try container.encode(target, forKey: .target)
        }
    }
}
