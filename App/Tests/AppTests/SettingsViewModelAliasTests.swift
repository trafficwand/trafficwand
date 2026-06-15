import XCTest
import TrafficWandCore
@testable import TrafficWand

/// Alias-focused tests for `SettingsViewModel` (Tasks 7/9/10).
///
/// Split out of `SettingsViewModelTests` so each file stays under the lint
/// type-body-length limit. Covers alias load/CRUD/persistence, referential
/// integrity (block-delete when referenced), the `destinationLabel(for:)` helper,
/// and the persisted browser-or-alias shapes that the rule/fallback editors commit.
@MainActor
final class SettingsViewModelAliasTests: XCTestCase {

    // MARK: - Mocks / stubs

    private final class MockConfigStore: ConfigStore, @unchecked Sendable {
        var loaded: AppConfig
        private(set) var saved: [AppConfig] = []

        init(loaded: AppConfig) {
            self.loaded = loaded
        }

        func load() throws -> AppConfig { loaded }

        func save(_ config: AppConfig) throws {
            saved.append(config)
            loaded = config
        }

        var lastSaved: AppConfig? { saved.last }
        var saveCount: Int { saved.count }
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

    private func chromeTarget(_ profile: String? = nil) -> BrowserTarget {
        BrowserTarget(bundleID: "com.google.Chrome", profileID: profile)
    }

    private func firefoxTarget(_ profile: String? = nil) -> BrowserTarget {
        BrowserTarget(bundleID: "org.mozilla.firefox", profileID: profile)
    }

    private func chromeDestination(_ profile: String? = nil) -> RoutingDestination {
        .browser(chromeTarget(profile))
    }

    private func firefoxDestination(_ profile: String? = nil) -> RoutingDestination {
        .browser(firefoxTarget(profile))
    }

    private func alias(_ name: String, _ target: BrowserTarget, id: UUID = UUID()) -> ProfileAlias {
        ProfileAlias(id: id, name: name, target: target)
    }

    private func makeViewModel(
        config: AppConfig,
        browsers: [Browser] = []
    ) -> (SettingsViewModel, MockConfigStore) {
        let store = MockConfigStore(loaded: config)
        let vm = SettingsViewModel(
            configStore: store,
            browserProvider: StubBrowserProvider(browsers: browsers),
            updater: MockUpdater()
        )
        return (vm, store)
    }

    // MARK: - aliases: load

    func testLoadReadsAliases() {
        let personal = alias("Personal", chromeTarget("Default"))
        let work = alias("Work", chromeTarget("Profile 1"))
        let config = AppConfig(aliases: [personal, work], rules: [], fallback: .picker)
        let (vm, _) = makeViewModel(config: config)

        vm.load()

        XCTAssertEqual(vm.aliases, [personal, work])
    }

    // MARK: - aliases: CRUD + persistence

    func testAddAliasPersistsAndAppends() {
        let (vm, store) = makeViewModel(config: AppConfig(rules: [], fallback: .picker))
        vm.load()

        let new = alias("Personal", chromeTarget())
        vm.addAlias(new)

        XCTAssertEqual(vm.aliases, [new])
        XCTAssertEqual(store.lastSaved?.aliases, [new])
        XCTAssertEqual(store.saveCount, 1)
    }

    func testUpdateAliasPersistsTheChange() {
        let original = alias("Personal", chromeTarget())
        let config = AppConfig(aliases: [original], rules: [], fallback: .picker)
        let (vm, store) = makeViewModel(config: config)
        vm.load()

        var edited = original
        edited.name = "Home"
        edited.target = firefoxTarget()
        vm.updateAlias(edited)

        XCTAssertEqual(vm.aliases, [edited])
        XCTAssertEqual(store.lastSaved?.aliases, [edited])
        XCTAssertEqual(store.saveCount, 1)
    }

