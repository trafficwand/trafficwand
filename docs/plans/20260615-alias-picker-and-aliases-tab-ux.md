# Alias Picker Selection + Master-Detail Aliases Tab + Tab Description

## Overview

Three follow-up UX improvements to the profile-aliases feature (shipped on
`feature/profile-aliases`):

1. **Select an alias in the picker.** The floating picker shown on a `.prompt`
   decision (a new/unrouted link) currently only offers concrete browser/profile
   rows — there is no way to route the link to an alias. Add an **Aliases** section
   at the top of the picker so the user can pick a named alias (e.g. "Work"). When
   "Remember choice" is ticked for an alias selection, persist an **`.alias(id)`
   rule** (the reusable, late-binding behavior — re-pointing the alias later also
   re-routes this remembered site), not a frozen concrete rule.
2. **Master-detail Aliases tab.** Replace the sheet-based alias editor with a
   list-on-the-left / editor-in-the-main-pane layout. Selecting an alias edits it
   inline; edits **persist live** (name commits on focus-out/Enter, browser/profile
   on change) — no Save/Cancel sheet.
3. **Aliases tab description.** Add a short always-visible explanation at the top of
   the Aliases tab describing what aliases are for.

**How it integrates:** Alias resolution still lives in Core. The picker resolves a
chosen alias to a concrete `BrowserTarget` for the immediate launch (so the launch
path is unchanged) and separately carries the chosen `RoutingDestination` for the
"remember" persistence. The master-detail and description changes are App-only view
work over the existing `SettingsViewModel` alias CRUD.

## Context (from discovery)

Files/components involved:

- **Picker (App):** `App/Sources/UI/Picker/PickerViewModel.swift` (holds `browsers`,
  builds flattened `selectableItems`, `onSelect: (BrowserTarget, remember)`),
  `BrowserPickerView.swift` (renders rows; keyboard nav over `selectableItems`),
  `PickerPanelController.swift` (conforms to `PickerPresenting`; `makeViewModel`,
  `handleSelection(target:url:browsers:remember:)` → launch + `rulePersister.remember`).
- **Picker seam (App):** `App/Sources/PickerPresenting.swift`
  (`presentPicker(url:browsers:)`), `App/Sources/RoutingService.swift` — **two**
  `presentPicker` call sites: the `.prompt` case inside `route(url:)` (~line 92, where
  `config` IS in scope so `config.aliases` is available) **and** a fallback call inside
  the private `open(target:url:browsers:)` (~line 116, where `config` is **NOT** in
  scope — see Technical Details for how aliases reach it).
- **Remember path:** `TrafficWandCore/Sources/TrafficWandCore/Matching/RememberRule.swift`
  (`rule(forURL:target:)` → builds `Rule(destination: .browser(target))`),
  `App/Sources/Adapters/ConfigRuleStore.swift` (`RulePersisting.remember(url:target:)`
  → `RememberRule` + `AppConfig.upserting`).
- **Aliases tab (App):** `App/Sources/UI/Settings/AliasesListView.swift` (`List` +
  `.sheet`-based editor, blocked-delete alert, empty-state description),
  `App/Sources/UI/Settings/AliasEditorView.swift` (sheet: `draft` + Save/Cancel,
  uses the shared `BrowserProfilePicker`).
- **View model (App):** `App/Sources/UI/Settings/SettingsViewModel.swift` already has
  `aliases`, `addAlias`/`updateAlias`/`deleteAlias(id:)`, `isReferenced`,
  `referencingRules`, `isFallbackReferencing`, `browserLabel(for:)`,
  `destinationLabel(for:)` — reused as-is.
- **Core models (unchanged shape):** `ProfileAlias` (`id`, `name`,
  `target: BrowserTarget`), `RoutingDestination` (`.browser`/`.alias` +
  `resolved(in:)`).

Related patterns found:

- **`BrowserProfilePicker`** (`App/Sources/UI/Settings/BrowserProfilePicker.swift`) —
  the shared browser+profile control with the reset-on-browser-change rule; reuse it
  in the inline detail editor.
