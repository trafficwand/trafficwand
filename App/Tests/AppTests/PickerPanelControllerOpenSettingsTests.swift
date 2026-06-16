import AppKit
import XCTest
import TrafficWandCore
@testable import TrafficWand

/// Tests for `PickerPanelController`'s open-settings forwarding (Task 3 of the
/// picker-settings-entry plan).
///
/// The controller's job here is two-step wiring:
///
///  1. When `presentPicker` (or its test seam, `makeViewModel(url:browsers:)`)
///     builds a `PickerViewModel`, the view model's `onOpenSettings` closure must
///     forward to the controller's `handleOpenSettings(tab:)`, which in turn
///     invokes the injected `onOpenSettings: @MainActor (SettingsTab) -> Void`
///     closure with the requested tab and then dismisses the panel.
///  2. `handleOpenSettings` is re-entrancy-guarded by the same `isDismissing`
///     flag that protects `handleSelection`. A second call while the picker is
///     already animating out (e.g. a stray click on the gear, or `⌘,` pressed
///     twice) must be a no-op.
///
/// The pure VM-side forwarding (each `SettingsTab` value reaches the injected
/// closure) is covered by `PickerViewModelTests`; here we add coverage that
/// must live at the controller layer: an anticipatory smoke test for a
/// `SettingsTab` case the picker UI doesn't expose today, the
/// dismiss-on-action behaviour, and the re-entrancy guard.
@MainActor
final class PickerPanelControllerOpenSettingsTests: XCTestCase {

    // MARK: - Fakes

    /// No-op `BrowserLaunching`: never invoked in these tests (open-settings does
    /// not launch), but required to construct a controller.
    private struct NoopLauncher: BrowserLaunching, @unchecked Sendable {
        func launch(target: BrowserTarget, browser: Browser, url: URL) throws {}
    }

    /// No-op `LastUsedRecording`: open-settings does not touch last-used.
    private final class NoopLastUsed: LastUsedRecording {
        func get() -> BrowserTarget? { nil }
        func set(_ target: BrowserTarget) {}
    }

    /// No-op `RulePersisting`: open-settings does not remember a rule.
    private struct NoopRulePersister: RulePersisting {
        func remember(url: URL, destination: RoutingDestination) {}
    }

    /// Stub icon provider — open-settings does not paint, but the controller's
    /// init requires one.
    private struct StubIconProvider: BrowserIconProviding {
        func icon(for browser: Browser) -> NSImage {
            NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!
        }
    }

    /// Recorder for the injected `onOpenSettings` closure. Appends every tab
    /// the controller was asked to open.
    ///
    /// `@unchecked Sendable` because the recorder is captured by an `@escaping`
    /// closure stored on the controller but mutated single-threaded on the main
    /// actor during the test.
    private final class OpenSettingsRecorder: @unchecked Sendable {
        var tabs: [SettingsTab] = []
    }

    // MARK: - Fixtures

    private let url = URL(string: "https://example.com/page")!

    private let safari = Browser(
        bundleID: "com.apple.Safari",
        name: "Safari",
        appURL: URL(fileURLWithPath: "/Applications/Safari.app"),
        profiles: []
    )

    /// Builds a controller wired to a fresh recorder, returning both.
    private func makeController() -> (PickerPanelController, OpenSettingsRecorder) {
        let recorder = OpenSettingsRecorder()
        let controller = PickerPanelController(
            launcher: NoopLauncher(),
            lastUsedStore: NoopLastUsed(),
            rulePersister: NoopRulePersister(),
            iconProvider: StubIconProvider(),
            onOpenSettings: { tab in
                recorder.tabs.append(tab)
            }
        )
        return (controller, recorder)
    }

    // MARK: - View model wiring

    func testViewModelOpenSettingsAboutForwardsToInjectedOpener() {
        // `.about` is a `SettingsTab` case the picker UI itself doesn't expose
        // today (gear → `.rules`, `⌘,` → `.general`). Anticipatory smoke test
        // that the wiring passes any tab value through transparently for any
        // future entry point that wants to deep-link to another tab.
        let (controller, recorder) = makeController()

        let viewModel = controller.makeViewModel(url: url, browsers: [safari])
        viewModel.openSettings(tab: .about)

        XCTAssertEqual(recorder.tabs, [.about])
    }

    // MARK: - Dismiss-on-action

    func testHandleOpenSettingsDismissesThePresentedPicker() {
        // Present a live picker, then ask the controller to open Settings. The
        // panel must be torn down synchronously (the `panel` reference is
        // cleared by `dismiss()` before the fade-out animation begins) so the
        // floating picker isn't left stacking above the Settings window.
        let (controller, _) = makeController()

        controller.presentPicker(url: url, browsers: [safari])
        XCTAssertTrue(controller.isPickerVisible, "presentPicker should leave a panel installed")

        controller.handleOpenSettings(tab: .rules)

        XCTAssertFalse(
            controller.isPickerVisible,
            "handleOpenSettings should dismiss the picker so it doesn't overlap Settings"
        )
    }

    // MARK: - Re-entrancy guard

    func testHandleOpenSettingsIgnoresSecondCallWhileDismissing() {
        // With a live panel, the first `handleOpenSettings` call invokes
        // `dismiss()`, which synchronously sets `isDismissing = true` (the
        // animation runs over ~0.18s, but the flag flips first). A second call
        // inside that window — e.g. a stray click on the gear or a repeated
        // `⌘,` keypress before the panel finishes fading — must be guarded and
        // produce no additional opener invocation, mirroring the protection on
        // `handleSelection`.
        let (controller, recorder) = makeController()

        controller.presentPicker(url: url, browsers: [safari])
        controller.handleOpenSettings(tab: .rules)
        controller.handleOpenSettings(tab: .rules)

        XCTAssertEqual(recorder.tabs, [.rules])
    }

    // MARK: - State recovery

    func testHandleOpenSettingsAfterRepresentingPickerWorksAgain() {
        // After a dismiss-via-open-settings, a freshly presented picker must be
        // able to open Settings again — i.e. the controller's state (the
        // `isDismissing` latch in particular) is reset by `presentPicker`. A
        // regression that left the latch stuck would silently break the gear /
        // `⌘,` entry points on every subsequent picker.
        let (controller, recorder) = makeController()

        controller.presentPicker(url: url, browsers: [safari])
        controller.handleOpenSettings(tab: .rules)

        controller.presentPicker(url: url, browsers: [safari])
        controller.handleOpenSettings(tab: .general)

        XCTAssertEqual(recorder.tabs, [.rules, .general])
    }
}
