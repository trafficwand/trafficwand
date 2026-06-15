import SwiftUI
import TrafficWandCore

/// Inline live-persist editor for a single profile alias: its display name and the
/// concrete browser + profile it resolves to.
///
/// Shown in the detail pane of `AliasesListView`'s `NavigationSplitView` for the
/// selected alias. Unlike the former sheet, there is **no Save/Cancel** and no local
/// draft: every change commits straight through `viewModel.updateAlias`, matching the
/// app's persist-on-mutation pattern.
///
/// - The **name** field commits on Enter (`.onSubmit`) **and** on focus-out: an
///   editable `TextField` only fires `.onSubmit` on Return, so a `@FocusState` +
///   `.onChange(of:)` pair flushes the typed name when focus leaves. Committing on
///   commit boundaries (not every keystroke) avoids persisting a half-typed name.
/// - The **browser/profile** change commits immediately when `BrowserProfilePicker`
///   writes through its binding. The profile picker is driven by the profiles of the
///   currently-chosen browser, and switching browsers resets a profile the new
///   browser can't honor (mirrors `RuleEditorView`).
struct AliasEditorView: View {
    @Bindable var viewModel: SettingsViewModel

    /// The id of the alias being edited; the live alias is fetched from the view
    /// model so the editor always reflects the current persisted value.
    let aliasID: UUID

    /// Local editing buffer for the name, committed on Enter / focus-out so a
    /// half-typed name is never persisted mid-keystroke.
    @State private var nameText: String

    @FocusState private var nameFieldFocused: Bool

    init(viewModel: SettingsViewModel, aliasID: UUID) {
        self.viewModel = viewModel
        self.aliasID = aliasID
        self._nameText = State(initialValue: viewModel.alias(withID: aliasID)?.name ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $nameText, prompt: Text("Personal"))
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFieldFocused)
                    .onSubmit { commitName() }
                    .onChange(of: nameFieldFocused) { _, focused in
                        // `.onSubmit` only fires on Return; flush on focus-out too.
                        if !focused { commitName() }
                    }
                Text("A reusable name (e.g. \"Personal\", \"Work\") that rules and the "
                    + "fallback can point at. Re-pointing it here updates every rule that uses it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                BrowserProfilePicker(browsers: viewModel.browsers, target: targetBinding)
            }
        }
        .formStyle(.grouped)
        // Re-seed the name buffer (and reset focus state) when the selection changes
        // to a different alias, so the field shows the newly-selected alias's name.
        .onChange(of: aliasID) { _, newID in
            nameText = viewModel.alias(withID: newID)?.name ?? ""
        }
    }

    /// Binding to the selected alias's concrete target. Writing commits the whole
    /// alias (with the new target) via `updateAlias` immediately.
    private var targetBinding: Binding<BrowserTarget> {
        Binding(
            get: { viewModel.alias(withID: aliasID)?.target ?? BrowserTarget(bundleID: "", profileID: nil) },
            set: { newTarget in
                guard var alias = viewModel.alias(withID: aliasID) else { return }
                alias.target = newTarget
                viewModel.updateAlias(alias)
            }
        )
    }

    /// Commits the buffered name to the alias and persists, unless it is unchanged.
    private func commitName() {
        guard var alias = viewModel.alias(withID: aliasID), alias.name != nameText else { return }
        alias.name = nameText
        viewModel.updateAlias(alias)
    }
}

#if DEBUG
#Preview("Alias Editor") {
    AliasEditorView(
        viewModel: PreviewFixtures.makePreviewSettingsViewModel(),
        aliasID: PreviewFixtures.sampleAliases.first!.id
    )
    .frame(width: 460, height: 320)
}
#endif
