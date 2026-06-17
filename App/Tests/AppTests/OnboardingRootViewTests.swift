import XCTest
@testable import TrafficWand

/// Tests for `OnboardingRootView` (Task 4): the paged onboarding card.
///
/// SwiftUI views are impractical to deep-assert in XCTest, so these tests verify
/// the behavior the view actually wires up:
///
///  - the view constructs across every page index without crashing;
///  - the per-page pure helpers the view uses for its layout decisions
///    (`OnboardingRootView.showsDefaultBrowserButton(for:)`,
///    `OnboardingRootView.primaryButtonTitle(isLastPage:)`) return the expected
///    values — i.e. the default-browser page shows a Set-as-Default affordance and
///    the last page's primary button is "Open Settings";
///  - the last page's primary action (`openSettings()`) reaches the injected
///    closure.
///
/// Uses an isolated `UserDefaults` suite for the `OnboardingStore`, never the
/// host's real defaults (mirrors `OnboardingViewModelTests`).
@MainActor
final class OnboardingRootViewTests: XCTestCase {

    // MARK: - Fixtures

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: OnboardingStore!

    private var openedTabs: [SettingsTab] = []
    private var finishedCount = 0

    override func setUp() {
        super.setUp()
        suiteName = "io.tomakado.TrafficWand.tests.onboardingView.\(UUID().uuidString)"
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

    private func makeViewModel() -> OnboardingViewModel {
        OnboardingViewModel(
            store: store,
            onOpenSettings: { [weak self] tab in self?.openedTabs.append(tab) },
            onFinish: { [weak self] in self?.finishedCount += 1 }
        )
    }

    private func makeView(viewModel: OnboardingViewModel) -> OnboardingRootView {
        OnboardingRootView(viewModel: viewModel, defaultBrowserManager: DefaultBrowserManager())
    }

    // MARK: - Construction across pages

    func testConstructsAcrossEveryPageIndexWithoutCrashing() {
        let vm = makeViewModel()
        for index in 0..<vm.pages.count {
            while vm.currentIndex < index { vm.next() }
            let view = makeView(viewModel: vm)
            // Touching `body` forces the page's view tree to build for this index.
            _ = view.body
        }
        XCTAssertEqual(vm.currentIndex, vm.pages.count - 1)
    }

    // MARK: - Default-browser affordance

    func testOnlyDefaultBrowserPageShowsSetAsDefaultButton() {
        XCTAssertFalse(OnboardingRootView.showsDefaultBrowserButton(for: .menuBar))
        XCTAssertTrue(OnboardingRootView.showsDefaultBrowserButton(for: .defaultBrowser))
        XCTAssertFalse(OnboardingRootView.showsDefaultBrowserButton(for: .rules))
        XCTAssertFalse(OnboardingRootView.showsDefaultBrowserButton(for: .aliases))
    }

    // MARK: - Primary button

    func testPrimaryButtonTitleIsNextUntilLastPageThenOpenSettings() {
        XCTAssertEqual(OnboardingRootView.primaryButtonTitle(isLastPage: false), "Next")
        XCTAssertEqual(OnboardingRootView.primaryButtonTitle(isLastPage: true), "Open Settings")
    }

    func testLastPagePrimaryActionDeepLinksRulesAndCompletes() {
        let vm = makeViewModel()
        for _ in 0..<vm.pages.count { vm.next() }
        XCTAssertTrue(vm.isLastPage)

        // Exercise the real button wiring (`primaryAction()`), not `openSettings()` /
        // `complete()` in isolation: on the last page it must deep-link `.rules`,
        // mark onboarding completed, and fire `onFinish` (here a counter; production
        // closes the window) — exactly once.
        makeView(viewModel: vm).primaryAction()

        XCTAssertEqual(openedTabs, [.rules])
        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertEqual(finishedCount, 1)
    }

    func testIntermediatePagePrimaryActionAdvances() {
        let vm = makeViewModel()
        XCTAssertFalse(vm.isLastPage)

        // On a non-last page, the primary button advances and does NOT complete.
        makeView(viewModel: vm).primaryAction()

        XCTAssertEqual(vm.currentIndex, 1)
        XCTAssertTrue(openedTabs.isEmpty)
        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertEqual(finishedCount, 0)
    }
}
