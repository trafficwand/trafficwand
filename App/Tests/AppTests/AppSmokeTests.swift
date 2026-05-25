import XCTest
import TrafficWandCore

/// Proves the app **test** target links against the local `TrafficWandCore`
/// package (the wiring verified in Task 1) by touching a real Core type.
final class AppSmokeTests: XCTestCase {
    func testCorePackageIsLinked() {
        XCTAssertEqual(AppConfig.default.fallback, .picker)
    }
}
