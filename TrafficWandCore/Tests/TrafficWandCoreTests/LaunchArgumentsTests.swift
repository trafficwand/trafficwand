import Foundation
import Testing
@testable import TrafficWandCore

@Suite("BrowserFamily mapping from bundle ID")
struct BrowserFamilyTests {
    @Test(
        "Chromium bundle IDs map to .chromium",
        arguments: [
            "com.google.Chrome",
            "com.google.Chrome.beta",
            "com.google.Chrome.canary",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.vivaldi.Vivaldi",
            "org.chromium.Chromium",
            "net.imput.helium"              // Helium
        ]
    )
    func chromiumBundleIDs(_ bundleID: String) {
        #expect(BrowserFamily(bundleID: bundleID) == .chromium)
    }

    @Test("Firefox bundle ID maps to .firefox")
    func firefoxBundleID() {
        #expect(BrowserFamily(bundleID: "org.mozilla.firefox") == .firefox)
    }

    @Test("Safari bundle ID maps to .safari")
    func safariBundleID() {
        #expect(BrowserFamily(bundleID: "com.apple.Safari") == .safari)
    }

    @Test("Zen (a Firefox fork) maps to .firefox")
    func zenBundleID() {
        #expect(BrowserFamily(bundleID: "app.zen-browser.zen") == .firefox)
    }

    @Test("An unknown bundle ID defaults to .chromium")
    func unknownBundleID() {
        #expect(BrowserFamily(bundleID: "com.example.SomeBrowser") == .chromium)
    }

    @Test("An empty bundle ID defaults to .chromium")
    func emptyBundleID() {
        #expect(BrowserFamily(bundleID: "") == .chromium)
    }

    @Test(
        "Curated browsers are recognized by isKnownBrowser",
        arguments: [
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
            "net.imput.helium",             // Helium
            "org.mozilla.firefox",
            "app.zen-browser.zen",          // Zen
            "com.apple.Safari"
        ]
    )
    func knownBrowsers(_ bundleID: String) {
        #expect(BrowserFamily.isKnownBrowser(bundleID: bundleID))
    }

    @Test(
        "Non-browser http handlers and TrafficWand itself are not known browsers",
        arguments: [
            "com.googlecode.iterm2",    // iTerm
            "net.kovidgoyal.kitty",     // kitty
            "io.tomakado.TrafficWand",  // self
            "com.example.SomeBrowser",  // arbitrary unknown
            ""
        ]
    )
    func unknownAppsAreNotKnownBrowsers(_ bundleID: String) {
        #expect(!BrowserFamily.isKnownBrowser(bundleID: bundleID))
    }

    @Test("isKnownBrowser is case-sensitive on the exact reverse-DNS bundle ID")
    func isKnownBrowserCaseSensitive() {
        #expect(!BrowserFamily.isKnownBrowser(bundleID: "COM.GOOGLE.CHROME"))
    }

    @Test("Mapping is case-sensitive on the exact reverse-DNS bundle ID")
    func caseSensitiveMapping() {
        // Bundle IDs are matched exactly; a differently-cased string is not a
        // known browser and falls through to the .chromium default.
        #expect(BrowserFamily(bundleID: "COM.GOOGLE.CHROME") == .chromium)
    }
}

@Suite("LaunchArguments argv tail (spike §4 contract)")
struct LaunchArgumentsTests {
    private let url = URL(string: "https://x/")!

    // MARK: Chromium

