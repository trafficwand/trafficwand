# Integrate Sparkle for In-App Updates (issue #7)

## Context

Issue #7 ("App updates") asks for three things: **manual update checks**, **automatic
update checks**, and **the update flow itself**. TrafficWand is distributed outside the
App Store as a Developer-ID-signed, notarized DMG (uploaded to GitHub Releases on each
`v*.*.*` tag), so there is no App Store update path — users would otherwise have to
manually re-download. [Sparkle](https://sparkle-project.org) is the standard framework
for self-updating non-App-Store macOS apps and is the chosen solution.

The app is **non-sandboxed** with Hardened Runtime, which is the simplest case for
Sparkle (no XPC installer-launcher service, no sandbox temporary exceptions, no extra
entitlements). The work splits into two halves:

1. **In-app** (App layer only): add the Sparkle SPM dependency, a "Check for Updates…"
   menu item, and an automatic-check toggle in General settings — all behind a testable
   protocol seam to honor the project's Core/App + seam conventions.
2. **Release infrastructure**: Sparkle requires its own **EdDSA signature** on each
   update plus a hosted **appcast.xml** feed. We host the appcast **as a GitHub Release
   asset**, served via the stable `releases/latest/download/appcast.xml` URL (no GitHub
   Pages, no `gh-pages` branch), point enclosures at the version-specific Release DMG
   assets, and automate EdDSA signing + appcast upload in `release.yml`.

**Decisions locked in with the user:** appcast hosted as a Release asset via the
`/latest/download/` redirect; full CI automation now; Sparkle's first-launch permission
prompt for the auto-update UX; update preferences live in the **General** settings tab.

**Incorporates plan-review findings (2026-05-30):** the bundle-version injection fix
(Task 2) is the critical prerequisite — without it Sparkle's version comparison reads a
frozen `1`; the monotonic build number derived from commit count avoids any
git-history comparison in `verify-release-version.sh`; nested Sparkle XPC/Autoupdate
notarization is explicitly verified; bootstrap above the existing `v0.1.0`/build `1` is
called out.

## Solution Overview

- **Dependency:** add Sparkle 2.x as a remote SPM package in `project.yml`; `task generate`.
- **Authoritative, monotonic version:** convert `Info.plist` to
  `CFBundleShortVersionString = $(MARKETING_VERSION)` and
  `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`, and have `task build-info` derive
  `CURRENT_PROJECT_VERSION` from `git rev-list --count HEAD` into `BuildInfo.xcconfig`
  (same signed-and-authoritative injection path already used for `GIT_COMMIT`). Result:
  every commit yields a strictly-higher build number with no manual bump, and Sparkle's
  `sparkle:version` reflects the real shipped build.
- **Seam:** define `UpdaterControlling` (App seam) so menu + settings logic is testable
  with a `MockUpdater`; the concrete `SparkleUpdater` wraps `SPUStandardUpdaterController`.
  Mirrors the existing `PickerPresenting`/`InstalledBrowsersProviding` pattern.
- **Manual check:** "Check for Updates…" menu item in `StatusBarController`, wired through
  an `onCheckForUpdates` closure (same pattern as `onOpenAbout`).
- **Automatic check:** a `Toggle` in `GeneralSettingsView` bound through `SettingsViewModel`
  to the seam's `automaticallyChecksForUpdates`. No `SUEnableAutomaticChecks` key in
  Info.plist → Sparkle shows its standard first-launch permission prompt.
- **Update flow:** handled entirely by Sparkle's standard user driver (download, release
  notes, install, relaunch). No custom UI.
- **Feed:** `SUFeedURL = https://github.com/tomakado/trafficwand/releases/latest/download/appcast.xml`,
  `SUPublicEDKey` in Info.plist. Each release: CI `sign_update`s the DMG (private key via
  stdin from a repo secret), renders `appcast.xml` with the version-specific Release DMG
  download URL as the enclosure, and uploads `appcast.xml` alongside the DMG as a release
  asset.

## Technical Details

