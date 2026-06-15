import SwiftUI
import TrafficWandCore

/// The Aliases tab: a list of reusable profile aliases with add, edit, and delete.
///
/// All mutations flow through `SettingsViewModel`, which persists each change
/// immediately. Adding or editing presents `AliasEditorView` as a sheet, committing
/// only on Save. Deleting a referenced alias is **blocked**: the row's delete action
/// surfaces an alert explaining which rules (and/or the fallback) still point at it,
/// because deleting it would orphan those references.
struct AliasesListView: View {
    @Bindable var viewModel: SettingsViewModel

    /// The alias currently being edited in the sheet, or `nil` when no sheet is up.
    @State private var editing: EditingAlias?

    /// The alias whose blocked-delete explanation is currently shown, or `nil`.
    @State private var blockedDelete: ProfileAlias?

    /// Wraps the alias under edit plus whether it is a brand-new (add) alias, so the
    /// sheet's Save commits via the right view-model method.
    private struct EditingAlias: Identifiable {
        let alias: ProfileAlias
        let isNew: Bool
        var id: UUID { alias.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.aliases.isEmpty {
                emptyState
            } else {
                aliasList
            }
            Divider()
            toolbar
        }
        .sheet(item: $editing) { item in
            AliasEditorView(
                alias: item.alias,
                browsers: viewModel.browsers,
                onSave: { saved in
                    if item.isNew {
                        viewModel.addAlias(saved)
                    } else {
                        viewModel.updateAlias(saved)
                    }
                    editing = nil
                },
                onCancel: { editing = nil }
            )
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "link")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No aliases yet")
                .font(.headline)
            Text("Create a reusable alias (e.g. \"Personal\" or \"Work\") and point rules "
                + "at it. Change the alias once to re-route every rule that uses it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var aliasList: some View {
        List {
            ForEach(viewModel.aliases) { alias in
                // The `ZStack` wrapper is load-bearing: a custom row View placed
                // directly inside a `List`'s `ForEach` crashes the macOS Xcode
                // preview (matches the `RulesListView` workaround).
                ZStack {
                    AliasRow(
                        name: alias.name,
                        targetLabel: viewModel.browserLabel(for: alias.target)
                    )
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    editing = EditingAlias(alias: alias, isNew: false)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        attemptDelete(alias)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Button {
                editing = EditingAlias(alias: defaultNewAlias, isNew: true)
            } label: {
                Label("Add Alias", systemImage: "plus")
            }
            .disabled(viewModel.browsers.isEmpty)
            Spacer()
        }
        .padding(8)
    }

    /// A blank alias pre-targeting the first available browser, used when adding.
    private var defaultNewAlias: ProfileAlias {
        let bundleID = viewModel.browsers.first?.bundleID ?? ""
        return ProfileAlias(
            name: "",
            target: BrowserTarget(bundleID: bundleID, profileID: nil)
        )
    }

    /// Deletes the alias, or surfaces the blocked-delete alert when it is referenced.
    private func attemptDelete(_ alias: ProfileAlias) {
        if viewModel.isReferenced(alias.id) {
            blockedDelete = alias
        } else {
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "(no name)" : name)
                    .font(.body)
                Text(targetLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

#if DEBUG
#Preview("Aliases") {
    AliasesListView(viewModel: PreviewFixtures.makePreviewSettingsViewModel())
}

#Preview("Aliases — empty") {
    AliasesListView(
        viewModel: PreviewFixtures.makePreviewSettingsViewModel(config: PreviewFixtures.emptyConfig)
    )
}
#endif
