# task dmg — signed, notarized, packaged release build

## Overview

Add a new `task dmg` Taskfile target that produces a Developer-ID-signed,
notarized, stapled, DMG-packaged release of TrafficWand in a single
non-interactive invocation. The deliverable is `dist/TrafficWand-<version>.dmg`,
ready to upload to a GitHub release. The target must run identically on a
developer's Mac (using a Developer ID cert in the login keychain) and on
`macos-26` GitHub Actions runners (using a cert imported into a temporary
keychain), so all secrets and identity references flow through environment
variables — no interactive prompts, no hardcoded user-specific values.

This closes the explicit "out of scope for v1" distribution gap noted in
`README.md` §Distribution and listed under "Post-Completion" in
`docs/plans/completed/20260525-trafficwand-browser-router.md`.

## Context (from discovery)

- **Project type:** Swift/macOS native menu-bar agent. Local SPM package
  `TrafficWandCore/` + thin AppKit/SwiftUI app shell under `App/`. Build flow
  is Taskfile → XcodeGen → `xcodebuild`. Tests run via `swift test` (Core) and
  `xcodebuild test` (app target).
- **Already release-ready in `project.yml`:** `CODE_SIGN_STYLE: Manual`,
  `ENABLE_HARDENED_RUNTIME: YES`, entitlements minimal
  (`com.apple.security.app-sandbox = false`, no `cs.allow-*`),
  `CODE_SIGN_IDENTITY: "-"` (ad-hoc) is only the *local* default and can be
  overridden at the `xcodebuild` invocation. No `project.yml` change needed.
- **Embedded framework:** `TrafficWandCore.framework` ships inside the .app
  (SPM-derived). This is why `xcodebuild -exportArchive` is the correct path:
  Xcode signs nested frameworks first, then the app, with the right timestamp
  and runtime flags. `codesign --deep` is known-flaky for SPM frameworks.
- **`Info.plist`:** `CFBundleShortVersionString=0.1.0`, `LSUIElement=true`
  (menu-bar agent), `GitCommitHash=$(GIT_COMMIT)` injected via
  `BuildInfo.xcconfig` at build time (codesign-safe — the substitution happens
  before `_CodeSign` runs).
- **No existing signing/release scripts.** `.github/workflows/ci.yml` runs
  lint + build + test only; no release workflow yet.
- **Taskfile patterns observed:** multi-line shell blocks are common
  (`build-info`, `test-core`, `run`); tasks use `deps:` for sequencing;
  variables under `vars:` use `{{.NAME}}` interpolation. New task should
  depend on `generate` (which transitively runs `build-info`, so the git
  commit hash in `Info.plist` is fresh).

## Development Approach

- **Testing approach:** Static + preflight + e2e.
  - `shellcheck` must pass on the script after every code-modifying task.
  - The script ships a `--preflight` mode that validates env vars, cert
    presence, and tool availability without running the expensive
    archive/notarize steps — provides fast feedback during setup.
  - One full end-to-end run on a real Apple Developer account is required
    before merge (Task 7).
- **No unit tests for shell glue** (no idiomatic framework, and the value of
  unit-testing a sequence of `xcodebuild`/`codesign`/`notarytool` invocations
  is near zero). Static analysis + preflight + one real run is the
  proportionate test rigor.
- Complete each task fully before moving to the next.
- Small, focused changes — script grows section-by-section.
- Update this plan file inline if scope changes during implementation.
- `task lint` (SwiftLint) is unaffected by this change but must remain clean.

## Testing Strategy

- **Static (shellcheck):** runs at end of every task that touches
  `scripts/build-dmg.sh`. Must exit 0.
- **Preflight (`--preflight` flag):** validates `DEVELOPER_ID_APPLICATION`,
  `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD` env vars;
  validates `create-dmg`, `xcodebuild`, `xcrun notarytool` on PATH; validates
  `security find-identity` lists the requested signing identity. Negative
  paths (unset env var, missing cert) must exit non-zero with a named-cause
  message.