    func testUpdateUnknownAliasDoesNothing() {
        let original = alias("Personal", chromeTarget())
        let config = AppConfig(aliases: [original], rules: [], fallback: .picker)
        let (vm, store) = makeViewModel(config: config)
        vm.load()

        vm.updateAlias(alias("Stranger", firefoxTarget()))

        XCTAssertEqual(vm.aliases, [original])
        XCTAssertEqual(store.saveCount, 0)
    }

    func testDeleteUnreferencedAliasPersists() {
        let target = alias("Personal", chromeTarget())
        let config = AppConfig(aliases: [target], rules: [], fallback: .picker)
        let (vm, store) = makeViewModel(config: config)
        vm.load()

        vm.deleteAlias(id: target.id)

        XCTAssertTrue(vm.aliases.isEmpty)
        XCTAssertEqual(store.lastSaved?.aliases, [])
        XCTAssertEqual(store.saveCount, 1)
    }

    // MARK: - aliases: referential integrity

    func testReferencingRulesReturnsRulesPointingAtAlias() {
        let aliasItem = alias("Work", chromeTarget("Profile 1"))
        let referencing = Rule(pattern: "*.work.com", destination: .alias(aliasItem.id), isEnabled: true)
        let other = Rule(pattern: "*.home.com", destination: chromeDestination(), isEnabled: true)
        let config = AppConfig(aliases: [aliasItem], rules: [referencing, other], fallback: .picker)
        let (vm, _) = makeViewModel(config: config)
        vm.load()

        XCTAssertEqual(vm.referencingRules(aliasID: aliasItem.id), [referencing])
        XCTAssertTrue(vm.isReferenced(aliasItem.id))
    }

    func testFallbackReferenceIsDetected() {
        let aliasItem = alias("Work", chromeTarget("Profile 1"))
        let config = AppConfig(
            aliases: [aliasItem],
            rules: [],
            fallback: .defaultBrowser(.alias(aliasItem.id))
        )
        let (vm, _) = makeViewModel(config: config)
        vm.load()

        XCTAssertTrue(vm.isFallbackReferencing(aliasID: aliasItem.id))
        XCTAssertTrue(vm.isReferenced(aliasItem.id))
    }

    func testDeleteReferencedAliasIsNoOp() {
        let aliasItem = alias("Work", chromeTarget("Profile 1"))
        let referencing = Rule(pattern: "*.work.com", destination: .alias(aliasItem.id), isEnabled: true)
        let config = AppConfig(aliases: [aliasItem], rules: [referencing], fallback: .picker)
        let (vm, store) = makeViewModel(config: config)
        vm.load()

        vm.deleteAlias(id: aliasItem.id)

        XCTAssertEqual(vm.aliases, [aliasItem], "A referenced alias is not deleted.")
        XCTAssertEqual(store.saveCount, 0, "A blocked delete must not persist.")
    }

    func testDeleteAliasReferencedByFallbackIsNoOp() {
        let aliasItem = alias("Work", chromeTarget("Profile 1"))
        let config = AppConfig(
            aliases: [aliasItem],
            rules: [],
            fallback: .defaultBrowser(.alias(aliasItem.id))
        )
        let (vm, store) = makeViewModel(config: config)
        vm.load()

        vm.deleteAlias(id: aliasItem.id)

        XCTAssertEqual(vm.aliases, [aliasItem])
        XCTAssertEqual(store.saveCount, 0)
    }

    // MARK: - aliases: persist() writes aliases into AppConfig

    func testPersistWritesAliasesIntoSavedConfig() {
        let existing = alias("Personal", chromeTarget())
        let config = AppConfig(aliases: [existing], rules: [], fallback: .picker)
        let (vm, store) = makeViewModel(config: config)
        vm.load()

        // Any mutation triggers persist(); the saved config must carry aliases.
        vm.setFallback(.lastUsed)

        XCTAssertEqual(store.lastSaved?.aliases, [existing])
    }

    // MARK: - destinationLabel

