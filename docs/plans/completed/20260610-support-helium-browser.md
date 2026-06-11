# Support Helium Browser

Addresses [issue #37](https://github.com/tomakado/trafficwand/issues/37).

## Overview

Add the [Helium browser](https://github.com/imputnet/helium) (by imput, bundle ID
`net.imput.helium`) to TrafficWand so it:

1. **Appears in the picker** — added to `BrowserFamily.chromiumBrowserBundleIDs`, which
   flows into the computed `knownBrowserBundleIDs` union (the curated display allowlist).
2. **Has its profiles discovered** — its Chromium `Local State` / profile directories
   are found via a `ProfilePathResolver` sub-path mapping.

Helium is **Chromium-based**, so it already *launches* correctly today (unknown bundle
IDs default to the `.chromium` family and get Chromium-style `--profile-directory=<dir>`
launch args). The only reason code is needed is the deliberate **listing-vs-launching**
split: launching is permissive, but the picker shows only a curated allowlist. So
"support Helium" = two additive entries (allowlist + profile path) plus tests/docs — no
new logic, mirroring the #35 (Arc/Dia/Comet/Zen) / #20 precedent.

**Verified facts** (real install, confirmed via web research):
- Bundle ID: `net.imput.helium`
- Profile data lives **directly** under `~/Library/Application Support/net.imput.helium/`
  (`Default/`, `Profile 1/`, `Local State` sit directly inside it). This is the
  Vivaldi/Chromium-style layout (sub-path points at the containing dir), **not** the
  `Arc/User Data` nesting used by Arc/Comet/Dia. The sub-path is therefore just
  `net.imput.helium`, and it is treated as **verified** (no "pending device
  verification" caveat).

## Context (from discovery)

Files/components involved:
- `TrafficWandCore/Sources/TrafficWandCore/Browsers/BrowserFamily.swift` — the
  `chromiumBrowserBundleIDs` display allowlist (Core, pure Swift).
- `App/Sources/Adapters/ProfilePathResolver.swift` — `subPathsByBundleID` mapping
  (App-side adapter).
- `TrafficWandCore/Tests/TrafficWandCoreTests/LaunchArgumentsTests.swift` — the
  `knownBrowsers` and `chromiumBundleIDs` parameterized tests, both in the
  **`BrowserFamilyTests`** suite (the `LaunchArgumentsTests` suite later in the same file
  is unrelated argv-tail coverage).
- `App/Tests/AppTests/ProfilePathResolverTests.swift` — per-bundle-ID sub-path assertions.
- `App/Tests/AppTests/BrowserProviderMergeTests.swift` — end-to-end picker-merge /
  allowlist filtering test (`testMergeFiltersNonBrowserHTTPHandlers`).
- `README.md` (line ~141) — the Chromium-family example list
  ("Chrome, Edge, Brave, Vivaldi, Chromium, Arc, Dia, Comet, …").

Related patterns found:
- **Listing vs. launching split**: `BrowserFamily.init(bundleID:)` defaults unknowns to
  `.chromium` (launch is permissive); `knownBrowserBundleIDs` / `isKnownBrowser` gates
  *picker listing* only.
- **Profile path resolution**: `ProfilePathResolver.subPathsByBundleID` maps bundle ID →
  Application Support sub-path; pure string building over an injected base dir, unit-tested
  with a fixed base (no real `~/Library` reads).
- The #35 commit (ef7ce17) is the exact template for this change.

Dependencies identified: none new. No `Info.plist` change (it registers a generic
http/https handler, not per-browser entries — #35 did not touch it).

## Development Approach

- **Testing approach**: **TDD** (CLAUDE.md mandates failing-test-first for Core changes;
  applied to the App adapter tests too for consistency).
- Complete each task fully before moving to the next; make small, focused changes.
- **CRITICAL: every task includes new/updated tests** (success + edge/error cases).
- **CRITICAL: all tests pass before starting the next task.**
- Keep Core free of system dependencies (no AppKit import — `task test-core` guards this).
- Keep `task lint` clean.
- Maintain backward compatibility (purely additive entries).

## Testing Strategy

- **Unit tests (Core)**: extend the `BrowserFamilyTests.knownBrowsers` arguments with
  `net.imput.helium` (the genuine red-then-green step), and add `net.imput.helium` to the
  `BrowserFamilyTests.chromiumBundleIDs` arguments (a green-from-start documentation
  assertion — already passes via the default case).
- **Unit tests (App)**: extend `ProfilePathResolverTests` with a Helium assertion;
  extend `BrowserProviderMergeTests` so Helium survives the picker allowlist filter and
  (with a resolver path) discovers Chromium profiles.
- **No e2e/UI test harness** in this project; `xcodebuild test` (the `TrafficWandTests`
  target) is the integration layer and covers the App adapters.
- Run `task test-core` for the fast Core loop, then `task test` for the full suite.

## Progress Tracking

- Mark completed items `[x]` immediately when done.
- Add newly discovered tasks with ➕ prefix; blockers with ⚠️ prefix.
- Keep this plan in sync with actual work.

## Solution Overview

Two additive data entries behind the existing seams, each driven by a failing test first:

1. **Picker listing** — add `"net.imput.helium"` to
   `BrowserFamily.chromiumBrowserBundleIDs`. This flows into `knownBrowserBundleIDs` and
   makes `isKnownBrowser("net.imput.helium")` true, so `BrowserMerger.merge` keeps Helium
   in the picker. Family classification is unchanged (already `.chromium` by default).
2. **Profile discovery** — add `"net.imput.helium": "net.imput.helium"` to
   `ProfilePathResolver.subPathsByBundleID`, so the Chromium profile reader is pointed at
   `~/Library/Application Support/net.imput.helium/` to parse `Local State`.

Key design decision: sub-path = `net.imput.helium` (containing-dir style, like
Vivaldi/Chromium), **not** `Helium/User Data`. Documented inline so it isn't
"normalized" away later.

## Technical Details

- `chromiumBrowserBundleIDs` (Set<String>) gains one element. No init/launch-arg change.
- `subPathsByBundleID` ([String: String]) gains one pair under the "Chromium family"
  group (alongside Vivaldi/Chromium, which also point at the containing dir — not under
  the `User Data`-nested newcomers group).
- Comment for the new entry states the path is verified from a real install.

## What Goes Where

- **Implementation Steps** (`[ ]`): code + tests + README — all in-repo.
- **Post-Completion** (no checkboxes): optional real-device sanity check of profile
  discovery against a live Helium install (path is already verified, so this is
  confirmation, not a blocker).

## Implementation Steps

### Task 1: List Helium in the picker (Core allowlist)

**Files:**
- Modify: `TrafficWandCore/Sources/TrafficWandCore/Browsers/BrowserFamily.swift`
- Modify: `TrafficWandCore/Tests/TrafficWandCoreTests/LaunchArgumentsTests.swift`

- [x] (TDD — red) Add `"net.imput.helium"` to the `knownBrowsers` parameterized test
  `arguments` array (in the **`BrowserFamilyTests`** suite of `LaunchArgumentsTests.swift`,
  ~line 50-64) with a `// Helium` comment; run `task test-core` and confirm it **fails**
  (Helium not yet on the allowlist).
- [x] (green) Add `"net.imput.helium"` to `chromiumBrowserBundleIDs` in
  `BrowserFamily.swift` with a `// Helium` comment.
- [x] (Documentation assertion — green from start) Add `"net.imput.helium"` to the
  existing `chromiumBundleIDs` `arguments` array (`BrowserFamilyTests`, ~line 9-17). This
  documents that Helium classifies as `.chromium`; it passes immediately via the default
  case (not a TDD red step), mirroring how Arc/Comet/Dia were handled.
- [x] (Edge case) Do **not** add a Helium-specific case-sensitivity test — the generic
  `isKnownBrowserCaseSensitive` and `caseSensitiveMapping` tests already cover the
  principle for all bundle IDs, and the touched file is near the SwiftLint `file_length`
  limit.
- [x] Run `task test-core` — must pass (including the no-AppKit import guard) before Task 2.

### Task 2: Discover Helium profiles (App profile-path mapping)

**Files:**
- Modify: `App/Sources/Adapters/ProfilePathResolver.swift`
- Modify: `App/Tests/AppTests/ProfilePathResolverTests.swift`

- [x] (TDD) Add an assertion to `ProfilePathResolverTests` that
  `resolver.applicationSupportDirectory(forBundleID: "net.imput.helium")?.path` equals
  `base.appendingPathComponent("net.imput.helium").path`; run `task test` (or the
  relevant test) and confirm it **fails**.
- [x] Add `"net.imput.helium": "net.imput.helium"` to `subPathsByBundleID` in
  `ProfilePathResolver.swift`, under the **Chromium family** group (with Vivaldi/Chromium,
  the containing-dir entries) — **not** under the `User Data`-nested Arc/Comet/Dia group.
- [x] Add an inline comment: Helium stores its Chromium profile config directly under
  `net.imput.helium/` (verified from a real install) — do not nest under `User Data`.
- [x] (Edge case) Add/confirm a test that an unknown bundle ID still returns `nil`
  (likely already present — verify it covers the "absent family" path).
  Confirmed: `testProfilePathResolverUnsupportedFamiliesReturnNil` already covers
  `com.example.Unknown` returning nil.
- [x] Run `task test` — profile-path tests must pass before Task 3.

### Task 3: End-to-end picker-merge coverage

**Files:**
- Modify: `App/Tests/AppTests/BrowserProviderMergeTests.swift`

- [x] In `testMergeFiltersNonBrowserHTTPHandlers`, update **both** the `candidates` array
  (add `candidate("net.imput.helium", "Helium")`) **and** the expected `XCTAssertEqual(ids,
  [...])` set (add `"net.imput.helium"`) — editing only one half breaks the test. This
  proves Helium passes the picker allowlist while terminals/non-browsers are still dropped.
- [x] (Optional, if it adds signal) Add/extend a merge test that, given a resolver path
  for `net.imput.helium`, attaches discovered Chromium profiles to the Helium entry
  (skipped — redundant with existing `testMergeKnownChromiumBrowserWithResolverPathDiscoversProfiles`,
  which already proves an arbitrary non-Chrome Chromium browser is classified `.chromium`
  and gets its profiles attached; Helium uses the identical default-family path).
- [x] Run `task test` — must pass before Task 4.

### Task 4: Update documentation

**Files:**
- Modify: `README.md`

- [x] Add **Helium** to the Chromium-family example list (~line 141:
  "Chrome, Edge, Brave, Vivaldi, Chromium, Arc, Dia, Comet, …" → include Helium).
- [x] (no new pattern — no CLAUDE.md change needed)

### Task 5: Verify acceptance criteria

- [x] Verify Helium appears in `knownBrowserBundleIDs` and `isKnownBrowser`.
  Confirmed: `"net.imput.helium"` in `chromiumBrowserBundleIDs` (BrowserFamily.swift:59),
  which feeds `knownBrowserBundleIDs` (union) and `isKnownBrowser`.
- [x] Verify `ProfilePathResolver` returns the correct `net.imput.helium` directory.
  Confirmed: `"net.imput.helium": "net.imput.helium"` mapping (ProfilePathResolver.swift:42).
- [x] Verify the merge test proves Helium is listed (not filtered out).
  Confirmed: `testMergeFiltersNonBrowserHTTPHandlers` has Helium in both `candidates`
  and the expected `ids` set (BrowserProviderMergeTests.swift:92,113).
- [x] Run full suite: `task test-core` **and** `task test` — all pass.
  `task test-core`: 132 tests in 14 suites passed. `task test`: 132 tests, 0 failures.
- [x] Run `task lint` — clean (no violations).

### Task 6: Finalize

- [x] Confirm all checkboxes above are `[x]`.
- [x] Move this plan to `docs/plans/completed/`.

## Post-Completion

*Informational — no checkboxes.*

**Manual verification (optional):**
- On a machine with Helium installed, set TrafficWand as default browser, confirm Helium
  shows up in the picker and that its real profiles (`Default`, any `Profile N`) are
  discovered and routable. The profile path is already verified, so this is a sanity
  confirmation rather than a gating step.