- **Resolution stays in Core / decision boundary unchanged** — the App resolves an
  alias to a concrete target only to launch; routing logic is untouched.
- **Persist-on-mutation** — `SettingsViewModel` persists every change; the live-edit
  detail editor leans on this via `updateAlias`.
- **Logic in the view model, views declarative** — picker selection/destination
  mapping goes in `PickerViewModel` (unit-tested); the master-detail view stays thin.

Dependencies identified:

- `PickerPresenting.presentPicker` signature gains `aliases:` — updates the protocol,
  its conformer, the two `RoutingService` call sites, and the test mock.
- `PickerViewModel.onSelect` signature changes to carry a `RoutingDestination` (for
  remember) alongside the concrete launch target — updates `PickerPanelController` and
  the `BrowserPickerView` preview.
- `RulePersisting.remember` + `RememberRule` gain a `RoutingDestination`-based path.

## Development Approach

- **Testing approach: TDD** (per `CLAUDE.md`: for Core, write the failing test first;
  put App logic in the view model and unit-test it there — views stay declarative).
- Use the `task` runner only: `task test-core` (Core), `task test` (App; run
  `task generate` first if new source files are added), `task lint` (keep clean).
  Pass `dangerouslyDisableSandbox: true` on `task` Bash calls.
- Keep Core Foundation-only (no AppKit; the `task test-core` grep guard enforces it).
- **Every task includes new/updated tests** (success + edge/error cases).
- **All tests pass before starting the next task.**

### Build / compile-unit note (read before starting)

Changing `PickerViewModel.onSelect` (Task 2) and the `PickerPresenting` /
`RulePersisting` signatures breaks the picker's App consumers at the type level until
they are all migrated. Treat **Tasks 2–4 as one App picker compile-unit**: write each
task's failing tests as planned, but expect `task test` (xcodebuild) to compile and go
green only at the **end of Task 4**. `task test-core` stays green throughout (Task 1 is
additive and self-contained). Tasks 5–6 (Aliases tab) are an independent App change and
each can go green on its own.

## Testing Strategy

- **Unit tests (Core):** `task test-core` — `RememberRule` destination-based builder
  (alias + browser), plus the existing target-based path still works.
- **Unit tests (App):** `task test` — `PickerViewModel` alias rows + select→
  (launch target, remember destination) mapping; `PickerPanelController` launch +
  remember-destination wiring; `ConfigRuleStore` remember-destination upsert;
  `RoutingService` passes aliases through; `SettingsViewModel`/preview-fixture sanity.
- **No e2e/UI-automation harness** exists; SwiftUI views are exercised by light tests +
  `#Preview` fixtures. Keep selection/mapping logic in the view model and test it there;
  the master-detail layout and description text are validated by Post-Completion manual
  smoke test (consistent with project precedent).

## Progress Tracking

- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix
- update this plan if implementation deviates from original scope

## Solution Overview

**Picker alias selection (the destination-carrying selection):**

- `PickerViewModel` gains `aliases: [ProfileAlias]`. `SelectableItem` becomes a tagged
  value so a row is either an alias or a browser/profile:

  ```swift
  struct SelectableItem: Identifiable {
      let id: String
      let kind: Kind
      enum Kind { case alias(ProfileAlias); case browser(Browser, BrowserProfile?) }
  }
  ```

  with computed `launchTarget: BrowserTarget` (alias → `alias.target`; browser →
  `BrowserTarget(bundleID:profileID:)`) and `rememberDestination: RoutingDestination`
  (alias → `.alias(alias.id)`; browser → `.browser(launchTarget)`).
- Alias rows are **prepended** to the list (an "Aliases" group before the browser
  groups). **Only aliases whose `target.bundleID` is among the offered `browsers`
  (installed) are shown** — an alias pointing at an uninstalled browser can't launch, so
  it is filtered out (edge case, tested).
