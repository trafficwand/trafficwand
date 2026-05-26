import XCTest
import TrafficWandCore
@testable import TrafficWand

/// Tests for `LastUsedStore` (Task 12): the small persistence seam that records
/// the last browser/profile a fallback link was sent to, so `.lastUsed` policy
/// can resolve.
///
/// CRITICAL: these tests use an **isolated** `UserDefaults` suite (a per-suite
/// domain), never the app's real defaults, and remove that domain in `tearDown`
/// so the host machine's defaults are untouched.
final class LastUsedStoreTests: XCTestCase {

    /// A unique suite name per test instance keeps parallel/isolated runs clean.
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: LastUsedStore!

    override func setUp() {
        super.setUp()
        suiteName = "io.tomakado.TrafficWand.tests.lastUsed.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = LastUsedStore(defaults: defaults)
    }

    override func tearDown() {
        // Wipe the isolated domain so nothing leaks into real defaults.
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Empty state

    func testGetReturnsNilWhenNothingStored() {
        XCTAssertNil(store.get())
    }

    // MARK: - Set / get round trip

    func testSetThenGetRoundTripsTargetWithProfile() {
        let target = BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 1")

        store.set(target)

        XCTAssertEqual(store.get(), target)
    }

    func testSetThenGetRoundTripsTargetWithoutProfile() {
        let target = BrowserTarget(bundleID: "com.apple.Safari", profileID: nil)

        store.set(target)

        XCTAssertEqual(store.get(), target)
    }

    func testSetOverwritesPreviousValue() {
        store.set(BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 1"))
        let latest = BrowserTarget(bundleID: "org.mozilla.firefox", profileID: "default-release")

        store.set(latest)

        XCTAssertEqual(store.get(), latest)
    }

    // MARK: - Clear

    func testClearRemovesStoredValue() {
        store.set(BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 1"))

        store.clear()

        XCTAssertNil(store.get())
    }

    func testClearOnEmptyStoreIsNoOp() {
        store.clear()
        XCTAssertNil(store.get())
    }

    // MARK: - Persistence is real (survives a fresh store on the same suite)

    func testValuePersistsAcrossStoreInstancesOnSameSuite() {
        let target = BrowserTarget(bundleID: "com.brave.Browser", profileID: "Default")
        store.set(target)

        // A brand-new store over the same UserDefaults suite must see the value.
        let reopened = LastUsedStore(defaults: UserDefaults(suiteName: suiteName)!)

        XCTAssertEqual(reopened.get(), target)
    }

    // MARK: - Isolation guard

    func testStoreDoesNotPolluteStandardDefaults() {
        // The app host shares `UserDefaults.standard` with the real app, which
        // legitimately records a last-used target when it runs. Assert our isolated
        // store leaves standard UNCHANGED (not that it starts empty), so the test is
        // robust whether or not the app has been used on this machine.
        let before = UserDefaults.standard.data(forKey: LastUsedStore.defaultsKey)

        store.set(BrowserTarget(bundleID: "com.google.Chrome", profileID: "Profile 1"))

        let after = UserDefaults.standard.data(forKey: LastUsedStore.defaultsKey)
        XCTAssertEqual(before, after, "isolated store must not write to standard defaults")
    }
}
