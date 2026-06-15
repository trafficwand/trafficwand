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
  `FallbackPolicy`, `AppConfig` — including `AppConfig.upserting` for inserting-or-updating
  a rule by pattern, `Browser`, `BrowserProfile`, `RoutingDecision`), glob matching
  (`GlobPattern`, `RuleMatcher`), registrable-domain extraction and remember-rule
  construction (`RegistrableDomain`, `RememberRule`), routing (`Router.decide`), config
  persistence (`FileConfigStore`), profile parsing (`ChromeProfileReader`,
  `FirefoxProfileReader`), and launch-arg construction (`BrowserFamily`,
  `LaunchArguments`). It is unit-tested exhaustively via `swift test`.
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
- **App-side:** `PickerPresenting`, `InstalledBrowsersProviding`, `LastUsedRecording`,
  `RulePersisting`, `BrowserIconProviding` — narrow seams the App defines over its concrete
  adapters (`PickerPanelController`, `WorkspaceBrowserProvider`, `LastUsedStore`,
  `ConfigRuleStore`, `WorkspaceBrowserIconProvider`) so `RoutingService` and the view models
  can be tested with mocks. `RulePersisting` wraps `ConfigStore` so the picker can persist a
  "remember this site" routing rule; `BrowserIconProviding` wraps `NSWorkspace` to supply a
  browser's real app icon to the picker.

When adding behavior that touches the system, define/extend a seam rather than calling
`NSWorkspace`/`Process` directly from logic that should be testable.

The `SettingsTab` enum + the `SettingsSelection` `@Observable` holder are the
deep-link coordination value between `StatusBarController` ("About TrafficWand…"
menu item) and `SettingsRootView`'s `TabView` selection. The holder is owned by
`SettingsWindowController` (not by `@State` inside the view) so deep-link
writes survive across `rootView` updates and stay externally observable in
tests.

SwiftUI `#Preview` blocks compile into the app target (never the test target), so shared
preview mocks and sample data live in `App/Sources/UI/Previews/PreviewFixtures.swift` under
`#if DEBUG`, declared `internal` (not `private`) so the DEBUG test target can
`@testable import` them.

## Commands

| Command          | What it does                                                      |
| ---------------- | ---------------------------------------------------------------- |
| `task generate`  | Generate the Xcode project from `project.yml` (XcodeGen).        |
| `task build`     | Build the app target (optional `CONFIG` var, default `Debug`; e.g. `CONFIG=Release task build`). |
| `task run`       | Build and launch the app.                                        |
| `task test`      | Run the app test target (`xcodebuild test`, includes Core).     |
| `task test-core` | Run Core tests (`swift test`) + the no-AppKit import guard.     |
| `task lint`      | Run SwiftLint.                                                   |
| `task dmg`       | Build, sign, notarize, and package the app as a DMG (release).  |
| `task install`   | Release build installed to `/Applications`; quits running instance, no relaunch. |
| `task install-dev` | Debug build installed to `/Applications`; quits running instance, no relaunch. |
| `task sparkle:install`  | Download the pinned Sparkle binary tools into `.sparkle/`. |
| `task sparkle:gen-keys` | Generate the Sparkle EdDSA signing keypair (operator, one-time). |
| `task`           | Default: generate + build + lint + test-core + test.            |

For a fast TDD loop on Core, prefer `task test-core` (plain `swift test`, no Xcode build).

## Build system

- **Local SPM package** `TrafficWandCore/` provides the pure core; both the app target
  and its test target depend on it (wired in `project.yml` under `packages:`).
- **XcodeGen** generates `TrafficWand.xcodeproj` from `project.yml`. The `.xcodeproj` is
  **generated, not committed** — run `task generate` after cloning or after changing
  `project.yml`. Do not hand-edit the generated project; edit `project.yml` instead.

## Build-info / commit-hash injection

The About tab surfaces the current short commit hash. To keep the embedded `Info.plist`
**signed and authoritative**, the hash is injected the Xcode-native way, not by
post-build PlistBuddy mutation (which would invalidate the code signature):

1. `task build-info` (a dependency of `build`, `run`, `test`, and the default task)
   writes `BuildInfo.xcconfig` at the repo root with `GIT_COMMIT = <short hash>`
   (or `unknown` outside a git work tree) **and** `CURRENT_PROJECT_VERSION =
   <git rev-list --count HEAD>` (fallback `1` outside a git work tree) — the
   monotonic build number Sparkle compares as `sparkle:version`.
2. `project.yml` wires that xcconfig into the `TrafficWand` target via
   `configFiles`, exposing both `GIT_COMMIT` and `CURRENT_PROJECT_VERSION` as
   build settings (the literal `CURRENT_PROJECT_VERSION` is intentionally absent
   from `project.yml` so the xcconfig value wins).
3. `App/Resources/Info.plist` declares `GitCommitHash = $(GIT_COMMIT)`. Xcode's
   "Process Info.plist file" phase substitutes the value **before** `_CodeSign` runs,
   so the embedded plist is final at signing time.
4. `BuildInfo.current` reads `Bundle.main.infoDictionary["GitCommitHash"]` at runtime.

`BuildInfo.xcconfig` is gitignored (regenerated per build). Do not "fix" this by
shelling out PlistBuddy after `xcodebuild` — that breaks the signature on release
builds.

## Release packaging

