import XCTest
@testable import TrafficWand

/// Tests for `OnboardingViewModel` (Task 2): the `@Observable @MainActor`
/// navigation state backing the onboarding flow.
///
/// The view model owns the page list, the current index, navigation (`next()` /
/// `back()` with clamping), and turns user actions into injected side effects
/// (`openSettings()` → `onOpenSettings(.rules)`, `complete()` →
/// `store.markCompleted()` + `onFinish()`). It performs **no** AppKit work —
/// `DefaultBrowserManager` is held by the view, keeping this fully testable.
///
/// These tests use an isolated `UserDefaults` suite for the `OnboardingStore`,
/// never the host's real defaults (mirrors `OnboardingStoreTests`).
@MainActor
final class OnboardingViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: OnboardingStore!

    /// Records the side effects fired by the view model's actions.
    private var openedTabs: [SettingsTab] = []
    private var finishedCount = 0

    override func setUp() {
        super.setUp()
        suiteName = "io.tomakado.TrafficWand.tests.onboardingVM.\(UUID().uuidString)"
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

    // MARK: - Pages

    func testPagesAreInExpectedOrder() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.pages, [.menuBar, .defaultBrowser, .rules, .aliases])
    }

    func testStartsAtFirstPage() {
        let vm = makeViewModel()
        XCTAssertEqual(vm.currentIndex, 0)
        XCTAssertEqual(vm.currentPage, .menuBar)
        XCTAssertTrue(vm.isFirstPage)
        XCTAssertFalse(vm.isLastPage)
    }

    // MARK: - Navigation

    func testNextAdvances() {
        let vm = makeViewModel()
        vm.next()
        XCTAssertEqual(vm.currentIndex, 1)
        XCTAssertEqual(vm.currentPage, .defaultBrowser)
        XCTAssertFalse(vm.isFirstPage)
        XCTAssertFalse(vm.isLastPage)
    }

    func testNextClampsAtLastPage() {
        let vm = makeViewModel()
        for _ in 0..<10 { vm.next() }
        XCTAssertEqual(vm.currentIndex, vm.pages.count - 1)
        XCTAssertEqual(vm.currentPage, .aliases)
        XCTAssertTrue(vm.isLastPage)
    }

    func testBackRetreats() {
        let vm = makeViewModel()
        vm.next()
        vm.next()
        vm.back()
        XCTAssertEqual(vm.currentIndex, 1)
        XCTAssertEqual(vm.currentPage, .defaultBrowser)
    }

    func testBackClampsAtFirstPage() {
        let vm = makeViewModel()
        for _ in 0..<5 { vm.back() }
        XCTAssertEqual(vm.currentIndex, 0)
        XCTAssertTrue(vm.isFirstPage)
    }

    // MARK: - Open Settings

    func testOpenSettingsInvokesClosureWithRulesTab() {
        let vm = makeViewModel()
        vm.openSettings()
        XCTAssertEqual(openedTabs, [.rules])
    }

    // MARK: - Complete

    func testCompleteMarksStoreCompletedAndFiresOnFinish() {
        let vm = makeViewModel()
        XCTAssertFalse(store.hasCompletedOnboarding)

        vm.complete()

        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertEqual(finishedCount, 1)
    }

    func testCompleteIsIdempotent() {
        let vm = makeViewModel()
        vm.complete()
        vm.complete()
        vm.complete()
        XCTAssertTrue(store.hasCompletedOnboarding)
        // `complete()` is idempotent via the `didFinish` guard: `onFinish` fires at
        // most once across all calls, so the button-press → close → windowWillClose
        // sequence never double-fires (no double-close / re-entrancy).
        XCTAssertEqual(finishedCount, 1)
    }
}