- **End-to-end (Task 7):** one real `task dmg` run against the developer's
  Apple Developer account. Verify: DMG exists at expected path; mount + drag
  + launch on a clean Mac; `spctl --assess` reports `accepted source=Notarized
  Developer ID`.
- **No e2e UI tests** apply — this is build/release tooling, not app UI.

## Progress Tracking

- Mark completed items with `[x]` immediately when done.
- Add newly discovered tasks with ➕ prefix.
- Document issues/blockers with ⚠️ prefix.
- Update plan if implementation deviates from original scope.

## Solution Overview

```
task dmg
  └── deps: [generate]   (transitively: build-info)
  └── cmd: ./scripts/build-dmg.sh

scripts/build-dmg.sh   (set -euo pipefail)
  ├── parse args (--preflight short-circuit)
  ├── rm -rf build/        (ephemeral intermediates; dist/ is preserved)
  ├── preflight
  │     ├── env: DEVELOPER_ID_APPLICATION, APPLE_ID,
  │     │         APPLE_TEAM_ID, APPLE_APP_SPECIFIC_PASSWORD
  │     ├── tools: create-dmg, xcodebuild present;
  │     │         xcrun notarytool --version probes the subcommand
  │     └── cert: security find-identity matches $DEVELOPER_ID_APPLICATION
  ├── resolve VERSION from xcodebuild -showBuildSettings
  ├── xcodebuild archive   → build/TrafficWand.xcarchive
  ├── generate build/ExportOptions.plist (heredoc, templated from env)
  ├── xcodebuild -exportArchive   → build/export/TrafficWand.app
  │   (authoritative signing happens here, driven by ExportOptions.plist;
  │    timestamp + hardened runtime are applied automatically for
  │    method=developer-id — do NOT pass --timestamp at archive time)
  ├── codesign --verify --strict --verbose=2   (NO --deep; deprecated)
  ├── ditto -c -k --keepParent .app .zip
  ├── notarytool submit .zip --wait      ← notarize .app
  ├── stapler staple .app
  ├── stapler validate .app
  ├── spctl --assess --type execute      ← fast-fail before DMG round-trip
  ├── create-dmg → dist/TrafficWand-$VERSION.dmg
  ├── notarytool submit .dmg --wait      ← notarize .dmg
  ├── stapler staple .dmg
  └── spctl --assess --type open --context context:primary-signature
       (DMG uses --type open, .app above uses --type execute — intentional)
```

**Key design decisions:**

- **Auth model:** App-specific password via env vars. Works identically
  locally (shell profile) and in GitHub Actions (Secrets → env). If team
  scale or rotation friction later warrants it, swapping to an ASC API key
  is a localized change in one function in the script.
- **Identity reference:** Full identity name in `DEVELOPER_ID_APPLICATION`
  (e.g. `"Developer ID Application: Ildar Karymov (TEAMID)"`). Same env var
  drives both the `CODE_SIGN_IDENTITY` override at archive time and the
  preflight `security find-identity` validation.
- **`ExportOptions.plist`:** Generated at runtime via heredoc into `build/`,
  templated from env (`teamID=$APPLE_TEAM_ID`). Never committed —
  team-ID-per-developer is baked in, so no value in checking it in.
- **Double notarization (.app then .dmg):** Both artifacts carry stapled
  tickets, so Gatekeeper passes 100% offline regardless of how the user
  extracted the .app. ~4–10 min total per release.
- **Script vs inline:** Logic lives in `scripts/build-dmg.sh`; Taskfile
  target is one line. Enables `shellcheck`, direct invocation during
  debugging, and reuse from a future `.github/workflows/release.yml`.

## Technical Details

