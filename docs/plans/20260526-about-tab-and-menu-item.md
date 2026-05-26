# About Tab + Menu Item (Issue #4)

## Overview

Add an "About" surface to TrafficWand that satisfies issue [#4](https://github.com/tomakado/trafficwand/issues/4): app name, app icon, version + build identifier, commit hash, copyright notice, license notice, and a "Sponsor" button.

The About content lives as a **third tab** in the existing Settings window, alongside General and Rules. It is reachable two ways:

1. The Settings window itself (`Settings…` menu item / `⌘,`) — users can switch to it like any other tab.
2. A new **"About TrafficWand…"** item in the status-bar menu that opens the Settings window **deep-linked to the About tab**.

The commit hash is injected via a generated `BuildInfo.xcconfig` (written by a Taskfile step before `xcodebuild` runs) → exposed as a `GIT_COMMIT` build setting → substituted into `Info.plist` via Xcode's standard `$(VAR)` plist processing, *before* code signing. This avoids the trap of mutating a signed bundle's Info.plist after the fact.

The license notice is backed by a new top-level `LICENSE` file (MIT, copyright Ildar Karymov, 2026).

## Context (from discovery)

- **Files/components involved**
  - `App/Sources/UI/StatusBarController.swift` — owns the status-bar menu (Set as Default / Settings… / Quit). New About item slots in here.
  - `App/Sources/UI/Settings/SettingsRootView.swift` — `TabView` host. Today the tabs use implicit selection; must move to an explicit `selection:` binding to support deep-linking.
  - `App/Sources/UI/Settings/SettingsWindowController.swift` — `show()` must accept an optional initial tab and pass it through.
  - `App/Sources/AppMain.swift` — wires the status-bar `onOpenSettings` hook; needs an analogous `onOpenAbout` hook that calls `show(initialTab: .about)`.
  - `project.yml` — add `xcconfig: BuildInfo.xcconfig` to the `TrafficWand` target.
  - `Taskfile.yml` — add a `build-info` step that writes `BuildInfo.xcconfig` with the current short commit hash; have `build` / `run` / `test` depend on it.
  - `App/Resources/Info.plist` — gains a `GitCommitHash` key whose value is `$(GIT_COMMIT)`.
  - `App/Tests/AppTests/` — new tests for `BuildInfo`, `SettingsTab`, and the wiring extensions of `SettingsWindowController` / `StatusBarController`.
  - **New** top-level `LICENSE`.
  - **New** `BuildInfo.xcconfig` at repo root (or `App/Resources/`); **gitignored** because it's generated per-build.
  - **New** `App/Sources/UI/Settings/AboutSettingsView.swift`, `App/Sources/BuildInfo.swift`.

- **Related patterns found**
  - `StatusMenuState` is the established "pure decision behind an AppKit shell" pattern — `BuildInfo` and `SettingsTab` follow the same shape.
  - `SettingsWindowController` already centralizes activation (`NSApp.activate(ignoringOtherApps:)`) + `makeKeyAndOrderFront`; reuse it verbatim, just parameterize the entry tab.
  - `onOpenSettings: () -> Void` closure pattern in `StatusBarController` is the precedent for `onOpenAbout: () -> Void`.

- **Dependencies identified**
  - No new SPM packages. SwiftUI + AppKit + Foundation only.
  - `Bundle.main.infoDictionary` for version (`CFBundleShortVersionString`), build (`CFBundleVersion`), and `GitCommitHash`.
  - `NSImage(named: NSImage.applicationIconName)` for the app icon.

## Development Approach

- **Testing approach**: **TDD where it pays, regular where it doesn't** — failing tests first for the pure helpers (`BuildInfo`, `SettingsTab`, status-menu / window-controller wiring). The SwiftUI `AboutSettingsView` and the xcconfig generation are covered by manual verification (no snapshot framework in this repo, and `Bundle.main` inside the unit-test target points at the xctest runner, not the app bundle — so a runtime smoke test on `GitCommitHash` would silently read the wrong plist).
- Complete each task fully before moving to the next.
- Make small, focused changes.
- **CRITICAL: every task MUST include new/updated tests** for code changes in that task
  - Tests are not optional — they are a required part of the checklist.
  - Tests cover success AND error/edge cases.
- **CRITICAL: all tests must pass before starting the next task** — no exceptions. Run `task test-core` for Core changes and `task test` for app-target changes.
- **CRITICAL: update this plan file when scope changes during implementation.**
- Maintain backward compatibility — existing `SettingsWindowController.show()` (no args) keeps working.

## Testing Strategy

- **Unit tests** (required per task): `BuildInfoTests`, `SettingsTabTests`, `SettingsWindowControllerAboutTests`, `StatusBarControllerAboutTests`.
- **E2E tests**: this project has no UI e2e harness (Playwright/Cypress/etc.). UI flows are covered by manual verification in Post-Completion.
- **Test command**: `task test-core` (fast) then `task test` (full app tests, includes Core).

## Progress Tracking

- Mark completed items with `[x]` immediately when done.
- Add newly discovered tasks with `➕` prefix.
- Document issues/blockers with `⚠️` prefix.
- Update the plan if implementation deviates from original scope.
- Keep the plan in sync with actual work done.

## Solution Overview

```
status-bar menu                        Settings window
┌───────────────────────────┐          ┌───────────────────────────────────────────┐
│ [✓] TrafficWand is your   │          │ [General] [Rules] [About]                 │
│     default browser       │          │ ─────────────────────────────────────────│
│                           │          │            [App icon, 96pt]               │
│ ─────                     │          │           TrafficWand                     │
│ About TrafficWand…  ◀──── │ ◀── new  │       Version 0.1.0 (build 1)             │
│ Settings…           ⌘,    │          │       commit abc1234 (selectable)         │
│ ─────                     │          │                                           │
│ Quit                ⌘Q    │          │       © 2026 Ildar Karymov                │
└───────────────────────────┘          │       MIT License        (link → GitHub) │
                                       │                                           │
"About TrafficWand…" calls             │           [ ♥ Sponsor on GitHub ]         │
  settingsWindowController             └───────────────────────────────────────────┘
  .show(initialTab: .about)
```

Key design decisions:

- **About as a Settings tab** (per user direction). Avoids a second window controller and keeps all "non-routing app surfaces" in one place. The menu item is the discovery path users expect ("About <App>" must be findable from the menu).
- **`SettingsTab` enum** as the deep-link key. Pure, exhaustive, testable; `SettingsRootView` uses it as the `TabView` selection. `SettingsWindowController.show(initialTab:)` writes into the same enum.
- **`BuildInfo` is pure and minimal** — three stored properties (`version`, `build`, `commit`) and an `init(infoDictionary:)`. No formatting helpers; the view inlines the format string.
- **Commit hash via Taskfile-generated xcconfig** — code-signing-safe; uses Xcode's standard plist variable substitution. See "Commit hash injection" below.
- **URL constants and the sponsor button** live as `private` constants inside `AboutSettingsView`. No separate `AboutLinks` module — three URLs and a copyright string don't justify one.
- **LICENSE** is added as a top-level MIT file (copyright Ildar Karymov, year 2026), closing the gap that the About tab would otherwise expose.
- **About-tab links go through `NSWorkspace.shared.open`** like any other URL. On a dev machine where TrafficWand is the system default browser, this hands the URL back to TrafficWand → if no rule matches `github.com`, the user's configured fallback fires (the picker, by default). This is honest behavior — TrafficWand should not bypass its own routing for its own links — and it's documented in the verification checklist so testers aren't surprised.

## Technical Details

### `BuildInfo` (App/Sources/BuildInfo.swift)

```swift
struct BuildInfo: Equatable {
    let version: String         // "0.1.0"
    let build: String           // "1"
    let commit: String?         // "abc1234" or nil if missing/"unknown"/empty

    init(infoDictionary: [String: Any])
    static var current: BuildInfo { .init(infoDictionary: Bundle.main.infoDictionary ?? [:]) }
}
```

- `commit` is `nil` when the key is absent, empty, or equal to the sentinel `"unknown"`.
- The view formats `"Version \(info.version) (build \(info.build))"` and `"commit \(commit)"` inline — no convenience properties on `BuildInfo`.

### `SettingsTab` (App/Sources/UI/Settings/SettingsTab.swift)

```swift
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, rules, about
    var id: String { rawValue }
}
```

- `SettingsRootView` uses `@State private var selection: SettingsTab` initialized from an `initialTab` parameter, defaulting to `.general`.

### `SettingsWindowController.show(initialTab:)`

```swift
func show(initialTab: SettingsTab? = nil)
private(set) var lastRequestedTab: SettingsTab?   // test seam
```

- When called with a non-nil `initialTab`, the controller reassigns the hosting controller's `rootView` to a fresh `SettingsRootView(initialTab:)` *and* records the value in `lastRequestedTab`.
- When called with `nil`, the existing window's content is left as-is (so re-opening from `Settings…` doesn't pin to whatever the last deep-link was).
- `lastRequestedTab` is `private(set)` so tests can assert on it without poking into the hosting controller's SwiftUI `@State` (which isn't externally observable).

