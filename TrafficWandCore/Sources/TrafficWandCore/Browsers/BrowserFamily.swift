import Foundation

/// The browser engine family a bundle identifier belongs to.
///
/// Family determines how a profile is selected on the command line: the Chromium
/// family takes `--profile-directory=<dir>`, Firefox takes `-P <name>`, and Safari
/// (and everything unknown) has no command-line profile selection. The concrete
/// argv tail is built by `LaunchArguments`; this enum is the lookup that drives it.
///
/// The bundle-ID allowlists below come from the launch-mechanism spike (§4) and
/// are the single source of truth — extend them here when adding browser support.
public enum BrowserFamily: Equatable, Sendable {
    /// Chromium-based browsers (Chrome, Edge, Brave, Vivaldi, Chromium, …).
    case chromium
    /// Mozilla Firefox.
    case firefox
    /// Apple Safari (no command-line profile selection).
    case safari
    /// Any browser not in a known family; treated like Safari for launch args.
    case other

    /// Chromium-family bundle identifiers (spike §4).
    private static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "org.chromium.Chromium",
    ]

    /// Firefox-family bundle identifiers (spike §4).
    private static let firefoxBundleIDs: Set<String> = [
        "org.mozilla.firefox",
    ]

    /// Safari bundle identifier.
    private static let safariBundleID = "com.apple.Safari"

    /// Maps a bundle identifier to its browser family.
    ///
    /// Matching is exact (case-sensitive reverse-DNS); anything not in a known
    /// allowlist maps to `.other`.
    public init(bundleID: String) {
        if BrowserFamily.chromiumBundleIDs.contains(bundleID) {
            self = .chromium
        } else if BrowserFamily.firefoxBundleIDs.contains(bundleID) {
            self = .firefox
        } else if bundleID == BrowserFamily.safariBundleID {
            self = .safari
        } else {
            self = .other
        }
    }
}
