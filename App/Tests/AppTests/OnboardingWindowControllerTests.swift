import AppKit
import SwiftUI
import XCTest
@testable import TrafficWand

/// Tests for `OnboardingWindowController` (Task 5): the `NSWindow` adapter that
/// hosts `OnboardingRootView`, mirroring `SettingsWindowController`.
///
/// Verifies the controller builds, `show()` doesn't crash, and dismissing the
/// window via the `windowWillClose` delegate path marks the injected
/// `OnboardingStore` completed and fires `onFinish` exactly once. Also pins the
/// production wiring: the last-page primary action both deep-links `.rules` and
/// closes the window, and `onFinish` fires exactly once across the full
/// button-press → `close()` → `windowWillClose` sequence (no double-fire).
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

    /// Builds a controller wired exactly like production: `onFinish` calls the
    /// controller's `close()` (so the last-page button dismisses the window), plus a
    /// test counter so we can assert it fires exactly once. Returns both the
    /// controller and its view model so tests can drive the real button path.
    private func makeController() -> (OnboardingWindowController, OnboardingViewModel) {
        var controllerRef: OnboardingWindowController?
        let viewModel = OnboardingViewModel(
            store: store,
            onOpenSettings: { [weak self] tab in self?.openedTabs.append(tab) },
            onFinish: { [weak self] in
                self?.finishedCount += 1
                controllerRef?.close()
            }
        )
        let controller = OnboardingWindowController(viewModel: viewModel)
        controllerRef = controller
        return (controller, viewModel)
    }

    /// Rebuilds the `OnboardingRootView` the controller hosts, sharing the same view
    /// model, so a test can invoke the real `primaryAction()` button wiring.
    private func makeView(viewModel: OnboardingViewModel) -> OnboardingRootView {
        OnboardingRootView(viewModel: viewModel, defaultBrowserManager: DefaultBrowserManager())
    }

    // MARK: - Construction

    func testControllerBuilds() {
        _ = makeController()
        XCTAssertFalse(store.hasCompletedOnboarding)
    }

    // MARK: - Show

    func testShowDoesNotCrash() {
        let (controller, _) = makeController()
        controller.show()
        XCTAssertFalse(store.hasCompletedOnboarding)
        controller.close()
        XCTAssertTrue(store.hasCompletedOnboarding)
    }

    // MARK: - Completion on close

    func testClosingWindowMarksStoreCompletedAndFiresOnFinish() {
        let (controller, _) = makeController()
        controller.show()
        XCTAssertFalse(store.hasCompletedOnboarding)

        controller.close()

        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertEqual(finishedCount, 1)
    }

    /// The production terminal path: the last-page primary button deep-links
    /// `.rules`, completes onboarding, AND closes the window — and `onFinish` fires
    /// exactly once across the full button-press → `close()` → `windowWillClose`
    /// re-entry (idempotent `complete()`, no double-fire / recursion).
    func testLastPagePrimaryActionDeepLinksRulesClosesWindowAndFiresOnFinishOnce() {
        let (controller, viewModel) = makeController()
        controller.show()
        for _ in 0..<viewModel.pages.count { viewModel.next() }
        XCTAssertTrue(viewModel.isLastPage)

        // Drive the real button wiring (not openSettings()/complete() in isolation).
        makeView(viewModel: viewModel).primaryAction()

        XCTAssertEqual(openedTabs, [.rules], "last-page button must deep-link to Rules")
        XCTAssertTrue(store.hasCompletedOnboarding, "onboarding must be marked completed")
        XCTAssertEqual(finishedCount, 1, "onFinish must fire exactly once across button + windowWillClose")
    }
}
