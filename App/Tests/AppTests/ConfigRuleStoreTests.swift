import XCTest
import TrafficWandCore
@testable import TrafficWand

/// Tests for `ConfigRuleStore` (Task 3).
///
/// `ConfigRuleStore` is the App-side `RulePersisting` adapter: it builds a
/// remember-rule from a URL (`RememberRule`), upserts it into the stored config
/// (`AppConfig.upserting`), and persists it via `ConfigStore`. These tests drive
/// it with a mock store that mirrors saves back into its loaded config (so an
/// upsert sees the previously-saved rule), and assert on the recorded saves.
final class ConfigRuleStoreTests: XCTestCase {

    // MARK: - Mocks

    /// Mock `ConfigStore`: returns a seeded config on `load`, records every `save`,
    /// and mirrors the saved config back into `loaded` so a subsequent load sees it.
    ///
    /// `@unchecked Sendable` because `ConfigStore` is `Sendable` but the mock holds
    /// mutable recording state; tests use it single-threaded.
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

    // MARK: - Fixtures

    private func chromeTarget(_ profile: String? = nil) -> BrowserTarget {
        BrowserTarget(bundleID: "com.google.Chrome", profileID: profile)
    }

    private func firefoxTarget(_ profile: String? = nil) -> BrowserTarget {
        BrowserTarget(bundleID: "org.mozilla.firefox", profileID: profile)
    }

    // MARK: - remember()

    func testRememberSavesARuleScopedToTheRegistrableDomain() {
        let store = MockConfigStore(loaded: AppConfig(rules: [], fallback: .picker))
        let sut = ConfigRuleStore(configStore: store)

        let target = chromeTarget("Work")
        sut.remember(url: URL(string: "https://www.x.com/some/path")!, target: target)

        XCTAssertEqual(store.saveCount, 1)
        let rules = store.lastSaved?.rules ?? []
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.pattern, "*x.com")
        XCTAssertEqual(rules.first?.target, target)
        XCTAssertEqual(rules.first?.isEnabled, true)
    }

    func testRememberSameDomainTwiceUpdatesRatherThanDuplicates() {
        let store = MockConfigStore(loaded: AppConfig(rules: [], fallback: .picker))
        let sut = ConfigRuleStore(configStore: store)

        sut.remember(url: URL(string: "https://www.x.com/a")!, target: chromeTarget("Work"))
        let latest = firefoxTarget("Personal")
        sut.remember(url: URL(string: "https://news.x.com/b")!, target: latest)

        // Two saves, but the final config has a single rule for the domain with the
        // latest target (upsert, not append).
        XCTAssertEqual(store.saveCount, 2)
        let rules = store.lastSaved?.rules ?? []
        let matching = rules.filter { $0.pattern == "*x.com" }
        XCTAssertEqual(matching.count, 1)
        XCTAssertEqual(matching.first?.target, latest)
    }

    func testRememberPreservesExistingUnrelatedRule() {
        let unrelated = Rule(
            pattern: "*github.com",
            target: firefoxTarget("Personal"),
            isEnabled: true
        )
        let store = MockConfigStore(loaded: AppConfig(rules: [unrelated], fallback: .picker))
        let sut = ConfigRuleStore(configStore: store)

        let target = chromeTarget("Work")
        sut.remember(url: URL(string: "https://www.x.com/some/path")!, target: target)

        XCTAssertEqual(store.saveCount, 1)
        let rules = store.lastSaved?.rules ?? []
        // The pre-existing rule survives, and the new domain rule is appended after it.
        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(rules.first, unrelated)
        XCTAssertEqual(rules.last?.pattern, "*x.com")
        XCTAssertEqual(rules.last?.target, target)
    }

    func testRememberHostlessURLSavesNothing() {
        let store = MockConfigStore(loaded: AppConfig(rules: [], fallback: .picker))
        let sut = ConfigRuleStore(configStore: store)

        sut.remember(url: URL(string: "mailto:foo@x.com")!, target: chromeTarget())

        XCTAssertEqual(store.saveCount, 0)
    }

    func testRememberSwallowsSaveError() {
        let store = MockConfigStore(loaded: AppConfig(rules: [], fallback: .picker))
        store.saveError = ConfigStoreError.corruptConfiguration
        let sut = ConfigRuleStore(configStore: store)

        // Must not throw even though save fails.
        sut.remember(url: URL(string: "https://www.x.com/a")!, target: chromeTarget())

        XCTAssertEqual(store.saveCount, 1, "A save was attempted.")
        // The save threw before mirroring, so the persisted/loaded config is unchanged.
        XCTAssertTrue(store.loaded.rules.isEmpty)
    }

    func testRememberSwallowsLoadError() {
        let store = MockConfigStore(loaded: AppConfig(rules: [], fallback: .picker))
        store.loadError = ConfigStoreError.corruptConfiguration
        let sut = ConfigRuleStore(configStore: store)

        // Load failure must not throw and must not attempt a save.
        sut.remember(url: URL(string: "https://www.x.com/a")!, target: chromeTarget())

        XCTAssertEqual(store.saveCount, 0)
    }
}
