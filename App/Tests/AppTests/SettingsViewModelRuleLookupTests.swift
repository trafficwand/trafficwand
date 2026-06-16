import XCTest
import TrafficWandCore
@testable import TrafficWand

/// Tests for `SettingsViewModel.rule(withID:)`, the lookup the master-detail
/// Rules tab uses to resolve its `selectedRuleID` (held in view `@State`) to the
/// live rule the inline detail editor edits.
///
/// Split out into a dedicated file (mirroring `SettingsViewModelAliasLookupTests`)
/// so the already-large `SettingsViewModelTests` stays under the lint
/// `type_body_length` limit.
@MainActor
final class SettingsViewModelRuleLookupTests: XCTestCase {

    private final class MockConfigStore: ConfigStore, @unchecked Sendable {
        var loaded: AppConfig
        init(loaded: AppConfig) { self.loaded = loaded }
        func load() throws -> AppConfig { loaded }
        func save(_ config: AppConfig) throws { loaded = config }
    }

    private struct StubBrowserProvider: InstalledBrowsersProviding {
        let browsers: [Browser]
        func installedBrowsers() -> [Browser] { browsers }
    }

    private final class MockUpdater: UpdaterControlling {
        var automaticallyChecksForUpdates = false
        var canCheckForUpdates = true
        func checkForUpdates() {}
    }

    private func chromeTarget(_ profile: String? = nil) -> BrowserTarget {
        BrowserTarget(bundleID: "com.google.Chrome", profileID: profile)
    }

    private func rule(_ pattern: String, _ target: BrowserTarget) -> Rule {
        Rule(pattern: pattern, destination: .browser(target))
    }

    private func makeViewModel(config: AppConfig) -> SettingsViewModel {
        let vm = SettingsViewModel(
            configStore: MockConfigStore(loaded: config),
            browserProvider: StubBrowserProvider(browsers: []),
            updater: MockUpdater()
        )
        vm.load()
        return vm
    }

    func testRuleWithIDReturnsMatchingRule() {
        let first = rule("*.example.com", chromeTarget("Default"))
        let second = rule("*.work.com", chromeTarget("Profile 1"))
        let vm = makeViewModel(config: AppConfig(aliases: [], rules: [first, second], fallback: .picker))

        XCTAssertEqual(vm.rule(withID: second.id), second)
    }

    func testRuleWithIDReturnsNilForUnknownID() {
        let only = rule("*.example.com", chromeTarget("Default"))
        let vm = makeViewModel(config: AppConfig(aliases: [], rules: [only], fallback: .picker))

        XCTAssertNil(vm.rule(withID: UUID()))
    }

    func testRuleWithIDReflectsLivePersistedEdit() {
        let original = rule("*.example.com", chromeTarget())
        let vm = makeViewModel(config: AppConfig(aliases: [], rules: [original], fallback: .picker))

        var edited = original
        edited.pattern = "*.edited.com"
        vm.updateRule(edited)

        // The detail editor re-fetches by the selected id and sees the new value.
        XCTAssertEqual(vm.rule(withID: original.id)?.pattern, "*.edited.com")
    }
}
