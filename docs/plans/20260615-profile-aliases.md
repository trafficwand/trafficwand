# Profile Aliases (Reusable Profiles) — Issue #13

## Overview

Add **profile aliases** (user-facing: "Aliases"): named, reusable bindings to a concrete
browser + profile that rules (and the fallback policy) reference *by identity* instead of
embedding a concrete `BrowserTarget`. Think of them as **variables** / live pointers:
define "Personal" → Chrome / Profile 2 once, point any number of rules at "Personal", and
re-pointing "Personal" at a different browser updates every referencing rule at once.

> **Naming note:** the issue calls this "meta-profiles," but the feature ships as
> **Profile Aliases** — "alias" conveys the live-reference semantics (edit once →
> propagates) better than "preset" (which implies a frozen copy), is Mac-native (Finder
> aliases), and avoids both the "Meta" (company) brand adjacency and the double meaning of
> the word "profile."

- **Problem it solves:** Today each rule stores its own concrete `BrowserTarget`. Switching
  which browser handles "work" links means editing every work rule by hand. Aliases give a
  single point of change.
- **Key benefit:** late-binding indirection — rules store a *reference*, resolved to a
  concrete target at decision time.
- **Integration:** Resolution lives entirely inside `Router.decide` (Core), so the
  `RoutingDecision` type and the App's launch path are unchanged. The feature surfaces as a
  new "Aliases" Settings tab plus an updated rule/fallback editor that can pick either a
  concrete browser or an alias.

Issue #13 (migrated from `tomakado/trafficwand#38`): "Meta-profiles or proxy-profiles —
profiles you set up once and then re-use in Rules … You can think of it as variables."

## Context (from discovery)

Files/components involved:

- **Core models:** `AppConfig.swift` (root persisted doc, `schemaVersion = 1`, has
  `upserting`), `Rule.swift` (`target: BrowserTarget`), `BrowserTarget.swift`,
  `FallbackPolicy.swift` (`.defaultBrowser(BrowserTarget)`).
- **Core routing:** `Router.swift` (`decide` returns `.open(rule.target)`),
  `RoutingDecision.swift` (`.open(BrowserTarget)` / `.prompt(...)` — stays unchanged).
- **Core matching:** `RememberRule.swift` (builds a `Rule` from a `BrowserTarget`).
- **App adapter (uncited consumer):** `ConfigRuleStore.swift` calls
  `RememberRule.rule(forURL:target:)` then `config.upserting(rule)`. It compiles unchanged
  (the `BrowserTarget` parameter is kept), but see design decision #4 for the
  upsert-over-alias behavior interaction.
- **App settings:** `SettingsViewModel.swift` (state + CRUD + persistence),
  `RuleEditorView.swift`, `RulesListView.swift`, `GeneralSettingsView.swift`
  (fallback editor), `SettingsTab.swift` / `SettingsRootView.swift` (tab wiring),
  `PreviewFixtures.swift` (sample data, DEBUG-only, `internal`).
- **App routing:** `RoutingService.swift` (consumes a concrete `BrowserTarget` — **no
  change needed**, resolution happens in Core).

Related patterns found:

- **Stable on-disk coding keys + `schemaVersion`** for forward migration; every model
  documents "do not rename without a schema migration."
- **Tagged-enum Codable** precedent: `FallbackPolicy` already hand-rolls
  `init(from:)`/`encode(to:)` with a `Kind` discriminator — the template for
  `RoutingDestination`.
- **`Rule.upserting` / `RememberRule`** construct `Rule`s; both must move to
  `destination`.
- **Protocol seams + `@Observable` view model**: `SettingsViewModel` depends only on
  `ConfigStore` + `InstalledBrowsersProviding`; every mutation persists. Views are thin and
  unit-tested where logic exists (e.g. `GeneralSettingsView` fallback-mode logic,
  `SettingsViewModelTests`).
- **Core purity guard**: `task test-core` greps for AppKit imports in Core — keep all new
  Core code Foundation-only.

