import SwiftUI
import TrafficWandCore

/// Edits a single routing rule: its glob pattern, destination browser + profile,
/// and enabled flag.
///
/// Presented as a sheet from `RulesListView`. It edits a local working copy and
/// only commits via `onSave` when the user confirms, so cancelling leaves the
/// underlying config untouched. The pattern field is annotated with glob examples
/// (the documented v1 host-glob semantics) and the profile picker is driven by the
/// profiles of the currently-chosen browser.
struct RuleEditorView: View {
    /// The browsers available as rule destinations (with discovered profiles).
    let browsers: [Browser]

    /// Working copy of the rule being edited.
    @State private var draft: Rule

    /// The chosen browser's bundle ID, tracked separately so the profile picker can
    /// react to browser changes (and reset the profile when it is unsupported).
    @State private var selectedBundleID: String

    /// The chosen profile id (`nil` = default profile), tracked separately from the
    /// target so the picker can bind to an optional cleanly.
    @State private var selectedProfileID: String?

    /// Commit handler: receives the finished rule. Called on Save only.
    let onSave: (Rule) -> Void
    /// Dismiss handler: called on Cancel or after Save.
    let onCancel: () -> Void

    init(
        rule: Rule,
        browsers: [Browser],
        onSave: @escaping (Rule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.browsers = browsers
        self._draft = State(initialValue: rule)
        self._selectedBundleID = State(initialValue: rule.target.bundleID)
        self._selectedProfileID = State(initialValue: rule.target.profileID)
        self.onSave = onSave
        self.onCancel = onCancel
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

    /// Whether the rule can be saved: a non-empty pattern and a resolvable browser.
    /// Guards against persisting an unusable target (e.g. an empty browser list).
    private var canSave: Bool {
        !draft.pattern.trimmingCharacters(in: .whitespaces).isEmpty && selectedBrowser != nil
    }

    private func commit() {
        var finished = draft
        finished.target = BrowserTarget(
            bundleID: selectedBundleID,
            profileID: selectedProfileID
        )
        onSave(finished)
    }

    /// Documented v1 glob semantics with concrete examples, shown under the field.
    private static let globHelpText = """
    Wildcards match the host. * = any characters (e.g. *.github.com matches \
    gist.github.com), *google.com matches google.com and its subdomains, \
    ? = exactly one character. Matching is case-insensitive.
    """
}
