import XCTest
@testable import TrafficWand

/// Tests for the **pure** "is the current default handler us?" comparison helper
/// behind `DefaultBrowserManager.isDefault` (Task 12).
///
/// The live query (which app currently handles http/https) is the thin,
/// untested `NSWorkspace` adapter line; the *decision* — comparing the current
/// default bundle ID to our own, case-insensitively — is pure and exercised here.
final class DefaultBrowserStatusTests: XCTestCase {

    func testMatchingBundleIDIsDefault() {
        XCTAssertTrue(
            DefaultBrowserManager.isCurrentDefault(
                currentDefaultBundleID: "io.tomakado.TrafficWand",
                ourBundleID: "io.tomakado.TrafficWand"
            )
        )
    }

    func testCaseInsensitiveMatchIsDefault() {
        XCTAssertTrue(
            DefaultBrowserManager.isCurrentDefault(
                currentDefaultBundleID: "IO.TOMAKADO.trafficwand",
                ourBundleID: "io.tomakado.TrafficWand"
            )
        )
    }

    func testDifferentBundleIDIsNotDefault() {
        XCTAssertFalse(
            DefaultBrowserManager.isCurrentDefault(
                currentDefaultBundleID: "com.google.Chrome",
                ourBundleID: "io.tomakado.TrafficWand"
            )
        )
    }

    func testNilCurrentDefaultIsNotDefault() {
        XCTAssertFalse(
            DefaultBrowserManager.isCurrentDefault(
                currentDefaultBundleID: nil,
                ourBundleID: "io.tomakado.TrafficWand"
            )
        )
    }

    func testEmptyCurrentDefaultIsNotDefault() {
        XCTAssertFalse(
            DefaultBrowserManager.isCurrentDefault(
                currentDefaultBundleID: "",
                ourBundleID: "io.tomakado.TrafficWand"
            )
        )
    }
}
