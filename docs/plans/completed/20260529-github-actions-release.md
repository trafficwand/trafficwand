# GitHub Actions for Release (issue #28)

## Overview

When a version tag is pushed, a GitHub Actions workflow should create (or update)
the corresponding GitHub Release, attaching:

1. A **changelog** — GitHub's auto-generated release notes (commits/PRs since the
   previous release).
2. The **signed & notarized `.dmg`** produced by the existing `scripts/build-dmg.sh`
   pipeline (`dist/TrafficWand-<version>.dmg`).

This automates what is today a manual `task dmg` + manual GitHub release. The build,
sign, notarize, staple, and package steps already exist and are reused verbatim — this
work adds the **CI trigger, certificate import, version verification, and release
publication** around them.

## Context (from discovery)

- Files/components involved:
  - `scripts/build-dmg.sh` — full archive → sign → notarize → staple → DMG → notarize
    DMG pipeline. Reads 4 env vars; falls back to the environment when `.dmg.env` is
    absent (i.e. designed to run in CI). Produces `dist/TrafficWand-<version>.dmg`.
    Its `preflight()` **requires the Developer ID identity to already exist in a
    codesigning keychain** (`security find-identity -v -p codesigning | grep ...`).
  - `Taskfile.yml` — `task dmg` runs `generate` (→ `build-info`) then `build-dmg.sh`.
  - `.github/workflows/ci.yml` — existing CI on `macos-26`, uses `setup-xcode`,
    `go-task/setup-task`, and `brew install` for `xcodegen` / `swiftlint`.
  - `project.yml` — `MARKETING_VERSION: "0.1.0"` under `settings.base` is the single
    source of truth for the app version and the DMG filename.
- Related patterns found:
  - CI installs toolchain via Homebrew and runs everything through `task`.
  - The repo's design ethos: decision-shaped logic is extracted and unit-tested;
    system glue is kept thin. The tag↔version check is the one testable seam here.
- Dependencies identified:
  - `create-dmg` (Homebrew) is **not** preinstalled on runners — must `brew install`.
  - The signing **private key + certificate** must be imported from a secret; GitHub
    `macos-26` runners ship with no Developer ID identity.

## Development Approach

- **testing approach**: Regular (code first, then tests). The only unit-testable unit
  is `scripts/verify-release-version.sh`; it gets a companion assertion test script.
  The workflow YAML itself is verified by `actionlint` (syntax) plus a real tag-push
  dry run (Post-Completion — needs live secrets).
- complete each task fully before moving to the next
- make small, focused changes
- **every task with logic MUST include new/updated tests**; the version-check script
  is the task that carries real unit assertions
- **all tests must pass before starting next task**
- **update this plan file when scope changes during implementation**
- maintain backward compatibility (do not alter `build-dmg.sh` behavior; only call it)

## Testing Strategy

- **unit tests**: `scripts/verify-release-version.sh` gets `scripts/verify-release-version.test.sh`,
  a self-contained bash assertion runner covering: exact match, `v`-prefixed match,
  mismatch (must fail non-zero), missing arg (must fail). Runnable locally with no
  network, Xcode, or secrets.
- **workflow validation**: lint `.github/workflows/release.yml` with `actionlint`
  (or `gh workflow view` / YAML parse) — catches syntax and expression errors without
  a live run.
- **e2e**: not applicable as automated CI tests — the true end-to-end check is a real
  tag push with secrets configured, which is a Post-Completion manual step (it costs a
  full notarization round-trip and requires the live Apple credentials).

## Progress Tracking

- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix
- keep plan in sync with actual work done

## Solution Overview

A new workflow `.github/workflows/release.yml`:

