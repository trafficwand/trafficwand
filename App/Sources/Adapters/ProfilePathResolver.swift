import Foundation
import TrafficWandCore

/// Resolves the per-family `~/Library/Application Support` directory that holds a
/// browser's profile configuration (`Local State` for Chromium, `profiles.ini`
/// for Firefox), keyed on bundle identifier.
///
/// This is the seam that `ProfileReading` readers need: the App passes the real
/// per-family support directory, the readers parse whatever lives inside it.
///
/// The path mapping is **pure string building** over an injected base directory
/// (the user's Application Support folder), so it is unit-tested with a fixed base
/// and no real `~/Library` reads.
public protocol ProfilePathResolving: Sendable {
    /// The Application Support directory containing the given browser's profile
    /// configuration, or `nil` for families with no command-line profile support
    /// (Safari, unknown).
    func applicationSupportDirectory(forBundleID bundleID: String) -> URL?
}

/// Concrete `ProfilePathResolving` using the canonical macOS per-family
/// sub-paths under a base Application Support directory.
public struct ProfilePathResolver: ProfilePathResolving {
    /// The base `~/Library/Application Support` directory (injected for testing).
    private let applicationSupportDirectory: URL

    /// Canonical per-bundle-ID sub-path under Application Support (verified macOS
    /// layout). Families without a profile-config directory are simply absent.
    private static let subPathsByBundleID: [String: String] = [
        // Chromium family.
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "org.chromium.Chromium": "Chromium",
        // Firefox family.
        "org.mozilla.firefox": "Firefox"
    ]

    /// - Parameter applicationSupportDirectory: The base Application Support
    ///   directory. Defaults to the current user's real folder; tests inject a
    ///   fixed base.
    public init(applicationSupportDirectory: URL) {
        self.applicationSupportDirectory = applicationSupportDirectory
    }

    /// Convenience initializer resolving the current user's real Application
    /// Support directory. Used by the App at runtime.
    public init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        self.init(applicationSupportDirectory: base)
    }

    public func applicationSupportDirectory(forBundleID bundleID: String) -> URL? {
        guard let subPath = Self.subPathsByBundleID[bundleID] else { return nil }
        return applicationSupportDirectory.appendingPathComponent(subPath, isDirectory: true)
    }
}