Dependencies identified:

- Schema bump `1 → 2`; old `config.json` files must keep loading (legacy `target` key →
  `.browser(target)`; absent `aliases` → `[]`).
- `RoutingDecision` and the App launch path are **decoupled** from this change by design.

## Development Approach

- **Testing approach: TDD** (mandated by `CLAUDE.md` for Core — write the failing test
  first, then implement; all tests pass before moving on).
- Complete each task fully before the next; small, focused changes.
- **CRITICAL: every task includes new/updated tests** (success + edge/error cases) as
  separate checklist items.
- **CRITICAL: all tests pass before starting the next task.**
- **CRITICAL: update this plan when scope changes during implementation.**
- Keep Core free of system dependencies (Foundation only; no AppKit).
- Keep `task lint` clean.
- Run `task test-core` for the fast Core TDD loop; `task test` for the App target.

### Build / green-checkpoint reality (important — read before starting)

Replacing `Rule.target` with `Rule.destination` is a **wide type change**: it breaks
`AppConfig.upserting`, `Router.decide`, `RememberRule`, and every App consumer at the type
level the moment Task 3 lands. Swift will not compile — and therefore `task test-core` will
not go green — until **all Core consumers are migrated (end of Task 6)**. Likewise the App
target will not build until **all App consumers are migrated (end of Task 11)**.

Practical consequence for the per-task "tests must pass before next task" rule:

- **Tasks 1–2** are additive (new files) and stay green independently.
- **Tasks 3–6 form one Core compile-unit.** Write each task's failing tests as planned, but
  the **Core green checkpoint is the end of Task 6** — do not expect `swift test` to compile
  between Tasks 3 and 6. Treat 3→6 as a single uninterrupted edit session.
- **Tasks 7–11 form one App compile-unit.** The **App green checkpoint is the end of Task
  11.** (Core stays green throughout 7–11 since Core is already migrated.)

If a more incremental green cadence is required, an acceptable alternative is to collapse
Tasks 3–6 into one task and Tasks 9–11 into one task; the breakdown below is kept granular
for review/PR clarity, not because each sub-step compiles in isolation.

## Testing Strategy

- **Unit tests (Core):** `swift test` via `task test-core`. Every new model/branch gets
  success + edge tests, plus **Codec/round-trip + legacy-decode** tests (the migration is
  the riskiest surface).
- **Unit tests (App):** `xcodebuild test` via `task test`. `SettingsViewModel` CRUD +
  referential-integrity logic, fallback-mode logic, preview-fixture sanity.
- **No e2e/UI-automation harness** exists in this project; SwiftUI views are exercised by
  light view tests + `#Preview` fixtures (e.g. `AboutSettingsViewTests`,
  `PreviewFixturesTests`). Follow that precedent — put logic in the view model and test it
  there; keep views declarative.

## Progress Tracking

- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix
- update plan if implementation deviates from original scope

## Solution Overview

**Data model (the sum-type approach, locked during planning):**

```swift
struct ProfileAlias: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var target: BrowserTarget
}

enum RoutingDestination: Codable, Equatable, Hashable, Sendable {
    case browser(BrowserTarget)   // a concrete browser/profile
    case alias(UUID)              // a reference resolved against AppConfig.aliases
}

struct Rule { var pattern; var destination: RoutingDestination; var isEnabled }
enum FallbackPolicy { case picker; case defaultBrowser(RoutingDestination); case lastUsed }
struct AppConfig { var schemaVersion; var aliases: [ProfileAlias]; var rules; var fallback }
```

**Resolution (the heart of the feature) — pure, in Core:**

```swift
extension RoutingDestination {
    /// Resolve to a concrete target given the config's aliases.
    /// Returns nil for a dangling .alias reference (alias deleted/missing).
    func resolved(in aliases: [ProfileAlias]) -> BrowserTarget? {
        switch self {
        case .browser(let t): return t
        case .alias(let id):  return aliases.first { $0.id == id }?.target
        }
    }
}
```