- **Trigger**: `push` on tags matching `v*.*.*`.
- **Permissions**: `contents: write` (required to create releases and upload assets).
- **Runner**: `macos-26` (matches existing CI).
- **Steps**:
  1. `actions/checkout@v6` with `fetch-depth: 0` (full history so generated notes /
     any git-based step have all tags).
  2. `maxim-lobanov/setup-xcode@v1` (`latest-stable`) + `go-task/setup-task@v2`.
  3. `brew install xcodegen create-dmg`.
  4. **Import Developer ID certificate** into a throwaway keychain via inline
     `security` commands (decode base64 `.p12` from secret, create + unlock keychain,
     `security import`, `set-key-partition-list`, add to the user search list).
  5. **Verify version** — `scripts/verify-release-version.sh "$GITHUB_REF_NAME"`
     fails the job fast if the tag (minus `v`) ≠ `MARKETING_VERSION` in `project.yml`.
  6. `task dmg` — generate, build, sign, notarize, staple, package. The 4 Apple env
     vars come from secrets; `.dmg.env` is absent in CI so the script reads the
     environment.
  7. **Create or update the release** — `gh release create` with `--generate-notes`
     `--verify-tag` if the release doesn't exist yet, else `gh release upload --clobber`
     to (re)attach the DMG to the existing release (idempotent re-runs).
  8. **Cleanup** (`if: always()`) — delete the temporary keychain.

Key design decisions & rationale:

- **Verify-match (not tag-drives-build)**: keeps `project.yml` the single source of
  truth for the version while guaranteeing the tag is meaningful; no build-time
  mutation of `MARKETING_VERSION`. A mismatched tag is an operator error and should
  fail loudly *before* a 10-minute notarized build.
- **Manual `security` keychain commands**: no third-party action handles the private
  key; the signing path stays fully auditable in-repo.
- **GitHub auto-generated notes**: `gh release create --generate-notes` satisfies the
  "list of commits/changes since last release" requirement with zero custom git
  plumbing, and groups by PR/contributor for free.
- **Reuse `task dmg` unchanged**: the workflow is thin glue; all signing/notarizing
  logic stays in the already-reviewed `build-dmg.sh`.

## Technical Details

### Secrets required (configured in repo Settings → Secrets and variables → Actions)

| Secret | Purpose |
| ------ | ------- |
| `APPLE_ID` | Apple ID email for notarization (→ `build-dmg.sh`). |
| `APPLE_TEAM_ID` | 10-char team identifier. |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for `notarytool`. |
| `DEVELOPER_ID_APPLICATION` | Full identity common name, e.g. `Developer ID Application: Name (TEAMID)`. |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64 of the exported `.p12` (cert **+ private key**). |
| `MACOS_CERTIFICATE_PASSWORD` | Password protecting that `.p12`. |

The temporary keychain password is generated in-step (`uuidgen`), not a secret.

### `verify-release-version.sh` contract

- Input: `$1` = tag ref (e.g. `v0.1.0` or `0.1.0`); leading `v` stripped.
- Optional `$2` (or `PROJECT_FILE` env) = path to the project file, defaulting to
  `project.yml`. This indirection exists **only** so the unit test can point the script
  at a temp fixture instead of the repo's live `project.yml` — keeps the test
  independent of the current `MARKETING_VERSION`.
- Reads `MARKETING_VERSION` from the project file. The real line is indented and quoted
  (`    MARKETING_VERSION: "0.1.0"`), so the parse **must strip the key, colon,
  surrounding double-quotes, and leading/trailing whitespace** before comparing.
  No Xcode/generate needed, so it runs before `task dmg`.
- Exit `0` and echo the version on match; `die` non-zero with a clear, distinct message
  on (a) missing/empty tag arg, (b) `MARKETING_VERSION` not found/empty in the file,
  and (c) tag≠version mismatch.

### Certificate import (inline, step 4) — shape