- **Archive invocation:**
  ```
  xcodebuild archive \
    -project TrafficWand.xcodeproj \
    -scheme TrafficWand \
    -configuration Release \
    -archivePath build/TrafficWand.xcarchive \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"
  ```
  The `CODE_SIGN_IDENTITY` override flips the `project.yml` ad-hoc default
  to the real Developer ID cert for the in-archive signature. Note: this is
  *not* the signature that ships — `exportArchive` re-signs from scratch
  using `ExportOptions.plist`. The override on archive is for archive-level
  integrity (Xcode validates the archive itself); the *shipping* signature
  is produced by step 5 below. Do NOT pass `--timestamp` or
  `OTHER_CODE_SIGN_FLAGS` here — `exportArchive` applies timestamp +
  hardened runtime automatically for `method=developer-id`.
- **`ExportOptions.plist` keys:**
  `method=developer-id`, `teamID=$APPLE_TEAM_ID`, `signingStyle=manual`,
  `signingCertificate="Developer ID Application"`. The friendly name is
  idiomatic; if disambiguation is ever needed (multiple Developer ID certs
  in the keychain), interpolate `$DEVELOPER_ID_APPLICATION` instead — the
  env var already carries the team-ID-bearing common name. Add a one-line
  comment in the heredoc noting this choice.
- **Notarization invocation (both .app and .dmg):**
  ```
  xcrun notarytool submit <path> \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
  ```
  On non-zero exit, fetch and print the submission log
  (`xcrun notarytool log <submission-id>`) before exiting.
- **create-dmg layout (v1, no background image):**
  ```
  create-dmg \
    --volname "TrafficWand $VERSION" \
    --window-pos 200 120 --window-size 720 340 \
    --icon-size 100 \
    --icon "TrafficWand.app" 200 170 \
    --app-drop-link 480 170 \
    --no-internet-enable \
    "dist/TrafficWand-$VERSION.dmg" \
    "build/export/"
  ```
- **Version resolution:**
  ```
  VERSION=$(xcodebuild -project TrafficWand.xcodeproj -scheme TrafficWand \
    -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ MARKETING_VERSION /{print $2; exit}')
  ```
  Single source of truth = `project.yml` → `MARKETING_VERSION`.

## What Goes Where

- **Implementation Steps** (checkboxes): script, Taskfile target, .gitignore,
  README update, full e2e verify, plan archive.
- **Post-Completion** (no checkboxes): GitHub Actions release workflow,
  optional DMG background image, App Store Connect API key migration.

## Implementation Steps

### Task 1: Add `.gitignore` entries and bootstrap `scripts/build-dmg.sh` with preflight

**Files:**
- Modify: `.gitignore`
- Create: `scripts/build-dmg.sh`

