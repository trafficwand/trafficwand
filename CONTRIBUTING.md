# Contributing to TrafficWand

Thanks for your interest in TrafficWand. This document covers everything a contributor or
maintainer needs: how to report issues, build the app, run the tests, and produce a signed
release.

> Looking to **use** TrafficWand? See the [README](README.md) — it covers downloading,
> installing, and setting it as your default browser.

## Reporting bugs & requesting features

Bugs and feature requests go through GitHub issues:
**<https://github.com/trafficwand/trafficwand/issues>**.

When filing a bug, include your macOS version, the browser(s)/profiles involved, and the
steps to reproduce. For routing problems, the rule pattern and the link that misbehaved
are especially helpful.

## Working conventions

- **English only** for code, comments, docs, and commit messages.
- **TDD for Core.** Any change to `TrafficWandCore` starts with a failing test, then the
  implementation; all tests must pass before moving on. Every code change ships with
  new/updated tests covering both the success and the edge/error cases.
- **Keep Core pure.** `TrafficWandCore` depends on Foundation only — never import AppKit
  (or any UI framework) there. Inject time, the filesystem, and the workspace via
  protocols. `task test-core` enforces this with a build-time guard that fails if any Core
  source imports AppKit.
- **Keep `task lint` clean.**
- **Go through `task`.** Drive XcodeGen and `xcodebuild` through the `Taskfile`, never by
  calling `swift`/`xcodebuild`/`xcodegen` directly for routine workflows.

See [`CLAUDE.md`](CLAUDE.md) for the deeper architectural guidance these conventions come
from.

## Requirements