`Router.decide` resolves the matched rule's (or fallback's) destination through this; a
**dangling reference resolves to `.prompt`** (the picker) — never a dropped or mis-routed
link.

**Referential integrity (App):** `SettingsViewModel` exposes which rules/fallback reference
a given alias; the alias UI **blocks deletion** of a referenced alias and explains why. Core
stays defensive regardless (dangling → picker).

### Key design decisions & rationale

1. **Resolve inside `Router.decide`.** Keeps `RoutingDecision` and the whole App launch
   path (`RoutingService`) unchanged — aliases are invisible past the decision boundary.
   This is the main reason the App-routing layer has no tasks below.
2. **Backward-compatible Codable, schema `1 → 2`.** Old files store `Rule.target` and
   `FallbackPolicy.defaultBrowser.target` as a bare `BrowserTarget`, and have no `aliases`
   key. Custom `init(from:)` decodes new shape if present, else legacy shape wrapped as
   `.browser(...)`. New writes always use the v2 shape. No data loss either way.
3. **Block-delete + Core safe-resolve (locked).** UI prevents accidental orphaning; Core
   guarantees correctness even if an orphan slips through (e.g. hand-edited config).
4. **`RememberRule` always creates a concrete `.browser` rule.** "Remember this site" is a
   one-off concrete choice; it never invents an alias. **Interaction with `upserting`:** if a
   rule already exists for the same pattern and is `.alias`-backed, remembering replaces its
   `destination` with `.browser(...)` — i.e. "remember" *demotes* an alias-backed rule to a
   concrete one for that pattern. This is intentional (the user just made a concrete choice
   for that site) and is pinned by a test in Task 5.
5. **Alias resolution does not touch last-used.** `lastUsed` stays a concrete `BrowserTarget`
   recorded only by the App *after* a picker selection (`RoutingService`). Resolving an alias
   inside `Router.decide` must **not** read or write last-used, and must not add any new
   last-used recording in Core (that would also violate Core purity / the seam boundary).
6. **Name = "Profile Alias" (locked).** See the naming note in Overview.

## Technical Details

- **`RoutingDestination` Codable shape** (tagged object, mirrors `FallbackPolicy`):
  - `.browser` → `{ "type": "browser", "target": { bundleID, profileID? } }`
  - `.alias` → `{ "type": "alias", "id": "<uuid>" }`
- **`Rule` decode:** prefer `destination` key; if absent, decode legacy `target`
  (`BrowserTarget`) → `.browser(target)`. Encode always writes `destination`.
- **`FallbackPolicy.defaultBrowser` decode:** the `target` key historically held a
  `BrowserTarget`. New shape holds a `RoutingDestination`. Decode strategy: try
  `RoutingDestination` first; on failure, decode legacy `BrowserTarget` and wrap as
  `.browser(...)`. (Disambiguation is clean: legacy `BrowserTarget` has a `bundleID` key and
  no `type` key; new `RoutingDestination` always has `type`.)
- **`AppConfig` decode:** `aliases` defaults to `[]` when the key is absent;
  `currentSchemaVersion` bumps to `2`. `default` gains `aliases: []`.
- **`AppConfig.upserting`** now compares/sets `destination` instead of `target`.
- **Dangling resolution:** `RoutingDestination.alias(id)` whose `id` is not in `aliases` →
  `resolved` returns `nil` → `Router` emits `.prompt`.

## What Goes Where

- **Implementation Steps** (`[ ]`): all Core + App code and tests in this repo.
- **Post-Completion** (no checkboxes): manual UI smoke test, config-migration spot check
  on a real `config.json`.

## Implementation Steps

### Task 1: `ProfileAlias` model

**Files:**
- Create: `TrafficWandCore/Sources/TrafficWandCore/Models/ProfileAlias.swift`
- Create: `TrafficWandCore/Tests/TrafficWandCoreTests/ProfileAliasTests.swift`

