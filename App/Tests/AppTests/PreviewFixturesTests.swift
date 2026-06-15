#if DEBUG
import AppKit
import XCTest
import TrafficWandCore
@testable import TrafficWand

/// Smoke tests for the shared SwiftUI `#Preview` fixtures (Task 5).
///
/// `#Preview` code compiles into the **app target**, never the test target, so the
/// fixtures in `App/Sources/UI/Previews/PreviewFixtures.swift` are `internal`
/// (not `private`) and reachable here via `@testable import TrafficWand`. These
/// tests are regression guards: they keep the sample data internally consistent
/// (every sample rule targets a sample browser), prove the preview factory wires
/// its mocks and loads them, and catch a typo in the menu-bar glyph symbol name.
///
/// The whole file is `#if DEBUG`-guarded because the fixtures only exist in DEBUG.
final class PreviewFixturesTests: XCTestCase {

    // MARK: - Sample data consistency

    func testSampleBrowsersAreNonEmpty() {
        XCTAssertFalse(PreviewFixtures.sampleBrowsers.isEmpty)
    }

    func testEverySampleRuleTargetsASampleBrowser() {
        let browsersByBundleID = Dictionary(
            uniqueKeysWithValues: PreviewFixtures.sampleBrowsers.map { ($0.bundleID, $0) }
        )
        XCTAssertFalse(PreviewFixtures.sampleRules.isEmpty)
        for rule in PreviewFixtures.sampleRules {
            guard let browser = browsersByBundleID[rule.target.bundleID] else {
                XCTFail(
                    "Sample rule \(rule.pattern) targets \(rule.target.bundleID), which is not a sample browser."
                )
                continue
            }
            // A rule that names a profile must reference a profile that actually
            // exists on its target browser; otherwise the editor preview renders a
            // broken profile picker.
            if let profileID = rule.target.profileID {
                XCTAssertTrue(
                    browser.profiles.contains { $0.id == profileID },
                    "Sample rule \(rule.pattern) targets profile \(profileID), "
                        + "which is not a profile of \(browser.bundleID)."
                )
            }
        }
    }

    // MARK: - Preview view-model factory

    @MainActor
    func testMakePreviewSettingsViewModelPopulatesRulesAndBrowsers() {
        let viewModel = PreviewFixtures.makePreviewSettingsViewModel()

        XCTAssertEqual(
            viewModel.rules,
            PreviewFixtures.sampleRules,
            "The populated factory loads the sample rules verbatim."
        )
        XCTAssertEqual(
            viewModel.browsers.map(\.bundleID),
            PreviewFixtures.sampleBrowsers.map(\.bundleID),
            "The factory loads the sample browsers from the provider."
        )
    }

    /// The empty-config factory path backs the empty-state preview: the config has
    /// no rules, but browsers still come from the provider (not the config), so the
    /// editor's browser picker stays populated.
    @MainActor
    func testMakePreviewSettingsViewModelWithEmptyConfigHasNoRulesButKeepsBrowsers() {
        let viewModel = PreviewFixtures.makePreviewSettingsViewModel(
            config: PreviewFixtures.emptyConfig
        )

        XCTAssertTrue(viewModel.rules.isEmpty, "The empty config yields no rules.")
        XCTAssertEqual(
            viewModel.browsers.map(\.bundleID),
            PreviewFixtures.sampleBrowsers.map(\.bundleID),
            "Browsers come from the provider, so they survive an empty config."
        )
    }

    // MARK: - Menu-bar icon symbol

    @MainActor
    func testStatusIconSymbolResolvesToAnImage() {
        let image = NSImage(
            systemSymbolName: StatusBarController.statusIconSymbolName,
            accessibilityDescription: nil
        )
        XCTAssertNotNil(image, "The menu-bar icon SF Symbol name must resolve to a non-nil NSImage.")
    }

    // MARK: - Preview icon provider fallback

    /// `PreviewIconProvider` falls back to a per-family SF Symbol when the browser's
    /// app is not installed on disk. The real-icon path depends on which apps are
    /// installed (not safe to assert in CI), so this points each family at a
    /// non-existent app URL to force the deterministic fallback branch — which also
    /// guards the `BrowserFamily` mapping and catches a fallback symbol-name typo.
    func testPreviewIconProviderFallsBackToSymbolForMissingApp() {
        let provider = PreviewIconProvider()
        // One bundle ID per family, each pointed at a path that cannot exist.
        let families: [(bundleID: String, label: String)] = [
            ("com.apple.Safari", "safari"),
            ("org.mozilla.firefox", "firefox"),
            ("com.google.Chrome", "chromium")
        ]
        for family in families {
            let browser = Browser(
                bundleID: family.bundleID,
                name: family.label,
                appURL: URL(fileURLWithPath: "/nonexistent/\(family.label).app"),
                profiles: []
            )
            // If the fallback symbol name were a typo, `NSImage(systemSymbolName:)`
            // would return nil and the provider's force-unwrap would trap here. A
            // resolved system-symbol image is `isValid`.
            XCTAssertTrue(
                provider.icon(for: browser).isValid,
                "The \(family.label) fallback SF Symbol must resolve to a valid NSImage."
            )
        }
    }
}
#endif
