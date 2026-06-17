import Foundation
import Observation

/// Observable navigation state backing the first-launch onboarding flow.
///
/// This is the fully unit-testable heart of onboarding: it owns the page list and
/// the current index, advances/retreats with clamping at the bounds, and turns the
/// two terminal user actions into injected side effects so the view model itself
/// performs **no** AppKit work:
///
///  - `openSettings()` → `onOpenSettings(.rules)` (the host opens the Settings
///    window deep-linked to the Rules tab; the view dismisses afterward).
///  - `complete()` → marks the `OnboardingStore` completed (so the flow shows
///    exactly once) and fires `onFinish` (the host closes the onboarding window).
///
/// `DefaultBrowserManager` is intentionally **not** held here — the default-browser
/// page's live "Set as Default" button is owned by the view (exactly like
/// `GeneralSettingsView`), keeping this view model free of `NSWorkspace` and fully
/// testable.
@MainActor
@Observable
final class OnboardingViewModel {
    /// The ordered onboarding pages (= `OnboardingPage.allCases`).
    let pages: [OnboardingPage] = OnboardingPage.allCases

    /// Index of the currently shown page within `pages`.
    private(set) var currentIndex: Int = 0

    private let store: OnboardingStore
    private let onOpenSettings: (SettingsTab) -> Void
    private let onFinish: () -> Void

    /// - Parameters:
    ///   - store: The first-launch flag store; `complete()` marks it completed.
    ///   - onOpenSettings: Receives the deep-link `SettingsTab` when the user opens
    ///     Settings from the last page (always `.rules`).
    ///   - onFinish: Invoked when onboarding completes; the host closes the window.
    init(
        store: OnboardingStore,
        onOpenSettings: @escaping (SettingsTab) -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.store = store
        self.onOpenSettings = onOpenSettings
        self.onFinish = onFinish
    }

    /// The page currently shown.
    var currentPage: OnboardingPage {
        pages[currentIndex]
    }

    /// Whether the first page is shown (so the view can hide / disable Back).
    var isFirstPage: Bool {
        currentIndex == 0
    }

    /// Whether the last page is shown (so the view can swap Next for the primary
    /// "Open Settings" action).
    var isLastPage: Bool {
        currentIndex == pages.count - 1
    }

    /// Fractional progress through the flow (0 on the first page, 1 on the last),
    /// for a progress indicator.
    var progress: Double {
        guard pages.count > 1 else { return 1 }
        return Double(currentIndex) / Double(pages.count - 1)
    }

    /// Advances to the next page, clamping at the last (no wraparound).
    func next() {
        currentIndex = min(currentIndex + 1, pages.count - 1)
    }

    /// Retreats to the previous page, clamping at the first (no wraparound).
    func back() {
        currentIndex = max(currentIndex - 1, 0)
    }

    /// Asks the host to open Settings deep-linked to the Rules tab.
    func openSettings() {
        onOpenSettings(.rules)
    }

    /// Marks onboarding completed (so it shows exactly once) and fires `onFinish`.
    /// Marking the store is idempotent; `onFinish` fires per call (the window
    /// controller dedups window-close vs. button-press via the store flag).
    func complete() {
        store.markCompleted()
        onFinish()
    }
}
