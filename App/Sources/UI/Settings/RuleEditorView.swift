import SwiftUI
import TrafficWandCore

/// Inline live-persist editor for a single routing rule: its glob pattern, destination
/// (a concrete browser + profile **or** a reusable alias), and enabled flag.
///
/// Shown in the detail pane of `RulesListView`'s `NavigationSplitView` for the selected
/// rule. There is **no Save/Cancel** and no local draft of the whole rule: every change
/// commits straight through `SettingsViewModel`, matching the app's persist-on-mutation
/// pattern (mirrors `AliasEditorView`). Deletion is not hosted here — it lives on the
/// "−" button in `RulesListView`'s sidebar bottom bar (paired with "+", with a delete
/// confirmation).
///
/// - The **pattern** field commits on Enter (`.onSubmit`) **and** on focus-out: an
///   editable `TextField` only fires `.onSubmit` on Return, so a `@FocusState` +
///   `.onChange(of:)` pair flushes the typed pattern when focus leaves. Committing on
///   commit boundaries (not every keystroke) avoids persisting a half-typed pattern.
///   The commit is **rule-identity-safe**: it is given the rule id to write to
///   explicitly, so a focus-out that races a selection change can never write the
///   buffered text onto the newly-selected rule. The detail pane in `RulesListView`
///   additionally pins this view's identity with `.id(ruleID)` so switching selection
///   re-inits the editor (fresh `patternText`); the editor itself still flushes the
///   **outgoing** rule on `.onChange(of: ruleID)` (and on `.onDisappear`) so a
///   typed-but-unsubmitted pattern is neither lost nor misrouted.
/// - An empty pattern persists (and shows "(no pattern)" in the row), mirroring the
///   alias editor's empty name → "(no name)"; there is no `canSave` gate.
/// - The **destination** commits immediately when `DestinationEditor` writes through its
///   binding; `DestinationEditor.pushDestination` already refuses an unusable target, so
///   destination validity stays enforced without a save gate.
/// - The **Enabled** toggle commits immediately via `setRule`, so it stays in lockstep
///   with the sidebar row's enable checkbox (both write the same `@Observable` state).
struct RuleEditorView: View {
    @Bindable var viewModel: SettingsViewModel

    /// The id of the rule being edited; the live rule is fetched from the view model so
    /// the editor always reflects the current persisted value.
    let ruleID: UUID

    /// Local editing buffer for the pattern, committed on Enter / focus-out so a
    /// half-typed pattern is never persisted mid-keystroke.
    @State private var patternText: String

    @FocusState private var patternFieldFocused: Bool

    init(viewModel: SettingsViewModel, ruleID: UUID) {
        self.viewModel = viewModel
        self.ruleID = ruleID
        self._patternText = State(initialValue: viewModel.rule(withID: ruleID)?.pattern ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField("Pattern", text: $patternText, prompt: Text("*.github.com"))
                    .textFieldStyle(.roundedBorder)
                    .focused($patternFieldFocused)
                    .onSubmit { commitPattern(to: ruleID) }
                    .onChange(of: patternFieldFocused) { _, focused in
                        // `.onSubmit` only fires on Return; flush on focus-out too.
                        // Commit explicitly to the rule currently being edited so a
                        // focus-out that races a selection change can't misroute.
                        if !focused { commitPattern(to: ruleID) }
                    }
                Text(Self.globHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                DestinationEditor(
                    browsers: viewModel.browsers,
                    aliases: viewModel.aliases,
                    destination: destinationBinding
                )
            }

            Section {
                Toggle("Enabled", isOn: enabledBinding)
            }
        }
        .formStyle(.grouped)
        // When the selection changes to a different rule, flush the OUTGOING rule's
        // buffered pattern first (using `oldID`, before re-seeding) so a typed-but-
        // unsubmitted pattern is committed to the right rule, then re-seed the buffer
        // for the newly-selected rule. (With `.id(ruleID)` on the detail view this path
        // is normally not hit — SwiftUI re-inits the editor — but it is kept as a
        // belt-and-braces safeguard against a reused instance.)
        .onChange(of: ruleID) { oldID, newID in
            commitPattern(to: oldID)
            patternText = viewModel.rule(withID: newID)?.pattern ?? ""
        }
        // Flush a typed-but-unsubmitted pattern when the editor is torn down (selection
        // cleared / switched to the placeholder), since `.onChange(of: focus)` does not
        // reliably fire on removal.
        .onDisappear {
            commitPattern(to: ruleID)
        }
    }

    /// Binding to the selected rule's destination. Writing commits the whole rule (with
    /// the new destination) via `updateRule` immediately. The `get` fallback is
    /// read-only — `DestinationEditor` never persists it as an unusable target.
    private var destinationBinding: Binding<RoutingDestination> {
        Binding(
            get: {
                viewModel.rule(withID: ruleID)?.destination
                    ?? .browser(BrowserTarget(bundleID: "", profileID: nil))
            },
            set: { newDestination in
                guard var rule = viewModel.rule(withID: ruleID) else { return }
                rule.destination = newDestination
                viewModel.updateRule(rule)
            }
        )
    }

    /// Binding to the selected rule's enabled flag. Writing commits via `setRule`, so it
    /// stays in sync with the sidebar row's enable checkbox.
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.rule(withID: ruleID)?.isEnabled ?? true },
            set: { newValue in
                guard let rule = viewModel.rule(withID: ruleID) else { return }
                viewModel.setRule(rule, enabled: newValue)
            }
        )
    }

    /// Commits the buffered pattern to the rule identified by `id` and persists, unless
    /// it is unchanged. Taking the id explicitly (rather than reading the view's current
    /// `ruleID`) makes the commit rule-identity-safe: a focus-out that races a selection
    /// change writes to the rule that was being edited, never the newly-selected one.
    private func commitPattern(to id: UUID) {
        guard var rule = viewModel.rule(withID: id), rule.pattern != patternText else { return }
        rule.pattern = patternText
        viewModel.updateRule(rule)
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
        viewModel: PreviewFixtures.makePreviewSettingsViewModel(),
        ruleID: PreviewFixtures.sampleRules.first!.id
    )
    .frame(width: 460, height: 360)
}

#Preview("Rule Editor — alias destination") {
    RuleEditorView(
        viewModel: PreviewFixtures.makePreviewSettingsViewModel(),
        ruleID: PreviewFixtures.sampleRules[2].id
    )
    .frame(width: 460, height: 360)
}
#endif