- [x] append `build/` and `dist/` to `.gitignore` under a new `# Release packaging artifacts (task dmg)` comment header — distinct from the existing `# Build artifacts` (SPM `.build/`) section
- [x] create `scripts/build-dmg.sh` with `#!/usr/bin/env bash`, `set -euo pipefail`, and shebang executable bit (`chmod +x`)
- [x] add usage/help text printed on `-h`/`--help`
- [x] implement `preflight()` function: check required env vars (`DEVELOPER_ID_APPLICATION`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD`); check `create-dmg` and `xcodebuild` on PATH via `command -v`; probe notarytool via `xcrun notarytool --version >/dev/null 2>&1` (this validates both that `xcrun` resolves the subcommand and that the active Xcode is recent enough); check `security find-identity -v -p codesigning` includes `$DEVELOPER_ID_APPLICATION`
- [x] parse args: if `--preflight`, run `preflight()` then exit 0; otherwise run `preflight()` and fall through (no other steps yet — a `TODO` comment marks where the pipeline will continue)
- [x] run `shellcheck scripts/build-dmg.sh` — must pass
- [x] run `scripts/build-dmg.sh --preflight` with all env vars unset — must exit non-zero with a message naming the first missing variable
- [x] run `scripts/build-dmg.sh --preflight` with env vars set + a bogus identity name — must exit non-zero with a message naming the missing cert
- [x] run `scripts/build-dmg.sh --preflight` with valid env + real cert — must exit 0 with no other output (deferred to manual verify — requires Apple Developer creds)

### Task 2: Add archive + exportArchive + signature verification to script

**Files:**
- Modify: `scripts/build-dmg.sh`

- [x] add `rm -rf build/` at the very start of the non-preflight path (after preflight, before any work) — treats `build/` as fully ephemeral, avoids stale-artifact ambiguity across runs; leaves `dist/` alone since that's the deliverable directory
- [x] add `mkdir -p build dist` after the rm so intermediate paths exist
- [x] add `resolve_version()` function that parses `MARKETING_VERSION` from `xcodebuild -showBuildSettings`; exports `VERSION`
- [x] add archive step: `xcodebuild archive` with `CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"` only (NO `OTHER_CODE_SIGN_FLAGS=--timestamp` — exportArchive applies that authoritatively a step later)
- [x] add `write_export_options()` function that emits `build/ExportOptions.plist` via heredoc (method=developer-id, teamID, signingStyle=manual, signingCertificate="Developer ID Application") — include a one-line comment in the heredoc explaining the friendly-name choice and the disambiguation alternative
- [x] add export step: `xcodebuild -exportArchive` writing to `build/export/`
- [x] add `codesign --verify --strict --verbose=2 build/export/TrafficWand.app` post-export (NO `--deep` — deprecated; the verifier walks nested code unconditionally)
- [x] add a `TODO` comment marking where notarization will be added (followed by `exit 0` so the partial script terminates cleanly during this task's e2e test)
- [x] run `shellcheck scripts/build-dmg.sh` — must pass
- [x] run `scripts/build-dmg.sh --preflight` — must still exit 0 (regression check) — negative-path verified (exits non-zero naming first missing env var); positive path deferred to manual verify (requires Apple Developer creds)
- [x] run `scripts/build-dmg.sh` end-to-end with valid creds; expect: archive built, .app exported, codesign --verify passes, then script reaches the notarization TODO and exits 0 (no further commands) (deferred to manual verify — requires Apple Developer creds)

### Task 3: Add notarize-and-staple step for the .app

**Files:**
- Modify: `scripts/build-dmg.sh`

- [x] add `notarize()` helper that takes a path arg, runs `xcrun notarytool submit <path> --apple-id ... --team-id ... --password ... --wait`, and on non-zero captures the submission ID and prints `xcrun notarytool log <submission-id>` before re-raising the failure
- [x] add step: `ditto -c -k --keepParent build/export/TrafficWand.app build/TrafficWand.zip` (no separate cleanup needed — `rm -rf build/` at script start handles it on the next run)
- [x] call `notarize build/TrafficWand.zip`
- [x] call `xcrun stapler staple build/export/TrafficWand.app`
- [x] add `xcrun stapler validate build/export/TrafficWand.app` post-staple check
- [x] add `spctl --assess --type execute -vv build/export/TrafficWand.app` fast-fail check — must report `accepted source=Notarized Developer ID`; this catches a malformed .app ticket *before* spending another 5 min on the DMG notarization round-trip
- [x] move the `TODO` / `exit 0` sentinel from Task 2 to *after* this new block (so the partial-script e2e in this task still terminates cleanly)
- [x] run `shellcheck scripts/build-dmg.sh` — must pass
- [x] run `scripts/build-dmg.sh --preflight` — regression check; negative-path verified (exits non-zero naming first missing env var); positive path deferred to manual verify (requires Apple Developer creds)
- [x] run `scripts/build-dmg.sh` end-to-end; expect: .app notarized, ticket stapled, stapler validate passes, spctl assess accepts, script then exits (DMG steps still missing) (deferred to manual verify — requires Apple Developer creds)

### Task 4: Add DMG build + notarize/staple .dmg + final spctl check

**Files:**
- Modify: `scripts/build-dmg.sh`

- [x] remove the Task 3 `TODO`/`exit 0` sentinel so execution continues past staple
- [x] add `create-dmg` invocation (volname, window/icon layout, `--app-drop-link`, `--no-internet-enable`) writing to `dist/TrafficWand-$VERSION.dmg`
- [x] call `notarize "dist/TrafficWand-$VERSION.dmg"`
- [x] call `xcrun stapler staple "dist/TrafficWand-$VERSION.dmg"`
- [x] add final `spctl --assess --type open --context context:primary-signature -vv "dist/TrafficWand-$VERSION.dmg"` — must report `accepted source=Notarized Developer ID`; add a short comment noting that DMGs require `--type open` while .app uses `--type execute` (intentional, do not unify)
- [x] print final one-line summary: `→ dist/TrafficWand-<version>.dmg (<size>)`
- [x] run `shellcheck scripts/build-dmg.sh` — must pass
- [x] run `scripts/build-dmg.sh --preflight` — regression check; negative-path verified (exits non-zero naming first missing env var); positive path deferred to manual verify (requires Apple Developer creds)
- [x] run `scripts/build-dmg.sh` end-to-end; expect: full pipeline succeeds, DMG exists with stapled ticket (deferred to manual verify — requires Apple Developer creds)

### Task 5: Wire `task dmg` Taskfile target

**Files:**
- Modify: `Taskfile.yml`

- [x] add `dmg` task between `run` and `test-core`; description `"Build, sign, notarize, and package the app as a DMG (release)"`; `deps: [generate]`; single cmd `./scripts/build-dmg.sh`
- [x] add a prose comment above the task (matching the comment style of `generate` at `Taskfile.yml:21–25`) explaining: `deps: [generate]` is for `.xcodeproj` freshness + `BuildInfo.xcconfig` materialization, not for compilation — the script's `xcodebuild archive` does its own full Release build
- [x] confirm `task --list` shows the new task with description
- [x] run `task dmg` with valid creds — must produce `dist/TrafficWand-<version>.dmg` identical to a direct script invocation (deferred to manual verify — requires Apple Developer creds)
- [x] run `task` (default) — must still succeed (no regression to build/lint/test-core/test pipeline)

### Task 6: Update README distribution section

**Files:**
- Modify: `README.md`

- [x] replace the entire §Distribution paragraph — including the dangling cross-reference to "Post-Completion section of the implementation plan" (which now points at an archived v1 plan under `completed/`) — with a short setup + run block: (1) Apple Developer Program required, (2) `brew install create-dmg`, (3) export the four env vars (one-time), (4) `task dmg`, (5) output at `dist/TrafficWand-<version>.dmg`
- [x] keep tone consistent with rest of README (terse, no runbook-style detail)
- [x] mention `scripts/build-dmg.sh --preflight` for setup validation
- [x] verify rendered README looks reasonable in a Markdown previewer
- [x] no tests needed (documentation-only)

### Task 7: Verify acceptance criteria

- [x] verify `task dmg` produces `dist/TrafficWand-<version>.dmg` from a clean state (delete `build/` and `dist/`, then run) (deferred to manual verify — requires Apple Developer creds)
- [x] verify version in DMG filename matches `MARKETING_VERSION` in `project.yml` (deferred to manual verify — requires Apple Developer creds)
- [x] mount the DMG, drag TrafficWand.app to /Applications, launch — no Gatekeeper warning (deferred to manual verify — requires Apple Developer creds)
- [x] `spctl --assess --type execute -vv /Applications/TrafficWand.app` → `accepted source=Notarized Developer ID` (deferred to manual verify — requires Apple Developer creds)
- [x] launch the app, verify About tab shows correct version + non-`unknown` git commit hash (sanity check that BuildInfo injection survived the Release build path) (deferred to manual verify — requires Apple Developer creds)
- [x] negative path: unset `APPLE_ID`, rerun `task dmg`, must fail in preflight with a named-cause message (no expensive work performed) — verified: `task dmg` with `APPLE_ID` unset exits 1 after preflight with message `build-dmg: error: required environment variable not set: APPLE_ID` (no archive/notarize work performed)
- [x] `task lint` clean
- [x] `task test-core` and `task test` clean (no regression) — `task test-core` 126 tests passed; `task test` 116 tests passed (** TEST SUCCEEDED **)

### Task 8: Update documentation and archive plan

**Files:**
- Modify: `CLAUDE.md`
- Move: this plan file to `docs/plans/completed/`

- [x] add a `## Release packaging` subsection to `CLAUDE.md` (one short paragraph: `task dmg` does signed + notarized + DMG, the four env vars it expects, pointer to `scripts/build-dmg.sh --preflight` for setup validation) — mirror the existing "Build system" / "Build-info / commit-hash injection" tone
- [x] move `docs/plans/20260528-task-dmg-signing-and-packaging.md` to `docs/plans/completed/`
- [x] confirm `task` (default) still clean

## Post-Completion

*Items requiring manual intervention or external systems — no checkboxes, informational only.*

**External system updates:**

- **`.github/workflows/release.yml` (separate PR):** Trigger on tag push
  (e.g. `v*`). Steps:
  1. Checkout.
  2. Setup Xcode latest-stable.
  3. `brew install xcodegen swiftlint create-dmg`.
  4. Create a temporary keychain (`security create-keychain`,
     `security set-keychain-settings`, `security unlock-keychain`).
  5. Decode base64-encoded `.p12` from `secrets.DEVELOPER_ID_CERT_P12_BASE64`
     to a temp file; import via `security import` into the temp keychain
     with `secrets.DEVELOPER_ID_CERT_PASSWORD`.
  6. **CRITICAL:** `security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_NAME"`.
     Without this, `codesign` blocks on a UI prompt that no one can dismiss on
     a headless runner — the single most common cause of CI signing hangs.
  7. Add the temp keychain to the search list (`security list-keychains -d user -s ...`).
  8. Export the four notary env vars from `secrets.*` into the job env.
  9. `task dmg`.
  10. Upload `dist/*.dmg` as the release asset via `softprops/action-gh-release@v2`.
  11. Cleanup: delete the temp keychain (always runs, even on failure).

  Also consider an `actions/cache` step keyed on `Package.resolved` for SPM
  deps — macos-26 runners take 5+ min on a cold archive otherwise. The
  current change is designed so the workflow is ~40–50 lines including the
  keychain dance.
- **Apple Developer setup (one-time per developer/team):**
  - Enroll in Apple Developer Program (done — that's the trigger for this
    plan).
  - In Xcode → Settings → Accounts, add the Apple ID, download the
    "Developer ID Application" certificate to the login keychain.
  - At `appleid.apple.com` → Sign-In and Security → App-Specific Passwords,
    generate one named e.g. `trafficwand-notarize`.
  - Add the four env vars to shell profile (`~/.zshrc` / `~/.config/fish/...`).

**Optional polish (not required for v1):**

- DMG background image: design a PNG, commit under `App/Resources/`, add
  `--background <path>` to the `create-dmg` invocation, refine icon
  coordinates to align with the artwork.
- Auto-update via Sparkle. Out of scope for v1 (already deferred in v1 plan).
- Migrate notary auth from app-specific-password env vars to ASC API key
  if/when team scale or password rotation friction warrants it. Localized
  change in `scripts/build-dmg.sh`'s `notarize()` helper.

**Manual verification (recommended before first public release):**

- Test the DMG on a clean macOS account (no prior TrafficWand install, no
  Apple Developer tooling) — verify Gatekeeper first-launch flow is clean.
- Verify the .app's URL handler registers correctly after install via the
  DMG (System Settings → Default web browser should list TrafficWand).
