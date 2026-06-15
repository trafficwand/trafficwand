import SwiftUI
import TrafficWandCore

/// Edits a single routing rule: its glob pattern, destination (a concrete browser
/// + profile **or** a reusable alias), and enabled flag.
///
/// Presented as a sheet from `RulesListView`. It edits a local working copy and
/// only commits via `onSave` when the user confirms, so cancelling leaves the
/// underlying config untouched. A segmented control switches the destination
/// between "Browser" (the bundle/profile pickers) and "Alias" (a picker over the
/// configured aliases); `commit()` builds the matching `RoutingDestination`.
struct RuleEditorView: View {
    /// The browsers available as rule destinations (with discovered profiles).
    let browsers: [Browser]

    /// The aliases available as rule destinations.
    let aliases: [ProfileAlias]

    /// Working copy of the rule being edited.
    @State private var draft: Rule

    /// The active destination mode (Browser vs Alias), seeded from the rule.
    @State private var mode: DestinationMode

    /// The chosen browser's bundle ID, tracked separately so the profile picker can
    /// react to browser changes (and reset the profile when it is unsupported).
    @State private var selectedBundleID: String

    /// The chosen profile id (`nil` = default profile), tracked separately from the
    /// target so the picker can bind to an optional cleanly.
    @State private var selectedProfileID: String?

    /// The chosen alias id when in `.alias` mode (`nil` until one is picked).
    @State private var selectedAliasID: UUID?

    /// Commit handler: receives the finished rule. Called on Save only.
    let onSave: (Rule) -> Void
    /// Dismiss handler: called on Cancel or after Save.
    let onCancel: () -> Void

    /// The destination kind a rule routes to, surfaced as a segmented control.
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

    init(
        rule: Rule,
        browsers: [Browser],
        aliases: [ProfileAlias],
        onSave: @escaping (Rule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.browsers = browsers
        self.aliases = aliases
        self._draft = State(initialValue: rule)
        self.onSave = onSave
        self.onCancel = onCancel

        // Seed the mode + selections from the rule's existing destination.
        switch rule.destination {
        case .browser(let target):
            self._mode = State(initialValue: .browser)
            self._selectedBundleID = State(initialValue: target.bundleID)
            self._selectedProfileID = State(initialValue: target.profileID)
            self._selectedAliasID = State(initialValue: aliases.first?.id)
        case .alias(let id):
            self._mode = State(initialValue: .alias)
            self._selectedBundleID = State(initialValue: browsers.first?.bundleID ?? "")
            self._selectedProfileID = State(initialValue: nil)
            self._selectedAliasID = State(initialValue: id)
        }
    }

    /// The browser currently selected (if it is among the available browsers).
    private var selectedBrowser: Browser? {
        browsers.first { $0.bundleID == selectedBundleID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Rule")
                .font(.headline)

            Form {
                Section {
                    TextField("Pattern", text: $draft.pattern, prompt: Text("*.github.com"))
                        .textFieldStyle(.roundedBorder)
                    Text(Self.globHelpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Destination", selection: $mode) {
                        ForEach(DestinationMode.allCases) { mode in
                            Text(mode.title)
                                .tag(mode)
                                // No aliases configured → no alias to pick; keep the
                                // user in Browser mode rather than offering an empty list.
                                .disabled(mode == .alias && aliases.isEmpty)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .browser:
                        browserPickers
                    case .alias:
                        aliasPicker
                    }
                }

                Section {
                    Toggle("Enabled", isOn: $draft.isEnabled)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onChange(of: selectedBundleID) { _, _ in
            // Switching to a browser that lacks the previously-chosen profile clears
            // the profile so we never persist a profile the new browser can't honor.
            if let selectedBrowser, !selectedBrowser.profiles.contains(where: { $0.id == selectedProfileID }) {
                selectedProfileID = nil
            }
        }
    }

    @ViewBuilder
    private var browserPickers: some View {
        Picker("Browser", selection: $selectedBundleID) {
            ForEach(browsers) { browser in
                Text(browser.name).tag(browser.bundleID)
            }
        }

        if let selectedBrowser, !selectedBrowser.profiles.isEmpty {
            Picker("Profile", selection: $selectedProfileID) {
                Text("Default").tag(String?.none)
                ForEach(selectedBrowser.profiles) { profile in
                    Text(profile.name).tag(String?.some(profile.id))
                }
            }
        }
    }

    @ViewBuilder
    private var aliasPicker: some View {
        Picker("Alias", selection: $selectedAliasID) {
            ForEach(aliases) { alias in
                Text(alias.name).tag(UUID?.some(alias.id))
            }
        }
    }

    /// Whether the rule can be saved: a non-empty pattern and a resolvable
    /// destination in the active mode.
    private var canSave: Bool {
        guard !draft.pattern.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch mode {
        case .browser:
            return selectedBrowser != nil
        case .alias:
            return selectedAliasID.map { id in aliases.contains { $0.id == id } } ?? false
        }
    }

    private func commit() {
        var finished = draft
        switch mode {
        case .browser:
            finished.destination = .browser(
                BrowserTarget(bundleID: selectedBundleID, profileID: selectedProfileID)
            )
        case .alias:
            // `canSave` guarantees a resolvable alias id is selected here.
            if let id = selectedAliasID {
                finished.destination = .alias(id)
            }
        }
        onSave(finished)
    }

    /// Documented v1 glob semantics with concrete examples, shown under the field.
    private static let globHelpText = """
    Wildcards match the host. * = any characters (e.g. *.github.com matches \
    gist.github.com), *google.com matches google.com and its subdomains, \
    ? = exactly one character. Matching is case-insensitive.
    """
}

#if DEBUG
#Preview("Rule Editor") {
    RuleEditorView(
        rule: PreviewFixtures.sampleRules.first!,
        browsers: PreviewFixtures.sampleBrowsers,
        aliases: PreviewFixtures.sampleAliases,
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("Rule Editor — new") {
    RuleEditorView(
        rule: Rule(
            pattern: "",
            destination: .browser(
                BrowserTarget(
                    bundleID: PreviewFixtures.sampleBrowsers.first!.bundleID,
                    profileID: nil
                )
            ),
            isEnabled: true
        ),
        browsers: PreviewFixtures.sampleBrowsers,
        aliases: PreviewFixtures.sampleAliases,
        onSave: { _ in },
        onCancel: {}
    )
}
#endif
