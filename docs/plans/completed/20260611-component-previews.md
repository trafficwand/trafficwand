# SwiftUI Component Previews — Rules, Editor, Picker, Menu-bar Icon

## Context

TrafficWand's UI has almost no preview coverage. Only `BrowserPickerView` has working
`#Preview` blocks; the Settings views have none (`RulesListView` even carries a broken
commented-out stub with an unfilled `<#T##[Browser]#>` placeholder). Without previews, the
only way to iterate on this UI is a full `task run` round-trip through the menu-bar agent.

The structural blocker: **`#Preview` code compiles into the app target, never the test
target**, so the mocks in `App/Tests/AppTests/` are invisible to previews. The Settings
views also share one heavy dependency — `SettingsViewModel(configStore:browserProvider:updater:)`.

**Priority (per request):** the views that genuinely need previews are the **rules list**,
the **rules editor**, the **picker**, and the **menu-bar icon**. Everything else (General,
SettingsRoot, About tabs) is nice-to-have.

"Up-to-date" is enforced by a clean DEBUG build (preview code constructs each view with its
*current* initializer), plus small smoke tests for the shared fixtures and the icon symbol.

## Approach (decided)

- **Shared fixtures file** `App/Sources/UI/Previews/PreviewFixtures.swift`, all `#if DEBUG`,
  `internal` (not `private`) so the DEBUG test target can `@testable import` them. Scoped to
  what rules list/editor need: sample browsers/rules + the `SettingsViewModel` mock trio.
- **Picker**: already has up-to-date previews (`BrowserPickerView.swift:273-328`) — verify
  it still builds, do not touch it (its `private PreviewIconProvider` stays as-is).
- **Menu-bar icon**: not a SwiftUI view. Extract the SF Symbol name to one shared constant
  (single source of truth for `configureButton()` + the preview), then add a small SwiftUI
  `#Preview` rendering that symbol as a menu-bar-style template image (light/dark).

## Reference patterns to reuse

- Preview convention: `App/Sources/UI/Picker/BrowserPickerView.swift:273-328` — `#if DEBUG`
  block + protocol stub + a factory passing no-op closures. New work mirrors this.
- Mock shapes to copy: `App/Tests/AppTests/SettingsViewModelTests.swift:22-66`
  (`MockConfigStore`, `StubBrowserProvider`, `MockUpdater`).
- Initializers (all verified): `SettingsViewModel(configStore:browserProvider:updater:)`
  (`SettingsViewModel.swift:69`), `RuleEditorView(rule:browsers:onSave:onCancel:)`
  (`RuleEditorView.swift:32`), Core model memberwise inits in
  `TrafficWandCore/Sources/TrafficWandCore/Models/`.
- Menu-bar icon: the literal `"arrow.trianglehead.branch"` + `isTemplate = true` at
  `StatusBarController.swift:121-125`. Smoke-test precedent: the About-tab URL smoke test
  rationale (`AboutSettingsView.swift:21-26`).

## Development Approach

- Regular (not TDD): previews aren't TDD-shaped. Build fixtures → per-view previews → smoke
  tests. The "up-to-date" guarantee is the DEBUG compile (`task build`).
- `task generate` after adding the new file (XcodeGen globs `App/Sources`; `.xcodeproj` is
  generated). `task lint` stays clean; English-only.

## Testing Strategy

- **Compile-time (primary):** `task build` compiles all `#if DEBUG` preview code in DEBUG;
  a clean build proves each `#Preview` constructs its view with the current initializer.
- **Smoke tests (regression guards):** fixtures stay valid (sample rules target sample
  browsers; the factory loads them), and the menu-bar icon symbol resolves to a non-nil
  `NSImage`. Reachable from the DEBUG test target via `@testable import TrafficWand`.
- No snapshot framework, so visual correctness stays manual (Xcode canvas) — Post-Completion.

---

## Required

### Task 1: Shared preview fixtures

**Files:**
- Create: `App/Sources/UI/Previews/PreviewFixtures.swift`

- [x] Wrap the whole file in `#if DEBUG` / `#endif`.
- [x] `enum PreviewFixtures` with `static let sampleBrowsers: [Browser]` (Chrome w/
      Personal+Work profiles, Firefox, Safari — bundle IDs `com.google.Chrome`,
      `org.mozilla.firefox`, `com.apple.Safari`) and `static let sampleRules: [Rule]`
      (enabled/disabled, with and without a profile). **Every `sampleRules[].target.bundleID`
      MUST exist in `sampleBrowsers`** (Task 5 asserts this).
