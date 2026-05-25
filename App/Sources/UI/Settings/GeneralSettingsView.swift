import SwiftUI
import TrafficWandCore

/// The general tab: fallback policy selection plus default-browser status and a
/// "Set as Default" button.
///
/// The fallback policy is one of three modes. `.defaultBrowser` additionally needs
/// a browser (and optional profile) target, so selecting that mode reveals a
/// browser + profile picker. Every change is committed to `SettingsViewModel`,
/// which persists immediately. The default-browser status and the Set-as-Default
/// action go through the injected `DefaultBrowserManager` (the only AppKit-touching
/// dependency here; injected so the view stays previewable/testable-adjacent).
struct GeneralSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    /// Manages default-browser status + the Set-as-Default request.
    let defaultBrowserManager: DefaultBrowserManager

    /// The selected fallback mode, mapped to/from `FallbackPolicy` by the view model.
    private enum FallbackMode: String, CaseIterable, Identifiable {
        case picker
        case defaultBrowser
        case lastUsed
        var id: String { rawValue }

        var title: String {
            switch self {
            case .picker: return "Show picker"
            case .defaultBrowser: return "Open in a specific browser"
            case .lastUsed: return "Use last-used browser"
            }
        }
    }

    /// Re-read on appear/refresh; the live default status can change outside the app.
    @State private var isDefaultBrowser = false

    var body: some View {
        Form {
            Section("Default Browser") {
                HStack {
                    Image(systemName: isDefaultBrowser ? "checkmark.seal.fill" : "exclamationmark.triangle")
                        .foregroundStyle(isDefaultBrowser ? .green : .orange)
                    Text(isDefaultBrowser
                        ? "TrafficWand is your default browser."
                        : "TrafficWand is not your default browser.")
                    Spacer()
                    if !isDefaultBrowser {
                        Button("Set as Default") { setAsDefault() }
                    }
                }
            }

            Section("When no rule matches") {
                Picker("Fallback", selection: fallbackModeBinding) {
                    ForEach(FallbackMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                if currentMode == .defaultBrowser {
                    fallbackBrowserPickers
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { isDefaultBrowser = defaultBrowserManager.isDefault }
    }

    // MARK: - Fallback mode binding

    /// The mode derived from the current `FallbackPolicy`.
    private var currentMode: FallbackMode {
        switch viewModel.fallback {
        case .picker: return .picker
        case .defaultBrowser: return .defaultBrowser
        case .lastUsed: return .lastUsed
        }
    }

    /// Binding that maps a `FallbackMode` selection back to a `FallbackPolicy`,
    /// preserving any already-chosen target when switching into `.defaultBrowser`.
    private var fallbackModeBinding: Binding<FallbackMode> {
        Binding(
            get: { currentMode },
            set: { mode in
                switch mode {
                case .picker:
                    viewModel.setFallback(.picker)
                case .lastUsed:
                    viewModel.setFallback(.lastUsed)
                case .defaultBrowser:
                    viewModel.setFallback(.defaultBrowser(currentDefaultTarget))
                }
            }
        )
    }

    /// The target used when entering `.defaultBrowser` mode: the existing one if the
    /// policy already carries it, else the first available browser, else empty.
    private var currentDefaultTarget: BrowserTarget {
        if case .defaultBrowser(let target) = viewModel.fallback {
            return target
        }
        let bundleID = viewModel.browsers.first?.bundleID ?? ""
        return BrowserTarget(bundleID: bundleID, profileID: nil)
    }

    // MARK: - Fallback browser + profile pickers

    @ViewBuilder
    private var fallbackBrowserPickers: some View {
        Picker("Browser", selection: fallbackBundleBinding) {
            ForEach(viewModel.browsers) { browser in
                Text(browser.name).tag(browser.bundleID)
            }
        }

        if let browser = selectedFallbackBrowser, !browser.profiles.isEmpty {
            Picker("Profile", selection: fallbackProfileBinding) {
                Text("Default").tag(String?.none)
                ForEach(browser.profiles) { profile in
                    Text(profile.name).tag(String?.some(profile.id))
                }
            }
        }
    }

    private var selectedFallbackBrowser: Browser? {
        viewModel.browsers.first { $0.bundleID == currentDefaultTarget.bundleID }
    }

    private var fallbackBundleBinding: Binding<String> {
        Binding(
            get: { currentDefaultTarget.bundleID },
            set: { bundleID in
                // Switching browser resets the profile unless the new browser has it.
                let newBrowser = viewModel.browsers.first { $0.bundleID == bundleID }
                let keepProfile = newBrowser?.profiles.contains { $0.id == currentDefaultTarget.profileID } ?? false
                viewModel.setFallback(.defaultBrowser(
                    BrowserTarget(bundleID: bundleID, profileID: keepProfile ? currentDefaultTarget.profileID : nil)
                ))
            }
        )
    }

    private var fallbackProfileBinding: Binding<String?> {
        Binding(
            get: { currentDefaultTarget.profileID },
            set: { profileID in
                viewModel.setFallback(.defaultBrowser(
                    BrowserTarget(bundleID: currentDefaultTarget.bundleID, profileID: profileID)
                ))
            }
        )
    }

    // MARK: - Set as default

    private func setAsDefault() {
        defaultBrowserManager.setAsDefault { _ in
            Task { @MainActor in
                isDefaultBrowser = defaultBrowserManager.isDefault
            }
        }
    }
}
