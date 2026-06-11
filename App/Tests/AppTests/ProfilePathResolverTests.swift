import XCTest
import TrafficWandCore
@testable import TrafficWand

/// Tests for `ProfilePathResolver`'s per-family Application Support path
/// construction (pure string building over an injected base directory).
final class ProfilePathResolverTests: XCTestCase {

    func testProfilePathResolverChromiumFamilyPaths() {
        let base = URL(fileURLWithPath: "/Users/test/Library/Application Support")
        let resolver = ProfilePathResolver(applicationSupportDirectory: base)

        XCTAssertEqual(
            resolver.applicationSupportDirectory(forBundleID: "com.google.Chrome")?.path,
            base.appendingPathComponent("Google/Chrome").path
        )
        XCTAssertEqual(
            resolver.applicationSupportDirectory(forBundleID: "com.google.Chrome.beta")?.path,
            base.appendingPathComponent("Google/Chrome Beta").path
        )
        XCTAssertEqual(
            resolver.applicationSupportDirectory(forBundleID: "com.google.Chrome.canary")?.path,
            base.appendingPathComponent("Google/Chrome Canary").path
        )
        XCTAssertEqual(
            resolver.applicationSupportDirectory(forBundleID: "com.microsoft.edgemac")?.path,
            base.appendingPathComponent("Microsoft Edge").path
        )
        XCTAssertEqual(
            resolver.applicationSupportDirectory(forBundleID: "com.brave.Browser")?.path,
            base.appendingPathComponent("BraveSoftware/Brave-Browser").path
        )
        XCTAssertEqual(
            resolver.applicationSupportDirectory(forBundleID: "com.vivaldi.Vivaldi")?.path,
            base.appendingPathComponent("Vivaldi").path
        )
        XCTAssertEqual(
            resolver.applicationSupportDirectory(forBundleID: "org.chromium.Chromium")?.path,
            base.appendingPathComponent("Chromium").path
        )
        // Helium stores its Chromium profile config directly under
        // net.imput.helium/ (containing-dir style, like Vivaldi/Chromium).
        XCTAssertEqual(
            resolver.applicationSupportDirectory(forBundleID: "net.imput.helium")?.path,
            base.appendingPathComponent("net.imput.helium").path
        )
    }

    func testProfilePathResolverChromiumNewcomerPaths() {
        // Arc, Comet, and Dia are Chromium-family browsers added so their profiles
        // are discovered like Chrome/Edge/Brave. (Comet/Dia paths are pending
        // device verification but still resolve to a candidate sub-path.)
        let base = URL(fileURLWithPath: "/Users/test/Library/Application Support")
        let resolver = ProfilePathResolver(applicationSupportDirectory: base)

        XCTAssertEqual(
            resolver.applicationSupportDirectory(forBundleID: "company.thebrowser.Browser")?.path,
            base.appendingPathComponent("Arc/User Data").path
        )
        XCTAssertEqual(
            resolver.applicationSupportDirectory(forBundleID: "ai.perplexity.comet")?.path,
            base.appendingPathComponent("Comet/User Data").path
        )
        XCTAssertEqual(
            resolver.applicationSupportDirectory(forBundleID: "company.thebrowser.dia")?.path,
            base.appendingPathComponent("Dia/User Data").path
        )
    }

    func testProfilePathResolverFirefoxPath() {
        let base = URL(fileURLWithPath: "/Users/test/Library/Application Support")
        let resolver = ProfilePathResolver(applicationSupportDirectory: base)

        XCTAssertEqual(
            resolver.applicationSupportDirectory(forBundleID: "org.mozilla.firefox")?.path,
            base.appendingPathComponent("Firefox").path
        )
    }

    func testProfilePathResolverZenFirefoxFamilyPath() {
        // Zen is a Firefox fork; its profile config lives under a "zen" sub-path
        // (pending device verification).
        let base = URL(fileURLWithPath: "/Users/test/Library/Application Support")
        let resolver = ProfilePathResolver(applicationSupportDirectory: base)

        XCTAssertEqual(
            resolver.applicationSupportDirectory(forBundleID: "app.zen-browser.zen")?.path,
            base.appendingPathComponent("zen").path
        )
    }

    func testProfilePathResolverUnsupportedFamiliesReturnNil() {
        let base = URL(fileURLWithPath: "/Users/test/Library/Application Support")
        let resolver = ProfilePathResolver(applicationSupportDirectory: base)

        // Safari and unknown bundle IDs have no profile-config directory.
        XCTAssertNil(resolver.applicationSupportDirectory(forBundleID: "com.apple.Safari"))
        XCTAssertNil(resolver.applicationSupportDirectory(forBundleID: "com.example.Unknown"))
    }
}
