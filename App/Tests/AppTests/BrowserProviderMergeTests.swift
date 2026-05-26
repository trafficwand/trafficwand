import XCTest
import TrafficWandCore
@testable import TrafficWand

/// Tests for the **pure** parts of browser discovery (Task 10):
///   - `BrowserCandidate` → `[Browser]` merge helper (`BrowserMerger`), exercised
///     without any `NSWorkspace` involvement, and
///   - `ProfilePathResolver` per-family Application Support path construction.
///
/// `WorkspaceBrowserProvider`'s only untestable line is the live `NSWorkspace`
/// call; everything decision-shaped is funneled through `BrowserMerger` and
/// covered here.
final class BrowserProviderMergeTests: XCTestCase {

    /// TrafficWand's own bundle identifier (matches `project.yml`'s
    /// `PRODUCT_BUNDLE_IDENTIFIER`). The merge helper must never list itself.
    private let selfBundleID = "io.tomakado.TrafficWand"

    // MARK: - Stub ProfileReading

    /// A stub `ProfileReading` that returns canned profiles per Application
    /// Support directory, recording the directories it was asked about. No file
    /// system is touched.
    private final class StubProfileReader: ProfileReading, @unchecked Sendable {
        /// Maps an Application Support directory path → profiles to return.
        var profilesByDirectory: [String: [BrowserProfile]] = [:]
        /// Directories the reader was queried with, in call order.
        private(set) var queriedDirectories: [URL] = []

        func readProfiles(applicationSupportDirectory: URL) throws -> [BrowserProfile] {
            queriedDirectories.append(applicationSupportDirectory)
            return profilesByDirectory[applicationSupportDirectory.path] ?? []
        }
    }

    /// A `ProfilePathResolving` stub mapping bundle IDs to fixed support dirs so
    /// the merge can be tested without real `~/Library` paths.
    private struct StubPathResolver: ProfilePathResolving {
        let directories: [String: URL]
        func applicationSupportDirectory(forBundleID bundleID: String) -> URL? {
            directories[bundleID]
        }
    }

    // MARK: - Helpers

    private func candidate(_ bundleID: String, _ name: String) -> BrowserCandidate {
        BrowserCandidate(
            bundleID: bundleID,
            name: name,
            appURL: URL(fileURLWithPath: "/Applications/\(name).app")
        )
    }

    // MARK: - Self exclusion

    func testMergeExcludesTrafficWandItself() {
        let candidates = [
            candidate(selfBundleID, "TrafficWand"),
            candidate("com.google.Chrome", "Google Chrome")
        ]

        let browsers = BrowserMerger.merge(
            candidates: candidates,
            selfBundleID: selfBundleID,
            profileReaderForFamily: { _ in StubProfileReader() },
            pathResolver: StubPathResolver(directories: [:])
        )

        XCTAssertFalse(browsers.contains { $0.bundleID == selfBundleID },
                       "TrafficWand must exclude itself from the browser list.")
        XCTAssertEqual(browsers.map(\.bundleID), ["com.google.Chrome"])
    }

    // MARK: - Allowlist filtering

    func testMergeFiltersNonBrowserHTTPHandlerByAllowlist() {
        // A random app that claims to handle http but is not a real browser.
        let candidates = [
            candidate("com.example.SomeMailApp", "Mailer"),
            candidate("com.google.Chrome", "Google Chrome"),
            candidate("org.mozilla.firefox", "Firefox"),
            candidate("com.apple.Safari", "Safari")
        ]

        let browsers = BrowserMerger.merge(
            candidates: candidates,
            selfBundleID: selfBundleID,
            profileReaderForFamily: { _ in StubProfileReader() },
            pathResolver: StubPathResolver(directories: [:])
        )

        let ids = Set(browsers.map(\.bundleID))
        XCTAssertFalse(ids.contains("com.example.SomeMailApp"),
                       "A non-browser http handler must be filtered by the allowlist.")
        XCTAssertEqual(ids, ["com.google.Chrome", "org.mozilla.firefox", "com.apple.Safari"])
    }

    // MARK: - Non-default browsers still appear

    func testMergeKeepsRealNonDefaultBrowser() {
        // Brave is a real, allowlisted browser that is not the system default —
        // it must still appear (we do not filter by default-ness).
        let candidates = [
            candidate("com.brave.Browser", "Brave Browser")
        ]

        let browsers = BrowserMerger.merge(
            candidates: candidates,
            selfBundleID: selfBundleID,
            profileReaderForFamily: { _ in StubProfileReader() },
            pathResolver: StubPathResolver(directories: [:])
        )

        XCTAssertEqual(browsers.map(\.bundleID), ["com.brave.Browser"])
    }

    // MARK: - De-duplication by bundle ID

