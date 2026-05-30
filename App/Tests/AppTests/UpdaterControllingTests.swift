import XCTest
@testable import TrafficWand

/// Tests for the `UpdaterControlling` seam contract (Task 3).
///
/// The concrete `SparkleUpdater` is exercised only via the manual update flow —
/// its behavior is Sparkle's and isn't unit-testable in-process. What *is* testable
/// is the seam shape that `StatusBarController` and `SettingsViewModel` depend on:
/// `checkForUpdates()` is forwarded, `automaticallyChecksForUpdates` round-trips,
/// and `canCheckForUpdates` is readable. `MockUpdater` records calls and stores the
/// property so downstream wiring (Tasks 4–5) can be tested against it.
@MainActor
final class UpdaterControllingTests: XCTestCase {

    /// Mock seam: records `checkForUpdates()` calls, round-trips the auto-check
    /// property, and exposes a settable `canCheckForUpdates` so tests can simulate
    /// "busy" / "ready" states.
    private final class MockUpdater: UpdaterControlling {
        private(set) var checkForUpdatesCallCount = 0
        var automaticallyChecksForUpdates = false
        var canCheckForUpdates = true

        func checkForUpdates() {
            checkForUpdatesCallCount += 1
        }
    }

    func testCheckForUpdatesIsForwarded() {
        let updater = MockUpdater()
        XCTAssertEqual(updater.checkForUpdatesCallCount, 0)

        updater.checkForUpdates()
        updater.checkForUpdates()

        XCTAssertEqual(updater.checkForUpdatesCallCount, 2,
                       "Each checkForUpdates() call should be recorded")
    }

    func testAutomaticallyChecksForUpdatesRoundTrips() {
        let updater = MockUpdater()
        XCTAssertFalse(updater.automaticallyChecksForUpdates)

        updater.automaticallyChecksForUpdates = true
        XCTAssertTrue(updater.automaticallyChecksForUpdates,
                      "Setting the property should be reflected on read")

        updater.automaticallyChecksForUpdates = false
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
    }

    func testCanCheckForUpdatesIsReadable() {
        let updater = MockUpdater()
        XCTAssertTrue(updater.canCheckForUpdates)

        updater.canCheckForUpdates = false
        XCTAssertFalse(updater.canCheckForUpdates,
                       "canCheckForUpdates reflects the updater's readiness")
    }

    /// The seam is referenced through the protocol type by `StatusBarController`
    /// and `SettingsViewModel`, so confirm the mock satisfies that abstraction.
    func testMockConformsToSeamThroughProtocolType() {
        let updater: any UpdaterControlling = MockUpdater()
        updater.automaticallyChecksForUpdates = true
        updater.checkForUpdates()

        XCTAssertTrue(updater.automaticallyChecksForUpdates)
        XCTAssertTrue(updater.canCheckForUpdates)
    }
}
