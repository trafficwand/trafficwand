import Foundation

/// The browser engine family a bundle identifier belongs to.
///
/// Family determines how a profile is selected on the command line: the Chromium
/// family takes `--profile-directory=<dir>`, Firefox takes `-P <name>`, and Safari
/// has no command-line profile selection. The concrete argv tail is built by
/// `LaunchArguments`; this enum is the lookup that drives it.
///
/// **Chromium is the default family.** Nearly every modern non-Safari/non-Firefox
/// browser is Chromium-based, so any bundle ID not on the Firefox or Safari lists
/// maps to `.chromium`. This means any Chromium-based browser we haven't explicitly
/// named still launches correctly with Chromium-style profile selection.
///
/// The Firefox/Safari bundle-ID allowlists below come from the launch-mechanism
/// spike (§4) and are the single source of truth for the non-default families —
/// extend the Firefox set here when adding a Firefox-fork browser. Chromium needs
/// no allowlist: it is the catch-all default.
///
/// **Listing vs. launching.** Family classification is permissive (unknown ⇒
/// `.chromium`) so anything we route to launches correctly. *Which* apps appear in
/// the picker is a separate, curated decision: `knownBrowserBundleIDs` /
/// `isKnownBrowser(bundleID:)`. `NSWorkspace`'s http(s)-handler enumeration returns
/// non-browsers too — terminals (iTerm, kitty), Electron apps, and TrafficWand
/// itself all register as http(s) handlers — so the picker filters to this
/// allowlist while launch stays permissive.
public enum BrowserFamily: Equatable, Sendable {
    /// Chromium-based browsers (Chrome, Edge, Brave, Vivaldi, Chromium, …) and the
    /// default for any browser not explicitly classified as Firefox or Safari.
    case chromium
    /// Mozilla Firefox and Firefox forks (e.g. Zen).
    case firefox
    /// Apple Safari (no command-line profile selection).
    case safari

    /// Firefox-family bundle identifiers (spike §4). Includes Zen, a Firefox fork.
    private static let firefoxBundleIDs: Set<String> = [
        "org.mozilla.firefox",
        "app.zen-browser.zen"
    ]

    /// Safari bundle identifier.
    private static let safariBundleID = "com.apple.Safari"

    /// Chromium-family browsers TrafficWand surfaces in the picker. These all
    /// classify as `.chromium` via the catch-all default, so this set is
    /// **display-only** — it does not affect launch-arg construction.
    private static let chromiumBrowserBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "org.chromium.Chromium",
        "company.thebrowser.Browser",   // Arc
        "ai.perplexity.comet",          // Comet
        "company.thebrowser.dia",       // Dia
        "net.imput.helium"              // Helium
    ]

    /// Bundle identifiers of the browsers TrafficWand surfaces in the picker.
    ///
    /// Chromium remains the launch default for *any* unknown bundle ID, but only
    /// these curated, real browsers are *listed* — keeping non-browser http(s)
    /// handlers (terminals, Electron apps, TrafficWand itself) out of the picker.
    public static let knownBrowserBundleIDs: Set<String> = chromiumBrowserBundleIDs
        .union(firefoxBundleIDs)
        .union([safariBundleID])

    /// Whether `bundleID` is a browser TrafficWand surfaces in the picker.
    ///
    /// This gates *listing*, not *launching*: an unknown bundle ID still launches
    /// as Chromium (see `init(bundleID:)`), it is simply not offered in the picker.
    public static func isKnownBrowser(bundleID: String) -> Bool {
        knownBrowserBundleIDs.contains(bundleID)
    }

    /// Maps a bundle identifier to its browser family.
    ///
    /// Matching is exact (case-sensitive reverse-DNS). Firefox and Safari are
    /// matched against their allowlists; **anything else defaults to `.chromium`**,
    /// since nearly every modern non-Safari/non-Firefox browser is Chromium-based.
    public init(bundleID: String) {
        if BrowserFamily.firefoxBundleIDs.contains(bundleID) {
            self = .firefox
        } else if bundleID == BrowserFamily.safariBundleID {
            self = .safari
        } else {
            self = .chromium
        }
    }
}
