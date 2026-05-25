import Foundation

/// The profile-discovery seam for a single browser family.
///
/// A `ProfileReading` parses a browser's on-disk profile configuration into a
/// list of `BrowserProfile`s. Parsing is **pure**: the only input is the base
/// directory whose contents are read (Foundation file reads only, no AppKit).
///
/// The base directory is **injected** so the App can pass the real per-family
/// `~/Library/Application Support/<browser>` path, while tests pass a fixture or
/// temporary directory. Concrete readers (`ChromeProfileReader`,
/// `FirefoxProfileReader`) know which file inside that directory to read.
///
/// Behavior contract:
/// - A **missing** configuration file returns `[]` (an absent browser/profile
///   set is not an error).
/// - A **garbled/unparseable** configuration returns `[]` rather than crashing;
///   discovery is best-effort and must never take down routing.
public protocol ProfileReading: Sendable {
    /// Reads the browser's profiles from its configuration under `applicationSupportDirectory`.
    ///
    /// - Parameter applicationSupportDirectory: The per-family Application Support
    ///   directory that contains the profile configuration file.
    /// - Returns: The discovered profiles, or `[]` if the configuration is missing
    ///   or cannot be parsed.
    /// - Throws: Only unexpected I/O errors; missing/garbled configuration must
    ///   resolve to `[]`, not a thrown error.
    func readProfiles(applicationSupportDirectory: URL) throws -> [BrowserProfile]
}
