import XCTest
@testable import TrafficWand

/// Smoke tests for the AboutSettingsView's static link constants.
///
/// The URLs are force-unwrapped `URL(string:)` literals — a typo in the
/// string would crash on the *first* render of the About tab in the field.
/// These tests catch that at build time by exercising the same force-unwrap
/// paths without rendering the view.
final class AboutSettingsViewTests: XCTestCase {

    func testSponsorURLConstructs() {
        XCTAssertEqual(
            AboutSettingsView.Links.sponsor.absoluteString,
            "https://github.com/sponsors/tomakado"
        )
    }

    func testLicenseURLConstructs() {
        XCTAssertEqual(
            AboutSettingsView.Links.license.absoluteString,
            "https://github.com/trafficwand/trafficwand/blob/main/LICENSE"
        )
    }
}
