import XCTest
import TrafficWandCore

/// Proves the app **test** target links against the local `TrafficWandCore`
/// package (the wiring verified in Task 1). Real app-layer tests arrive in
/// later tasks.
final class AppSmokeTests: XCTestCase {
    func testCorePackageIsLinked() {
        XCTAssertEqual(TrafficWandCore.name, "TrafficWandCore")
    }
}
