# Rules Tab → Master-Detail (parity with Aliases tab)

## Overview

Restructure the **Rules** tab to mirror the **Aliases** tab's master-detail layout: a
sidebar list of rules on the left and an **inline, live-persisting** editor in the detail
pane, with paired **+ / −** buttons in the sidebar's bottom bar. This replaces today's
plain `List` + modal-sheet editor + toolbar "Add Rule" button.

Three user-facing changes, all in the App adapter layer:

1. **Master-detail layout.** `RulesListView` becomes a `NavigationSplitView` (sidebar +
   inline detail editor), exactly like `AliasesListView`.
2. **Inline live-persist editor.** `RuleEditorView` drops its working-copy draft and
   Save/Cancel; the pattern commits on Enter/focus-out, the destination and the enabled
   flag commit on change — exactly like `AliasEditorView`.
3. **+ / − sidebar bottom bar.** "+" adds a blank rule and selects it; "−" deletes the
   **selected** rule and is disabled when nothing is selected. Unlike aliases, **"−"
   requires a confirmation dialog** ("Delete this rule?") before deleting.

Reordering (`.onMove`) is retained. The enable control is kept in **both** places — the
leading checkbox on each sidebar row **and** an "Enabled" toggle in the editor — and they
**stay in sync automatically** because both bind to the same `@Observable` view-model
state (see Solution Overview).

### Problem it solves
The two settings tabs currently use different interaction models (Rules = sheet editor;
Aliases = inline master-detail). This unifies them so the app feels consistent, and makes
the rule editor's enable toggle and the row checkbox a single coherent control.

### Why no Core changes
All rule mutations already exist and are tested in `SettingsViewModel` (`addRule`,
`updateRule`, `setRule`, `deleteRule(id:)`, `moveRules`). This work is purely the SwiftUI
adapter layer plus one additive, testable view-model lookup (`rule(withID:)`, mirroring the
existing `alias(withID:)`).

## Context (from discovery)

- **Files involved:**
  - `App/Sources/UI/Settings/RulesListView.swift` — today a `VStack` of `List` (custom
    `RuleRow` with leading checkbox, tap → sheet) + a toolbar "Add Rule" button + `.onMove`.
    Becomes a `NavigationSplitView` with a +/− bottom bar.
  - `App/Sources/UI/Settings/RuleEditorView.swift` — today a sheet editing a `draft: Rule`
    with `onSave`/`onCancel`/`onDelete` closures, a `canSave` gate, and a delete
    confirmation. Becomes an inline live-persist editor (`@Bindable viewModel` + `ruleID`).
  - `App/Sources/UI/Settings/SettingsViewModel.swift` — add `rule(withID:)`.
  - `App/Sources/UI/Settings/AliasesListView.swift` / `AliasEditorView.swift` — **reference
    templates** (do not change). The new rule views copy their structure: sidebar `List`
    with `.tag`/selection + `.safeAreaInset` bottom bar; `.id(selectedID)` on the detail
    editor; commit-on-Enter/focus-out + `.onChange(of: id)` / `.onDisappear` flush.
  - `App/Sources/UI/Settings/DestinationEditor.swift` — reused by the editor (Browser/Alias
    segmented destination picker), unchanged.
  - `App/Sources/UI/Previews/PreviewFixtures.swift` — preview view-model fixtures; the
    `RuleEditorView` `#Preview` signature changes (now `viewModel` + `ruleID`).
  - `App/Tests/AppTests/SettingsViewModelTests.swift` — add `rule(withID:)` tests.

