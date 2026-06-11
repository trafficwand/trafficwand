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

    // MARK: - Picker allowlist filters non-browser http handlers

    func testMergeFiltersNonBrowserHTTPHandlers() {
        // NSWorkspace's http(s)-handler enumeration returns non-browsers too:
        // terminals (iTerm, kitty), and other apps that register http handling.
        // The picker allowlist (`BrowserFamily.isKnownBrowser`) must drop them
        // while keeping curated, real browsers — including the newcomers.
        let candidates = [
            candidate("com.googlecode.iterm2", "iTerm"),
            candidate("net.kovidgoyal.kitty", "kitty"),
            candidate("com.example.SomeMailApp", "Mailer"),
            candidate("com.google.Chrome", "Google Chrome"),
            candidate("org.mozilla.firefox", "Firefox"),
            candidate("com.apple.Safari", "Safari"),
            candidate("company.thebrowser.Browser", "Arc"),
            candidate("ai.perplexity.comet", "Comet"),
            candidate("app.zen-browser.zen", "Zen"),
            candidate("net.imput.helium", "Helium")
        ]

        let browsers = BrowserMerger.merge(
            candidates: candidates,
            selfBundleID: selfBundleID,
            profileReaderForFamily: { _ in StubProfileReader() },
            pathResolver: StubPathResolver(directories: [:])
        )

        let ids = Set(browsers.map(\.bundleID))
        XCTAssertFalse(ids.contains("com.googlecode.iterm2"), "iTerm is a terminal, not a browser.")
        XCTAssertFalse(ids.contains("net.kovidgoyal.kitty"), "kitty is a terminal, not a browser.")
        XCTAssertFalse(ids.contains("com.example.SomeMailApp"), "A non-browser http handler must be filtered.")
        XCTAssertEqual(ids, [
            "com.google.Chrome",
            "org.mozilla.firefox",
            "com.apple.Safari",
            "company.thebrowser.Browser",
            "ai.perplexity.comet",
            "app.zen-browser.zen",
            "net.imput.helium"
        ])
    }

    func testMergeExcludesTrafficWandViaAllowlistEvenIfSelfIDMismatches() {
        // Defense in depth: even if the self-exclusion bundle ID does not match at
        // runtime, TrafficWand is not on the browser allowlist, so it is dropped.
        let browsers = BrowserMerger.merge(
            candidates: [
                candidate("io.tomakado.TrafficWand", "TrafficWand"),
                candidate("com.google.Chrome", "Google Chrome")
            ],
            selfBundleID: "some.other.id",   // deliberately not TrafficWand's ID
            profileReaderForFamily: { _ in StubProfileReader() },
            pathResolver: StubPathResolver(directories: [:])
        )

        XCTAssertEqual(browsers.map(\.bundleID), ["com.google.Chrome"],
                       "TrafficWand must never list itself, allowlist drops it.")
    }

    func testMergeKnownBrowserWithNoResolverPathHasEmptyProfiles() {
        // Graceful degradation: a known browser with no resolver path is still
        // listed, just with no discovered profiles (launches its default profile).
        let browsers = BrowserMerger.merge(
            candidates: [candidate("company.thebrowser.Browser", "Arc")],
            selfBundleID: selfBundleID,
            profileReaderForFamily: { _ in StubProfileReader() },
            pathResolver: StubPathResolver(directories: [:])
        )

        XCTAssertEqual(browsers.map(\.bundleID), ["company.thebrowser.Browser"])
        XCTAssertEqual(browsers.first?.profiles, [],
                       "No resolver path → empty profiles, but the browser is still listed.")
    }

    func testMergeKnownChromiumBrowserWithResolverPathDiscoversProfiles() {
        // The real Arc/Comet/Dia runtime path: a non-Chrome Chromium browser is
        // classified `.chromium`, gets the Chromium (Chrome-style) reader, and
        // attaches the discovered profiles.
        let supportDir = URL(fileURLWithPath: "/tmp/Arc/User Data")
        let cannedProfiles = [
            BrowserProfile(id: "Default", name: "Default"),
            BrowserProfile(id: "Profile 1", name: "Work")
        ]
        let reader = StubProfileReader()
        reader.profilesByDirectory = [supportDir.path: cannedProfiles]

        var requestedFamilies: [BrowserFamily] = []
        let browsers = BrowserMerger.merge(
            candidates: [candidate("company.thebrowser.Browser", "Arc")],
            selfBundleID: selfBundleID,
            profileReaderForFamily: { family in
                requestedFamilies.append(family)
                return reader
            },
            pathResolver: StubPathResolver(directories: ["company.thebrowser.Browser": supportDir])
        )

        XCTAssertEqual(browsers.map(\.bundleID), ["company.thebrowser.Browser"],
                       "Arc is listed.")
        XCTAssertEqual(requestedFamilies, [.chromium],
                       "Arc must be classified as the Chromium default.")
        XCTAssertEqual(browsers.first?.profiles, cannedProfiles,
                       "The Chromium reader's discovered profiles must attach to the browser.")
        XCTAssertEqual(reader.queriedDirectories, [supportDir],
                       "The reader must be queried with the resolved support directory.")
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

}
