import SwiftUI
import TrafficWandCore

/// The Aliases tab: a master-detail editor for reusable profile aliases.
///
/// The sidebar lists the aliases with an Add button and a swipe/contextual delete;
/// selecting one shows `AliasEditorView` inline in the detail pane. All mutations flow
/// through `SettingsViewModel`, which persists each change immediately — there is no
/// Save/Cancel sheet; edits in the detail editor persist live (name on Enter/focus-out,
/// browser/profile on change).
///
/// Deleting a referenced alias is **blocked**: the row's delete action surfaces an
/// alert explaining which rules (and/or the fallback) still point at it, because
/// deleting it would orphan those references.
struct AliasesListView: View {
    @Bindable var viewModel: SettingsViewModel

    /// The alias currently selected in the sidebar / shown in the detail pane.
    @State private var selectedAliasID: UUID?

    /// The alias whose blocked-delete explanation is currently shown, or `nil`.
    @State private var blockedDelete: ProfileAlias?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .alert(
            "Alias in use",
            isPresented: Binding(
                get: { blockedDelete != nil },
                set: { if !$0 { blockedDelete = nil } }
            ),
            presenting: blockedDelete
        ) { _ in
            Button("OK", role: .cancel) { blockedDelete = nil }
        } message: { alias in
            Text(blockedDeleteMessage(for: alias))
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        // The list is just the scannable alias rows; the "what is an alias" blurb
        // lives in the detail placeholder (a List row truncates multi-line text and
        // the wide detail pane wraps it cleanly — see `placeholder`).
        List(selection: $selectedAliasID) {
            ForEach(viewModel.aliases) { alias in
                AliasRow(
                    name: alias.name,
                    targetLabel: viewModel.browserLabel(for: alias.target)
                )
                .tag(alias.id)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        attemptDelete(alias)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        attemptDelete(alias)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        // Pin an Add control to the BOTTOM of the sidebar — the native source-list
        // idiom (System Settings / Mail / Finder sidebars). A `.toolbar` item here
        // would instead be hoisted into the Settings window's titlebar (next to the
        // window title), which looks stray since the tab itself owns no titlebar
        // chrome. `.safeAreaInset` keeps the bar fixed while the list scrolls.
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 0) {
                Button(action: addAlias) {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.browsers.isEmpty)
                .help("Add Alias")
                .accessibilityLabel("Add Alias")
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(alignment: .top) { Divider() }
            .background(.bar)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selectedAliasID, viewModel.alias(withID: id) != nil {
            // Pin identity to the selected alias so switching selection RE-INITS the
            // editor (fresh name buffer / focus state) rather than reusing the instance
            // and risking a stale buffered name being committed to the wrong alias.
            AliasEditorView(viewModel: viewModel, aliasID: id)
                .id(id)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "link")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(viewModel.aliases.isEmpty ? "No aliases yet" : "Select an alias")
                .font(.headline)
            Text(viewModel.aliases.isEmpty
                ? "Add one with the + button to get started."
                : "Choose an alias on the left to edit it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // The "what is an alias" explanation lives here in the wide detail pane,
            // where it wraps cleanly and is shown exactly when nothing is selected —
            // the moment a user wonders what aliases are for.
            Text("An alias is a named, reusable destination (e.g. \"Personal\" or "
                + "\"Work\") that rules and the fallback point at by name. Re-point it "
                + "once to re-route everything that uses it.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Actions

    /// Creates a blank alias (pre-targeting the first browser), persists it, and
    /// selects it so the detail editor opens ready to edit.
    private func addAlias() {
        let bundleID = viewModel.browsers.first?.bundleID ?? ""
        let alias = ProfileAlias(
            name: "",
            target: BrowserTarget(bundleID: bundleID, profileID: nil)
        )
        viewModel.addAlias(alias)
        selectedAliasID = alias.id
    }

    /// Deletes the alias, or surfaces the blocked-delete alert when it is referenced.
    private func attemptDelete(_ alias: ProfileAlias) {
        if viewModel.isReferenced(alias.id) {
            blockedDelete = alias
        } else {
            if selectedAliasID == alias.id { selectedAliasID = nil }
            viewModel.deleteAlias(id: alias.id)
        }
    }

    /// Explanation shown when a delete is blocked: lists the referencing rule
    /// patterns and notes the fallback if it points at the alias.
    private func blockedDeleteMessage(for alias: ProfileAlias) -> String {
        var parts: [String] = []
        let rules = viewModel.referencingRules(aliasID: alias.id)
        if !rules.isEmpty {
            let patterns = rules
                .map { $0.pattern.isEmpty ? "(no pattern)" : $0.pattern }
                .joined(separator: ", ")
            parts.append("rule(s): \(patterns)")
        }
        if viewModel.isFallbackReferencing(aliasID: alias.id) {
            parts.append("the fallback policy")
        }
        let used = parts.joined(separator: " and ")
        return "\"\(alias.name)\" is still used by \(used). "
            + "Re-point those to another destination before deleting it."
    }
}

/// A single alias row: its name and the concrete browser/profile it resolves to.
private struct AliasRow: View {
    let name: String
    let targetLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name.isEmpty ? "(no name)" : name)
                .font(.body)
            Text(targetLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
// Master-detail list: the sidebar lists the alias rows; the detail shows the
// empty-selection placeholder (with the "what is an alias" explanation) until a
// sidebar row is clicked (the inline detail editor is previewed standalone in
// `AliasEditorView`).
#Preview("Aliases — list") {
    AliasesListView(viewModel: PreviewFixtures.makePreviewSettingsViewModel())
        .frame(width: 640, height: 380)
}

// Empty config: the detail shows the "No aliases yet" placeholder (with the alias
// explanation); the sidebar is an empty list with the Add (+) bar at the bottom.
#Preview("Aliases — empty") {
    AliasesListView(
        viewModel: PreviewFixtures.makePreviewSettingsViewModel(config: PreviewFixtures.emptyConfig)
    )
    .frame(width: 640, height: 380)
}
#endif
