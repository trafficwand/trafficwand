import AppKit
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
                        // The "specific browser" mode needs a real destination; disable
                        // it only when there is neither a browser nor an alias to target,
                        // so we never persist an unusable empty-bundleID target.
                        Text(mode.title)
                            .tag(mode)
                            .disabled(mode == .defaultBrowser && !hasAnyDestination)
                    }
                }
                .pickerStyle(.radioGroup)

                if !hasAnyDestination {
                    Text("Install a browser or create an alias to route to a specific one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if currentMode == .defaultBrowser {
                    fallbackDestinationEditor
                }
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $viewModel.automaticUpdatesEnabled)
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshDefaultStatus() }
        // The default-browser status can change outside the app (e.g. via System
        // Settings). Re-read whenever the app becomes active so the row never goes
        // stale while the Settings window stays open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshDefaultStatus()
        }
    }

    /// Re-reads whether TrafficWand is currently the default browser.
    private func refreshDefaultStatus() {
        isDefaultBrowser = defaultBrowserManager.isDefault
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

    /// Whether there is any destination (browser or alias) to route to. Entering
    /// `.defaultBrowser` mode is refused unless this is true.
    private var hasAnyDestination: Bool {
        !viewModel.browsers.isEmpty || !viewModel.aliases.isEmpty
    }

    /// Binding that maps a `FallbackMode` selection back to a `FallbackPolicy`,
    /// preserving any already-chosen destination when switching into `.defaultBrowser`.
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
                    // Refuse to enter .defaultBrowser with no destination at all: it
                    // would persist an unusable empty-bundleID target. The option is
                    // also visually disabled above; this is the load-bearing guard.
                    guard hasAnyDestination else { return }
                    viewModel.setFallback(.defaultBrowser(currentDefaultDestination))
                }
            }
        )
    }

    /// The destination used when entering `.defaultBrowser` mode: the existing one if
    /// the policy already carries it, else the first browser, else the first alias.
    private var currentDefaultDestination: RoutingDestination {
        if case .defaultBrowser(let destination) = viewModel.fallback {
            return destination
        }
        if let bundleID = viewModel.browsers.first?.bundleID {
            return .browser(BrowserTarget(bundleID: bundleID, profileID: nil))
        }
        if let alias = viewModel.aliases.first {
            return .alias(alias.id)
        }
        return .browser(BrowserTarget(bundleID: "", profileID: nil))
    }

    // MARK: - Fallback destination editor (browser-or-alias)

    /// The destination kind the fallback routes to, surfaced as a segmented control.
    private enum DestinationMode: String, CaseIterable, Identifiable {
        case browser
        case alias
        var id: String { rawValue }

        var title: String {
            switch self {
            case .browser: return "Browser"
            case .alias: return "Alias"
            }
        }
    }

    private var currentDestinationMode: DestinationMode {
        if case .alias = currentDefaultDestination { return .alias }
        return .browser
    }

    private var destinationModeBinding: Binding<DestinationMode> {
        Binding(
            get: { currentDestinationMode },
            set: { mode in
                switch mode {
                case .browser:
                    guard let bundleID = viewModel.browsers.first?.bundleID else { return }
                    viewModel.setFallback(.defaultBrowser(
                        .browser(BrowserTarget(bundleID: bundleID, profileID: nil))
                    ))
                case .alias:
                    guard let alias = viewModel.aliases.first else { return }
                    viewModel.setFallback(.defaultBrowser(.alias(alias.id)))
                }
            }
        )
    }

    @ViewBuilder
    private var fallbackDestinationEditor: some View {
        Picker("Destination", selection: destinationModeBinding) {
            ForEach(DestinationMode.allCases) { mode in
                Text(mode.title)
                    .tag(mode)
                    .disabled(
                        (mode == .browser && viewModel.browsers.isEmpty)
                            || (mode == .alias && viewModel.aliases.isEmpty)
                    )
            }
        }
        .pickerStyle(.segmented)

        switch currentDestinationMode {
        case .browser:
            fallbackBrowserPickers
        case .alias:
            fallbackAliasPicker
        }
    }

    /// The concrete target carried by the current default destination when it is a
    /// `.browser` (else an empty target for the picker bindings to fall back on).
    private var currentDefaultTarget: BrowserTarget {
        if case .browser(let target) = currentDefaultDestination {
            return target
        }
        return BrowserTarget(bundleID: viewModel.browsers.first?.bundleID ?? "", profileID: nil)
    }

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

    @ViewBuilder
    private var fallbackAliasPicker: some View {
        Picker("Alias", selection: fallbackAliasBinding) {
            ForEach(viewModel.aliases) { alias in
                Text(alias.name).tag(UUID?.some(alias.id))
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
                viewModel.setFallback(.defaultBrowser(.browser(
                    BrowserTarget(bundleID: bundleID, profileID: keepProfile ? currentDefaultTarget.profileID : nil)
                )))
            }
        )
    }

    private var fallbackProfileBinding: Binding<String?> {
        Binding(
            get: { currentDefaultTarget.profileID },
            set: { profileID in
                viewModel.setFallback(.defaultBrowser(.browser(
                    BrowserTarget(bundleID: currentDefaultTarget.bundleID, profileID: profileID)
                )))
            }
        )
    }

    private var fallbackAliasBinding: Binding<UUID?> {
        Binding(
            get: {
                if case .alias(let id) = currentDefaultDestination { return id }
                return viewModel.aliases.first?.id
            },
            set: { id in
                guard let id else { return }
                viewModel.setFallback(.defaultBrowser(.alias(id)))
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