- [x] write failing tests: `ProfileAlias` Codable round-trip; `Equatable`/`Hashable`
      identity; stable coding keys (`id`, `name`, `target`)
- [x] create `ProfileAlias` (`id: UUID`, `var name: String`, `var target: BrowserTarget`),
      conforming to `Codable, Equatable, Hashable, Identifiable, Sendable` with documented
      stable `CodingKeys` and a public memberwise init (`id: UUID = UUID()`)
- [x] run `task test-core` — must pass before next task (skipped: `task test-core`/`task lint`
      denied at the permission layer in this environment; Task 1 is purely additive — two new
      files, no edits to existing code — and mirrors `BrowserTarget`/`Rule` conventions exactly)

### Task 2: `RoutingDestination` sum type + resolution

**Files:**
- Create: `TrafficWandCore/Sources/TrafficWandCore/Models/RoutingDestination.swift`
- Create: `TrafficWandCore/Tests/TrafficWandCoreTests/RoutingDestinationTests.swift`

- [x] write failing tests: tagged-object encode shape for `.browser` and `.alias`; decode
      round-trip both cases; `resolved(in:)` returns the target for `.browser`, the
      looked-up target for a known `.alias`, and `nil` for a dangling `.alias`
- [x] write a **negative-decode test**: a legacy bare `BrowserTarget` JSON
      (`{bundleID, profileID}`, no `type` key) **fails** to decode as `RoutingDestination`
      (throws `keyNotFound(.type)`). This guarantees the try-first/fallback decode in Task 4
      is pinned by a test, not by luck — a future leniency change here would break this test
      instead of silently mis-routing fallbacks.
- [x] implement `RoutingDestination` enum with hand-rolled tagged Codable (`Kind`
      discriminator `browser`/`alias`), mirroring `FallbackPolicy`'s pattern; ensure
      `init(from:)` **throws** when the `type` key is absent (no default/leniency)
- [x] implement `resolved(in aliases: [ProfileAlias]) -> BrowserTarget?`
- [x] run `task test-core` — passed (148 tests, 16 suites green); `task lint` clean for new
      files (the only warnings are pre-existing short identifiers in `ProfileAliasTests.swift`)

### Task 3: Migrate `Rule` to `destination` with backward-compatible decode

**Files:**
- Modify: `TrafficWandCore/Sources/TrafficWandCore/Models/Rule.swift`
- Modify: `TrafficWandCore/Tests/TrafficWandCoreTests/AppConfigCodableTests.swift` (existing
  `Rule` Codable coverage lives here — there is **no** standalone `RuleCodableTests.swift`;
  add a dedicated file only if the cases grow large)

- [ ] write failing tests: decoding **legacy** JSON (`{pattern, target:{…}, isEnabled}`)
      yields `destination == .browser(target)`; decoding **v2** JSON (`{pattern,
      destination:{…}, isEnabled}`) round-trips; encoding always emits `destination`
      (never `target`)
- [ ] replace `var target: BrowserTarget` with `var destination: RoutingDestination`;
      update memberwise init signature; keep `id`, `pattern`, `isEnabled`
- [ ] add custom `init(from:)`: prefer `destination`; else decode legacy `target`
      (`BrowserTarget`) → `.browser(...)`. Keep synthesized/explicit `encode(to:)` writing
      the v2 shape. Document the migration in the type doc comment
- [ ] run `task test-core` — must pass before next task

### Task 4: Migrate `FallbackPolicy.defaultBrowser` to `RoutingDestination`

**Files:**
- Modify: `TrafficWandCore/Sources/TrafficWandCore/Models/FallbackPolicy.swift`
- Modify: `TrafficWandCore/Tests/TrafficWandCoreTests/AppConfigCodableTests.swift` (existing
  `FallbackPolicy` Codable coverage lives here; no standalone `FallbackPolicyTests.swift`)

