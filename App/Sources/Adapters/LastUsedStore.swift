import Foundation
import TrafficWandCore

/// Persists the **last-used** routing target so the `.lastUsed` fallback policy
/// can resolve to it. Backed by `UserDefaults`.
///
/// The `UserDefaults` instance is injected so tests pass an isolated suite
/// (`UserDefaults(suiteName:)`) and never touch the host's real defaults. The app
/// uses `.standard`.
///
/// The `BrowserTarget` is `Codable`, so it is JSON-encoded to `Data` for storage —
/// a single key holds the whole value, keeping the on-disk shape and the round
/// trip trivial to reason about and test.
public struct LastUsedStore {
    /// The single defaults key holding the encoded last-used target.
    static let defaultsKey = "com.tomakado.TrafficWand.lastUsedTarget"

    private let defaults: UserDefaults

    /// - Parameter defaults: The backing store. Defaults to `.standard` for the
    ///   app; tests inject an isolated `UserDefaults(suiteName:)`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Records `target` as the most recently used routing destination.
    ///
    /// Encoding can only fail for a non-`Codable` shape, which `BrowserTarget`
    /// never is; on the impossible failure path we leave any prior value intact.
    public func set(_ target: BrowserTarget) {
        guard let data = try? JSONEncoder().encode(target) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    /// Returns the last-used target, or `nil` if none has been recorded (or a
    /// previously stored value is unreadable).
    public func get() -> BrowserTarget? {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return nil }
        return try? JSONDecoder().decode(BrowserTarget.self, from: data)
    }

    /// Forgets the last-used target (e.g. on reset). A no-op when nothing is stored.
    public func clear() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
