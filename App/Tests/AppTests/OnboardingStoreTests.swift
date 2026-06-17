import XCTest
@testable import TrafficWand

/// Tests for `OnboardingStore` (Task 1): the first-launch flag seam that records
/// whether the onboarding flow has been completed, so it is shown exactly once.
///
/// CRITICAL: these tests use an **isolated** `UserDefaults` suite (a per-suite
/// domain), never the app's real defaults, and remove that domain in `tearDown`
/// so the host machine's defaults are untouched (mirrors `LastUsedStoreTests`).
final class OnboardingStoreTests: XCTestCase {

    /// A unique suite name per test instance keeps parallel/isolated runs clean.
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: OnboardingStore!

    override func setUp() {
        super.setUp()
        suiteName = "io.tomakado.TrafficWand.tests.onboarding.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = OnboardingStore(defaults: defaults)
    }

    override func tearDown() {
        // Wipe the isolated domain so nothing leaks into real defaults.
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Default state

    func testDefaultIsNotCompleted() {
        XCTAssertFalse(store.hasCompletedOnboarding)
    }

    // MARK: - Mark completed

    func testMarkCompletedSetsCompleted() {
        store.markCompleted()
        XCTAssertTrue(store.hasCompletedOnboarding)
    }

    func testMarkCompletedIsIdempotent() {
        store.markCompleted()
        store.markCompleted()
        XCTAssertTrue(store.hasCompletedOnboarding)
    }

    // MARK: - Persistence is real (survives a fresh store on the same suite)

    func testCompletionPersistsAcrossStoreInstancesOnSameSuite() {
        store.markCompleted()

        // A brand-new store over the same UserDefaults suite must see the flag.
        let reopened = OnboardingStore(defaults: UserDefaults(suiteName: suiteName)!)

        XCTAssertTrue(reopened.hasCompletedOnboarding)
    }

    // MARK: - Isolation guard

    func testStoreDoesNotPolluteStandardDefaults() {
        // The app host shares `UserDefaults.standard` with the real app, which may
        // legitimately mark onboarding completed when it runs. Assert our isolated
        // store leaves standard UNCHANGED (not that it starts empty), so the test is
        // robust whether or not the app has been used on this machine. Guards against
        // a leaked test write silently marking the dev's own install as onboarded.
        let before = UserDefaults.standard.object(forKey: OnboardingStore.defaultsKey)

        store.markCompleted()

        let after = UserDefaults.standard.object(forKey: OnboardingStore.defaultsKey)
        XCTAssertEqual(
            before as? Bool, after as? Bool,
            "isolated store must not write to standard defaults"
        )
    }
}