- **`SelectableItem.id` scheme (retain + extend):** keep the existing collision-proof
  ids — browser-default `"\(bundleID)#self"`, profile `"\(bundleID)#profile:\(profile.id)"`
  — and add alias rows as `"alias:\(alias.id.uuidString)"`. The `alias:` prefix can't
  collide with the `bundleID#…` forms. `id` stays a `String` (the view's
  `hoveredItemID: SelectableItem.ID` and `ForEach`/keyboard identity depend on
  `ID == String`).
- `onSelect` changes to
  `(_ launchTarget: BrowserTarget, _ rememberDestination: RoutingDestination, _ remember: Bool) -> Void`.
  `select(...)`/`activateSelection()` compute both from the chosen item.

**Remember as alias (Core + seam):**

- `RememberRule.rule(forURL:destination:)` builds `Rule(pattern, destination:, isEnabled)`
  for any `RoutingDestination`. The existing `rule(forURL:target:)` is kept and
  delegates with `.browser(target)` (back-compat, zero behavior change for other callers).
- `RulePersisting.remember(url:destination:)` replaces `remember(url:target:)`;
  `ConfigRuleStore` builds via the destination-based `RememberRule` and upserts
  (`AppConfig.upserting` already keys on `destination`, so an alias selection persists
  an `.alias(id)` rule).

**Master-detail Aliases tab:**

- `AliasesListView` becomes a `NavigationSplitView`: sidebar = alias list (+ Add button,
  swipe/contextual delete with the existing blocked-delete alert); detail = the inline
  editor for the selected alias, or the **description / "select an alias" placeholder**
  when nothing is selected.
- The editor (an inline `AliasEditorView`, no longer a sheet) **live-persists**: the
  name field commits via `updateAlias` on `.onSubmit`/focus-out; the
  `BrowserProfilePicker` change commits via `updateAlias` immediately. Selection state
  (`selectedAliasID`) is local `@State`; **Add** creates via `addAlias` and selects the
  new alias.

**Aliases tab description:**

- A concise always-visible blurb at the top of the tab (or the detail placeholder)
  explaining: an alias is a named, reusable destination ("Personal", "Work") that rules
  and the fallback point at by name; re-point it once to re-route everything that uses it.

### Key design decisions & rationale

1. **Resolve-to-launch in the view model, remember-the-destination separately.** The
   picker has the aliases, so it collapses an alias to a concrete `BrowserTarget` for the
   immediate launch (controller launch path unchanged) while passing the chosen
   `RoutingDestination` for persistence. Keeps Core/Router untouched.
2. **Remember an alias → `.alias(id)` rule (supersedes original decision #4 *for picker
   alias selections only*).** The original "remember always concrete" decision applied
   when the picker only offered concrete browsers. An explicit alias pick is a request for
   the reusable binding, so we persist `.alias(id)`. Picking a concrete browser/profile
   still persists `.browser(...)` exactly as before.
3. **Filter uninstalled-target aliases out of the picker.** An alias whose browser isn't
   installed can't launch; showing it would dead-end (the controller would re-present).
   Hide it instead.
4. **Live-persist master-detail (no sheet).** Matches the app's persist-on-mutation
   pattern and the requested System-Settings-style editing; name commits on focus-out to
   avoid per-keystroke churn.

## Technical Details

- **`onSelect` signature:**
  `(_ launchTarget: BrowserTarget, _ rememberDestination: RoutingDestination, _ remember: Bool) -> Void`.
- **`handleSelection`** launches `launchTarget` (resolved, concrete) and, when
  `remember`, calls `rulePersister.remember(url:destination: rememberDestination)`.
- **`presentPicker(url:browsers:aliases:)`** — at the `.prompt` case in `route(url:)`,
  `config` is in scope so pass `config.aliases`. The **fallback** call lives in the
  private `open(target:url:browsers:)`, which does **not** have `config` in scope — so
  give `open(...)` a new `aliases: [ProfileAlias]` parameter and pass `config.aliases`
  from its `route(url:)` caller (the only caller). Do **not** write `config.aliases`
  inside `open(...)` directly — it won't compile. (If threading the param is undesirable,
  `[]` at the fallback is acceptable, but the parameter is preferred so a remembered
  alias still works on that path.)
