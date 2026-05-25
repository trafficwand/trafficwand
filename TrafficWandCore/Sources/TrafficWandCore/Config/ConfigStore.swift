import Foundation

/// The persistence seam for the application configuration.
///
/// This protocol isolates `AppConfig` persistence from the filesystem so the
/// decision/UI layers can be exercised with in-memory or mock stores. The App
/// injects the concrete `FileConfigStore`, pointing at
/// `~/Library/Application Support/TrafficWand`; tests inject a temp directory.
public protocol ConfigStore: Sendable {
    /// Loads the stored configuration.
    ///
    /// - Returns: The persisted configuration, or `AppConfig.default` if nothing
    ///   has been stored yet.
    /// - Throws: `ConfigStoreError.corruptConfiguration` if a config exists but
    ///   cannot be decoded; underlying I/O errors otherwise.
    func load() throws -> AppConfig

    /// Persists the configuration.
    ///
    /// Implementations must be atomic: a failed save must leave any
    /// previously-saved configuration intact.
    ///
    /// - Parameter config: The configuration to persist.
    /// - Throws: An error if the write fails.
    func save(_ config: AppConfig) throws
}

/// Errors surfaced by a `ConfigStore` that callers can recover from.
public enum ConfigStoreError: Error, Equatable, Sendable {
    /// A configuration file exists on disk but could not be decoded.
    ///
    /// This is recoverable: the corrupt file is backed up aside (see
    /// `FileConfigStore`) and the caller may fall back to `AppConfig.default`
    /// and re-save a fresh configuration.
    case corruptConfiguration
}
