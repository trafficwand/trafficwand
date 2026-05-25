# CLAUDE.md — TrafficWand

Guidance for working in this repository.

## IMPORTANT: this is a Swift/macOS project, not Go

The Go/gommon "golden rules" in the global `~/.claude/CLAUDE.md` (use `task` for Go,
prefer gommon packages, pass `context.Context` as the first parameter, wrap errors with
`%w`) **DO NOT apply here.** This is a native macOS app written in Swift.

The one rule that *does* carry over: **the `task` runner is used** — but here it drives
Swift, XcodeGen, and `xcodebuild`, not Go. Always go through `task`, never call
`swift`/`xcodebuild`/`xcodegen` directly for routine workflows.

English only for code, comments, docs, and commits.

## Architecture: the Core/App split

TrafficWand is two layers, and keeping them separate is the whole point of the design.

- **`TrafficWandCore`** — a local SPM package of **pure Swift (Foundation only, NO
  AppKit)**. All decision-shaped logic lives here: models (`Rule`, `BrowserTarget`,
  `FallbackPolicy`, `AppConfig`, `Browser`, `BrowserProfile`, `RoutingDecision`), glob
  matching (`GlobPattern`, `RuleMatcher`), routing (`Router.decide`), config persistence
  (`FileConfigStore`), profile parsing (`ChromeProfileReader`, `FirefoxProfileReader`),
  and launch-arg construction (`BrowserFamily`, `LaunchArguments`). It is unit-tested
  exhaustively via `swift test`.
  - **Enforced purity:** `task test-core` includes a grep guard that fails the build if
    any Core source imports AppKit. Do not import AppKit (or any UI framework) in Core.

- **`App/`** — a **thin AppKit/SwiftUI adapter layer**. It owns the menu-bar agent
  (`StatusBarController`), URL intake (`AppMain.application(_:open:)` →
  `RoutingService`), Settings (SwiftUI hosted via `NSHostingController`), the picker
  (`NSPanel` + `NSHostingView`), and the concrete adapters that touch `NSWorkspace` /
  `Process` / the filesystem. Tested via `xcodebuild test` (the `TrafficWandTests`
  target).

The rule of thumb: **anything decision-shaped goes in Core and gets a unit test;
anything that touches the system is a thin adapter in App, kept behind a protocol so the
decision logic stays testable.**

## Protocol seams

These protocols keep `NSWorkspace`/`Process`/filesystem out of the tested logic:

- **Core:** `ConfigStore`, `ProfileReading`, `BrowserLaunching` — pure protocols Core
  defines so it never reaches for the system itself.
- **App-side:** `PickerPresenting`, `InstalledBrowsersProviding`, `LastUsedRecording` —
  narrow seams the App defines over its concrete adapters (`PickerPanelController`,
  `WorkspaceBrowserProvider`, `LastUsedStore`) so `RoutingService` and the view models
  can be tested with mocks.

When adding behavior that touches the system, define/extend a seam rather than calling
`NSWorkspace`/`Process` directly from logic that should be testable.

## Commands

| Command          | What it does                                                      |
| ---------------- | ---------------------------------------------------------------- |
| `task generate`  | Generate the Xcode project from `project.yml` (XcodeGen).        |
| `task build`     | Build the app target.                                            |
| `task run`       | Build and launch the app.                                        |
| `task test`      | Run the app test target (`xcodebuild test`, includes Core).     |
| `task test-core` | Run Core tests (`swift test`) + the no-AppKit import guard.     |
| `task lint`      | Run SwiftLint.                                                   |
| `task`           | Default: generate + build + lint + test-core + test.            |

For a fast TDD loop on Core, prefer `task test-core` (plain `swift test`, no Xcode build).

## Build system

- **Local SPM package** `TrafficWandCore/` provides the pure core; both the app target
  and its test target depend on it (wired in `project.yml` under `packages:`).
- **XcodeGen** generates `TrafficWand.xcodeproj` from `project.yml`. The `.xcodeproj` is
  **generated, not committed** — run `task generate` after cloning or after changing
  `project.yml`. Do not hand-edit the generated project; edit `project.yml` instead.

## Working conventions

- TDD: for Core changes, write the failing test first, then implement; all tests must
  pass before moving on.
- Every code change includes new/updated tests (success and edge/error cases).
- Keep Core free of system dependencies; inject time/filesystem/workspace via protocols.
- Keep `task lint` clean.