```bash
KEYCHAIN_PATH="$RUNNER_TEMP/app-signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
echo -n "$MACOS_CERTIFICATE_P12_BASE64" | base64 --decode -o "$RUNNER_TEMP/cert.p12"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$RUNNER_TEMP/cert.p12" -P "$MACOS_CERTIFICATE_PASSWORD" \
  -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
# Partition list MUST include `codesign:` — without it, codesign/xcodebuild can
# hang on a UI prompt or fail with errSecInternalComponent at signing time
# (after the ~10-min build). `apple-tool:,apple:` alone is insufficient.
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
# Make the new keychain searchable so `security find-identity` in build-dmg.sh's
# preflight resolves the identity. Verb is `list-keychains` (PLURAL) for both
# read and write; the singular form is not a valid security subcommand.
security list-keychains -d user -s "$KEYCHAIN_PATH" \
  $(security list-keychains -d user | sed 's/[\"]//g')
```

### Release publication (step 7) — shape

```bash
TAG="$GITHUB_REF_NAME"
DMG="$(ls dist/TrafficWand-*.dmg)"
if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DMG" --clobber
else
  gh release create "$TAG" "$DMG" --generate-notes --verify-tag --title "$TAG"
fi
```

(`GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}` in the step env — `gh` is preinstalled on
GitHub-hosted macOS runners, no `brew install gh` needed. Note: `--generate-notes`
applies on first creation; re-runs only re-upload the asset and leave notes intact —
documented behavior, acceptable for the issue's scope.)

### Concurrency

Set `concurrency: { group: release-${{ github.ref }}, cancel-in-progress: false }`.
A tag push is rare and serial, but **`cancel-in-progress: false` is deliberate**:
never cancel an in-flight notarization (it wastes a ~10-min Apple round-trip and can
leave a half-published release). This differs from `ci.yml`, which uses
`cancel-in-progress: true` because cancelling a stale build is harmless.

## What Goes Where

- **Implementation Steps** (`[ ]`): the version-check script + its test, the workflow
  file, doc updates, and `actionlint` validation — all doable in-repo.
- **Post-Completion** (no checkboxes): configuring the 6 GitHub secrets, exporting the
  `.p12`, and the live tag-push smoke test — these need credentials and external state.

## Implementation Steps

### Task 1: Add `verify-release-version.sh` + test

**Files:**
- Create: `scripts/verify-release-version.sh`
- Create: `scripts/verify-release-version.test.sh`

- [x] create `scripts/verify-release-version.sh`: strip optional leading `v` from `$1`,
      read `MARKETING_VERSION` from the project file (default `project.yml`, overridable
      via `$2`/`PROJECT_FILE` for testability), compare; echo version + exit 0 on match,
      print a clear error + exit non-zero on mismatch
- [x] parse must strip the key/colon, surrounding double-quotes, and leading/trailing
      whitespace from the indented YAML line `    MARKETING_VERSION: "0.1.0"`
- [x] handle missing/empty arg and missing/empty `MARKETING_VERSION` with distinct error
      messages (fail non-zero)
- [x] `chmod +x` both scripts; use `set -euo pipefail` and a `die()` helper consistent
      with `build-dmg.sh`
- [x] create `scripts/verify-release-version.test.sh`: write a temp fixture project file
      in the real format (`    MARKETING_VERSION: "1.2.3"`) and point the script at it,
      so tests are independent of the repo's current version; assert exact-match passes,
      `v`-prefixed match passes, mismatch fails non-zero, missing-arg fails non-zero,
      missing-`MARKETING_VERSION` fails non-zero
- [x] run `bash scripts/verify-release-version.test.sh` — all assertions must pass
      before next task

### Task 2: Add the release workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [x] trigger on `push` tags `v*.*.*`; set `permissions: contents: write`; runner
      `macos-26`; `concurrency: { group: release-${{ github.ref }}, cancel-in-progress: false }`
- [x] steps: `checkout@v6` (`fetch-depth: 0`), `setup-xcode@v1` (`latest-stable`),
      `setup-task@v2`, `brew install xcodegen create-dmg`
- [x] add the certificate-import step (inline `security` commands, secrets via `env`) —
      use `list-keychains` (plural) and partition list `apple-tool:,apple:,codesign:`
- [x] add the version-verify step calling `scripts/verify-release-version.sh "$GITHUB_REF_NAME"`
- [x] add the `task dmg` step with the 4 Apple secrets exported as `env`
- [x] add the create-or-update release step (`gh release create --generate-notes
      --verify-tag` / `gh release upload --clobber`) with `GH_TOKEN`
- [x] add an `if: always()` keychain-cleanup step (`security delete-keychain`)
- [x] validate with `actionlint` (or `brew install actionlint && actionlint
      .github/workflows/release.yml`); fix any reported issues — must be clean before
      next task

### Task 3: Document the release flow

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md` (only if it documents installation/releases)

- [x] extend CLAUDE.md "Release packaging" section: describe the tag-triggered
      `release.yml`, the 6 required secrets, and that it reuses `task dmg`
- [x] note the tag↔`MARKETING_VERSION` verification rule (bump `project.yml` before
      tagging)
- [x] update README §Distribution (line ~209): it currently documents only the manual
      `task dmg` flow and says the DMG is "ready to upload as a GitHub release" — add
      that pushing a `v*.*.*` tag now does this automatically via `release.yml`, and
      point users to the Releases page for the signed DMG
- [x] (no automated tests for docs; verify links/section names are correct by reading)

### Task 4: Verify acceptance criteria

- [x] confirm: tag push → release created/updated, with auto-generated notes and the
      signed/notarized DMG attached (verified by reading the workflow end-to-end and
      mapping each Overview requirement to a step) — trigger `on.push.tags: v*.*.*`;
      `task dmg` produces `dist/TrafficWand-*.dmg`; the "Create or update GitHub release"
      step attaches `$DMG` and uses `--generate-notes` for the changelog. All three
      Overview requirements map to concrete steps.
- [x] confirm idempotency: a re-run on an existing tag updates the asset, doesn't error
      — release step branches on `gh release view "$TAG"`: exists → `gh release upload
      --clobber` (re-attach, no error); first time → `gh release create`. Sound re-run.
- [x] confirm version mismatch fails the job before the expensive build — the
      "Verify release version" step (`scripts/verify-release-version.sh`) runs BEFORE the
      "Build, sign, notarize, and package DMG" (`task dmg`) step in the YAML; a mismatch
      aborts the job fast.
- [x] run `bash scripts/verify-release-version.test.sh` (full local test) — 7 tests,
      0 failures, exit 0.
- [x] run `actionlint .github/workflows/release.yml` (clean) — exit 0, no findings.

### Task 5: [Final] Update documentation & archive plan

- [x] re-read CLAUDE.md changes for accuracy
- [x] move this plan to `docs/plans/completed/`

## Post-Completion

*Items requiring manual intervention or external systems — informational only.*

**Secret & certificate setup** (one-time, before the first tagged release):
- Export the Developer ID Application identity (cert + private key) from Keychain
  Access as a password-protected `.p12`, then `base64 -i cert.p12 | pbcopy`.
- Add the 6 repo secrets listed in Technical Details (the 4 Apple vars + the 2 cert
  vars).

**Live smoke test** (the true end-to-end verification):
- Bump `MARKETING_VERSION` in `project.yml` if needed, commit, then push a matching
  tag (e.g. `git tag v0.1.0 && git push origin v0.1.0`).
- Watch the Actions run; confirm the Release appears with notes + the `.dmg`, and that
  the downloaded DMG passes Gatekeeper (`spctl --assess --type open -vv`).

**Known risks to watch on first run**:
- ⚠️ `create-dmg` drives Finder via AppleScript to lay out the window; it can be flaky
  on headless runners. If it fails, options are retry, or switch `build-dmg.sh` to a
  no-Finder DMG layout (`hdiutil`-only). Out of scope here but flagged.
- ⚠️ Notarization adds ~5–10 min and depends on Apple's service; the job timeout should
  accommodate it (default 360 min is plenty).
- ⚠️ The cert-import `security` sequence cannot be fully validated without live secrets;
  the first tagged run is where keychain/partition-list correctness is proven. The plan
  pins the two known footguns (plural `list-keychains`, `codesign:` in the partition
  list), but watch the import + first `codesign` step closely on run one.