    @Test("Chromium with a profile → --profile-directory=<dir> then URL last")
    func chromiumWithProfile() {
        let target = BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 1")
        #expect(
            LaunchArguments.build(for: target, url: url)
                == ["--profile-directory=Profile 1", "https://x/"]
        )
    }

    @Test("Every Chromium bundle ID honors the profile flag")
    func chromiumFamilyHonorsProfileFlag() {
        let bundleIDs = [
            "com.google.Chrome",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.vivaldi.Vivaldi",
            "org.chromium.Chromium"
        ]
        for bundleID in bundleIDs {
            let target = BrowserTarget(bundleID: bundleID, profileID: "Default")
            #expect(
                LaunchArguments.build(for: target, url: url)
                    == ["--profile-directory=Default", "https://x/"]
            )
        }
    }

    @Test("Chromium without a profile → just the URL")
    func chromiumNoProfile() {
        let target = BrowserTarget(bundleID: "com.google.Chrome", profileID: nil)
        #expect(LaunchArguments.build(for: target, url: url) == ["https://x/"])
    }

    @Test("Chromium with an empty profileID is treated as no profile (no empty flag)")
    func chromiumEmptyProfileTreatedAsNoProfile() {
        // An empty profileID must NOT produce a broken `--profile-directory=` flag.
        let empty = BrowserTarget(bundleID: "com.google.Chrome", profileID: "")
        #expect(LaunchArguments.build(for: empty, url: url) == ["https://x/"])

        // Whitespace-only is also treated as absent.
        let blank = BrowserTarget(bundleID: "com.google.Chrome", profileID: "   ")
        #expect(LaunchArguments.build(for: blank, url: url) == ["https://x/"])
    }

    @Test("Firefox with an empty profileID is treated as no profile")
    func firefoxEmptyProfileTreatedAsNoProfile() {
        let empty = BrowserTarget(bundleID: "org.mozilla.firefox", profileID: "")
        #expect(LaunchArguments.build(for: empty, url: url) == ["https://x/"])
    }

    // MARK: Firefox

    @Test("Firefox with a profile → -P <name> then URL last (no -no-remote)")
    func firefoxWithProfile() {
        let target = BrowserTarget(bundleID: "org.mozilla.firefox", profileID: "default-release")
        let argv = LaunchArguments.build(for: target, url: url)
        #expect(argv == ["-P", "default-release", "https://x/"])
        // Spike §4 decision: -no-remote is NOT used (it breaks the running-browser case).
        #expect(!argv.contains("-no-remote"))
    }

    @Test("Firefox without a profile → just the URL")
    func firefoxNoProfile() {
        let target = BrowserTarget(bundleID: "org.mozilla.firefox", profileID: nil)
        #expect(LaunchArguments.build(for: target, url: url) == ["https://x/"])
    }

    @Test("Zen (Firefox fork) with a profile → -P <name> then URL last")
    func zenWithProfile() {
        let target = BrowserTarget(bundleID: "app.zen-browser.zen", profileID: "default")
        #expect(
            LaunchArguments.build(for: target, url: url)
                == ["-P", "default", "https://x/"]
        )
    }

    // MARK: Safari / unknown

    @Test("Safari ignores any profile and yields just the URL")
    func safariWithProfile() {
        let target = BrowserTarget(bundleID: "com.apple.Safari", profileID: "Anything")
        #expect(LaunchArguments.build(for: target, url: url) == ["https://x/"])
    }

    @Test("An unknown browser with a profile is treated as Chromium (--profile-directory)")
    func unknownWithProfile() {
        // Unknown bundle IDs now default to the Chromium family, so a profileID,
        // when present, produces the Chromium profile flag.
        let target = BrowserTarget(bundleID: "com.example.SomeBrowser", profileID: "Anything")
        #expect(
            LaunchArguments.build(for: target, url: url)
                == ["--profile-directory=Anything", "https://x/"]
        )
    }

    @Test("An unknown browser without a profile yields just the URL")
    func unknownNoProfile() {
        // Unknown browsers carry no profileID in practice, so they still emit [url].
        let target = BrowserTarget(bundleID: "com.example.SomeBrowser", profileID: nil)
        #expect(LaunchArguments.build(for: target, url: url) == ["https://x/"])
    }

    // MARK: URL serialization & ordering

    @Test("The URL element uses absoluteString and is always last")
    func urlIsAbsoluteStringAndLast() {
        let full = URL(string: "https://user@example.com:8443/a/b?q=1#frag")!
        let target = BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 2")
        let argv = LaunchArguments.build(for: target, url: full)
        #expect(argv.last == full.absoluteString)
        #expect(argv == ["--profile-directory=Profile 2", full.absoluteString])
    }
}
