import XCTest
@testable import TrafficWand

/// Tests the single-instance decision: a fresh launch proceeds, but a launch that
/// finds another running copy yields (and the app quits) so two processes never
/// share `config.json`.
final class AppMainSingleInstanceTests: XCTestCase {

    func testYieldsWhenAnotherInstanceIsRunning() {
        XCTAssertTrue(AppMain.shouldYieldToExistingInstance(otherInstanceCount: 1))
        XCTAssertTrue(AppMain.shouldYieldToExistingInstance(otherInstanceCount: 3))
    }

    func testProceedsWhenNoOtherInstance() {
        XCTAssertFalse(AppMain.shouldYieldToExistingInstance(otherInstanceCount: 0))
    }
}