- **Alias row label:** alias name (primary) + resolved browser/profile label
  (secondary, via the same labeling used elsewhere); a section header "Aliases" above
  them. Browser rows render exactly as today.
- **Keyboard nav** is unchanged in mechanism — alias rows are part of `selectableItems`,
  so arrow/Return/`selectedIndex` highlighting covers them once prepended.

## What Goes Where

- **Implementation Steps** (`[ ]`): all Core + App code and tests in this repo.
- **Post-Completion** (no checkboxes): manual picker smoke test (alias appears, routes,
  remembers as alias) and master-detail UX smoke test in a running build.

## Implementation Steps

### Task 1: `RememberRule` destination-based builder (Core)

**Files:**
- Modify: `TrafficWandCore/Sources/TrafficWandCore/Matching/RememberRule.swift`
- Modify: `TrafficWandCore/Tests/TrafficWandCoreTests/RememberRuleTests.swift`

- [x] write failing tests: `rule(forURL:destination:)` returns a `Rule` carrying the
      given `RoutingDestination` for both `.alias(id)` and `.browser(target)`, with the
      same pattern scoping as today (registrable-domain `*x.com` and exact-host cases),
      and `nil` for a hostless URL
- [x] write a test that the existing `rule(forURL:target:)` still returns
      `.browser(target)` (delegation, no behavior change)
- [x] add `rule(forURL:destination: RoutingDestination)`; refactor the existing
      `rule(forURL:target:)` to delegate to it with `.browser(target)`; update the doc
      comment (a remembered alias selection now yields an `.alias` rule)
- [x] run `task test-core` — must pass before next task

### Task 2: `PickerViewModel` — aliases, alias rows, destination-carrying selection (App)

**Files:**
- Modify: `App/Sources/UI/Picker/PickerViewModel.swift`
- Modify (exists — migrate, do **not** create new): `App/Tests/AppTests/PickerViewModelTests.swift`
  (its harness builds the VM with a two-arg `onSelect: { target, remember in … }` at
  ~line 65 and existing assertions assume the flat `SelectableItem` with `.profile`)

> Picker compile-unit: App will not build until Task 4. Write/adjust tests now; the green
> checkpoint is end of Task 4.

- [x] migrate the existing test harness to the three-arg `onSelect` and tagged
      `SelectableItem.Kind`; update existing assertions (e.g.
      `testActivateSelectionSelectsBrowserDefault`) to the new shape
- [x] write failing tests: with aliases present, `selectableItems` lists the installed
      aliases first (in order, ids `"alias:<uuid>"`), then the browser/profile rows; an
      alias whose `target.bundleID` is **not** among `browsers` is excluded; selecting an
      alias row yields `launchTarget == alias.target` and
      `rememberDestination == .alias(alias.id)`; selecting a browser/profile row yields
      `.browser(target)`; `activateSelection()` over an alias row delivers the same;
      arrow-key nav reaches alias rows
- [x] add `aliases: [ProfileAlias]` to `init`; convert `SelectableItem` to the tagged
      `Kind` form (retain the existing browser/profile id scheme; add `"alias:<uuid>"`)
      with computed `launchTarget` / `rememberDestination`; build alias rows (filtered to
      installed targets) ahead of the browser rows
- [x] change `onSelect` to
      `(_ launchTarget: BrowserTarget, _ rememberDestination: RoutingDestination, _ remember: Bool)`;
      update `select(...)`/`activateSelection()` accordingly; update doc comments
- [x] (do not run `task test` yet — App is mid-migration; the green checkpoint is Task 4)

### Task 3: `BrowserPickerView` — Aliases section + alias rows (App)

**Files:**
- Modify: `App/Sources/UI/Picker/BrowserPickerView.swift`
- Modify: `App/Sources/UI/Previews/PreviewFixtures.swift` (if a picker preview helper
  needs aliases)

> Still within the picker compile-unit (green at end of Task 4).

