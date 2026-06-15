import XCTest
import TrafficWandCore
@testable import TrafficWand

/// Tests for `SettingsViewModel.alias(withID:)`, the lookup the master-detail
/// Aliases tab uses to resolve its `selectedAliasID` (held in view `@State`) to the
/// live alias the inline detail editor edits.
///
/// Split out of `SettingsViewModelAliasTests` so that file stays under the lint
/// `type_body_length` limit.
@MainActor
final class SettingsViewModelAliasLookupTests: XCTestCase {

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

    private func alias(_ name: String, _ target: BrowserTarget) -> ProfileAlias {
        ProfileAlias(name: name, target: target)
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

    func testAliasWithIDReturnsMatchingAlias() {
        let personal = alias("Personal", chromeTarget("Default"))
        let work = alias("Work", chromeTarget("Profile 1"))
        let vm = makeViewModel(config: AppConfig(aliases: [personal, work], rules: [], fallback: .picker))

        XCTAssertEqual(vm.alias(withID: work.id), work)
    }

    func testAliasWithIDReturnsNilForUnknownID() {
        let personal = alias("Personal", chromeTarget("Default"))
        let vm = makeViewModel(config: AppConfig(aliases: [personal], rules: [], fallback: .picker))

        XCTAssertNil(vm.alias(withID: UUID()))
    }

    func testAliasWithIDReflectsLivePersistedEdit() {
        let original = alias("Personal", chromeTarget())
        let vm = makeViewModel(config: AppConfig(aliases: [original], rules: [], fallback: .picker))

        var edited = original
        edited.name = "Home"
        vm.updateAlias(edited)

        // The detail editor re-fetches by the selected id and sees the new value.
        XCTAssertEqual(vm.alias(withID: original.id)?.name, "Home")
    }
}
