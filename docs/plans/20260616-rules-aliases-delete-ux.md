# Rules & Aliases Delete UX (issue #3 finish + alias delete)

## Overview

Closes the remaining UX gap in [issue #3 "Overhaul of rules management"](https://github.com/trafficwand/trafficwand/issues/3) plus the requested
discoverable delete for aliases. The **logic** for the issue's first two bullets already
shipped (reorder via `.onMove` → `SettingsViewModel.moveRules`, delete via `.onDelete` →
`deleteRules(at:)`, both tested), and alias deletion already works through
`SettingsViewModel.deleteAlias(id:)` with referential-integrity guards. What is missing is
the **visible, discoverable UX** the issue's third bullet hints at, and a delete path for
aliases that is actually findable.

This plan delivers three user-facing changes, all in the App adapter layer:

1. **Rule rows use a checkbox on the left** instead of a `.switch` toggle (the issue's
   explicit open question — "checkboxes instead of toggles").
2. **Rule deletion moves into the rule editor sheet** (`RuleEditorView`) as a destructive
   button, **with a confirmation dialog**, shown only when editing an existing rule.
3. **Alias deletion moves into the alias editor form** (`AliasEditorView`) as a destructive
   button, **without confirmation** (aliases are already integrity-guarded), reusing the
   existing block-and-explain path for referenced aliases.

The invisible row-level swipe / context-menu deletes are **removed** so each entity has a
single, discoverable delete path. Reordering (`.onMove`) stays.

### Problem it solves
- The issue's "use checkboxes instead of toggles / move toggles" question is unresolved.
- Delete exists but is invisible on macOS (swipe / right-click only), so it *feels*
  unimplemented — especially for aliases.

### Why no Core changes
All decision-shaped logic (`deleteAlias`, `isReferenced`, `referencingRules`, reorder,
toggle) already lives in `TrafficWandCore` / `SettingsViewModel` and is unit-tested. This
work is purely the thin AppKit/SwiftUI adapter layer plus one new view-model seam method
(`deleteRule(id:)`).

## Context (from discovery)

- **Files involved:**
  - `App/Sources/UI/Settings/RulesListView.swift` — rule list, `RuleRow` (the toggle),
    the sheet that hosts `RuleEditorView`, and the `.onDelete`/`.onMove` modifiers.
  - `App/Sources/UI/Settings/RuleEditorView.swift` — modal sheet editor (Save/Cancel),
    gains the delete button + confirmation.
  - `App/Sources/UI/Settings/AliasesListView.swift` — master-detail; owns
    `selectedAliasID`, `blockedDelete` alert, and `attemptDelete(_:)`. Loses the swipe /
    context-menu delete on rows.
  - `App/Sources/UI/Settings/AliasEditorView.swift` — inline live-persist detail editor;
    gains the delete button.
  - `App/Sources/UI/Settings/SettingsViewModel.swift` — add `deleteRule(id:)`; remove the
    now-unused `deleteRules(at: IndexSet)`.
  - `App/Tests/AppTests/SettingsViewModelTests.swift` — replace `testDeleteRulePersists`
    (currently exercises `deleteRules(at:)`) with a `deleteRule(id:)` test.
  - `App/Tests/AppTests/SettingsViewModelAliasTests.swift` — existing alias delete tests
    (`testDeleteUnreferencedAliasPersists`, `testDeleteReferencedAliasIsNoOp`,
    `testDeleteAliasReferencedByFallbackIsNoOp`) stand unchanged — the UI moves, the seam
    does not.

- **Related patterns found:**
  - Persist-on-mutation: every `SettingsViewModel` mutation calls `persist()`.
  - `RuleEditorView` already takes `onSave`/`onCancel` closures from its parent — adding an
    optional `onDelete` follows the same seam pattern.
  - `AliasesListView.attemptDelete(_:)` already does the full alias-delete dance
    (integrity check → `blockedDelete` alert, or clear selection → `deleteAlias`). The
    editor's button calls back into it rather than duplicating the logic.
  - The `ZStack` wrapper around `RuleRow` inside `List`/`ForEach` is load-bearing (works
    around a macOS Xcode-preview crash) — keep it.

- **Dependencies identified:** Task 3 (rule delete in editor) depends on Task 1
  (`deleteRule(id:)`). Task 2 (checkbox) is independent.

## Development Approach

- **Testing approach:** **TDD** for the view-model change (`deleteRule(id:)`) — write the
  failing XCTest first, then implement. SwiftUI view changes (checkbox style, editor
  buttons, confirmation dialog) are not unit-tested in this repo; they are covered by the
  view-model seam tests plus manual verification (see Post-Completion). Where a view change
  has a testable seam (the parent-supplied closures), assert behavior through the view
  model.
- Complete each task fully before moving to the next; make small, focused changes.
- **CRITICAL: every task with code changes includes new/updated tests**, success + edge.
- **CRITICAL: all tests pass before starting the next task.**
- Run `task test` (App + Core) after each task; keep `task lint` clean.
- Maintain backward compatibility — no persisted-model changes here, so `config.json`
  schema is untouched.

## Testing Strategy

- **Unit tests:** required for the `SettingsViewModel.deleteRule(id:)` change (success +
  unknown-id no-op). No save-throws variant — the existing rule/alias mutation tests have
  none, and the `persist()` failure path (logged, in-memory state preserved) is identical
  across all mutations, so a delete-specific variant would exceed convention without value.
- **Existing tests:** the alias delete tests already cover the integrity behavior the
  editor button triggers — verify they still pass after the UI move.
- **No e2e tests:** this project has no Playwright/Cypress harness. SwiftUI button/dialog
  behavior is verified manually (Post-Completion checklist).
- App tests run via `task test` (`xcodebuild test`, includes Core). Core-only fast loop is
  `task test-core`, but no Core changes are made here.

## Progress Tracking
- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix
- keep this plan in sync with actual work

## Solution Overview

- **Checkbox:** in `RuleRow`, change the enable control from `.toggleStyle(.switch)` to
  `.toggleStyle(.checkbox)`, keeping it on the leading edge and keeping the existing
  `.opacity(... ? 1 : 0.5)` dimming for disabled rows. The `Toggle` still consumes its own
  tap, so the row's `.onTapGesture` (open editor) is unaffected.
- **Rule delete:** `RuleEditorView` gains an optional `onDelete: (() -> Void)?` and a
  `@State showingDeleteConfirmation`. When `onDelete != nil` (editing, not adding), a
  destructive "Delete Rule" button appears on the leading side of the button row; tapping
  it presents a `.confirmationDialog`, and confirming calls `onDelete?()`. `RulesListView`
  passes `onDelete: nil` for new rules and
  `onDelete: { viewModel.deleteRule(id: item.rule.id); editing = nil }` for existing ones,
  and **removes** the `.onDelete` swipe modifier (keeps `.onMove`).
- **Alias delete:** `AliasEditorView` gains an `onDelete: () -> Void` and renders a
  destructive "Delete Alias" button (no confirmation). `AliasesListView` passes
  `onDelete: { attemptDelete(alias) }`, reusing the existing integrity check + blocked
  alert + selection-clear, and **removes** the row's `.swipeActions` and `.contextMenu`
  delete. The `blockedDelete` alert and `attemptDelete(_:)` stay.
- **View model:** add `deleteRule(id:)` (find by id, remove, persist; no-op if absent);
  remove `deleteRules(at: IndexSet)` once `.onDelete` is gone.

### Key design decisions & rationale
- **Single delete path per entity** (editor button, not swipe) — directly serves the
  issue's discoverability goal; avoids two competing affordances. *Reviewable: if keeping
  swipe-to-delete as a power-user shortcut is preferred, restore `.onDelete` on rules and
  leave `deleteRules(at:)` in place.*
- **Confirm rules, not aliases** — per decision: there is no undo in the app, so deleting a
  rule (a hand-entered pattern + destination) warrants one guarding click; an *unreferenced*
  alias is already integrity-guarded and lower-stakes, so it deletes immediately.
- **Reuse `attemptDelete` for aliases** — the integrity guard, blocked-delete alert, and
  `selectedAliasID` all live in `AliasesListView`; the editor button calls back rather than
  duplicating that logic in the editor.

## Technical Details

- **`SettingsViewModel.deleteRule(id:)`** — `guard let index = rules.firstIndex { $0.id ==
  id } else { return }; rules.remove(at: index); persist()`. Mirrors `updateRule`'s
  by-id + no-op-if-absent shape.
- **`RuleEditorView`** — new stored `let onDelete: (() -> Void)?` (defaulted nil-able via
  initializer), new `@State private var showingDeleteConfirmation = false`. Button row:
  destructive "Delete Rule" (leading) shown `if onDelete != nil`, then `Spacer()`, then
  Cancel/Save (unchanged). `.confirmationDialog("Delete this rule?", isPresented:
  $showingDeleteConfirmation, titleVisibility: .visible)` with a `.destructive` "Delete"
  calling `onDelete?()` and a cancel button.
- **`AliasEditorView`** — new stored `let onDelete: () -> Void`. A destructive "Delete
  Alias" button (e.g. its own `Section` or below the form) calling `onDelete()` directly.
- **Teardown safety (alias):** `attemptDelete` sets `selectedAliasID = nil` before
  `deleteAlias`, so the editor disappears; its `.onDisappear`/`.onChange` name-flush calls
  `commitName(to:)`, which guards on `viewModel.alias(withID:)` existing and the name being
  changed, so a delete cannot resurrect or misroute a name. **Note on save count:** if the
  user had a typed-but-unsubmitted name in the field, tapping "Delete Alias" moves focus,
  firing `commitName` (one save for the rename) *before* `onDelete()` runs the delete
  (a second save). That two-save sequence is **correct**, not a bug. The unit tests cover
  only the `attemptDelete` → `deleteAlias` seam (as the existing alias tests already do);
  the focus-flush-then-delete sequence has no view-model seam and is a manual-verification
  concern (Post-Completion).

## What Goes Where
- **Implementation Steps** (`[ ]`): all code + tests below — achievable in this repo.
- **Post-Completion** (no checkboxes): manual UI verification of the buttons, checkbox,
  confirmation dialog, and blocked-alias alert in the running app.

## Implementation Steps

### Task 1: Add `SettingsViewModel.deleteRule(id:)` (TDD), retire `deleteRules(at:)`

**Files:**
- Modify: `App/Sources/UI/Settings/SettingsViewModel.swift`
- Modify: `App/Tests/AppTests/SettingsViewModelTests.swift`

- [ ] write failing test `testDeleteRuleByIDPersists`: two rules loaded, `deleteRule(id:)`
      the first → `rules == [second]`, `store.lastSaved?.rules == [second]`, `saveCount == 1`
- [ ] write failing test `testDeleteUnknownRuleByIDIsNoOp`: `deleteRule(id:)` with a random
      UUID → rules unchanged, `saveCount == 0`
- [ ] implement `deleteRule(id:)` in `SettingsViewModel` (find by id, remove, persist;
      no-op if absent), placed beside `deleteRules(at:)`/`updateRule`
- [ ] remove `deleteRules(at: IndexSet)` and replace `testDeleteRulePersists` with the new
      by-id tests (it was the only caller once `.onDelete` is removed in Task 3 — verify no
      other references with a grep)
- [ ] run `task test` — must pass before next task

### Task 2: Rule rows use a leading checkbox instead of a switch

**Files:**
- Modify: `App/Sources/UI/Settings/RulesListView.swift`

- [ ] in `RuleRow`, change `.toggleStyle(.switch)` to `.toggleStyle(.checkbox)`, keeping the
      `Toggle("", isOn:).labelsHidden()` on the leading edge and the `.opacity(rule.isEnabled
      ? 1 : 0.5)` dimming
- [ ] confirm the row's `.onTapGesture` still opens the editor and the checkbox tap only
      toggles enable (the `Toggle` consumes its own hit area)
- [ ] update the `#Preview` if needed so disabled/enabled rows render correctly
- [ ] this is a pure SwiftUI restyle with no new view-model seam; covered by the existing
      `testSetRuleEnabledPersists`. Add no new unit test (the toggle action is unchanged);
      verify manually per Post-Completion
- [ ] run `task test` and `task lint` — must pass before next task

### Task 3: Move rule deletion into `RuleEditorView` with confirmation

**Files:**
- Modify: `App/Sources/UI/Settings/RuleEditorView.swift`
- Modify: `App/Sources/UI/Settings/RulesListView.swift`

- [ ] add `let onDelete: (() -> Void)?` to `RuleEditorView` (initializer param, defaulting
      to `nil`) and `@State private var showingDeleteConfirmation = false`
- [ ] render a destructive "Delete Rule" button on the leading side of the button row,
      shown only when `onDelete != nil`; tapping sets `showingDeleteConfirmation = true`
- [ ] add `.confirmationDialog("Delete this rule?", isPresented: $showingDeleteConfirmation,
      titleVisibility: .visible)` with a `.destructive` "Delete" that calls `onDelete?()`
      and a cancel action
- [ ] in `RulesListView`'s `.sheet`, pass `onDelete: item.isNew ? nil : { viewModel.deleteRule(id:
      item.rule.id); editing = nil }`
- [ ] remove the `.onDelete { ... }` modifier from the `ForEach` (keep `.onMove`)
- [ ] update the `RulesListView.swift` file-doc comment: it currently says "deletion uses
      `onDelete`" — change to reflect that deletion now happens via the editor's delete
      button + confirmation
- [ ] add a `#Preview` variant exercising the editor with a non-nil `onDelete` so the
      delete button + dialog render in previews
