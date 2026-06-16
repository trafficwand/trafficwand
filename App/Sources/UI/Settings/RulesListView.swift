import SwiftUI
import TrafficWandCore

/// The Rules tab: a master-detail editor for ordered, reorderable routing rules.
///
/// The sidebar lists the rules (each with a leading enable checkbox) and has paired
/// "+" / "−" buttons in a bottom bar (the native source-list idiom); selecting one shows
/// `RuleEditorView` inline in the detail pane. All mutations flow through
/// `SettingsViewModel`, which persists each change immediately — there is no Save/Cancel
/// sheet; edits in the detail editor persist live (pattern on Enter/focus-out,
/// destination and enabled on change). Reordering uses SwiftUI's `onMove`.
///
/// Delete is the "−" button, which removes the currently-selected rule (and is disabled
/// when nothing is selected) — there is no swipe/contextual delete on the rows. Unlike
/// aliases, deleting a rule is guarded by a **confirmation dialog** ("Delete this
/// rule?"): a rule has no undo, so it gets one guarding click. (Rules aren't referenced
/// by anything, so there is no blocked-delete path.)
struct RulesListView: View {
    @Bindable var viewModel: SettingsViewModel

    /// The rule currently selected in the sidebar / shown in the detail pane.
    @State private var selectedRuleID: UUID?

    /// The rule pending deletion, captured when the "−" button presents the
    /// confirmation dialog so the confirmed delete acts on that exact rule rather than
    /// re-reading the (possibly-changed) selection at confirm time.
    @State private var rulePendingDeletion: UUID?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .confirmationDialog(
            "Delete this rule?",
            isPresented: Binding(
                get: { rulePendingDeletion != nil },
                set: { if !$0 { rulePendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: rulePendingDeletion
        ) { id in
            Button("Delete", role: .destructive) { deleteRule(id: id) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedRuleID) {
            ForEach(viewModel.rules) { rule in
                // The `ZStack` wrapper is load-bearing: a custom row View placed
                // *directly* inside a `List`'s `ForEach` crashes the macOS Xcode
                // preview (Apple-confirmed; the running app is unaffected). Wrapping
                // the row in any container sidesteps it.
                // See developer.apple.com/forums/thread/803429.
                ZStack {
                    RuleRow(
                        rule: rule,
                        destinationLabel: viewModel.destinationLabel(for: rule.destination),
                        onToggle: { enabled in viewModel.setRule(rule, enabled: enabled) }
                    )
                }
                .tag(rule.id)
            }
            .onMove { source, destination in
                viewModel.moveRules(fromOffsets: source, toOffset: destination)
            }
        }
        // Pin the +/− controls to the BOTTOM of the sidebar — the native source-list
        // idiom (System Settings / Mail / Finder sidebars). `.safeAreaInset` keeps the
        // bar fixed while the list scrolls.
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 0) {
                Button(action: addRule) {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.browsers.isEmpty)
                .help("Add Rule")
                .accessibilityLabel("Add Rule")

                // Delete the selected rule; disabled when nothing is selected. Routes
                // through a confirmation dialog before actually deleting.
                Button {
                    rulePendingDeletion = selectedRuleID
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(selectedRuleID == nil)
                .help("Delete Rule")
                .accessibilityLabel("Delete Rule")
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
        if let id = selectedRuleID, viewModel.rule(withID: id) != nil {
            // Pin identity to the selected rule so switching selection RE-INITS the
            // editor (fresh pattern buffer / focus state) rather than reusing the
            // instance and risking a stale buffered pattern being committed to the
            // wrong rule.
            RuleEditorView(viewModel: viewModel, ruleID: id)
                .id(id)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(viewModel.rules.isEmpty ? "No rules yet" : "Select a rule")
                .font(.headline)
            Text(viewModel.rules.isEmpty
                ? "Add one with the + button to get started."
                : "Choose a rule on the left to edit it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Actions

    /// Creates a blank rule (pre-targeting the first browser, enabled), persists it, and
    /// selects it so the detail editor opens ready to edit.
    private func addRule() {
        let bundleID = viewModel.browsers.first?.bundleID ?? ""
        let rule = Rule(
            pattern: "",
            destination: .browser(BrowserTarget(bundleID: bundleID, profileID: nil)),
            isEnabled: true
        )
        viewModel.addRule(rule)
        selectedRuleID = rule.id
    }

    /// Deletes the rule captured when the confirmation dialog was presented (confirmed
    /// via the dialog). Clears the selection first if it still points at that rule so
    /// the editor tears down before the rule is removed.
    private func deleteRule(id: UUID) {
        if selectedRuleID == id { selectedRuleID = nil }
        viewModel.deleteRule(id: id)
    }
}

/// A single rule row: enable checkbox, pattern, and destination label.
private struct RuleRow: View {
    let rule: Rule
    let destinationLabel: String
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .accessibilityLabel(rule.isEnabled ? "Disable rule" : "Enable rule")

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.pattern.isEmpty ? "(no pattern)" : rule.pattern)
                    .font(.body)
                Text(destinationLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .opacity(rule.isEnabled ? 1 : 0.5)
    }
}
#if DEBUG
#Preview("Rules") {
    RulesListView(viewModel: PreviewFixtures.makePreviewSettingsViewModel())
        .frame(width: 640, height: 380)
}

#Preview("Rules — empty") {
    RulesListView(
        viewModel: PreviewFixtures.makePreviewSettingsViewModel(config: PreviewFixtures.emptyConfig)
    )
    .frame(width: 640, height: 380)
}
#endif