    func testMergeDeduplicatesByBundleIDKeepingFirst() {
        // NSWorkspace can list multiple copies of the same app (e.g. one in
        // /Applications and one elsewhere). The merge must keep only the first
        // occurrence per bundle ID.
        let first = BrowserCandidate(
            bundleID: "com.google.Chrome",
            name: "Google Chrome",
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")
        )
        let duplicate = BrowserCandidate(
            bundleID: "com.google.Chrome",
            name: "Google Chrome (copy)",
            appURL: URL(fileURLWithPath: "/Users/me/Applications/Google Chrome.app")
        )

        let browsers = BrowserMerger.merge(
            candidates: [first, duplicate],
            selfBundleID: selfBundleID,
            profileReaderForFamily: { _ in StubProfileReader() },
            pathResolver: StubPathResolver(directories: [:])
        )

        XCTAssertEqual(browsers.count, 1, "Duplicate bundle IDs must collapse to one.")
        // The first occurrence is kept (its name/url, not the duplicate's).
        XCTAssertEqual(browsers.first?.name, "Google Chrome")
        XCTAssertEqual(browsers.first?.appURL, URL(fileURLWithPath: "/Applications/Google Chrome.app"))
    }

    // MARK: - Profiles attached

    func testMergeAttachesDiscoveredProfiles() {
        let chromeSupport = URL(fileURLWithPath: "/tmp/AppSupport/Google/Chrome")
        let reader = StubProfileReader()
        reader.profilesByDirectory[chromeSupport.path] = [
            BrowserProfile(id: "Default", name: "Default"),
            BrowserProfile(id: "Profile 1", name: "Work")
        ]

        let browsers = BrowserMerger.merge(
            candidates: [candidate("com.google.Chrome", "Google Chrome")],
            selfBundleID: selfBundleID,
            profileReaderForFamily: { family in
                XCTAssertEqual(family, .chromium)
                return reader
            },
            pathResolver: StubPathResolver(directories: ["com.google.Chrome": chromeSupport])
        )

        XCTAssertEqual(browsers.count, 1)
        let chrome = try? XCTUnwrap(browsers.first)
        XCTAssertEqual(chrome?.profiles, [
            BrowserProfile(id: "Default", name: "Default"),
            BrowserProfile(id: "Profile 1", name: "Work")
        ])
        XCTAssertEqual(reader.queriedDirectories, [chromeSupport])
    }

    func testMergeAttachesEmptyProfilesWhenNoSupportDirectory() {
        // Safari has no profile reader / support dir → empty profiles, no crash.
        let browsers = BrowserMerger.merge(
            candidates: [candidate("com.apple.Safari", "Safari")],
            selfBundleID: selfBundleID,
            profileReaderForFamily: { _ in StubProfileReader() },
            pathResolver: StubPathResolver(directories: [:])
        )

        XCTAssertEqual(browsers.count, 1)
        XCTAssertEqual(browsers.first?.profiles, [])
    }

    func testMergeProfileReaderThrowingResolvesToEmpty() {
        struct ThrowingReader: ProfileReading {
            func readProfiles(applicationSupportDirectory: URL) throws -> [BrowserProfile] {
                throw CocoaError(.fileReadUnknown)
            }
        }
        let chromeSupport = URL(fileURLWithPath: "/tmp/AppSupport/Google/Chrome")

        let browsers = BrowserMerger.merge(
            candidates: [candidate("com.google.Chrome", "Google Chrome")],
            selfBundleID: selfBundleID,
            profileReaderForFamily: { _ in ThrowingReader() },
            pathResolver: StubPathResolver(directories: ["com.google.Chrome": chromeSupport])
        )

        XCTAssertEqual(browsers.first?.profiles, [],
                       "A throwing reader must degrade to empty profiles, not crash.")
    }

    // MARK: - Deterministic ordering

    func testMergeSortsBrowsersByName() {
        let candidates = [
            candidate("com.google.Chrome", "Google Chrome"),
            candidate("com.apple.Safari", "Safari"),
            candidate("com.brave.Browser", "Brave Browser")
        ]

        let browsers = BrowserMerger.merge(
            candidates: candidates,
            selfBundleID: selfBundleID,
            profileReaderForFamily: { _ in StubProfileReader() },
            pathResolver: StubPathResolver(directories: [:])
        )

        XCTAssertEqual(browsers.map(\.name), ["Brave Browser", "Google Chrome", "Safari"])
    }

    func testMergePreservesCandidateNameAndURL() {
        let appURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        let candidates = [
            BrowserCandidate(bundleID: "com.google.Chrome", name: "Google Chrome", appURL: appURL)
        ]

        let browsers = BrowserMerger.merge(
            candidates: candidates,
            selfBundleID: selfBundleID,
            profileReaderForFamily: { _ in StubProfileReader() },
            pathResolver: StubPathResolver(directories: [:])
        )

        XCTAssertEqual(browsers.first?.name, "Google Chrome")
        XCTAssertEqual(browsers.first?.appURL, appURL)
    }

    // MARK: - ProfilePathResolver

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
    }

    func testProfilePathResolverFirefoxPath() {
        let base = URL(fileURLWithPath: "/Users/test/Library/Application Support")
        let resolver = ProfilePathResolver(applicationSupportDirectory: base)

        XCTAssertEqual(
            resolver.applicationSupportDirectory(forBundleID: "org.mozilla.firefox")?.path,
            base.appendingPathComponent("Firefox").path
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
