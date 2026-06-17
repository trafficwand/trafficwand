import AppKit
import SwiftUI
import XCTest
@testable import TrafficWand

/// Tests for the onboarding image views' pure helpers.
///
/// `FramedScreenshot.image(forAsset:)` is the testable resolution decision: it
/// returns `nil` for an asset that isn't in the catalog (the placeholder branch)
/// and a non-`nil` `NSImage` once a matching asset exists. `MenuBarIllustration`
/// is rasterized via `ImageRenderer` and must produce a non-`nil` `NSImage`.
final class OnboardingImageTests: XCTestCase {

    func testImageForAssetReturnsNilForMissingAsset() {
        // A name that is never in the catalog → nil, driving FramedScreenshot to its
        // drawn placeholder branch. (Don't key this on a real onboarding asset name:
        // those resolve once the user drops the screenshot PNG into the catalog.)
        let resolved = FramedScreenshot.image(forAsset: "definitely-not-a-real-asset-name")
        XCTAssertNil(resolved)
    }

    func testImageForAssetReturnsImageWhenPresent() {
        // A system catalog name that always resolves, exercising the asset branch
        // without depending on a screenshot PNG that the user adds later.
        let resolved = FramedScreenshot.image(forAsset: NSImage.applicationIconName)
        XCTAssertNotNil(resolved)
    }

    @MainActor
    func testMenuBarIllustrationRasterizesToImage() {
        for scheme in [ColorScheme.light, .dark] {
            let image = MenuBarIllustration.rendered(colorScheme: scheme)
            XCTAssertNotNil(image, "expected a rasterized image for \(scheme)")
            if let image {
                XCTAssertGreaterThan(image.size.width, 0)
                XCTAssertGreaterThan(image.size.height, 0)
            }
        }
    }
}