- [x] replace the current `item.profile == nil` branching (in `row(for:)` and
      `rowLabel(for:)`) with a switch over `SelectableItem.Kind`; **preserve** the
      browser-group top-spacing (`isBrowserRow && !isFirst`) and the profile-row
      indentation (`.padding(.leading, 28)`); `hoveredItemID` stays `SelectableItem.ID`
      (== `String`)
- [x] render an "Aliases" section header + alias rows (alias name primary, resolved
      browser/profile secondary label) above the existing browser groups, with a divider/
      spacing between the Aliases group and the first browser group; keep the empty-state
      and keyboard-highlight behavior; alias rows are tappable like browser rows
- [x] update the `#Preview` / `previewViewModel` helper to pass sample aliases (reuse
      `PreviewFixtures.sampleAliases`) **and** fix its `onSelect: { _, _ in }` (~line 282)
      to the new three-arg signature `{ _, _, _ in }`; add a preview showing alias rows
- [x] (no separate test target for the view; row logic is covered by Task 2's view-model
      tests — noted)

### Task 4: Wire picker aliases end-to-end + remember-as-alias (App) — green checkpoint

**Files:**
- Modify: `App/Sources/PickerPresenting.swift`
- Modify: `App/Sources/UI/Picker/PickerPanelController.swift`
- Modify: `App/Sources/RoutingService.swift`
- Modify: `App/Sources/Adapters/ConfigRuleStore.swift`
- Modify: `App/Tests/AppTests/` — `PickerPanelControllerTests`,
  `PickerPanelControllerOpenSettingsTests` (**also breaks**: its `RulePersisting` mock
  `remember(url:target:)` at ~line 45 and its `presentPicker(url:browsers:)` calls at
  ~lines 116/139/156/159 both need migrating), `RoutingServiceTests` (its
  `PickerPresenting` mock `presentPicker(url:browsers:)` at ~line 70 needs `aliases:`),
  `ConfigRuleStoreTests`

- [x] write failing tests: `ConfigRuleStore.remember(url:destination:)` upserts a rule
      whose `destination` equals the passed destination (an `.alias(id)` persists an alias
      rule; a `.browser` persists a browser rule); `PickerPanelController.handleSelection`
      launches the concrete `launchTarget` and, on remember, calls
      `rulePersister.remember(url:destination:)` with the chosen destination; an
      unresolvable launch target still re-presents — **preserve coverage of the
      no-installed-browser recovery branch**: since uninstalled-target aliases are filtered
      at the VM layer (Task 2), exercise this via a `launchTarget` whose `bundleID` isn't
      in `browsers` (a stale/edge target), not via an alias row; `RoutingService` passes
      `config.aliases` into `presentPicker`
- [x] change `RulePersisting.remember(url:target:)` → `remember(url:destination:)`;
      update `ConfigRuleStore` to build via `RememberRule.rule(forURL:destination:)`
- [x] add `aliases:` to `PickerPresenting.presentPicker` and the
      `PickerPanelController` conformance (`presentPicker` → `makeViewModel(...,
      aliases:)`); update `handleSelection` to the new `onSelect` signature (launch
      `launchTarget`; remember `rememberDestination`)
