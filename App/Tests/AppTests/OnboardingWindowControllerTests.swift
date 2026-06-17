import AppKit
import SwiftUI
import XCTest
@testable import TrafficWand

/// Tests for `OnboardingWindowController` (Task 5): the `NSWindow` adapter that
/// hosts `OnboardingRootView`, mirroring `SettingsWindowController`.
///
/// Verifies the controller builds, `show()` doesn't crash, and dismissing the
/// window via the `windowWillClose` delegate path marks the injected
/// `OnboardingStore` completed and fires `onFinish` exactly once.
///
/// Uses an isolated `UserDefaults(suiteName:)` for the store so the host's real
/// defaults are never touched (mirrors `OnboardingViewModelTests`).
@MainActor
final class OnboardingWindowControllerTests: XCTestCase {

    // MARK: - Fixtures

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: OnboardingStore!

    private var openedTabs: [SettingsTab] = []
    private var finishedCount = 0

    override func setUp() {
        super.setUp()
        suiteName = "io.tomakado.TrafficWand.tests.onboardingWC.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = OnboardingStore(defaults: defaults)
        openedTabs = []
        finishedCount = 0
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeController() -> OnboardingWindowController {
        let viewModel = OnboardingViewModel(
            store: store,
            onOpenSettings: { [weak self] tab in self?.openedTabs.append(tab) },
            onFinish: { [weak self] in self?.finishedCount += 1 }
        )
        return OnboardingWindowController(viewModel: viewModel)
    }

    // MARK: - Construction

    func testControllerBuilds() {
        _ = makeController()
        XCTAssertFalse(store.hasCompletedOnboarding)
    }

    // MARK: - Show

    func testShowDoesNotCrash() {
        let controller = makeController()
        controller.show()
        controller.closeWindowForTesting()
    }

    // MARK: - Completion on close

    func testClosingWindowMarksStoreCompletedAndFiresOnFinish() {
        let controller = makeController()
        controller.show()
        XCTAssertFalse(store.hasCompletedOnboarding)

        controller.closeWindowForTesting()

        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertEqual(finishedCount, 1)
    }
}