- **Two URLs, split by stability need:** the **feed URL** is the stable
  `releases/latest/download/appcast.xml` redirect (baked into every shipped app, always
  serves the newest release's appcast); each appcast item's **enclosure URL** is the
  permanent version-specific `releases/download/v<version>/TrafficWand-<version>.dmg`. The
  appcast only needs to contain the latest item for update detection.
- **Hosting approach verified.** Sparkle's runtime feed fetch follows GitHub's 302
  redirect (`/latest/download/`) and finds updates correctly (Sparkle issues
  [#1450](https://github.com/sparkle-project/Sparkle/issues/1450) /
  [#1461](https://github.com/sparkle-project/Sparkle/issues/1461)). The *only* known
  redirect pitfall is in the `generate_appcast` **tool** — avoided here by **hand-rendering
  the appcast** via `sign_update` with an explicit versioned enclosure URL.
- **SPM declaration** (`project.yml` `packages:` block):
  ```yaml
  packages:
    TrafficWandCore:
      path: TrafficWandCore
    Sparkle:
      url: https://github.com/sparkle-project/Sparkle
      from: "2.6.0"   # pin to latest stable 2.x at implementation time
  ```
  Add `- package: Sparkle` to the `TrafficWand` target `dependencies`.
- **Info.plist** (`App/Resources/Info.plist`):
  - Change `CFBundleShortVersionString` `0.1.0` → `$(MARKETING_VERSION)` and
    `CFBundleVersion` `1` → `$(CURRENT_PROJECT_VERSION)` (currently hardcoded literals at
    lines 19–22 — **the critical bug to fix**).
  - Add Sparkle keys; deliberately omit `SUEnableAutomaticChecks` so the first-launch
    prompt appears:
    ```xml
    <key>SUFeedURL</key>
    <string>https://github.com/tomakado/trafficwand/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>__PUBLIC_ED_KEY__</string>   <!-- placeholder until Task 6 fills the real key -->
    ```
- **`task build-info`** (`Taskfile.yml`): in addition to `GIT_COMMIT`, write
  `CURRENT_PROJECT_VERSION = $(git rev-list --count HEAD)` (fallback `1` outside a work
  tree) into `BuildInfo.xcconfig`. `project.yml` already wires that xcconfig via
  `configFiles`, so `CFBundleVersion` resolves at "Process Info.plist" time, before
  signing — keeping the embedded plist signed and authoritative.
- **CI signing:** store the private EdDSA key as repo secret `SPARKLE_ED_PRIVATE_KEY`
  (output of `generate_keys -x`). `sign_update` reads it via **stdin** (the `-s` flag is
  deprecated since Sparkle 2.2.2). Obtain the `sign_update` binary by downloading the
  Sparkle release tarball **pinned to the same version as the SPM `from:` constraint**,
  verifying a checksum; clear quarantine if present (`xattr -dr com.apple.quarantine`).
- **Appcast item fields:** `sparkle:version` = built `.app` `CFBundleVersion`;
  `sparkle:shortVersionString` = `CFBundleShortVersionString` (MARKETING_VERSION);
  `sparkle:minimumSystemVersion` = `26.0`; `enclosure url` = versioned Release DMG;
  `sparkle:edSignature` + `length` from `sign_update`.
- **No entitlement changes** — app is non-sandboxed. Sparkle's embedded XPC services /
  Autoupdate are signed + notarized as part of the existing `xcodebuild archive` →
  `exportArchive` (developer-id, deep nested signing) → notarize pipeline — **but this is
  verified explicitly** (Task 8 / Post-Completion), since a nested helper lacking Hardened
  Runtime + secure timestamp is the canonical Sparkle notarization failure.
- **Seam shape** (`UpdaterControlling`):
  ```swift
  @MainActor protocol UpdaterControlling: AnyObject {
      var automaticallyChecksForUpdates: Bool { get set }
      var canCheckForUpdates: Bool { get }
      func checkForUpdates()
  }
  ```

## Development Approach

- **Testing approach:** Regular (code-first) for the App-layer Sparkle wiring — the
  testable surface is small seam/closure plumbing, verified against a `MockUpdater` in the
  `TrafficWandTests` target (`task test`). No new Core logic, so no Core TDD cycle. CI
  shell scripts get a cheap shell test where the logic is pure (appcast rendering),
  following the existing `scripts/verify-release-version.test.sh` precedent.
- Complete each task fully (code + tests passing) before the next.
- Keep `task lint` clean. Run `task generate` after every `project.yml` change.
- Sparkle's live download/install flow, notarization of nested helpers, and the appcast/CI
  publishing are validated manually (see Post-Completion) — they can't be unit-tested
  in-process.

## Testing Strategy

- **Unit tests** (`TrafficWandTests`, via `task test`): seam wiring only —
  `StatusBarController` invokes `onCheckForUpdates`; `SettingsViewModel`'s auto-update
  property reads/writes through the seam; `MockUpdater` records calls.
- **Shell test** (`task test` / direct run): `scripts/generate-appcast.test.sh` covers the
  pure XML/`<item>` rendering of `generate-appcast.sh` with a stub signature.
- **No e2e harness**; the end-to-end update flow + notarization are manual verification.

## Implementation Steps

### Task 1: Add Sparkle dependency and Sparkle Info.plist keys

**Files:**
- Modify: `project.yml` (add `Sparkle` package + target dependency)
- Modify: `App/Resources/Info.plist` (`SUFeedURL`, placeholder `SUPublicEDKey`)

- [x] add the `Sparkle` SPM package to `packages:` (pin a 2.x version) and
      `- package: Sparkle` to the `TrafficWand` target `dependencies`
- [x] add `SUFeedURL` and a placeholder `SUPublicEDKey` to `Info.plist` (intentionally
      non-functional until Task 6 supplies the real key)
- [x] run `task generate` and `task build` — confirm Sparkle links and the app builds
- [x] run `task test` (existing suite must stay green with the new dependency)

### Task 2: Make the bundle version authoritative and monotonic (CRITICAL prerequisite)

**Files:**
- Modify: `App/Resources/Info.plist` (`CFBundleShortVersionString`, `CFBundleVersion` → `$()`)
- Modify: `Taskfile.yml` (`build-info` also writes `CURRENT_PROJECT_VERSION`)

- [x] change `CFBundleShortVersionString` → `$(MARKETING_VERSION)` and `CFBundleVersion`
      → `$(CURRENT_PROJECT_VERSION)` in `Info.plist`
- [x] extend `task build-info` to write `CURRENT_PROJECT_VERSION = <git rev-list --count
      HEAD>` (fallback `1`) into `BuildInfo.xcconfig`, alongside `GIT_COMMIT`
      (also removed the literal `CURRENT_PROJECT_VERSION: "1"` from `project.yml` so the
      target configFile value wins)
- [x] `task generate && task build`, then confirm via
      `defaults read <built .app>/Contents/Info CFBundleVersion` that the value equals the
      commit count (not `1`) and `CFBundleShortVersionString` equals `MARKETING_VERSION`
      (verified: CFBundleVersion=52 = commit count, CFBundleShortVersionString=0.1.0)
- [x] run `task test` — must pass before next task

### Task 3: Define the `UpdaterControlling` seam + `SparkleUpdater` adapter

**Files:**
- Create: `App/Sources/Updates/UpdaterControlling.swift` (protocol seam)
- Create: `App/Sources/Updates/SparkleUpdater.swift` (wraps `SPUStandardUpdaterController`)

- [x] define `UpdaterControlling` (`checkForUpdates()`, `automaticallyChecksForUpdates`,
      `canCheckForUpdates`)
- [x] implement `SparkleUpdater`: init `SPUStandardUpdaterController(startingUpdater: true,
      updaterDelegate: nil, userDriverDelegate: nil)`, delegate seam members to
      `controller.updater`
- [x] write tests against a `MockUpdater` verifying the seam contract (calls recorded,
      property round-trips); `SparkleUpdater` itself is exercised via the manual flow
- [x] run `task test` — must pass before next task

### Task 4: Wire "Check for Updates…" menu item

**Files:**
- Modify: `App/Sources/UI/StatusBarController.swift` (add menu item + `onCheckForUpdates`)
- Modify: `App/Sources/AppMain.swift` (retain `SparkleUpdater`, pass closure)
- Modify: `StatusBarController` tests

- [x] add an `onCheckForUpdates` closure param to `StatusBarController` (mirror `onOpenAbout`)
- [x] add a "Check for Updates…" `NSMenuItem` in `configureMenu()` (near About/Settings)
- [x] in `AppMain.applicationDidFinishLaunching`, retain a `SparkleUpdater` and pass
      `onCheckForUpdates: { [weak self] in self?.updater?.checkForUpdates() }`
- [x] write tests: the menu item invokes the injected closure
- [x] run `task test` — must pass before next task

### Task 5: Add the automatic-update toggle to General settings

**Files:**
- Modify: `App/Sources/UI/Settings/SettingsViewModel.swift` (inject seam + bound property)
- Modify: `App/Sources/UI/Settings/GeneralSettingsView.swift` (add `Toggle`)
- Modify: `App/Sources/AppMain.swift` (inject the same `SparkleUpdater` into the view model)
- Modify: `SettingsViewModel` tests

- [x] inject `UpdaterControlling` into `SettingsViewModel`; expose `automaticUpdatesEnabled`
      get/set forwarding to the seam. (Deliberate choice: put the seam in the view model —
      not the view like `DefaultBrowserManager` — because `SettingsViewModelTests` already
      exists and the seam is a pure `@MainActor` protocol; note this divergence in code.)
- [x] add an "Automatically check for updates" `Toggle` to `GeneralSettingsView`
- [x] wire the shared `SparkleUpdater` instance into `SettingsViewModel` in `AppMain`
- [x] write tests with `MockUpdater`: toggling the property reads/writes the seam
- [x] run `task test` — must pass before next task

### Task 6: Generate EdDSA keys, add the secret, write the required spike doc

**Files:**
- Modify: `App/Resources/Info.plist` (real `SUPublicEDKey`)
- Create: `docs/spikes/sparkle-updates.md` (REQUIRED: key handling/rotation, the nested-XPC
  notarization verification recipe, appcast format)

- [x] operator action — `generate_keys` + real `SUPublicEDKey` done by operator at release
      setup (see Post-Completion / spike §6); placeholder `__PUBLIC_ED_KEY__` retained
- [x] external — operator adds the secret `SPARKLE_ED_PRIVATE_KEY` in GitHub repo settings
      (see Post-Completion / spike §6)
- [x] write `docs/spikes/sparkle-updates.md` documenting key handling, the
      `codesign`/`spctl` nested-helper verification steps, and the bootstrap-version note
- [x] (no unit tests — config/docs only; covered by manual release verification)

### Task 7: Automate appcast signing + upload in CI

**Files:**
- Create: `scripts/generate-appcast.sh` (sign DMG via stdin key, render `appcast.xml`)
- Create: `scripts/generate-appcast.test.sh` (pure-rendering test, stub signature)
- Modify: `.github/workflows/release.yml` (download pinned Sparkle tools, run script, upload asset)

- [x] `generate-appcast.sh`: download the pinned Sparkle tarball (checksum-verified) →
      `sign_update dist/TrafficWand-<v>.dmg` (private key via stdin) → read
      `CFBundleVersion`/`CFBundleShortVersionString` from the built `.app` → render
      `appcast.xml` with one `<item>` (versioned enclosure URL, `sparkle:edSignature`,
      `length`, `sparkle:version`, `sparkle:shortVersionString`,
      `sparkle:minimumSystemVersion` 26.0)
- [x] add a workflow step (after the DMG build) running the script with
      `SPARKLE_ED_PRIVATE_KEY`, then upload **both** the DMG and `appcast.xml` as release
      assets (`gh release create`/`upload --clobber`) — `/latest/download/appcast.xml`
      then serves this file automatically
- [x] write `generate-appcast.test.sh` exercising the XML rendering with a stub signature
      (follow `verify-release-version.test.sh` style); run it
- [x] note: `verify-release-version.sh` is unchanged — build number is CI-derived
      (commit count), so no previous-tag comparison is introduced

### Task 8: Verify acceptance criteria
- [x] manual — verify during release (see Post-Completion / docs/spikes/sparkle-updates.md
      §nested-notarization): "Check for Updates…" menu item triggers Sparkle's check UI and
      fronts correctly for the `.accessory` (LSUIElement) agent (activate if needed). Requires
      launching the app interactively; cannot be validated autonomously.
- [x] manual — verify during release: first-launch permission prompt appears (no
      `SUEnableAutomaticChecks` key); General-tab toggle reflects/controls
      `automaticallyChecksForUpdates`. Requires interactive first launch; cannot be validated
      autonomously.
- [x] manual — verify during release (see docs/spikes/sparkle-updates.md §nested-notarization):
      nested Sparkle code is notarization-conformant — in the exported `.app`, `codesign -dvvv`
      the embedded `Sparkle.framework` / `Autoupdate` / XPC services shows Hardened Runtime +
      secure timestamp; `spctl --assess` passes. Requires a real Developer-ID-signed/notarized
      release build; cannot be validated autonomously.
- [x] run full suite: `task` (generate + build + lint + test-core + test) — all green;
      confirm the no-AppKit Core guard still passes (Sparkle stays out of Core). Verified:
      lint clean, `test-core` 126 tests pass (no-AppKit grep guard passes; Sparkle absent from
      TrafficWandCore — only incidental "SwiftUI/AppKit-free" comment mentions, no imports),
      app `test` 125 tests pass (0 failures).

### Task 9: [Final] Documentation
- [x] update `CLAUDE.md` "Release packaging": the appcast/EdDSA flow (asset via
      `/latest/download/`), the commit-count build-number derivation, and bump the
      enumerated secrets list **and** the "six repo secrets" count → seven
      (`SPARKLE_ED_PRIVATE_KEY`)
- [x] update `README.md` if it documents installation/updates (added an Updates note under
      Distribution + bumped the CI secrets count six → seven with `SPARKLE_ED_PRIVATE_KEY`)
- [x] deferred — left in `docs/plans/` for the remaining exec review/finalize phases; move
      to `docs/plans/completed/` after the branch merges

## Post-Completion
*Items requiring manual intervention or external systems — no checkboxes.*

**One-time setup (operator):**
- Run `generate_keys`, add the public key to Info.plist (Task 6); add
  `SPARKLE_ED_PRIVATE_KEY` to repo secrets.
- No Pages/branch setup needed. After the first release, confirm
  `https://github.com/tomakado/trafficwand/releases/latest/download/appcast.xml` resolves
  (302 → the newest release's asset).

**Bootstrap (important):**
- A `v0.1.0` release / build `1` already exists. The **first Sparkle-enabled release must
  use `MARKETING_VERSION` strictly greater than `0.1.0`** (e.g. `0.2.0`); its CI-derived
  build number will already exceed `1`. Pre-Sparkle `0.1.0` installs have no updater and
  must be upgraded manually one last time — only `0.2.0+` installs self-update.

**End-to-end update verification (the real acceptance test):**
- Cut release *N* (≥ 0.2.0), install that DMG. Bump `MARKETING_VERSION`, tag *N+1*, let CI
  build/sign/publish.
- Launch the *N* app → "Check for Updates…" should discover *N+1*, show release notes,
  download, verify the EdDSA signature, install, and relaunch into *N+1*.
- Confirm the updated app passes Gatekeeper (`spctl --assess`) with no quarantine prompts
  after the in-place update (catches nested-helper notarization regressions).

**Notes / risks:**
- DMG feeds get **no delta updates** (deltas are for zipped `.app` bundles) — full DMG
  download each time. Acceptable for a small menu-bar app.
- If a future release sandboxes the app, Sparkle will then require the installer-launcher
  XPC service + entitlements — out of scope here.
