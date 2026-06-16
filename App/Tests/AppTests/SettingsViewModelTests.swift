import XCTest
import TrafficWandCore
@testable import TrafficWand

/// Tests for `SettingsViewModel` (Task 15).
///
/// The view model is the fully unit-testable heart of the Settings UI: it depends
/// only on the Core `ConfigStore` protocol and the App-side
/// `InstalledBrowsersProviding` seam (both injected), and makes no `NSWorkspace`
/// calls. Every mutation (add / edit / delete / reorder a rule, change fallback)
/// must mutate the in-memory config **and** persist it via `ConfigStore.save`, so
/// changes survive relaunch (Acceptance Criterion #5).
///
/// These tests drive the view model with a mock `ConfigStore` that records every
/// `save` (and the saved config) plus a stub provider returning a fixed browser
/// list, and assert both the in-memory state and the persisted side effect.
@MainActor
final class SettingsViewModelTests: XCTestCase {

    // MARK: - Mocks / stubs

    /// Mock `ConfigStore`: returns a seeded config on `load`, records every `save`.
    ///
    /// `@unchecked Sendable` because `ConfigStore` is `Sendable` but the mock holds
    /// mutable recording state; tests use it single-threaded on the main actor.
    private final class MockConfigStore: ConfigStore, @unchecked Sendable {
        var loaded: AppConfig
        private(set) var saved: [AppConfig] = []
        var loadError: Error?
        /// When set, `save` records the attempt then throws (mirrors a disk error).
        var saveError: Error?

        init(loaded: AppConfig) {
            self.loaded = loaded
        }

        func load() throws -> AppConfig {
            if let loadError { throw loadError }
            return loaded
        }

        func save(_ config: AppConfig) throws {
            saved.append(config)
            if let saveError { throw saveError }
            // Mirror persistence so a subsequent load reflects the saved value.
            loaded = config
        }

        var lastSaved: AppConfig? { saved.last }
        var saveCount: Int { saved.count }
    }

    /// Stub provider returning a fixed browser list.
    private struct StubBrowserProvider: InstalledBrowsersProviding {
        let browsers: [Browser]
        func installedBrowsers() -> [Browser] { browsers }
    }

    /// Mock update seam: round-trips the auto-check property so tests can verify the
    /// view model's `automaticUpdatesEnabled` reads from and writes through to it.
    private final class MockUpdater: UpdaterControlling {
        var automaticallyChecksForUpdates = false
        var canCheckForUpdates = true
        private(set) var checkForUpdatesCallCount = 0
        func checkForUpdates() { checkForUpdatesCallCount += 1 }
    }

    // MARK: - Fixtures

    private func browser(
        _ bundleID: String,
        _ name: String,
        profiles: [BrowserProfile] = []
    ) -> Browser {
        Browser(
            bundleID: bundleID,
            name: name,
            appURL: URL(fileURLWithPath: "/Applications/\(name).app"),
            profiles: profiles
        )
    }

    private func chromeDestination(_ profile: String? = nil) -> RoutingDestination {
        .browser(BrowserTarget(bundleID: "com.google.Chrome", profileID: profile))
    }

    private func firefoxDestination(_ profile: String? = nil) -> RoutingDestination {
        .browser(BrowserTarget(bundleID: "org.mozilla.firefox", profileID: profile))
    }

    private func makeViewModel(
        config: AppConfig,
        browsers: [Browser] = [],
        updater: MockUpdater = MockUpdater()
    ) -> (SettingsViewModel, MockConfigStore) {
        let store = MockConfigStore(loaded: config)
        let vm = SettingsViewModel(
            configStore: store,
            browserProvider: StubBrowserProvider(browsers: browsers),
            updater: updater
        )
        return (vm, store)
    }

    // MARK: - load()

