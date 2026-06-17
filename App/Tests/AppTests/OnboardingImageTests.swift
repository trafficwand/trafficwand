import AppKit
import SwiftUI
import XCTest
@testable import TrafficWand

/// Tests that every onboarding illustration rasterizes to a non-`nil` `NSImage` in
/// both light and dark — driving `FramedScreenshot`'s image branch (rather than its
/// placeholder fallback) and confirming the theme-aware render path works.
final class OnboardingImageTests: XCTestCase {

    @MainActor
    func testIllustrationsRasterizeInBothColorSchemes() {
        for scheme in [ColorScheme.light, .dark] {
            assertRenders(MenuBarIllustration.rendered(colorScheme: scheme), "menu bar", scheme)
            assertRenders(DefaultBrowserIllustration.rendered(colorScheme: scheme), "default browser", scheme)
            assertRenders(RulesIllustration.rendered(colorScheme: scheme), "rules", scheme)
            assertRenders(AliasesIllustration.rendered(colorScheme: scheme), "aliases", scheme)
        }
    }

    private func assertRenders(_ image: NSImage?, _ name: String, _ scheme: ColorScheme) {
        XCTAssertNotNil(image, "expected \(name) to rasterize in \(scheme)")
        if let image {
            XCTAssertGreaterThan(image.size.width, 0, "\(name) width in \(scheme)")
            XCTAssertGreaterThan(image.size.height, 0, "\(name) height in \(scheme)")
        }
    }
}
