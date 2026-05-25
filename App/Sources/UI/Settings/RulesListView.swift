import SwiftUI
import TrafficWandCore

/// The rules tab: an ordered, reorderable list of routing rules with add, edit,
/// delete, and per-row enable toggling.
///
/// All mutations flow through `SettingsViewModel`, which persists each change
/// immediately (Acceptance Criterion #5). Reordering uses SwiftUI's `onMove`;
/// deletion uses `onDelete`. Adding or editing presents `RuleEditorView` as a
/// sheet, committing only on Save.
struct RulesListView: View {
    @Bindable var viewModel: SettingsViewModel

    /// The rule currently being edited in the sheet, or `nil` when no sheet is up.
    /// A non-nil value drives the editor sheet; `isNew` distinguishes add vs edit.
    @State private var editing: EditingRule?

    /// Wraps the rule under edit plus whether it is a brand-new (add) rule, so the
    /// sheet's Save commits via the right view-model method.
    private struct EditingRule: Identifiable {
        let rule: Rule
        let isNew: Bool
        var id: UUID { rule.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.rules.isEmpty {
                emptyState
            } else {
                ruleList
            }
            Divider()
            toolbar
        }
        .sheet(item: $editing) { item in
            RuleEditorView(
                rule: item.rule,
                browsers: viewModel.browsers,
                onSave: { saved in
                    if item.isNew {
                        viewModel.addRule(saved)
                    } else {
                        viewModel.updateRule(saved)
                    }
                    editing = nil
                },
                onCancel: { editing = nil }
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No rules yet")
                .font(.headline)
            Text("Add a rule to route matching links to a specific browser and profile.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var ruleList: some View {
        List {
            ForEach(viewModel.rules) { rule in
                RuleRow(
                    rule: rule,
                    browserName: browserName(for: rule.target.bundleID),
                    onToggle: { enabled in viewModel.setRule(rule, enabled: enabled) }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    editing = EditingRule(rule: rule, isNew: false)
                }
            }
            .onMove { source, destination in
                viewModel.moveRules(fromOffsets: source, toOffset: destination)
            }
            .onDelete { offsets in
                viewModel.deleteRules(at: offsets)
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Button {
                editing = EditingRule(rule: defaultNewRule, isNew: true)
            } label: {
                Label("Add Rule", systemImage: "plus")
            }
            .disabled(viewModel.browsers.isEmpty)
            Spacer()
        }
        .padding(8)
    }

    /// A blank rule pre-targeting the first available browser, used when adding.
    private var defaultNewRule: Rule {
        let bundleID = viewModel.browsers.first?.bundleID ?? ""
        return Rule(
            pattern: "",
            target: BrowserTarget(bundleID: bundleID, profileID: nil),
            isEnabled: true
        )
    }

    /// Display name for a target bundle ID, falling back to the raw id if unknown.
    private func browserName(for bundleID: String) -> String {
        viewModel.browsers.first { $0.bundleID == bundleID }?.name ?? bundleID
    }
}

/// A single rule row: enable toggle, pattern, and destination browser name.
private struct RuleRow: View {
    let rule: Rule
    let browserName: String
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.pattern.isEmpty ? "(no pattern)" : rule.pattern)
                    .font(.body)
                Text(destinationLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .opacity(rule.isEnabled ? 1 : 0.5)
    }

    private var destinationLabel: String {
        if let profile = rule.target.profileID {
            return "\(browserName) — \(profile)"
        }
        return browserName
    }
}
