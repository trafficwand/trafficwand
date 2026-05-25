import XCTest
@testable import TrafficWand

/// Tests for the **pure** status-menu decision logic (`StatusMenuState`).
///
/// The live menu (an `NSStatusItem` with a real `NSMenu`) is the thin AppKit
/// shell covered by Post-Completion manual verification. The *decision* — what
/// title and checkmark the default-browser item should show given whether we are
/// already the default — is pure and exercised here.
final class StatusMenuStateTests: XCTestCase {

    func testDefaultBrowserItemWhenAlreadyDefault() {
        let item = StatusMenuState.defaultBrowserItem(isDefault: true)

        XCTAssertEqual(item.title, "TrafficWand is your default browser")
        XCTAssertTrue(item.isChecked)
    }

    func testDefaultBrowserItemWhenNotDefault() {
        let item = StatusMenuState.defaultBrowserItem(isDefault: false)

        XCTAssertEqual(item.title, "Set as Default Browser…")
        XCTAssertFalse(item.isChecked)
    }
}
