import AppKit
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
        // No PNG is shipped for this name yet, so the resolver must return nil,
        // driving FramedScreenshot to its drawn placeholder branch.
        let resolved = FramedScreenshot.image(forAsset: "onboarding-default-browser")
        XCTAssertNil(resolved)
    }

    func testImageForAssetReturnsNilForNonsenseName() {
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
        let image = MenuBarIllustration.rendered()
        XCTAssertNotNil(image)
        if let image {
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
        }
    }
}