    func testLoadPopulatesRulesAndBrowsersAndFallback() {
        let rule = Rule(pattern: "*github.com", destination: chromeDestination("Work"), isEnabled: true)
        let config = AppConfig(rules: [rule], fallback: .lastUsed)
        let browsers = [
            browser("com.google.Chrome", "Google Chrome"),
            browser("org.mozilla.firefox", "Firefox")
        ]
        let (vm, _) = makeViewModel(config: config, browsers: browsers)

        vm.load()

        XCTAssertEqual(vm.rules, [rule])
        XCTAssertEqual(vm.browsers.map(\.bundleID), ["com.google.Chrome", "org.mozilla.firefox"])
        XCTAssertEqual(vm.fallback, .lastUsed)
    }

    /// A second `load()` after an external writer (e.g. the picker's
    /// `ConfigRuleStore`) saved a new rule must reflect that rule. This underpins
    /// the dual-writer fix in `SettingsWindowController`, which reloads the view
    /// model when the Settings window regains focus so an in-memory edit doesn't
    /// clobber a picker-added rule.
    func testReloadAfterExternalSavePicksUpNewRules() {
        let existing = Rule(pattern: "*github.com", destination: chromeDestination(), isEnabled: true)
        let (vm, store) = makeViewModel(config: AppConfig(rules: [existing], fallback: .picker))
        vm.load()
        XCTAssertEqual(vm.rules, [existing])

        // Simulate an external writer (the picker) appending a remembered rule and
        // changing the fallback while the view model already holds the old state.
        let remembered = Rule(pattern: "*example.com", destination: firefoxDestination(), isEnabled: true)
        store.loaded = AppConfig(rules: [existing, remembered], fallback: .lastUsed)

        vm.load()

        XCTAssertEqual(vm.rules, [existing, remembered], "Reload reflects the externally-added rule.")
        XCTAssertEqual(vm.fallback, .lastUsed, "Reload reflects the externally-changed fallback.")
    }

    func testLoadWithCorruptConfigFallsBackToDefault() {
        let (vm, store) = makeViewModel(config: AppConfig(rules: [], fallback: .picker))
        store.loadError = ConfigStoreError.corruptConfiguration

        vm.load()

        XCTAssertEqual(vm.rules, AppConfig.default.rules)
        XCTAssertEqual(vm.fallback, AppConfig.default.fallback)
    }

    // MARK: - add rule

    func testAddRulePersistsAndAppends() {
        let (vm, store) = makeViewModel(config: AppConfig(rules: [], fallback: .picker))
        vm.load()

        let newRule = Rule(pattern: "*.example.com", destination: chromeDestination(), isEnabled: true)
        vm.addRule(newRule)

        XCTAssertEqual(vm.rules, [newRule])
        XCTAssertEqual(store.lastSaved?.rules, [newRule])
        XCTAssertEqual(store.saveCount, 1)
    }

    // MARK: - edit rule

    func testEditRulePersistsTheChange() {
        let original = Rule(pattern: "*github.com", destination: chromeDestination(), isEnabled: true)
        let (vm, store) = makeViewModel(config: AppConfig(rules: [original], fallback: .picker))
        vm.load()

        var edited = original
        edited.pattern = "*.github.com"
        edited.destination = firefoxDestination("Personal")
        edited.isEnabled = false
        vm.updateRule(edited)

        XCTAssertEqual(vm.rules.count, 1)
        XCTAssertEqual(vm.rules.first, edited)
        XCTAssertEqual(store.lastSaved?.rules.first, edited)
        XCTAssertEqual(store.saveCount, 1)
    }

    func testEditUnknownRuleDoesNothing() {
        let original = Rule(pattern: "*github.com", destination: chromeDestination(), isEnabled: true)
        let (vm, store) = makeViewModel(config: AppConfig(rules: [original], fallback: .picker))
        vm.load()

        let stranger = Rule(pattern: "*.nope.com", destination: chromeDestination(), isEnabled: true)
        vm.updateRule(stranger)

        XCTAssertEqual(vm.rules, [original])
        XCTAssertEqual(store.saveCount, 0)
    }

    // MARK: - delete rule