- [x] update `RoutingService`: pass `config.aliases` at the `.prompt` call site in
      `route(url:)`; give the private `open(target:url:browsers:)` a new
      `aliases: [ProfileAlias]` parameter and pass `config.aliases` from its `route(url:)`
      caller (do not reference `config` inside `open(...)` — it's out of scope there)
- [x] update all affected mocks/tests for the new signatures (including the two test
      files named above and the `BrowserPickerView` preview from Task 3)
- [x] run `task generate` then `task test` — App green checkpoint — and `task lint`

### Task 5: Master-detail Aliases tab (App)

**Files:**
- Modify: `App/Sources/UI/Settings/AliasesListView.swift`
- Modify: `App/Sources/UI/Settings/AliasEditorView.swift`
- Modify: `App/Tests/AppTests/` (extend `SettingsViewModel`/alias tests for any new
      view-model logic; otherwise assert behavior via the existing CRUD seams)

- [x] write failing tests for any logic moved to/added in the view model (e.g. a helper
      that returns the selected alias by id, or "added alias becomes selected"); confirm
      `updateAlias`/`addAlias`/`deleteAlias` live-persist (already covered — extend if the
      new flow adds logic)
- [x] restructure `AliasesListView` to a `NavigationSplitView`: sidebar = alias list
      with Add + swipe/contextual delete (keep the blocked-delete alert and
      `attemptDelete`); detail = inline editor for the selected alias, placeholder
      otherwise; track `selectedAliasID` in `@State`; Add selects the new alias.
      **Remove** the now-dead `editing`/`EditingAlias` state and the `.sheet` modifier
- [x] convert `AliasEditorView` to an inline live-persist editor: name commits via
      `viewModel.updateAlias` on Enter **and on focus-out** — wire `@FocusState`
      (`.focused(...)` + `.onChange(of: isFocused)`), since `.onSubmit` alone only fires
      on Enter; `BrowserProfilePicker` change commits via `updateAlias`; remove the
      Save/Cancel chrome and the local-draft-only model
- [x] update `#Preview`s for the master-detail layout (selected + empty-selection states)
- [x] run `task test` and `task lint` — must pass before next task

### Task 6: Aliases tab description (App)

**Files:**
- Modify: `App/Sources/UI/Settings/AliasesListView.swift`

- [x] add a concise, always-visible description at the top of the Aliases tab (or as the
      detail placeholder) explaining what an alias is and the re-point-once-re-route-all
      benefit. **Reconcile/dedupe the copy** — the same "re-point once to re-route" idea
      currently appears in the empty-state (`AliasesListView` ~lines 74-75) and the
      `AliasEditorView` name caption (~lines 50-51); avoid a third near-duplicate. Decide
      one canonical home (the tab/detail description) and trim the others to short,
      non-redundant hints
- [x] update the `#Preview`(s) to show the description
- [x] run `task test` and `task lint` — must pass before next task

### Task 7: Verify acceptance criteria

- [ ] verify picker: an alias appears as a selectable row; selecting it routes the link
      to the alias's resolved target; ticking "Remember" persists an `.alias(id)` rule
      (covered by `PickerViewModel` + `ConfigRuleStore` tests); a concrete pick still
      persists `.browser(...)`
- [ ] verify edge cases: alias targeting an uninstalled browser is hidden from the picker;
      a hostless URL still persists nothing; blocked-delete still works in the new layout
- [ ] verify master-detail: selecting an alias edits it inline; edits persist live; Add
      selects the new alias; the description is visible
- [ ] run full Core suite: `task test-core` (includes the no-AppKit guard)
- [ ] run full App suite: `task test`
- [ ] run `task lint` — must be clean

### Task 8: [Final] Documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md` (if it documents the picker / aliases UX)

- [ ] update `CLAUDE.md`: the picker now offers alias rows and a remembered alias
      selection persists an `.alias(id)` rule (note the `RememberRule.rule(forURL:
      destination:)` path and the `PickerPresenting.presentPicker(...aliases:)` signature);
      the Aliases tab is now master-detail with live-persist editing + a description
- [ ] update `README.md` if it describes the picker or the Aliases tab
- [ ] move this plan to `docs/plans/completed/` (`mkdir -p` first)

## Post-Completion
*Items requiring manual intervention or external systems — informational only*

**Manual verification:**
- In a running build (`task run`): trigger the picker on a new link, confirm an
  **Aliases** section appears with your aliases, pick one and confirm the link opens in
  the alias's resolved browser/profile, then repeat with "Remember choice" ticked and
  confirm a subsequent link to the same site routes automatically — and that re-pointing
  the alias in Settings re-routes that remembered site (the `.alias` rule, not a frozen
  target).
- Confirm an alias whose target browser is uninstalled does not appear in the picker.
- In the Aliases tab: confirm the master-detail layout, live-persist editing (name
  commits on Enter/focus-out), Add-selects-new, blocked-delete, and the description text.
