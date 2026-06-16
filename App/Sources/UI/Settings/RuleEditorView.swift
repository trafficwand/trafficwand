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
///
/// When editing an existing rule (i.e. `onDelete` is non-nil), the editor also shows a
/// destructive "Delete Rule" button, guarded by a confirmation dialog; it is hidden in
/// the add case. The title likewise reads "Edit Rule" vs "Add Rule" off that same flag.
struct RuleEditorView: View {
    /// The browsers available as rule destinations (with discovered profiles).
    let browsers: [Browser]

    /// The aliases available as rule destinations.
    let aliases: [ProfileAlias]

    /// Working copy of the rule being edited.
    @State private var draft: Rule

    /// Commit handler: receives the finished rule. Called on Save only.
    let onSave: (Rule) -> Void
    /// Dismiss handler: called on Cancel or after Save.
    let onCancel: () -> Void
    /// Delete handler: when non-nil (editing an existing rule, not adding), a
    /// destructive "Delete Rule" button is shown that, on confirmation, calls this.
    let onDelete: (() -> Void)?

    /// Drives the delete confirmation dialog.
    @State private var showingDeleteConfirmation = false

    init(
        rule: Rule,
        browsers: [Browser],
        aliases: [ProfileAlias],
        onSave: @escaping (Rule) -> Void,
        onCancel: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.browsers = browsers
        self.aliases = aliases
        self._draft = State(initialValue: rule)
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(onDelete == nil ? "Add Rule" : "Edit Rule")
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
                    DestinationEditor(
                        browsers: browsers,
                        aliases: aliases,
                        destination: $draft.destination
                    )
                }

                Section {
                    Toggle("Enabled", isOn: $draft.isEnabled)
                }
            }
            .formStyle(.grouped)

            HStack {
                if onDelete != nil {
                    Button("Delete Rule", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                    // A standalone destructive push button is not red on macOS (only in
                    // menus/confirmation dialogs); tint the label explicitly.
                    .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 460)
        .confirmationDialog(
            "Delete this rule?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Whether the rule can be saved: a non-empty pattern and a destination that
    /// resolves to a real browser or a still-present alias.
    private var canSave: Bool {
        guard !draft.pattern.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch draft.destination {
        case .browser(let target):
            return browsers.contains { $0.bundleID == target.bundleID }
        case .alias(let id):
            return aliases.contains { $0.id == id }
        }
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

#Preview("Rule Editor — deletable") {
    RuleEditorView(
        rule: PreviewFixtures.sampleRules.first!,
        browsers: PreviewFixtures.sampleBrowsers,
        aliases: PreviewFixtures.sampleAliases,
        onSave: { _ in },
        onCancel: {},
        onDelete: {}
    )
}
#endif