- macOS 26 (Tahoe) or later for the app.
- **Xcode 26+** (provides the Swift 6 toolchain and `xcodebuild`).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) and
  [SwiftLint](https://github.com/realm/SwiftLint), installed via Homebrew:

  ```sh
  brew install xcodegen swiftlint
  ```

- [Task](https://taskfile.dev) (`task`) as the command runner.

For building a **release DMG** (`task dmg`) you additionally need:

- Enrollment in the [Apple Developer Program](https://developer.apple.com/programs/) (for
  a Developer ID Application certificate + notarization access).
- [`create-dmg`](https://github.com/create-dmg/create-dmg), installed via Homebrew:

  ```sh
  brew install create-dmg
  ```

See [Distribution](#distribution) below for the full release setup.

The `.xcodeproj` is **generated** by XcodeGen from `project.yml` and is not committed —
run `task generate` after a fresh clone.

## Build & run

All workflows go through the `Taskfile`:

| Command            | What it does                                                                                                                                   |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `task generate`    | Generate `TrafficWand.xcodeproj` from `project.yml` (XcodeGen).                                                                                |
| `task build`       | Build the app target (`xcodebuild build`). Accepts an optional `CONFIG` var (default `Debug`; e.g. `CONFIG=Release task build`).               |
| `task build-info`  | Write `BuildInfo.xcconfig` with the current short git commit hash (auto-run by `build`/`run`/`test`/default).                                  |
| `task run`         | Build and launch the app.                                                                                                                      |
| `task test`        | Run the app test target (`xcodebuild test`); includes Core via SPM.                                                                            |
| `task test-core`   | Run the pure Core package tests (`swift test`) + the no-AppKit guard.                                                                          |
| `task lint`        | Run SwiftLint across the repo.                                                                                                                 |
| `task dmg`         | Build, sign, notarize, and package the app as a DMG (release — see [Distribution](#distribution) for setup).                                   |
| `task install`     | Release build installed to `/Applications`. Quits any running instance; does not relaunch. (unsigned — Gatekeeper may prompt on first launch)  |
| `task install-dev` | Debug build installed to `/Applications`. Quits any running instance; does not relaunch.                                                       |
| `task`             | Default: generate + build + lint + all tests.                                                                                                  |

Typical first run:

```sh
brew install xcodegen swiftlint
task generate
task build
task run
```

For a fast TDD loop on Core, prefer `task test-core` (plain `swift test`, no Xcode build).

## Architecture

TrafficWand is split into two layers, and keeping them separate is the whole point of the
design:

- **`TrafficWandCore`** — a pure Swift SPM package (Foundation only, **zero AppKit**).
  All the decision logic lives here: glob matching, rule matching, routing decisions,
  config persistence, profile parsing, and launch-argument construction. It is
  exhaustively unit-tested via `swift test`, and a build-time guard
  (`task test-core`) fails if any Core source imports AppKit.
- **App target** — a thin AppKit/SwiftUI shell that adapts the system (`NSWorkspace`,
  `Process`, the filesystem, the menu bar, Settings, and the picker panel) to the Core
  protocols. Assembled by XcodeGen from `project.yml`.

This split keeps the trustworthy, testable logic free of UI and system dependencies; the
app is just glue. The rule of thumb: **anything decision-shaped goes in Core and gets a
unit test; anything that touches the system is a thin adapter in App, kept behind a
protocol so the decision logic stays testable.**

See [`CLAUDE.md`](CLAUDE.md) for the protocol seams (`ConfigStore`, `ProfileReading`,
`BrowserLaunching`, `PickerPresenting`, and friends), the `RoutingDestination`/alias
resolution model, and the rest of the contributor notes.

## Distribution

TrafficWand is distributed as a **non-sandboxed Developer ID** app (so it can read
browser profile configs and launch profiles without sandbox exceptions): signed with a
Developer ID Application certificate, **Hardened Runtime** enabled, **notarized** and
stapled by Apple, packaged as a **DMG**.

Building a release DMG requires enrollment in the Apple Developer Program. One-time
setup:

```sh
brew install create-dmg
```

Then provide the four notary credentials. The easiest way is a gitignored
`.dmg.env` file at the repo root — copy the template and fill it in once:

```sh
cp .dmg.env.example .dmg.env
$EDITOR .dmg.env
```

`.dmg.env.example` documents where each value comes from (Team ID, the Developer ID
Application certificate, and the app-specific password). `scripts/build-dmg.sh` sources
`.dmg.env` automatically. Alternatively, export the four vars
(`DEVELOPER_ID_APPLICATION`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD`)
in your shell — in CI they come from environment secrets, so no file is needed there.

Validate the setup without running the full pipeline:

```sh
scripts/build-dmg.sh --preflight
```

Then produce a release:

```sh
task dmg
```

Output lands at `dist/TrafficWand-<version>.dmg`, ready to upload as a GitHub release
asset.

### Sparkle build & appcast pipeline

Installed copies self-update via [Sparkle](https://sparkle-project.org). The release
pipeline feeds the updater: after the DMG is built, signed, and notarized,
`scripts/generate-appcast.sh` EdDSA-signs the DMG (`sign_update`, key supplied via stdin
from `SPARKLE_ED_PRIVATE_KEY`) and renders `appcast.xml` with one `<item>` whose enclosure
points at the versioned `releases/download/v<version>/TrafficWand-<version>.dmg`. CI
uploads `appcast.xml` alongside the DMG as a release asset; the app's feed URL is the
stable `releases/latest/download/appcast.xml` redirect, which always resolves to the
newest release.

`CFBundleVersion` resolves to `$(CURRENT_PROJECT_VERSION)`, which `task build-info`
derives from `git rev-list --count HEAD`, so every commit yields a strictly-higher,
monotonic build number and Sparkle's version comparison stays reliable.
`CFBundleShortVersionString` resolves to `$(MARKETING_VERSION)`, which **must be bumped per
release**.

See [`docs/spikes/sparkle-updates.md`](docs/spikes/sparkle-updates.md) for the full update
flow, EdDSA key handling/rotation, the appcast format, and the nested-XPC/Autoupdate
notarization verification recipe.

### Automated releases

Pushing a `v*.*.*` tag does all of this automatically. The
[`release.yml`](.github/workflows/release.yml) workflow runs the same `task dmg`
pipeline in CI and creates (or updates) the matching GitHub Release with auto-generated
notes and the signed, notarized DMG attached. Bump `MARKETING_VERSION` in `project.yml`
to match the tag before pushing — a verify step compares the tag (minus the leading `v`)
against `MARKETING_VERSION` and fails the job before the expensive build on a mismatch.
Re-running an existing tag re-uploads the asset instead of erroring.

This requires **seven** repository secrets (Settings → Secrets and variables → Actions):
the four notary credentials above —

- `DEVELOPER_ID_APPLICATION`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

— plus, so CI can import the signing identity into a throwaway keychain:

- `MACOS_CERTIFICATE_P12_BASE64` (base64 of the exported `.p12` containing the certificate
  **and** its private key)
- `MACOS_CERTIFICATE_PASSWORD` (the `.p12` password)

— plus the updater signing key:

- `SPARKLE_ED_PRIVATE_KEY` (the EdDSA private key used to sign the update appcast).

CI signs the DMG, renders `appcast.xml`, and uploads it as a release asset.

## Where things live

- **`TrafficWandCore/`** — the pure-Swift decision logic (models, glob/rule matching,
  routing, config persistence, profile parsing, launch-arg construction). Foundation only,
  no AppKit. Unit-tested with `swift test`.
- **`App/`** — the AppKit/SwiftUI adapter layer (menu-bar agent, URL intake, Settings, the
  picker, and the concrete `NSWorkspace`/`Process`/filesystem adapters). Tested with
  `xcodebuild test`.
- **`docs/spikes/`** — deep-dive investigation notes:
  [`launch-mechanism.md`](docs/spikes/launch-mechanism.md) (how browsers are launched with
  profile flags) and [`sparkle-updates.md`](docs/spikes/sparkle-updates.md) (the full
  update flow and key handling).
- **[`CLAUDE.md`](CLAUDE.md)** — the canonical contributor guide: the Core/App split in
  full, the protocol seams, the persisted-config schema and migration path, and the build
  conventions.

## License

TrafficWand is released under the MIT License. See [`LICENSE`](LICENSE) for the full text.