    func testDestinationLabelForBrowserShowsNameAndProfile() {
        let chrome = browser(
            "com.google.Chrome",
            "Google Chrome",
            profiles: [BrowserProfile(id: "Profile 1", name: "Work")]
        )
        let (vm, _) = makeViewModel(config: AppConfig(rules: [], fallback: .picker), browsers: [chrome])
        vm.load()

        XCTAssertEqual(vm.destinationLabel(for: chromeDestination()), "Google Chrome")
        XCTAssertEqual(vm.destinationLabel(for: chromeDestination("Profile 1")), "Google Chrome — Work")
    }

    func testDestinationLabelForAliasShowsAliasName() {
        let aliasItem = alias("Work", chromeTarget("Profile 1"))
        let config = AppConfig(aliases: [aliasItem], rules: [], fallback: .picker)
        let (vm, _) = makeViewModel(config: config)
        vm.load()

        XCTAssertEqual(vm.destinationLabel(for: .alias(aliasItem.id)), "Work")
    }

    func testDestinationLabelForDanglingAliasShowsDeletedPlaceholder() {
        let (vm, _) = makeViewModel(config: AppConfig(rules: [], fallback: .picker))
        vm.load()

        XCTAssertEqual(vm.destinationLabel(for: .alias(UUID())), "(deleted alias)")
    }

    // MARK: - rule destination round-trip (Task 9: editor commit shapes)

    func testRuleEditedToAliasPersistsAliasDestination() {
        let aliasItem = alias("Work", chromeTarget("Profile 1"))
        let rule = Rule(pattern: "*.work.com", destination: chromeDestination(), isEnabled: true)
        let config = AppConfig(aliases: [aliasItem], rules: [rule], fallback: .picker)
        let (vm, store) = makeViewModel(config: config)
        vm.load()

        var edited = rule
        edited.destination = .alias(aliasItem.id)
        vm.updateRule(edited)

        XCTAssertEqual(vm.rules.first?.destination, .alias(aliasItem.id))
        XCTAssertEqual(store.lastSaved?.rules.first?.destination, .alias(aliasItem.id))
    }

    func testRuleEditedToBrowserPersistsBrowserDestination() {
        let aliasItem = alias("Work", chromeTarget("Profile 1"))
        let rule = Rule(pattern: "*.work.com", destination: .alias(aliasItem.id), isEnabled: true)
        let config = AppConfig(aliases: [aliasItem], rules: [rule], fallback: .picker)
        let (vm, store) = makeViewModel(config: config)
        vm.load()

        var edited = rule
        edited.destination = firefoxDestination("Personal")
        vm.updateRule(edited)

        XCTAssertEqual(vm.rules.first?.destination, firefoxDestination("Personal"))
        XCTAssertEqual(store.lastSaved?.rules.first?.destination, firefoxDestination("Personal"))
    }

    // MARK: - fallback destination shapes (Task 10: browser-or-alias default)

    func testFallbackWithAliasDestinationPersists() {
        let aliasItem = alias("Work", chromeTarget("Profile 1"))
        let config = AppConfig(aliases: [aliasItem], rules: [], fallback: .picker)
        let (vm, store) = makeViewModel(config: config)
        vm.load()

        vm.setFallback(.defaultBrowser(.alias(aliasItem.id)))

        XCTAssertEqual(vm.fallback, .defaultBrowser(.alias(aliasItem.id)))
        XCTAssertEqual(store.lastSaved?.fallback, .defaultBrowser(.alias(aliasItem.id)))
    }

    func testFallbackWithBrowserDestinationPersists() {
        let (vm, store) = makeViewModel(config: AppConfig(rules: [], fallback: .picker))
        vm.load()

        vm.setFallback(.defaultBrowser(chromeDestination("Work")))

        XCTAssertEqual(vm.fallback, .defaultBrowser(chromeDestination("Work")))
        XCTAssertEqual(store.lastSaved?.fallback, .defaultBrowser(chromeDestination("Work")))
    }
}
