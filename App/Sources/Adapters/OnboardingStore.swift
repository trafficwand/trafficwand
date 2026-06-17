import Foundation

/// Persists the **first-launch onboarding** completion flag so the onboarding
/// flow is shown exactly once. Backed by `UserDefaults`.
///
/// The `UserDefaults` instance is injected so tests pass an isolated suite
/// (`UserDefaults(suiteName:)`) and never touch the host's real defaults. The app
/// uses `.standard`. A single boolean key holds the whole state, keeping the
/// on-disk shape and the round trip trivial to reason about and test (mirrors
/// `LastUsedStore`).
public struct OnboardingStore {
    /// The single defaults key holding the onboarding-completed flag.
    static let defaultsKey = "io.tomakado.TrafficWand.onboardingCompleted"

    private let defaults: UserDefaults

    /// - Parameter defaults: The backing store. Defaults to `.standard` for the
    ///   app; tests inject an isolated `UserDefaults(suiteName:)`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether onboarding has already been completed. Defaults to `false` (not
    /// completed) when the key is absent — i.e. a fresh install.
    public var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: Self.defaultsKey)
    }

    /// Marks onboarding as completed. Idempotent: writing `true` again is a no-op
    /// in effect.
    public func markCompleted() {
        defaults.set(true, forKey: Self.defaultsKey)
    }
}
