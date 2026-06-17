import AppKit
import SwiftUI

/// The paged first-launch onboarding card.
///
/// Each page shows a flat, framed visual (`FramedScreenshot` — the rasterized
/// `MenuBarIllustration` for the menu-bar page, a named screenshot asset for the
/// others), the page title, and its body copy. A footer carries the live actions —
/// Back, the primary button, and a page-dot indicator. All navigation/completion
/// state lives in the injected `OnboardingViewModel`; this view performs no
/// decision logic of its own beyond a couple of pure per-page layout helpers.
///
/// The `defaultBrowser` page adds a live "Set as Default" button wired to the
/// injected `DefaultBrowserManager`. Matching `GeneralSettingsView`, the manager is
/// held by the **view** (not the view model): `@State isDefaultBrowser` is refreshed
/// on appear and whenever the app becomes active, since the default-browser status
/// can change outside the app.
///
/// The last page's primary button is "Open Settings" — it deep-links to the Rules
/// tab (issue #9's "button to open rules editor / settings"), then completes the
/// flow so the window closes and onboarding never reappears.
struct OnboardingRootView: View {
    @Bindable var viewModel: OnboardingViewModel

    /// Manages default-browser status + the Set-as-Default request. Held by the
    /// view (like `GeneralSettingsView`), keeping the view model AppKit-free.
    let defaultBrowserManager: DefaultBrowserManager

    /// Re-read on appear/refresh; the live default status can change outside the app.
    @State private var isDefaultBrowser = false

    /// Whether a given page should surface the live "Set as Default" affordance.
    /// Pure so the per-page layout decision is unit-testable.
    static func showsDefaultBrowserButton(for page: OnboardingPage) -> Bool {
        page == .defaultBrowser
    }

    /// The primary footer button's title: "Next" until the last page, then the
    /// "Open Settings" call to action. Pure so it can be asserted in tests.
    static func primaryButtonTitle(isLastPage: Bool) -> String {
        isLastPage ? "Open Settings" : "Next"
    }

    var body: some View {
        VStack(spacing: 24) {
            FramedScreenshot(source: imageSource(for: viewModel.currentPage), caption: viewModel.currentPage.title)
                .frame(maxHeight: 280)

            VStack(spacing: 10) {
                Text(viewModel.currentPage.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text(viewModel.currentPage.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            if Self.showsDefaultBrowserButton(for: viewModel.currentPage) {
                defaultBrowserAffordance
            }

            Spacer(minLength: 0)

            footer
        }
        .padding(28)
        .frame(width: 540, height: 600)
        .onAppear { refreshDefaultStatus() }
        // The default-browser status can change outside the app (e.g. via System
        // Settings). Re-read whenever the app becomes active so the row never goes
        // stale while the onboarding window stays open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshDefaultStatus()
        }
    }

    // MARK: - Image source

    /// Maps a page's `ImageSource` to a `FramedScreenshot.Source`, baking the
    /// menu-bar illustration to an `NSImage` for the `.rendered` case.
    private func imageSource(for page: OnboardingPage) -> FramedScreenshot.Source {
        switch page.image {
        case .asset(let name):
            return .asset(name)
        case .rendered:
            return .rendered(MenuBarIllustration.rendered())
        }
    }

    // MARK: - Default-browser affordance

    @ViewBuilder
    private var defaultBrowserAffordance: some View {
        HStack {
            Image(systemName: isDefaultBrowser ? "checkmark.seal.fill" : "exclamationmark.triangle")
                .foregroundStyle(isDefaultBrowser ? .green : .orange)
            Text(isDefaultBrowser
                ? "TrafficWand is your default browser."
                : "TrafficWand is not your default browser.")
                .font(.callout)
            Spacer()
            if !isDefaultBrowser {
                Button("Set as Default") { setAsDefault() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
        )
        .frame(maxWidth: 420)
    }

    private func refreshDefaultStatus() {
        isDefaultBrowser = defaultBrowserManager.isDefault
    }

    private func setAsDefault() {
        defaultBrowserManager.setAsDefault { _ in
            Task { @MainActor in
                isDefaultBrowser = defaultBrowserManager.isDefault
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 16) {
            pageDots

            HStack {
                Button("Back") { viewModel.back() }
                    .disabled(viewModel.isFirstPage)

                Spacer()

                Button(Self.primaryButtonTitle(isLastPage: viewModel.isLastPage)) {
                    primaryAction()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// One dot per page, the current one filled.
    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<viewModel.pages.count, id: \.self) { index in
                Circle()
                    .fill(index == viewModel.currentIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(viewModel.currentIndex + 1) of \(viewModel.pages.count)")
    }

    /// The primary button: advance on intermediate pages; on the last page open
    /// Settings (deep-linked to Rules) and complete the flow.
    private func primaryAction() {
        if viewModel.isLastPage {
            viewModel.openSettings()
            viewModel.complete()
        } else {
            viewModel.next()
        }
    }
}

#if DEBUG
#Preview {
    OnboardingRootView(
        viewModel: PreviewFixtures.makePreviewOnboardingViewModel(),
        defaultBrowserManager: DefaultBrowserManager()
    )
}
#endif