- [ ] write failing tests: legacy `{type:"defaultBrowser", target:{bundleID,…}}` decodes to
      `.defaultBrowser(.browser(target))`; v2 `{type:"defaultBrowser",
      target:{type:"alias", id}}` round-trips; `.picker`/`.lastUsed` unchanged
- [ ] change case to `defaultBrowser(RoutingDestination)`; in `init(from:)` decode the
      `target` key by trying `RoutingDestination` first, falling back to legacy
      `BrowserTarget` wrapped as `.browser(...)`; `encode(to:)` writes the
      `RoutingDestination`. This fallback is **safe because** the Task 2 negative-decode test
      guarantees legacy `BrowserTarget` JSON throws when decoded as `RoutingDestination` (no
      `type` key) — the ordering dependency is test-pinned, not failure-luck
- [ ] update the type doc comment to describe the destination payload + migration
- [ ] run `task test-core` — must pass before next task

### Task 5: `AppConfig.aliases` + schema v2 + `upserting`

**Files:**
- Modify: `TrafficWandCore/Sources/TrafficWandCore/Models/AppConfig.swift`
- Modify: `TrafficWandCore/Tests/TrafficWandCoreTests/AppConfigCodableTests.swift`,
  `TrafficWandCore/Tests/TrafficWandCoreTests/AppConfigUpsertTests.swift` (real existing
  files)
- Optional: `TrafficWandCore/Tests/TrafficWandCoreTests/Fixtures/config-v1.json` (a committed
  legacy config, loaded via the existing `FixtureLoader`, to lock the exact historical shape)