    func testDeleteRuleByIDPersists() {
        let first = Rule(pattern: "*a.com", destination: chromeDestination(), isEnabled: true)
        let second = Rule(pattern: "*b.com", destination: firefoxDestination(), isEnabled: true)
        let (vm, store) = makeViewModel(config: AppConfig(rules: [first, second], fallback: .picker))
        vm.load()
        vm.deleteRule(id: first.id)
        XCTAssertEqual(vm.rules, [second])
        XCTAssertEqual(store.lastSaved?.rules, [second])
        XCTAssertEqual(store.saveCount, 1)
    }

    func testDeleteUnknownRuleByIDIsNoOp() {
        let rule = Rule(pattern: "*a.com", destination: chromeDestination(), isEnabled: true)
        let (vm, store) = makeViewModel(config: AppConfig(rules: [rule], fallback: .picker))
        vm.load()
        vm.deleteRule(id: UUID())
        XCTAssertEqual(vm.rules, [rule])
        XCTAssertEqual(store.saveCount, 0)
    }

    // MARK: - reorder rule

    func testReorderRuleChangesOrderAndPersists() {
        let first = Rule(pattern: "*a.com", destination: chromeDestination(), isEnabled: true)
        let second = Rule(pattern: "*b.com", destination: firefoxDestination(), isEnabled: true)
        let third = Rule(pattern: "*c.com", destination: chromeDestination(), isEnabled: true)
        let (vm, store) = makeViewModel(config: AppConfig(rules: [first, second, third], fallback: .picker))
        vm.load()

        // Move the first rule to the end.
        vm.moveRules(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        XCTAssertEqual(vm.rules, [second, third, first])
        XCTAssertEqual(store.lastSaved?.rules, [second, third, first])
        XCTAssertEqual(store.saveCount, 1)
    }

    // MARK: - toggle enable

    func testSetRuleEnabledPersists() {
        let rule = Rule(pattern: "*a.com", destination: chromeDestination(), isEnabled: true)
        let (vm, store) = makeViewModel(config: AppConfig(rules: [rule], fallback: .picker))
        vm.load()

        vm.setRule(rule, enabled: false)

        XCTAssertEqual(vm.rules.first?.isEnabled, false)
        XCTAssertEqual(store.lastSaved?.rules.first?.isEnabled, false)
        XCTAssertEqual(store.saveCount, 1)
    }

    // MARK: - change fallback policy

    func testChangeFallbackToDefaultBrowserPersists() {
        let (vm, store) = makeViewModel(config: AppConfig(rules: [], fallback: .picker))
        vm.load()

        let destination = chromeDestination("Work")
        vm.setFallback(.defaultBrowser(destination))

        XCTAssertEqual(vm.fallback, .defaultBrowser(destination))
        XCTAssertEqual(store.lastSaved?.fallback, .defaultBrowser(destination))
        XCTAssertEqual(store.saveCount, 1)
    }

    func testChangeFallbackToLastUsedPersists() {
        let (vm, store) = makeViewModel(config: AppConfig(rules: [], fallback: .picker))
        vm.load()

        vm.setFallback(.lastUsed)

        XCTAssertEqual(vm.fallback, .lastUsed)
        XCTAssertEqual(store.lastSaved?.fallback, .lastUsed)
        XCTAssertEqual(store.saveCount, 1)
    }

    // MARK: - persist() save-error path

    func testAddRuleKeepsInMemoryStateWhenSaveThrows() {
        let (vm, store) = makeViewModel(config: AppConfig(rules: [], fallback: .picker))
        vm.load()
        // Make the next save fail (e.g. disk error); the mutation must still be
        // reflected in memory so the UI shows the user's intent.
        store.saveError = ConfigStoreError.corruptConfiguration

        let newRule = Rule(pattern: "*.example.com", destination: chromeDestination(), isEnabled: true)
        vm.addRule(newRule)

        XCTAssertEqual(vm.rules, [newRule], "Mutation is kept in memory even when save fails.")
        XCTAssertEqual(store.saveCount, 1, "A save was attempted.")
    }

    func testSetFallbackKeepsInMemoryStateWhenSaveThrows() {
        let (vm, store) = makeViewModel(config: AppConfig(rules: [], fallback: .picker))
        vm.load()
        store.saveError = ConfigStoreError.corruptConfiguration

        vm.setFallback(.lastUsed)

        XCTAssertEqual(vm.fallback, .lastUsed, "Fallback change is kept in memory even when save fails.")
        XCTAssertEqual(store.saveCount, 1)
    }

    // MARK: - persistence preserves the rest of the config

    func testFallbackChangeKeepsRules() {
        let rule = Rule(pattern: "*a.com", destination: chromeDestination(), isEnabled: true)
        let (vm, store) = makeViewModel(config: AppConfig(rules: [rule], fallback: .picker))
        vm.load()

        vm.setFallback(.lastUsed)

        XCTAssertEqual(store.lastSaved?.rules, [rule])
        XCTAssertEqual(store.lastSaved?.schemaVersion, AppConfig.currentSchemaVersion)
    }

    /// Loading a legacy (schemaVersion 1) config and mutating it must migrate the
    /// document forward: the persisted config is stamped with the current schema
    /// version, matching the "new writes always use schema v2" contract on
    /// `AppConfig`. (A default config already carries `currentSchemaVersion`, so the
    /// existing `testFallbackChangeKeepsRules` can't distinguish bump from preserve.)
    func testPersistMigratesLegacySchemaVersionForward() {
        let rule = Rule(pattern: "*a.com", destination: chromeDestination(), isEnabled: true)
        let legacy = AppConfig(schemaVersion: 1, rules: [rule], fallback: .picker)
        let (vm, store) = makeViewModel(config: legacy)
        vm.load()

        vm.setFallback(.lastUsed)

        XCTAssertEqual(
            store.lastSaved?.schemaVersion,
            AppConfig.currentSchemaVersion,
            "A load-then-save migrates a legacy v1 document forward to the current schema."
        )
    }

    /// A document written by a *newer* build (a higher schemaVersion than this one
    /// understands) must never be downgraded on save.
    func testPersistNeverDowngradesNewerSchemaVersion() {
        let future = AppConfig.currentSchemaVersion + 1
        let rule = Rule(pattern: "*a.com", destination: chromeDestination(), isEnabled: true)
        let newer = AppConfig(schemaVersion: future, rules: [rule], fallback: .picker)
        let (vm, store) = makeViewModel(config: newer)
        vm.load()

        vm.setFallback(.lastUsed)

        XCTAssertEqual(
            store.lastSaved?.schemaVersion,
            future,
            "A save must not downgrade a document written by a newer build."
        )
    }

    // MARK: - automatic updates toggle (seam in the view model)

    func testAutomaticUpdatesEnabledReflectsTheSeam() {
        let updater = MockUpdater()
        updater.automaticallyChecksForUpdates = true
        let (vm, _) = makeViewModel(config: AppConfig(rules: [], fallback: .picker), updater: updater)

        XCTAssertTrue(vm.automaticUpdatesEnabled, "Reading reflects the updater's current preference.")

        updater.automaticallyChecksForUpdates = false
        XCTAssertFalse(vm.automaticUpdatesEnabled, "A change in the seam is observed on read.")
    }

    func testSettingAutomaticUpdatesEnabledWritesThroughToTheSeam() {
        let updater = MockUpdater()
        let (vm, store) = makeViewModel(config: AppConfig(rules: [], fallback: .picker), updater: updater)
        XCTAssertFalse(updater.automaticallyChecksForUpdates)

        vm.automaticUpdatesEnabled = true
        XCTAssertTrue(updater.automaticallyChecksForUpdates, "Setting the property writes through to the seam.")

        vm.automaticUpdatesEnabled = false
        XCTAssertFalse(updater.automaticallyChecksForUpdates)

        // The Sparkle auto-check preference lives in the updater seam (UserDefaults),
        // not in AppConfig — toggling it must never persist to ConfigStore.
        XCTAssertEqual(store.saveCount, 0, "Toggling auto-updates must not mirror into AppConfig / ConfigStore.")
    }
}
