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

    @Test("An unknown bundle ID maps to .other")
    func unknownBundleID() {
        #expect(BrowserFamily(bundleID: "com.example.SomeBrowser") == .other)
    }

    @Test("An empty bundle ID maps to .other")
    func emptyBundleID() {
        #expect(BrowserFamily(bundleID: "") == .other)
    }

    @Test("Mapping is case-sensitive on the exact reverse-DNS bundle ID")
    func caseSensitiveMapping() {
        // Bundle IDs are matched exactly; a differently-cased string is not a
        // known browser and falls through to .other.
        #expect(BrowserFamily(bundleID: "COM.GOOGLE.CHROME") == .other)
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
            "org.chromium.Chromium",
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

    // MARK: Safari / unknown

    @Test("Safari ignores any profile and yields just the URL")
    func safariWithProfile() {
        let target = BrowserTarget(bundleID: "com.apple.Safari", profileID: "Anything")
        #expect(LaunchArguments.build(for: target, url: url) == ["https://x/"])
    }

    @Test("An unknown browser ignores any profile and yields just the URL")
    func unknownWithProfile() {
        let target = BrowserTarget(bundleID: "com.example.SomeBrowser", profileID: "Anything")
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