- **Related patterns found:**
  - `AliasesListView`: `List(selection:)` of rows with `.tag(id)`; `.safeAreaInset(edge:
    .bottom)` hosting borderless +/− buttons (`.background(.bar)`, top `Divider`); detail
    pinned with `.id(id)`; `attemptDelete`/selection-clear pattern.
  - `AliasEditorView`: live-persist via a `@FocusState` + buffered `nameText` committed on
    `.onSubmit`/focus-out with an explicit `commitName(to: id)` that is **identity-safe**
    (takes the id so a focus-out racing a selection change can't misroute); browser/profile
    commits immediately through a binding; `.onChange(of: aliasID)` and `.onDisappear`
    flush the outgoing buffer.
  - The `ZStack` wrapper around a custom row inside `List`/`ForEach` is load-bearing (macOS
    Xcode-preview crash workaround) — keep it for `RuleRow`.
  - Aliases have referential-integrity blocking on delete; **rules do not** — the rule "−"
    simply confirms then deletes (no blocked-delete alert needed).

- **Dependencies identified:** The editor rewrite and the list rewrite are **coupled** (the
  editor's initializer signature changes, and `RulesListView` is its only caller), so they
  land in the **same task** to keep the build green. Task 1 (`rule(withID:)`) is additive
  and precedes them.

## Development Approach

- **Testing approach:** **TDD** for the view-model change (`rule(withID:)`) — failing test
  first, then implement. The SwiftUI restructuring (master-detail, +/− bar, live-persist,
  confirmation dialog) has no unit-test seam in this repo (no SwiftUI view tests by
  convention); its logic routes through already-tested view-model methods (`addRule`,
  `updateRule`, `setRule`, `deleteRule(id:)`, `moveRules`) plus the new `rule(withID:)`.
  Verified manually (Post-Completion).
- Complete each task fully before the next; small, focused changes.
- **CRITICAL: every task with code changes includes new/updated tests** (success + edge).
- **CRITICAL: all tests pass before starting the next task.**
- Run `task test` (App + Core) and keep `task lint` clean after each task.
- Maintain backward compatibility — no persisted-model changes, so `config.json` schema is
  untouched.

## Testing Strategy

- **Unit tests:** required for `SettingsViewModel.rule(withID:)` (found + not-found),
  mirroring the existing `alias(withID:)` coverage shape.
- **Existing tests:** `addRule`, `updateRule`, `setRule`, `deleteRule(id:)`, `moveRules`
  tests must still pass — the UI restructuring reuses these seams unchanged.
- **No e2e tests:** no Playwright/Cypress harness. SwiftUI behavior verified manually.
- App tests run via `task test` (`xcodebuild test`, includes Core); no Core changes here.

## Progress Tracking
- mark completed items `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document blockers with ⚠️ prefix
- keep this plan in sync with actual work

## Solution Overview

- **Layout:** `RulesListView` → `NavigationSplitView { sidebar } detail: { detail }`,
  copying `AliasesListView`. Sidebar = `List(selection: $selectedRuleID)` of `RuleRow`
  (`.tag(rule.id)`) with `.onMove` retained for reordering. Bottom bar via
  `.safeAreaInset(edge: .bottom)` with borderless **+** and **−** buttons (top `Divider`,
  `.background(.bar)`).
- **Selection state:** `@State private var selectedRuleID: UUID?` in `RulesListView`.
- **Add (+):** builds a blank default rule (first installed browser, enabled), calls
  `viewModel.addRule(rule)`, sets `selectedRuleID = rule.id` (mirrors `addAlias`). Disabled
  when `viewModel.browsers.isEmpty`.
- **Delete (−):** disabled when `selectedRuleID == nil`. On tap, presents a
  `.confirmationDialog("Delete this rule?", titleVisibility: .visible)` with a destructive
  "Delete" that clears the selection and calls `viewModel.deleteRule(id:)`. (No
  referential-integrity blocking — rules aren't referenced by anything.)
- **Detail:** `if let id = selectedRuleID, viewModel.rule(withID: id) != nil {
  RuleEditorView(viewModel:, ruleID: id).id(id) } else { placeholder }`. The `.id(id)`
  re-inits the editor on selection change (fresh pattern buffer), as in the aliases tab.
- **Placeholder copy** (detail pane, mirroring `AliasesListView`'s two-tier headline +
  callout, but WITHOUT a "what is a rule" explanatory blurb — rules are self-evident,
  unlike aliases): when `viewModel.rules.isEmpty` → headline "No rules yet" + callout "Add
  one with the + button to get started." When rules exist but none is selected → headline
  "Select a rule" + callout "Choose a rule on the left to edit it." Use the
  `arrow.triangle.branch` SF Symbol (today's rules empty-state icon), not the alias `link`
  icon.
- **Inline editor (`RuleEditorView`):** `@Bindable var viewModel`, `let ruleID: UUID`,
  buffered `@State patternText` + `@FocusState`. A `Form` with: pattern `TextField`
  (commit-on-Enter/focus-out via `commitPattern(to: ruleID)`), the glob help text, a
  `DestinationEditor` bound to a destination binding that writes `updateRule`, and an
  "Enabled" `Toggle` bound to a binding that writes `setRule`. `.onChange(of: ruleID)`
  flushes the outgoing pattern then reseeds; `.onDisappear` flushes. No Save/Cancel, no
  `canSave` gate (an empty pattern persists and shows "(no pattern)", matching how the
  alias editor accepts an empty name → "(no name)").
- **Enable sync:** the row checkbox and the editor toggle both write through
  `setRule(_:enabled:)` on the `@Observable` `SettingsViewModel`; SwiftUI re-renders both
  on the resulting state change, so they stay in lockstep with no extra wiring. (Live-
  persist is what makes this free — a draft would desync the toggle from the row until
  Save.)

### Key design decisions & rationale
- **Editor + list rewritten in one task** — the initializer signature change couples them;
  splitting would leave the build broken between tasks.
- **"−" confirms; alias "−" doesn't** — per request. A rule (hand-entered pattern +
  destination) has no undo and isn't integrity-guarded, so it gets one guarding click; an
  unreferenced alias is lower-stakes.
- **Keep both enable controls** — per request; sync is automatic under live-persist.
- **Drop the row chevron** — selection highlight now indicates the active rule (alias rows
  have no chevron); keeps the two tabs visually consistent. *Reviewable.*

## Technical Details

- **`SettingsViewModel.rule(withID:)`** — `rules.first { $0.id == id }`. Mirrors
  `alias(withID:)`. Used by the detail builder and the editor's live fetch.
- **`RuleEditorView` bindings:**
  - destination: `Binding(get: { viewModel.rule(withID: ruleID)?.destination ?? <default
    browser> }, set: { var r = viewModel.rule(withID: ruleID); r.destination = $0;
    viewModel.updateRule(r) })`.
  - enabled: `Binding(get: { viewModel.rule(withID: ruleID)?.isEnabled ?? true }, set: {
    guard let r = viewModel.rule(withID: ruleID); viewModel.setRule(r, enabled: $0) })`.
  - `commitPattern(to id: UUID)`: `guard var r = viewModel.rule(withID: id), r.pattern !=
    patternText else { return }; r.pattern = patternText; viewModel.updateRule(r)` —
    identity-safe, mirrors `commitName(to:)`.
  - **Selection-switch flush ordering (the real edge case):** flush the **outgoing** id
    *before* reseeding, exactly like `AliasEditorView` — `.onChange(of: ruleID) { oldID,
    newID in commitPattern(to: oldID); patternText = viewModel.rule(withID: newID)?.pattern
    ?? "" }`. Committing to `newID`, or reseeding before flushing, would misroute a
    typed-but-unsubmitted pattern onto the newly-selected rule. (`.id(id)` on the detail
    view normally re-inits the editor so this path isn't hit, but keep it as the
    belt-and-braces safeguard, matching the alias editor.)
- **Dropped `canSave` — what it costs:** today `RuleEditorView.canSave` blocks Save on (a)
  an empty pattern AND (b) a destination that doesn't resolve to an installed browser / a
  present alias. Live-persist has no Save button to gate, so `canSave` is removed. Losing
  (a) is intentional (empty pattern persists → "(no pattern)", mirroring the alias editor's
  empty name → "(no name)"). Losing (b) is **safe because `DestinationEditor.pushDestination`
  already refuses to write a `.browser` whose bundleID isn't installed and refuses an empty
  alias selection** — destination validity was always enforced there, not only by `canSave`.
  Confirm the destination binding's `get` fallback (`?? <default browser>`) is read-only
  and never itself persists an unusable target.
- **Teardown safety:** "−" clears `selectedRuleID` before `deleteRule(id:)`, tearing down
  the editor; `.onDisappear` → `commitPattern(to: ruleID)` is a guarded no-op because
  `rule(withID:)` returns nil after delete (mirrors the alias teardown analysis).
- **Removed:** the `.sheet`, `EditingRule`, the toolbar `Add Rule` button, `defaultNewRule`
  (folded into the + action), and `RuleEditorView`'s `draft`/`onSave`/`onCancel`/`onDelete`/
  `canSave`/`showingDeleteConfirmation` + its delete confirmation (the confirmation moves to
  the sidebar "−").

## What Goes Where
- **Implementation Steps** (`[ ]`): all code + tests below.
- **Post-Completion** (no checkboxes): manual UI verification in the running app.

## Implementation Steps

### Task 1: Add `SettingsViewModel.rule(withID:)` (TDD)

**Files:**
- Modify: `App/Sources/UI/Settings/SettingsViewModel.swift`
- Create: `App/Tests/AppTests/SettingsViewModelRuleLookupTests.swift`

- [ ] put the new tests in a **dedicated file** `SettingsViewModelRuleLookupTests.swift`
      mirroring the existing `SettingsViewModelAliasLookupTests.swift` (which was split out
      to keep test files under SwiftLint's `type_body_length` limit) — do NOT append to the
      already-large `SettingsViewModelTests.swift`
- [ ] write failing test `testRuleWithIDReturnsMatchingRule`: load two rules, assert
      `rule(withID: second.id) == second`
- [ ] write failing test `testRuleWithIDReturnsNilForUnknownID`: assert `rule(withID:
      UUID()) == nil`
- [ ] write failing test `testRuleWithIDReflectsLivePersistedEdit`: load a rule, call
      `updateRule` with an edited copy (same id), assert `rule(withID: id)` returns the
      edited value — pins the exact live-fetch property the inline detail editor relies on
      (mirrors `testAliasWithIDReflectsLivePersistedEdit`)
- [ ] implement `rule(withID:)` in `SettingsViewModel` (`rules.first { $0.id == id }`),
      placed beside `alias(withID:)`, with a matching doc comment
- [ ] run `task test` and `task lint` — must pass before next task

### Task 2: Convert the Rules tab to master-detail with an inline live-persist editor

**Files:**
- Modify: `App/Sources/UI/Settings/RuleEditorView.swift`
- Modify: `App/Sources/UI/Settings/RulesListView.swift`
- Modify: `App/Sources/UI/Previews/PreviewFixtures.swift` (only if a fixture is needed)

- [ ] rewrite `RuleEditorView` as an inline live-persist editor: `@Bindable var viewModel`,
      `let ruleID: UUID`, buffered `@State patternText` + `@FocusState`; `Form` with the
      pattern `TextField` (commit on `.onSubmit` and on focus-out via `commitPattern(to:
      ruleID)`), the glob help text, a `DestinationEditor` bound to the destination binding
      (writes `updateRule`), and an "Enabled" `Toggle` bound to the enabled binding (writes
      `setRule`); add `.onChange(of: ruleID)` (flush outgoing + reseed) and `.onDisappear`
      (flush); remove `draft`/`onSave`/`onCancel`/`onDelete`/`canSave`/the delete
      confirmation; update the file-doc header to describe the inline live-persist behavior
- [ ] update both `RuleEditorView` `#Preview`s to the new `viewModel: + ruleID:` signature
      (use `PreviewFixtures` sample rules); add a fixture if none has a usable rule id
- [ ] rewrite `RulesListView` as a `NavigationSplitView` (sidebar + detail), mirroring
      `AliasesListView`: `@State selectedRuleID: UUID?`; sidebar `List(selection:)` of
      `RuleRow` (`.tag(rule.id)`, keep the `ZStack` wrapper) with the leading enable
      checkbox preserved and the chevron dropped; keep `.onMove` → `moveRules`
- [ ] add the `.safeAreaInset(edge: .bottom)` bottom bar with borderless **+** (adds a blank
      rule via `addRule`, selects it; disabled when `browsers.isEmpty`) and **−** (disabled
      when `selectedRuleID == nil`); wire **−** to a `.confirmationDialog("Delete this
      rule?", titleVisibility: .visible)` whose destructive action clears `selectedRuleID`
      then calls `deleteRule(id:)`
- [ ] build the detail pane: `RuleEditorView(viewModel:, ruleID: id).id(id)` when a rule is
      selected and still exists, else a placeholder ("No rules yet" / "Select a rule" with
      the existing add hint), mirroring `AliasesListView`'s placeholder
- [ ] update the `RulesListView` `#Preview`s if needed (signature is unchanged — still takes
      `viewModel`); update the file-doc header to describe the master-detail layout and the
      +/− bar with confirmed delete
- [ ] no new view-model test needed (UI routes through `addRule`/`updateRule`/`setRule`/
      `deleteRule(id:)`/`moveRules`/`rule(withID:)`, all already tested); confirm this
      explicitly
- [ ] regression check: confirm the existing rule-mutation tests still pass now that the UI
      drives those seams live (not via sheet Save) — `testEditRulePersistsTheChange`,
      `testSetRuleEnabledPersists`, `testDeleteRuleByIDPersists`,
      `testReorderRuleChangesOrderAndPersists`
- [ ] run `task test` and `task lint` — must pass before next task

### Task 3: Verify acceptance criteria
- [ ] Rules tab renders as sidebar + inline editor (master-detail), matching the Aliases tab
- [ ] editor live-persists: pattern on Enter/focus-out, destination on change, enabled on
      change — no Save/Cancel
- [ ] row checkbox and editor "Enabled" toggle stay in sync (both via `setRule`)
- [ ] **+** adds and selects a new rule; **−** is disabled with no selection and shows a
      confirmation dialog before deleting the selected rule
- [ ] reordering still works (`.onMove`); no leftover sheet / "Add Rule" toolbar button /
      `EditingRule` / `canSave`
- [ ] run full suite: `task test` (App + Core) and `task lint`

### Task 4: [Final] Update documentation
- [ ] update `CLAUDE.md` if the rules-tab description is now stale (it documents the rule
      editor; the Rules tab now mirrors the Aliases master-detail — adjust the relevant
      sentence(s))
- [ ] confirm the `RulesListView.swift` / `RuleEditorView.swift` file-doc headers were
      updated in Task 2
- [ ] move this plan to `docs/plans/completed/`

## Post-Completion
*Manual verification — no checkboxes, informational only*

**Manual UI verification (`task run`):**
- The Rules tab shows a sidebar list with a +/− bottom bar and an inline editor in the
  detail pane, visually consistent with the Aliases tab.
- Typing a pattern and clicking away (or pressing Enter) persists it; switching the
  destination or toggling Enabled persists immediately; all survive relaunch.
- Toggling the sidebar row checkbox updates the editor's Enabled toggle and vice-versa.
- **+** adds a blank rule and opens it in the editor; **−** is disabled until a rule is
  selected and asks for confirmation before deleting; cancelling the dialog keeps the rule.
- Dragging reorders rules; deleting a rule with a typed-but-unsubmitted pattern does not
  crash or misroute (it may persist the edit, then delete).
