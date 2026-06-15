import SwiftUI
import TrafficWandCore

/// Edits a single profile alias: its display name and the concrete browser +
/// profile it resolves to.
///
/// Presented as a sheet from `AliasesListView`. It edits a local working copy and
/// only commits via `onSave` when the user confirms, so cancelling leaves the
/// underlying config untouched. The profile picker is driven by the profiles of
/// the currently-chosen browser, and switching browsers resets a profile the new
/// browser can't honor (mirrors `RuleEditorView`).
struct AliasEditorView: View {
    /// The browsers available as alias targets (with discovered profiles).
    let browsers: [Browser]

    /// Working copy of the alias being edited.
    @State private var draft: ProfileAlias

    /// Commit handler: receives the finished alias. Called on Save only.
    let onSave: (ProfileAlias) -> Void
    /// Dismiss handler: called on Cancel or after Save.
    let onCancel: () -> Void

    init(
        alias: ProfileAlias,
        browsers: [Browser],
        onSave: @escaping (ProfileAlias) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.browsers = browsers
        self._draft = State(initialValue: alias)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    /// The browser currently selected (if it is among the available browsers).
    private var selectedBrowser: Browser? {
        browsers.first { $0.bundleID == draft.target.bundleID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Alias")
                .font(.headline)

            Form {
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("Personal"))
                        .textFieldStyle(.roundedBorder)
                    Text("A reusable name (e.g. \"Personal\", \"Work\") that rules and the "
                        + "fallback can point at. Re-pointing it here updates every rule that uses it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    BrowserProfilePicker(browsers: browsers, target: $draft.target)
                }
            }
            .formStyle(.grouped)

            HStack {
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
    }

    /// Whether the alias can be saved: a non-empty name and a resolvable browser.
    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && selectedBrowser != nil
    }
}

#if DEBUG
#Preview("Alias Editor") {
    AliasEditorView(
        alias: PreviewFixtures.sampleAliases.first!,
        browsers: PreviewFixtures.sampleBrowsers,
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("Alias Editor — new") {
    AliasEditorView(
        alias: ProfileAlias(
            name: "",
            target: BrowserTarget(
                bundleID: PreviewFixtures.sampleBrowsers.first!.bundleID,
                profileID: nil
            )
        ),
        browsers: PreviewFixtures.sampleBrowsers,
        onSave: { _ in },
        onCancel: {}
    )
}
#endif