- [ ] verify via `task test` that the existing rule tests + Task 1's `deleteRule(id:)` tests
      pass (the delete button's action routes through the already-tested seam) — must pass
      before next task

### Task 4: Move alias deletion into `AliasEditorView` (no confirmation)

**Files:**
- Modify: `App/Sources/UI/Settings/AliasEditorView.swift`
- Modify: `App/Sources/UI/Settings/AliasesListView.swift`

- [ ] add `let onDelete: () -> Void` to `AliasEditorView` and render a destructive "Delete
      Alias" button (its own `Section` or below the form), calling `onDelete()` directly
      (no confirmation dialog)
- [ ] in `AliasesListView`'s detail builder, fetch the live alias and pass
      `onDelete: { attemptDelete(alias) }` so the existing integrity guard + `blockedDelete`
      alert + selection-clear are reused
- [ ] remove the `.swipeActions` and `.contextMenu` delete from the sidebar `AliasRow`
      (keep `attemptDelete(_:)`, `blockedDelete`, and the alert)
- [ ] update the `AliasesListView.swift` file-doc comment: it currently describes a
      "swipe/contextual delete" and "the row's delete action surfaces an alert" — change to
      reflect that delete now lives on the editor's "Delete Alias" button (still routing
      through `attemptDelete` for the blocked-when-referenced alert)
