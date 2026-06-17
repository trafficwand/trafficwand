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
///    exactly once) and fires `onFinish` (the host closes the onboarding
///    window). It is idempotent — both side effects run at most once across the
///    last-page button press and the subsequent `windowWillClose`.
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

    /// Guards `complete()` so its side effects (`markCompleted()` + `onFinish()`)
    /// run exactly once across all completion paths — the last-page button and the
    /// subsequent `windowWillClose`. Without this, closing the window after the
    /// button completed would fire `onFinish` (which closes the window) a second
    /// time, risking re-entrancy.
    private var didFinish = false

    /// - Parameters:
    ///   - store: The first-launch flag store; `complete()` marks it completed.
    ///   - onOpenSettings: Receives the deep-link `SettingsTab` when the user opens
    ///     Settings from the last page (always `.rules`).
    ///   - onFinish: Invoked once when onboarding completes; the host wires this to
    ///     close the onboarding window. `complete()`'s `didFinish` guard ensures it
    ///     fires at most once even across the button-press + `windowWillClose` paths.
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

    /// Marks onboarding completed (so it shows exactly once) and fires `onFinish`
    /// (the host closes the window). Idempotent via the `didFinish` guard: the
    /// last-page button calls this, and the resulting window close calls it again
    /// from `windowWillClose` — only the first call does work, so `onFinish` never
    /// re-fires (no double-close / re-entrancy).
    func complete() {
        guard !didFinish else { return }
        didFinish = true
        store.markCompleted()
        onFinish()
    }
}
