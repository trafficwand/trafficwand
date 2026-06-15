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
///   The commit is **alias-identity-safe**: it is given the alias id to write to
///   explicitly, so a focus-out that races a selection change can never write the
///   buffered text onto the newly-selected alias. The detail pane in `AliasesListView`
///   additionally pins this view's identity with `.id(aliasID)` so switching
///   selection re-inits the editor (fresh `nameText`); the editor itself still
///   flushes the **outgoing** alias on `.onChange(of: aliasID)` (and on `.onDisappear`)
///   so a typed-but-unsubmitted name is neither lost nor misrouted.
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
                    .onSubmit { commitName(to: aliasID) }
                    .onChange(of: nameFieldFocused) { _, focused in
                        // `.onSubmit` only fires on Return; flush on focus-out too.
                        // Commit explicitly to the alias currently being edited so a
                        // focus-out that races a selection change can't misroute.
                        if !focused { commitName(to: aliasID) }
                    }
                Text("The name rules and the fallback refer to this alias by.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                BrowserProfilePicker(browsers: viewModel.browsers, target: targetBinding)
            }
        }
        .formStyle(.grouped)
        // When the selection changes to a different alias, flush the OUTGOING alias's
        // buffered name first (using `oldID`, before re-seeding) so a typed-but-
        // unsubmitted name is committed to the right alias, then re-seed the buffer
        // for the newly-selected alias. (With `.id(aliasID)` on the detail view this
        // path is normally not hit — SwiftUI re-inits the editor — but it is kept as a
        // belt-and-braces safeguard against a reused instance.)
        .onChange(of: aliasID) { oldID, newID in
            commitName(to: oldID)
            nameText = viewModel.alias(withID: newID)?.name ?? ""
        }
        // Flush a typed-but-unsubmitted name when the editor is torn down (selection
        // cleared / switched to the placeholder), since `.onChange(of: focus)` does not
        // reliably fire on removal.
        .onDisappear {
            commitName(to: aliasID)
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

    /// Commits the buffered name to the alias identified by `id` and persists, unless
    /// it is unchanged. Taking the id explicitly (rather than reading the view's
    /// current `aliasID`) makes the commit alias-identity-safe: a focus-out that
    /// races a selection change writes to the alias that was being edited, never the
    /// newly-selected one.
    private func commitName(to id: UUID) {
        guard var alias = viewModel.alias(withID: id), alias.name != nameText else { return }
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
