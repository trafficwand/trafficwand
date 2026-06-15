# `task install` — Build & install to ~/Applications

## Overview
Add convenience tasks that build the app and install the resulting `.app` bundle into
`~/Applications` for local use (issue #44):

- **`task install`** — Release build, installed to `~/Applications`.
- **`task install-dev`** — Debug build (same config as `task build`/`task run`),
  installed to `~/Applications`.

Both tasks quit any running TrafficWand instance, replace the bundle in `~/Applications`,
and stop (no relaunch). `~/Applications` is user-local, so no `sudo` is required.

This solves the gap where the only ways to get the app were `task run` (launches from
DerivedData, not installed) or `task dmg` (full signed/notarized release pipeline). There
was no lightweight "put the build in my Applications folder so I can use it" path.

## Context (from discovery)
- **Files/components involved:**
  - `Taskfile.yml` — add `install` + `install-dev`; parameterize `build` with a `CONFIG` var.
  - `scripts/install-app.sh` (new) — pure install logic (resolve built bundle → quit → replace).
  - `scripts/install-app.test.sh` (new) — assertion tests, matching existing script-test convention.
  - `README.md` — "Build & run" task table (line ~74).
  - `CLAUDE.md` — Commands table.
- **Related patterns found:**
  - `task run` already resolves the built bundle via
    `xcodebuild -showBuildSettings | awk '/ BUILT_PRODUCTS_DIR /.../ FULL_PRODUCT_NAME /...'`.
    Reuse this for path resolution (parameterized by `-configuration`).
    **`-showBuildSettings` is a non-building query, not a build** (same pattern `run`
    already relies on), so the script using it does **not** violate CLAUDE.md's
    "builds go through `task`" rule — the actual compile stays in the `deps: [build]` task.
  - `build` task currently builds **Debug** (no `-configuration` flag → Xcode default).
  - Project keeps non-trivial shell in `scripts/*.sh` with matching `*.test.sh`
    (`verify-release-version.sh`/`.test.sh`, `generate-appcast.sh`/`.test.sh`). Those tests
    inject env vars (e.g. `PROJECT_FILE=`) so logic runs without Xcode/network/secrets.
  - CLAUDE.md rule: routine builds go **through `task`**, never `xcodebuild` directly — so the
    build step stays in the Taskfile; the script only resolves the path and installs.
- **Dependencies identified:**
  - `xcodebuild` (already required), `ditto` (system), `pkill` (system). No new deps.
  - go-task var defaulting: `{{.CONFIG | default "Debug"}}`; deps-with-vars syntax.

## Development Approach
- **testing approach:** TDD for the script — write `install-app.test.sh` assertions first,
  then `install-app.sh` until green. The script is designed with injectable seams
  (`APP_PATH`, `INSTALL_DIR`) so its install logic runs in CI without Xcode or touching the
  real `~/Applications`.
- complete each task fully before moving to the next; small, focused changes.
- **every task includes new/updated tests** (the script task carries the `.test.sh`).
- **all tests pass before starting the next task.**
- run tests after each change; maintain backward compatibility (existing `task build`
  behavior — Debug by default — must not change).

## Testing Strategy
- **unit tests:** `scripts/install-app.test.sh` — self-contained bash assertions, no Xcode.
  Covers, via injected `APP_PATH` (fake `.app` dir), `INSTALL_DIR` (temp dir), and
  `QUIT_CMD` (fake quit command):
  - fresh install into an empty `INSTALL_DIR` (bundle copied, contents intact),
  - overwrite an existing stale bundle (old contents fully replaced, not merged),
  - `INSTALL_DIR` auto-created when absent,
  - the quit step fires (injected `QUIT_CMD` marker appears) — without touching a real process,
  - missing/nonexistent source `APP_PATH` → non-zero exit with a clear stderr message,
  - missing config argument → non-zero exit with usage message.
- **no e2e harness** in this project (no Playwright/Cypress). End-to-end behavior
  (real `xcodebuild` build + real `~/Applications` install + launch) is manual — see
  Post-Completion.

## Progress Tracking
- mark completed items with `[x]` immediately when done.
- add newly discovered tasks with ➕ prefix; blockers with ⚠️ prefix.
- keep this plan in sync with actual work.

## Solution Overview
Two-layer split, consistent with the repo:

1. **Taskfile (orchestration + build):** `build` gains an optional `CONFIG` var
   (default `Debug`, preserving current behavior). `install` and `install-dev` each
   `deps` on `build` with the right `CONFIG`, then invoke `scripts/install-app.sh <config>`.
   Building stays in the Taskfile/`xcodebuild` per CLAUDE.md.

2. **`scripts/install-app.sh` (pure install logic):** given a configuration name,
   resolves the freshly-built bundle path (or honors an injected `APP_PATH`), ensures the
   destination exists, terminates any running instance, and atomically-ish replaces the
   bundle. All system touch-points are injectable for testing.

Post-install: quit-only (per decision) — `pkill -x TrafficWand` before replacing the
bundle, no relaunch.

## Technical Details

### Taskfile changes
- `build` task:
  - add `vars: { CONFIG: '{{.CONFIG | default "Debug"}}' }`
  - command: `xcodebuild build -project TrafficWand.xcodeproj -scheme {{.SCHEME}} -configuration {{.CONFIG}} -destination 'platform=macOS'`
- `install` task: declare the configuration **once** as a task-local var, then thread it into
  both the build dep and the script arg so the two can't drift:
  ```yaml
  install:
    vars: { CONFIG: Release }
    deps: [{ task: build, vars: { CONFIG: '{{.CONFIG}}' } }]
    cmds: [ ./scripts/install-app.sh {{.CONFIG}} ]
  ```
- `install-dev` task: identical shape with `vars: { CONFIG: Debug }`.

  (The build and the script's own `-showBuildSettings -configuration` must reference the same
  configuration; declaring it once removes the two-literal drift risk.)

### `scripts/install-app.sh <configuration>`
Behavior (with `set -euo pipefail`):
1. Require a `<configuration>` arg; else die with usage on stderr.
2. Resolve source bundle:
   - If `APP_PATH` env is set (test/override seam), use it verbatim and skip resolution.
   - Else resolve via
     `xcodebuild -project TrafficWand.xcodeproj -scheme TrafficWand -configuration "$CONFIG" -showBuildSettings`
     parsing `BUILT_PRODUCTS_DIR` + `FULL_PRODUCT_NAME` (same awk one-liner as `run`).
3. Verify the source bundle exists and is a directory; else die on stderr.
4. Destination dir: `INSTALL_DIR` env (default `$HOME/Applications`); `mkdir -p` it.
5. Quit running instance via the `QUIT_CMD` seam (default `pkill -x TrafficWand`):
   `${QUIT_CMD:-pkill -x TrafficWand} 2>/dev/null || true`
   (no-op when not running; the `|| true` only swallows the exit code).
   **`-x` exact-matches the executable process name `TrafficWand`.**
6. Replace bundle: `rm -rf "$INSTALL_DIR/$bundle_name"` then
   `ditto "$APP_PATH" "$INSTALL_DIR/$bundle_name"` (`ditto` preserves bundle metadata and
   avoids merge-with-stale-contents that a plain `cp -R` into an existing dir can cause).
7. Print the installed path to stdout.

Seams for testability (mirrors `verify-release-version.sh`'s `PROJECT_FILE` pattern):
- `APP_PATH` — inject a fake `.app` fixture dir, skipping `xcodebuild`.
- `INSTALL_DIR` — point at a temp dir instead of `~/Applications`.
- `QUIT_CMD` — override the quit command. **Required for tests:** a bare
  `pkill -x TrafficWand` would terminate a *real* running TrafficWand when the suite is run
  locally with the app open (the `|| true` only hides the exit code, not the kill). Tests
  inject a fake `QUIT_CMD` (e.g. a script that `touch`es a marker file) so the suite never
  touches a real process **and** can assert the quit step actually fired.

## What Goes Where
- **Implementation Steps** (`[ ]`): script + tests, Taskfile wiring, doc table updates.
- **Post-Completion** (no checkboxes): real-build manual smoke test, `task lint` of shell is
  N/A (SwiftLint only) — manual `bash -n`/run is in steps.

## Implementation Steps

### Task 1: `scripts/install-app.sh` + tests (install logic, no Xcode)

**Files:**
- Create: `scripts/install-app.test.sh`
- Create: `scripts/install-app.sh`

- [x] write `scripts/install-app.test.sh` first (TDD) following the
      `verify-release-version.test.sh` structure: `fail`/`pass` helpers, temp fixtures via
      `mktemp -d` + `trap ... EXIT`, driving the SUT as `bash "$SUT" <config>` (matches the
      existing convention; keeps tests independent of the exec bit) with injected
      `APP_PATH`/`INSTALL_DIR`/`QUIT_CMD`
- [x] add assertions: fresh install copies bundle into empty `INSTALL_DIR`; contents present
- [x] add assertions: overwriting an existing stale bundle fully replaces it (a marker file
      from the old bundle is gone; new contents present) — proves `rm -rf` + `ditto`, not merge
- [x] add assertions: `INSTALL_DIR` auto-created when missing
- [x] add assertion: the quit step fires — inject `QUIT_CMD` as a fake that `touch`es a
      marker, assert the marker exists after a run (covers the "terminate running instance"
      acceptance criterion without killing any real process)
- [x] add assertions: nonexistent `APP_PATH` → non-zero exit + stderr substring; missing
      config arg → non-zero exit + usage substring
- [x] create `scripts/install-app.sh` implementing the behavior above until all assertions pass
- [x] `chmod +x` both scripts
- [x] run `bash scripts/install-app.test.sh` — must pass before Task 2

### Task 2: Wire `build` CONFIG var + `install`/`install-dev` into Taskfile

**Files:**
- Modify: `Taskfile.yml`

- [x] add `CONFIG` var (default `Debug`) to the `build` task and pass `-configuration {{.CONFIG}}`
- [x] add `install` task with a task-local `vars: { CONFIG: Release }` threaded into both
      `deps: [{ task: build, vars: { CONFIG: '{{.CONFIG}}' } }]` and `./scripts/install-app.sh {{.CONFIG}}`
- [x] add `install-dev` task — identical shape with `vars: { CONFIG: Debug }`
- [x] verify `task build` still defaults to Debug (no behavior change): `task build --dry` or
      inspect resolved command
- [x] confirm task graph parses: `task --list` shows `install` and `install-dev` with descriptions
- [x] re-run `bash scripts/install-app.test.sh` — must still pass before Task 3

### Task 3: Update documentation

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [x] add `task install` and `task install-dev` rows to the README "Build & run" table
      (note: Release vs Debug, installs to `~/Applications`, quits running instance, no relaunch)
- [x] add the same two rows to the CLAUDE.md Commands table
- [x] note that `task build` accepts an optional `CONFIG` (default Debug) where relevant
- [x] no code in this task → no new unit tests; re-run `bash scripts/install-app.test.sh`
      to confirm nothing regressed

### Task 4: Verify acceptance criteria
- [x] `task install` builds Release and places `TrafficWand.app` in `~/Applications`
      (verified via `INSTALL_DIR=$(mktemp -d) task install` — Release build succeeded,
      TrafficWand.app landed in temp dir with Contents/MacOS/TrafficWand binary + Info.plist)
- [x] `task install-dev` builds Debug and places it in `~/Applications`
      (verified via `INSTALL_DIR=$(mktemp -d) task install-dev` — Debug build succeeded,
      TrafficWand.app landed in temp dir with binary + Info.plist; build log shows "Sign to Run Locally")
- [x] a previously-installed bundle is replaced cleanly (no stale leftovers)
      (verified: touched STALE marker inside installed bundle, re-ran `INSTALL_DIR=<same-tmp> task install-dev`,
      confirmed STALE file gone; also covered by install-app.test.sh "overwrite stale bundle" assertion)
- [x] a running instance is terminated before replacement
      (covered by install-app.test.sh "quit step fires" assertion — injected QUIT_CMD touches a marker,
      assert marker present; real pkill behavior is manual per plan)
- [x] run `bash scripts/install-app.test.sh` (full script test suite green)
      (7/7 tests passed: fresh install, overwrite stale, INSTALL_DIR auto-create, quit step, nonexistent APP_PATH, missing config arg)
- [x] `task test-core` still green (sanity; unaffected, but confirms repo not broken)
      (132 tests in 14 suites — all passed)

### Task 5: [Final] Move plan to completed
- [x] `mkdir -p docs/plans/completed` and move this plan into it

## Post-Completion
*Items requiring manual intervention or external systems — no checkboxes, informational only*

**Manual verification:**
- Run `task install` on this Mac and confirm `~/Applications/TrafficWand.app` exists and
  launches (Release build is **not** notarized — Gatekeeper may require right-click → Open
  on first launch; document this in the README row if it proves annoying).
- Run `task install-dev`, confirm the Debug build installs and launches.
- With TrafficWand running, re-run `task install` and confirm the old instance is quit and
  the bundle is replaced without error.
- Confirm `~/Applications` is created on a machine that doesn't already have it.

**Notes / possible follow-ups (out of scope unless requested):**
- Ad-hoc codesign of the Release build to reduce Gatekeeper friction for local installs.
- Optional `INSTALL_DIR` override documented for users who prefer `/Applications` (needs sudo).