- [x] `#if DEBUG` mocks: `PreviewConfigStore: ConfigStore` as an **immutable `struct`**
      (no-op `save`; `load` returns a fixed `AppConfig`) → naturally `Sendable`, so do NOT
      copy the test mock's `@unchecked Sendable class`. Plus `PreviewBrowserProvider:
      InstalledBrowsersProviding` (returns `sampleBrowsers`) and `PreviewUpdater:
      UpdaterControlling` (`@MainActor final class`, stored `automaticallyChecksForUpdates`,
      `canCheckForUpdates = true`, no-op `checkForUpdates`).
- [x] `@MainActor static func makePreviewSettingsViewModel(config: AppConfig = <populated>)
      -> SettingsViewModel` that wires the three mocks and calls `load()`. Provide an
      empty-config path (e.g. pass `AppConfig(rules: [], fallback: .picker)`) for the empty
      state — no unused `load:` toggle.

### Task 2: RulesListView preview

**Files:**
- Modify: `App/Sources/UI/Settings/RulesListView.swift`

- [x] Delete the broken commented-out `#Preview` stub (lines ~157-162).
- [x] Add `#if DEBUG` `#Preview("Rules")` using
      `PreviewFixtures.makePreviewSettingsViewModel()` (populated).
- [x] Add `#Preview("Rules — empty")` using the empty-config factory path to exercise the
      empty state.

### Task 3: RuleEditorView preview

**Files:**
- Modify: `App/Sources/UI/Settings/RuleEditorView.swift`

- [x] Add `#if DEBUG` `#Preview("Rule Editor")` with `rule:
      PreviewFixtures.sampleRules.first!`, `browsers: PreviewFixtures.sampleBrowsers`, no-op
      `onSave`/`onCancel`.
- [x] Optionally add a "new/blank rule" variant (the Add path).

### Task 4: Menu-bar icon — extract symbol + preview

**Files:**
- Modify: `App/Sources/UI/StatusBarController.swift`

- [x] Extract the status-icon SF Symbol to one shared constant (single source of truth),
      e.g. `static let statusIconSymbolName = "arrow.trianglehead.branch"` (or a small
      `StatusBarIcon` enum). Use it in `configureButton()` (`StatusBarController.swift:121`).
- [x] Add a `#if DEBUG` SwiftUI `#Preview("Menu-bar icon")` (a tiny preview-only `View`)
      that renders `Image(systemName: StatusBarController.statusIconSymbolName)` as a
      template glyph at menu-bar scale, shown on both a light and a dark backdrop so the
      template rendering can be eyeballed. Import SwiftUI in the preview block only.
- [x] NSMenu not SwiftUI-previewable — stays manual (Post-Completion). (The live `NSMenu`
      itself isn't SwiftUI-previewable — its visuals stay under Post-Completion manual
      verification, as today.)

### Task 5: Smoke tests

**Files:**
- Create: `App/Tests/AppTests/PreviewFixturesTests.swift`

- [x] `#if DEBUG`-guarded; `@testable import TrafficWand`.
- [x] Assert `PreviewFixtures.sampleBrowsers` is non-empty and each sample
      `Rule.target.bundleID` resolves to a sample browser.
- [x] Assert `makePreviewSettingsViewModel()` returns a view model whose `rules`/`browsers`
      are populated (factory wires mocks + calls `load()`).
- [x] Assert `NSImage(systemSymbolName: StatusBarController.statusIconSymbolName,
      accessibilityDescription: nil) != nil` (typo guard for the menu-bar glyph).
- [x] Run tests — must pass before Task 6.

### Task 6: Verify

- [x] `task generate` (pick up the new file).
- [x] `task build` — clean DEBUG build proves every `#Preview` matches current inits.
- [x] `task test` — full app test target incl. the new smoke tests.
- [x] `task lint` — clean.
- [x] Confirm `BrowserPickerView` still builds unchanged; confirm rules list, rules editor,
      and menu-bar-icon previews compile.

---

## Nice-to-have (optional — only if time allows)

These reuse the Task 1 fixtures. Not required by the request; defer unless asked.

- **GeneralSettingsView** `#Preview`: `makePreviewSettingsViewModel()` +
  `DefaultBrowserManager(ourBundleID: "com.example.preview")` (concrete struct, not a seam —
  `isDefault` does a read-only `NSWorkspace` query, so the canvas shows the real "not
  default" state).
- **SettingsRootView** `#Preview`: the above + `SettingsSelection(tab: .general)`.
- **AboutSettingsView** `#Preview`: add `static let previewBuildInfo: BuildInfo` to fixtures
  (synthetic `infoDictionary`; use `GitCommitHash = "abc1234"` — NOT `"unknown"`/empty,
  which `BuildInfo.init` maps to `nil`, `BuildInfo.swift:32-38`) + a no-op `openURL`.

### Task 7: [Final] Docs & cleanup

- [x] If the shared `PreviewFixtures` file is a new convention, add a one-line note to
      `CLAUDE.md` (App-side conventions section).
- [x] move to docs/plans/completed/ (deferred to end of run — review phases still read this path)

## Post-Completion
*Manual / non-code items — no checkboxes.*

**Manual verification (no snapshot framework):**
- Open the canvases: `RulesListView` (populated + empty), `RuleEditorView`, the menu-bar
  icon preview (light + dark), and `BrowserPickerView` (unchanged).
- The live menu-bar dropdown (`NSMenu` items, checkmarks, validation) stays manual — run
  `task run` and open the menu, as today.