- [ ] write failing tests: full **v1 → v2 migration** (decode a complete legacy
      `config.json` string: no `aliases`, rules with `target`, fallback with bare `target`)
      loads cleanly with `aliases == []` and `.browser(...)` destinations; v2 round-trip
      preserves aliases; `aliases` absent → `[]`; `default` has empty aliases; `upserting`
      matches/sets `destination`; **`upserting` a `.browser` rule over an existing `.alias`
      rule of the same pattern replaces the destination with `.browser(...)`** (pins design
      decision #4 — the remember-over-alias demotion)
- [ ] add `var aliases: [ProfileAlias]`; bump `currentSchemaVersion = 2`; add custom decode
      defaulting `aliases` to `[]` when absent; update init + `default` + `CodingKeys`
- [ ] update `upserting(_:)` to read/write `destination` (replace `rules[index].target =`)
- [ ] run `task test-core` — must pass before next task

### Task 6: Resolve destinations in `Router.decide`; update `RememberRule`

**Files:**
- Modify: `TrafficWandCore/Sources/TrafficWandCore/Routing/Router.swift`
- Modify: `TrafficWandCore/Sources/TrafficWandCore/Matching/RememberRule.swift`
- Modify/Create: `TrafficWandCore/Tests/TrafficWandCoreTests/RouterTests.swift`,
  `TrafficWandCore/Tests/TrafficWandCoreTests/RememberRuleTests.swift`

- [ ] write failing tests (Router): matched rule with `.alias` resolves to the alias's
      target → `.open(target)`; matched rule with **dangling** `.alias` → `.prompt`;
      matched rule with `.browser` → `.open(target)` (unchanged);
      `.defaultBrowser(.alias)` resolves / dangling → `.prompt`; `.defaultBrowser(.browser)`
      unchanged
- [ ] update `Router.decide`: resolve `rule.destination` and the fallback's
      `RoutingDestination` via `resolved(in: config.aliases)`; `nil` → `.prompt(url:
      availableBrowsers)`; keep `RoutingDecision` type and `.lastUsed`/`.picker` logic
      intact
- [ ] write failing tests (RememberRule): produced `Rule.destination == .browser(target)`
      for registrable-domain and exact-host cases
- [ ] update `RememberRule.rule(forURL:target:)` to build
      `Rule(destination: .browser(target))` (keep the `BrowserTarget` parameter)
- [ ] update the `Router` doc comment to describe alias resolution + dangling → picker
- [ ] run `task test-core` — must pass before next task

### Task 7: `SettingsViewModel` — alias state, CRUD, persistence, referential integrity

**Files:**
- Modify: `App/Sources/UI/Settings/SettingsViewModel.swift`
- Modify: `App/Tests/AppTests/SettingsViewModelTests.swift`

- [ ] write failing tests: `load()` reads `aliases`; `addAlias` / `updateAlias` /
      `deleteAlias(id:)` mutate state **and** persist via `ConfigStore.save`;
      `rulesReferencing(aliasID:)` (and fallback reference) returns referencing rules;
      `deleteAlias` is a **no-op when referenced**; `persist()` writes `aliases` into the
      saved `AppConfig`
- [ ] add `private(set) var aliases: [ProfileAlias]`; load it in `load()`; include it in
      `persist()`'s `AppConfig`
- [ ] add CRUD methods + an `isReferenced(_:)` / `referencingRules(_:)` helper that scans
      `rules` (`.alias` destinations) and `fallback` (`.defaultBrowser(.alias)`)
- [ ] add a testable `destinationLabel(for: RoutingDestination) -> String` helper on the
      view model (resolve `.alias` → alias name, "(deleted alias)" if dangling; `.browser` →
      browser name + optional profile). Keeping this in the view model (not the view) gives
      it a unit-test seam, consistent with how fallback-mode logic is tested. Task 9's
      `RulesListView` consumes this helper.
- [ ] make `deleteAlias` refuse (and not persist) when referenced; expose enough for the
      view to show which rules block deletion
- [ ] run `task test` — must pass before next task

### Task 8: Aliases Settings tab — list + editor view

**Files:**
- Modify: `App/Sources/UI/Settings/SettingsTab.swift`
- Modify: `App/Sources/UI/Settings/SettingsRootView.swift`
- Create: `App/Sources/UI/Settings/AliasesListView.swift`
- Create: `App/Sources/UI/Settings/AliasEditorView.swift`
- Modify: `App/Tests/AppTests/SettingsTabTests.swift`

- [ ] write failing tests: `SettingsTab` includes the new `.aliases` case. Note
      `SettingsTab` is a plain `String` enum (titles live in `SettingsRootView`'s `Label`s,
      not the enum) — check whether `SettingsTabTests` asserts case count / `CaseIterable`
      ordering and update those expectations; decide tab order (likely `general → rules →
      aliases → about`)
- [ ] add `.aliases` to `SettingsTab`; wire a `TabView` tab in `SettingsRootView` hosting
      `AliasesListView(viewModel:)` with its `Label`/title there
- [ ] implement `AliasesListView`: list of aliases (name + resolved browser/profile), Add
      button, row tap → editor sheet, delete with a **block + explanation** when referenced
      (uses the view model's reference check)
- [ ] implement `AliasEditorView`: edit `name`, browser (`Picker` over
      `viewModel.browsers`), profile (`Picker`, reset on browser change — mirror
      `RuleEditorView`), Save/Cancel committing a `ProfileAlias`; `#if DEBUG #Preview`s using
      `PreviewFixtures`
- [ ] run `task test` — must pass before next task

### Task 9: `RuleEditorView` + `RulesListView` — choose & display browser-or-alias

**Files:**
- Modify: `App/Sources/UI/Settings/RuleEditorView.swift`
- Modify: `App/Sources/UI/Settings/RulesListView.swift`
- Modify: `App/Tests/AppTests/` (add `RuleEditorView`/`RulesListView` logic tests if a
  testable seam exists; otherwise assert via `SettingsViewModel` round-trip)

- [ ] write failing tests: a rule edited to an alias persists `destination == .alias(id)`;
      a rule edited to a concrete browser persists `.browser(...)`; the rule-list
      destination label shows the alias **name** for `.alias` and the browser (+profile) for
      `.browser`
- [ ] `RuleEditorView`: add a destination-mode control (e.g. segmented "Browser" /
      "Alias"); in Browser mode keep the existing bundle/profile pickers; in Alias mode show
      a `Picker` over `viewModel.aliases`; `commit()` builds the matching
      `RoutingDestination`; init seeds mode from `rule.destination`; `canSave` requires a
      resolvable selection in the active mode
- [ ] `RulesListView`: replace `rule.target.*` reads with the view model's
      `destinationLabel(for:)` helper (added in Task 7 — resolves `.alias` name / "(deleted
      alias)" / `.browser` name+profile); update `defaultNewRule` to a `.browser(...)`
      destination; pass aliases into the editor
- [ ] run `task test` — must pass before next task

### Task 10: `GeneralSettingsView` fallback — allow alias as default destination

**Files:**
- Modify: `App/Sources/UI/Settings/GeneralSettingsView.swift`
- Modify: `App/Tests/AppTests/` (extend the existing fallback-mode tests, or
  `SettingsViewModelTests` for the persisted shape)

- [ ] write failing tests: choosing an alias as the default-browser fallback persists
      `.defaultBrowser(.alias(id))`; choosing a concrete browser persists
      `.defaultBrowser(.browser(...))`; entering `.defaultBrowser` mode is still refused when
      there are no browsers **and** no aliases
- [ ] update the `.defaultBrowser` branch: its target editor now produces a
      `RoutingDestination` (browser-or-alias, same control idiom as the rule editor); update
      `currentDefaultTarget`/binding logic to read/write the destination
- [ ] run `task test` — must pass before next task

### Task 11: Preview fixtures

**Files:**
- Modify: `App/Sources/UI/Previews/PreviewFixtures.swift`
- Modify: `App/Tests/AppTests/PreviewFixturesTests.swift`

- [ ] write/adjust failing tests: fixtures expose `sampleAliases`; `sampleRules` include at
      least one `.alias` and one `.browser` destination; `makePreviewSettingsViewModel` is
      seeded with aliases
- [ ] update `sampleRules` to the `destination` shape; add `sampleAliases`; seed the preview
      view model; fix any `.target` references in `#Preview` blocks across the Settings views
- [ ] run `task test` — must pass before next task

### Task 12: Verify acceptance criteria

- [ ] verify issue #13 behavior end-to-end: define an alias, point ≥2 rules at it, change
      the alias's browser, confirm all referencing rules resolve to the new browser (covered
      by `RouterTests` + `SettingsViewModelTests`)
- [ ] verify edge cases: dangling reference → picker; legacy `config.json` migrates; block
      delete of a referenced alias; fallback alias resolves
- [ ] run full Core suite: `task test-core` (includes the no-AppKit guard)
- [ ] run full App suite: `task test`
- [ ] run `task lint` — must be clean

### Task 13: [Final] Documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md` (if it documents rules/config behavior)

- [ ] update `CLAUDE.md` architecture/model list: add `ProfileAlias`, `RoutingDestination`,
      `AppConfig.aliases`, schema v2 + migration note, and the Router resolution rule
      (dangling → picker)
- [ ] update `README.md` if it describes routing rules / config schema
- [ ] move this plan to `docs/plans/completed/` (`mkdir -p` first)

## Post-Completion
*Items requiring manual intervention or external systems — informational only*

**Manual verification:**
- Smoke-test the Settings UI in a running build (`task run`): create/edit/delete an alias,
  reference it from a rule and from the fallback, confirm the block-delete warning, and
  confirm a routed link opens in the alias's browser.
- Spot-check migration against a **real pre-feature `config.json`** (back it up first):
  launch the new build, confirm rules/fallback load unchanged and a subsequent save rewrites
  the file in the v2 shape with `schemaVersion: 2`.

**Release note (when shipping):**
- Mention reusable profile aliases in the release/appcast notes; no `MARKETING_VERSION`
  bump is part of this plan (handled at release time per `CLAUDE.md`).