### `StatusBarController` change

- Add `onOpenAbout: () -> Void = {}` init parameter (mirrors `onOpenSettings`).
- Insert a new `NSMenuItem("About TrafficWand…")` above the `Settings…` item, with action `#selector(openAbout)` calling `onOpenAbout()`. No keyboard shortcut (matches system About convention).
- Add a test seam: `internal var menu: NSMenu { statusItem.menu! }` so tests can pull the menu, locate items by title, and invoke their actions via `controller.perform(item.action!, with: item)`. This is the same shape the `Settings…` item will use in its test.

### Commit hash injection (codesign-safe)

End-to-end flow:

1. **Taskfile step `build-info`** writes `BuildInfo.xcconfig` to the repo root (gitignored):

   ```text
   // BuildInfo.xcconfig — generated, do not edit
   GIT_COMMIT = abc1234
   ```

   Resolution: `git rev-parse --short HEAD` if inside a git work tree; literal `unknown` otherwise.

2. **`Taskfile.yml`** — `build`, `run`, `test`, and the default task all depend on `build-info` so the xcconfig is regenerated before any `xcodebuild` invocation.

3. **`project.yml`** — the `TrafficWand` target adds `xcconfig: BuildInfo.xcconfig`. (Tests do *not* need the xcconfig; they don't read `GitCommitHash`.)

4. **`App/Resources/Info.plist`** — gains a `GitCommitHash` string whose literal value is `$(GIT_COMMIT)`. Xcode's "Process Info.plist file" phase substitutes the value from the build setting *before* `_CodeSign` runs, so the embedded plist is final at signing time.

5. **`BuildInfo.current`** reads `Bundle.main.infoDictionary["GitCommitHash"]` at runtime. The sentinel handling (`unknown` → `nil`) is the same path covered by `BuildInfoTests` against synthetic dictionaries.

6. **`.gitignore`** — add `BuildInfo.xcconfig`.

### Sponsor URL / copyright (inlined in `AboutSettingsView`)

```swift
private enum Links {
    static let sponsor    = URL(string: "https://github.com/sponsors/tomakado")!
    static let repository = URL(string: "https://github.com/tomakado/trafficwand")!
    static let license    = URL(string: "https://github.com/tomakado/trafficwand/blob/main/LICENSE")!
    static let copyright  = "© 2026 Ildar Karymov"
}
```

GitHub Sponsors is enabled for `tomakado`, so the URL ships as-is.

## What Goes Where

- **Implementation Steps** (`[ ]` checkboxes): code, tests, project.yml / Taskfile.yml / .gitignore edits, the LICENSE file, plan-completion housekeeping.
- **Post-Completion** (no checkboxes): manual UI verification, optional README screenshot.

## Implementation Steps

### Task 1: Add MIT LICENSE file + .gitignore entry

**Files:**
- Create: `LICENSE`
- Modify: `.gitignore`

- [ ] create `LICENSE` with the standard MIT text, copyright "2026 Ildar Karymov"
- [ ] add `BuildInfo.xcconfig` to `.gitignore` (file doesn't exist yet but will be generated in Task 3)
- [ ] no automated tests (static files); manual sanity: `head -1 LICENSE` shows `MIT License`

### Task 2: Add `BuildInfo` pure helper

**Files:**
- Create: `App/Sources/BuildInfo.swift`
- Create: `App/Tests/AppTests/BuildInfoTests.swift`

- [ ] write failing tests in `BuildInfoTests` covering: full dict (version + build + commit), missing commit key (→ `nil`), empty-string commit (→ `nil`), `"unknown"` sentinel commit (→ `nil`), missing version (→ empty string default), missing build (→ empty string default)
- [ ] implement `BuildInfo` struct + `init(infoDictionary:)` + `current` static; **no** `versionLine` / `commitLine` helpers (view formats inline)
- [ ] run `task test` — tests pass before Task 3

### Task 3: Inject `GitCommitHash` via Taskfile-generated xcconfig

**Files:**
- Modify: `Taskfile.yml`
- Modify: `project.yml`
- Modify: `App/Resources/Info.plist`

- [ ] add `build-info` task to `Taskfile.yml` that writes `BuildInfo.xcconfig` containing `GIT_COMMIT = <short hash or "unknown">`; resolve hash via `git rev-parse --short HEAD`, defaulting to `unknown` when not in a work tree or git isn't on PATH
- [ ] add `build-info` as a dependency of `build`, `run`, `test`, and the default task in `Taskfile.yml`
- [ ] add `xcconfig: BuildInfo.xcconfig` to the `TrafficWand` target in `project.yml`
- [ ] add `<key>GitCommitHash</key><string>$(GIT_COMMIT)</string>` to `App/Resources/Info.plist`
- [ ] run `task generate` to regenerate the Xcode project from the updated `project.yml`
- [ ] run `task build` — verify the built `.app`'s `Info.plist` actually contains the substituted hash: `defaults read "$(find ~/Library/Developer/Xcode/DerivedData -name TrafficWand.app -path '*Debug*' -type d | head -1)/Contents/Info" GitCommitHash` shows the current short hash
- [ ] no automated test for this step — `BuildInfo`'s parsing contract is already covered by Task 2; the runtime smoke test isn't viable (test bundle's `Bundle.main` is the xctest runner, not the app), so this is covered by manual verification in Task 8

### Task 4: Add `SettingsTab` enum

**Files:**
- Create: `App/Sources/UI/Settings/SettingsTab.swift`
- Create: `App/Tests/AppTests/SettingsTabTests.swift`

- [ ] write failing test asserting `id == rawValue` for each case (sanity check of the `Identifiable` conformance; the enum is trivial otherwise)
- [ ] implement `enum SettingsTab: String, CaseIterable, Identifiable { case general, rules, about; var id: String { rawValue } }`
- [ ] run `task test` — tests pass before Task 5

### Task 5: Build `AboutSettingsView`

**Files:**
- Create: `App/Sources/UI/Settings/AboutSettingsView.swift`

- [ ] create `AboutSettingsView` SwiftUI view rendering: app icon (`NSImage(named: NSImage.applicationIconName)` → `Image(nsImage:)`, ~96pt), app name (from `CFBundleName`), `"Version \(info.version) (build \(info.build))"`, commit line (selectable monospaced text, omitted when `info.commit == nil`), copyright string, license link (opens `Links.license` via `NSWorkspace.shared.open`), Sponsor button (opens `Links.sponsor`)
- [ ] declare URL constants and copyright string as a `private enum Links` inside the view file (no separate module)
- [ ] inject `BuildInfo` (defaulting to `.current`) and a `(URL) -> Void` open-closure (defaulting to `{ NSWorkspace.shared.open($0) }`) so the view is preview/test-friendly
- [ ] add a one-line top-of-file comment noting that visual rendering is covered by manual verification (Task 8), since the repo has no snapshot framework
- [ ] no automated test (pure inputs `BuildInfo` already tested in Task 2; URL constants are trivially their own test)

### Task 6: Wire About tab into `SettingsRootView` and `SettingsWindowController.show(initialTab:)`

**Files:**
- Modify: `App/Sources/UI/Settings/SettingsRootView.swift`
- Modify: `App/Sources/UI/Settings/SettingsWindowController.swift`
- Create: `App/Tests/AppTests/SettingsWindowControllerAboutTests.swift`

- [ ] change `SettingsRootView` to take an optional `initialTab: SettingsTab` (default `.general`) and an `@State private var selection: SettingsTab` initialized from it; bind `selection` to the `TabView`; add the `AboutSettingsView` as the third tab with system image `info.circle` and tag `.about`
- [ ] add `private(set) var lastRequestedTab: SettingsTab?` to `SettingsWindowController`
- [ ] add `func show(initialTab: SettingsTab? = nil)` to `SettingsWindowController`; when non-nil, store in `lastRequestedTab` and reassign the hosting controller's `rootView` to `SettingsRootView(initialTab:)` before activating + ordering front; when nil, leave the rootView untouched (preserves today's behavior)
- [ ] write `SettingsWindowControllerAboutTests` asserting: `show(initialTab: .about)` sets `lastRequestedTab` to `.about`; `show(initialTab: .rules)` then `show()` leaves `lastRequestedTab` at `.rules` (the no-arg call must not clear it)
- [ ] run `task test` — tests pass before Task 7

### Task 7: Add "About TrafficWand…" status-bar menu item

**Files:**
- Modify: `App/Sources/UI/StatusBarController.swift`
- Modify: `App/Sources/AppMain.swift`
- Create: `App/Tests/AppTests/StatusBarControllerAboutTests.swift`

- [ ] add `onOpenAbout: () -> Void = {}` init parameter to `StatusBarController`; insert an `NSMenuItem(title: "About TrafficWand…", action: #selector(openAbout), keyEquivalent: "")` above the existing `Settings…` item, with a separator preserving the existing visual grouping; add `@objc private func openAbout()` that calls `onOpenAbout()`
- [ ] add `internal var menu: NSMenu { statusItem.menu! }` as the test seam (replaces no current exposure)
- [ ] wire `onOpenAbout: { [weak self] in self?.openAbout() }` in `AppMain.applicationDidFinishLaunching`; add a private `openAbout()` that calls `settingsWindowController?.show(initialTab: .about)`
- [ ] write `StatusBarControllerAboutTests` covering: finding the "About TrafficWand…" item by title in `controller.menu`, calling `controller.perform(item.action!, with: item)`, and asserting the injected `onOpenAbout` ran and `onOpenSettings` did not; mirror with a Settings-item case (action invokes `onOpenSettings`, not `onOpenAbout`)
- [ ] run `task test` — tests pass before Task 8

### Task 8: Verify acceptance criteria

- [ ] verify all items from issue #4 are present in the About tab: app name, app icon, version + build, commit hash, copyright, license notice, sponsor button
- [ ] verify status-bar menu item opens Settings deep-linked to About
- [ ] verify the License link opens the GitHub LICENSE URL (note: on a dev box where TrafficWand is the default browser and no rule matches `github.com`, the configured fallback fires — picker / specific browser / last-used. This is expected behavior, not a bug.)
- [ ] verify the Sponsor button opens `https://github.com/sponsors/tomakado`
- [ ] verify Settings → manually switch to General / Rules tabs still works (no regression in tab selection)
- [ ] verify `Settings…` from the menu (not "About TrafficWand…") still opens to whatever tab was last shown / `.general` on first open — does NOT pin to `.about`
- [ ] confirm built `.app`'s Info.plist has a real commit hash via the `defaults read` command from Task 3
- [ ] run `task lint` — clean
- [ ] run `task test-core` — green
- [ ] run `task test` — green
- [ ] run `task` (default: generate + build + lint + test-core + test) — green

### Task 9: [Final] Update documentation and archive plan

**Files:**
- Modify: `CLAUDE.md`
- Move: this plan file to `docs/plans/completed/`

- [ ] add a short paragraph to `CLAUDE.md` describing the build-info pattern (Taskfile generates `BuildInfo.xcconfig` → `$(GIT_COMMIT)` substituted into `Info.plist` before signing). This is easy to get wrong (PlistBuddy post-build mutation is the common-but-broken alternative) and worth documenting once.
- [ ] decide whether `README.md` needs a mention; skip if it doesn't read as user-facing-feature-worthy.
- [ ] `mkdir -p docs/plans/completed` and move this plan file there.

## Post-Completion

*Items requiring manual intervention or external systems — no checkboxes, informational only.*

**Manual verification** (after Task 8):
- Launch the app with `task run`. Open the menu-bar menu, click **About TrafficWand…** — Settings window opens with the About tab pre-selected.
- The icon renders (not a generic placeholder), version reads `Version 0.1.0 (build 1)`, the commit line shows a real 7-char hash matching `git rev-parse --short HEAD`. Select-and-copy the commit hash — the text should be selectable.
- Click the license line — opens `https://github.com/tomakado/trafficwand/blob/main/LICENSE`. On a dev box where TrafficWand is the default browser, this loops through `RoutingService` and surfaces the configured fallback (picker by default) for `github.com`. Pick a browser to confirm; if you want a frictionless path, add a temporary `*.github.com → <any browser>` rule before testing.
- Click **Sponsor on GitHub** — opens `https://github.com/sponsors/tomakado` via the same routing path.
- Switch to General and Rules tabs — they still work, no UI regressions.
- Open `Settings…` from the menu (not About) — opens to the previously-shown tab or `.general` on first open, **not** `.about`.

**Optional**:
- Take a screenshot of the About tab for the README / release notes.