- [ ] update the `AliasEditorView` `#Preview` to pass an `onDelete: {}` closure
- [ ] confirm the existing `testDeleteUnreferencedAliasPersists` /
      `testDeleteReferencedAliasIsNoOp` / `testDeleteAliasReferencedByFallbackIsNoOp` still
      pass (the editor button routes through `attemptDelete` → `deleteAlias`, the same seam
      they cover — the focus-flush race is verified manually, not here)
- [ ] add a view-model test only if a new seam is introduced; none is expected here — note
      this explicitly if confirmed
- [ ] run `task test` and `task lint` — must pass before next task

### Task 5: Verify acceptance criteria
- [x] issue #3 bullet 1 (reorder rules): still works via `.onMove` (unchanged) — confirm
- [x] issue #3 bullet 2 (delete rules, not just disable): now via editor button +
      confirmation — confirm
- [x] issue #3 bullet 3 (checkbox vs toggle): rule rows show a leading checkbox — confirm
- [x] requested: alias delete is discoverable via the editor button, integrity-guarded —
      confirm
- [x] confirm the swipe/context-menu deletes are gone and reordering remains
- [x] run full suite: `task test` (App + Core) and `task lint`
- [x] verify test coverage: new `deleteRule(id:)` paths + existing alias delete paths green