`task dmg` produces a Developer-ID-signed, notarized, stapled, DMG-packaged release at
`dist/TrafficWand-<version>.dmg` in a single non-interactive invocation. The pipeline
lives in `scripts/build-dmg.sh` (archive → exportArchive → notarize .app → staple →
`create-dmg` → sign .dmg → notarize .dmg → staple) and expects four environment variables:
`DEVELOPER_ID_APPLICATION` (full identity name, e.g.
`"Developer ID Application: Name (TEAMID)"`), `APPLE_ID`, `APPLE_TEAM_ID`, and
`APPLE_APP_SPECIFIC_PASSWORD`. These can be exported in the shell or, more
conveniently, placed in a gitignored `.dmg.env` at the repo root (copy
`.dmg.env.example`) — `build-dmg.sh` sources it automatically at startup, before
preflight. Run `scripts/build-dmg.sh --preflight` to validate env
vars, tool availability (`create-dmg`, `xcodebuild`, `xcrun notarytool`), and signing
identity presence without invoking the expensive archive/notarize steps — use this to
verify a fresh setup before the first real `task dmg` run.

`APPLE_APP_SPECIFIC_PASSWORD` is passed to `xcrun notarytool` as a CLI argument, which
makes it visible via `ps` on multi-user hosts. This is intentional: env-var-based auth
lets the same script work locally and in GitHub Actions Secrets without a separate
`xcrun notarytool store-credentials` bootstrap step. Safe on single-user macOS and
single-tenant GitHub Actions runners (macOS defaults to hiding command-line args from
other users). Do NOT run `task dmg` on a shared/multi-user host without first migrating
the script to `xcrun notarytool store-credentials` + `--keychain-profile`.

### Tag-triggered CI release

Pushing a `v*.*.*` tag triggers `.github/workflows/release.yml`, which creates (or
updates) the matching GitHub Release with GitHub's auto-generated notes and the
signed/notarized DMG attached. The workflow is thin glue: it imports the Developer ID
certificate into a throwaway keychain, verifies the tag, then runs `task dmg` /
`scripts/build-dmg.sh` **verbatim** — all signing and notarizing logic stays in the
already-reviewed script. Re-running an existing tag re-uploads the asset
(`gh release upload --clobber`) instead of erroring.

The git tag must match `MARKETING_VERSION` in `project.yml`: a verify step
(`scripts/verify-release-version.sh`) compares the tag (minus the leading `v`) against
`MARKETING_VERSION` and fails the job fast on mismatch, before the expensive build.
**Bump `project.yml` before tagging.**

CI needs seven repo secrets (Settings → Secrets and variables → Actions): the four Apple
vars already used locally — `DEVELOPER_ID_APPLICATION`, `APPLE_ID`, `APPLE_TEAM_ID`,
`APPLE_APP_SPECIFIC_PASSWORD` — plus `MACOS_CERTIFICATE_P12_BASE64` (base64 of the
exported `.p12` containing the cert **and** private key) and `MACOS_CERTIFICATE_PASSWORD`
(the `.p12` password) for the CI cert import, plus `SPARKLE_ED_PRIVATE_KEY` (the exported
EdDSA private key, fed to `sign_update` via stdin to sign the update DMG). `.dmg.env` is
absent in CI, so `build-dmg.sh` reads these from the environment. (The release step also
uses `GITHUB_TOKEN`, but that is auto-provided by Actions and is not one of the seven repo
secrets — don't be misled by counting `secrets.*` references in the YAML.)

### In-app updates (Sparkle)

The app self-updates via [Sparkle](https://sparkle-project.org) — a "Check for Updates…"
menu item plus automatic background checks. The release pipeline feeds Sparkle:

- **Appcast feed.** After the DMG is built/signed/notarized, `scripts/generate-appcast.sh`
  EdDSA-signs the DMG (`sign_update`, key via stdin from `SPARKLE_ED_PRIVATE_KEY`) and
  renders `appcast.xml` with one `<item>` whose enclosure points at the **versioned**
  `releases/download/v<version>/TrafficWand-<version>.dmg`. CI uploads `appcast.xml`
  alongside the DMG as a release asset. There is **no GitHub Pages / `gh-pages` branch** —
  the app's `SUFeedURL` is the stable
  `https://github.com/trafficwand/trafficwand/releases/latest/download/appcast.xml` redirect,
  which always resolves to the newest release's `appcast.xml`.
- **Authoritative, monotonic build number.** `CFBundleVersion` is no longer a literal: it
  resolves to `$(CURRENT_PROJECT_VERSION)`, which `task build-info` derives from
  `git rev-list --count HEAD` into `BuildInfo.xcconfig` (same signed-Info.plist injection
  path as `GIT_COMMIT`; the literal `CURRENT_PROJECT_VERSION` was removed from
  `project.yml`). `CFBundleShortVersionString` resolves to `$(MARKETING_VERSION)`. Every
  commit yields a strictly-higher build number with no manual bump, so Sparkle's version
  comparison is reliable. **`MARKETING_VERSION` must still be bumped per release**, and the
  **first Sparkle-enabled release must use a `MARKETING_VERSION` strictly greater than
  `v0.1.0`** (pre-Sparkle `0.1.0` installs have no updater and must be upgraded manually
  one last time).

See `docs/spikes/sparkle-updates.md` for the full update flow, EdDSA key
handling/rotation, appcast format, and the nested-XPC/Autoupdate notarization verification
recipe.

## Working conventions

- TDD: for Core changes, write the failing test first, then implement; all tests must
  pass before moving on.
- Every code change includes new/updated tests (success and edge/error cases).
- Keep Core free of system dependencies; inject time/filesystem/workspace via protocols.
- Keep `task lint` clean.