### Task 6: [Final] Update documentation
- [x] confirm the stale file-doc comments in `RulesListView.swift` and `AliasesListView.swift`
      were updated in Tasks 3 and 4 (they, not `CLAUDE.md`, hold the "delete via onDelete /
      swipe" prose) — verified: both file-doc comments already describe deletion via the
      editor's destructive "Delete Rule"/"Delete Alias" button (no `onDelete`/swipe/contextual
      prose remains); no fix needed
- [x] update `CLAUDE.md` only if a pattern changed worth recording (it does not currently
      describe the delete affordance, so likely no change needed) — no CLAUDE.md change needed
- [x] reference issue #3 in the eventual commit/PR — the commits/PR will reference issue #3
- [x] move this plan to `docs/plans/completed/` — deferred: review and finalize phases still
      read this plan path; the exec orchestrator handles final placement

## Post-Completion
*Manual verification — no checkboxes, informational only*

**Manual UI verification (running app via `task run`):**
- Rule rows render a checkbox (not a switch) on the left; toggling it enables/disables and
  dims the row; the change survives relaunch.
- Tapping a rule row opens the editor; the editor shows a "Delete Rule" button **only when
  editing an existing rule** (not when adding); deleting prompts a confirmation dialog;
  confirming removes the rule and dismisses the sheet; cancelling the dialog keeps it.
- The alias editor shows a "Delete Alias" button; deleting an **unreferenced** alias removes
  it immediately (no dialog) and clears the detail pane; attempting to delete a **referenced**
  alias surfaces the "Alias in use" alert listing the referencing rules / fallback and does
  not delete.
- Reordering rules by drag still works; no swipe-to-delete or right-click "Delete" remains
  on rule or alias rows.
