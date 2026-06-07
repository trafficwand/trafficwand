# Support More Browsers (Chromium fallback for unknown browsers)

Addresses [issue #20](https://github.com/tomakado/trafficwand/issues/20): support Arc, Dia,
Comet, and Zen, and **treat any other (unknown) browser as Chromium instead of Safari**.

## Overview

- TrafficWand classifies every http(s) handler into a `BrowserFamily`
  (`.chromium` / `.firefox` / `.safari` / `.other`). Today `.other` (anything not on a
  small allowlist) is **dropped from the picker entirely** and, on the rare path where it
  is launched, is treated like Safari (no command-line profile selection).
- This change makes **Chromium the default family**: the `BrowserFamily(bundleID:)`
  fallback returns `.chromium` instead of `.other`, and the `.other` case is removed.
  Because nearly every modern non-Safari/non-Firefox browser is Chromium-based, this is the
  correct general default — and it means a browser we never explicitly listed (Arc, Dia,
  Comet, and future ones) still **appears in the picker and launches correctly**.
- Zen is a **Firefox fork**, not Chromium, so it is classified into the `.firefox` family
  (gets `-P <profile>` launching and `profiles.ini` discovery) rather than falling through
  to the Chromium default.
- Profile discovery for the named Chromium newcomers (Arc, Comet, Dia) is wired by adding
  their `~/Library/Application Support` sub-paths to `ProfilePathResolver`, so their
  profiles show up in the picker just like Chrome/Edge/Brave.

### Why this is the right shape

The exact bundle IDs / support paths for Comet and Dia are hard to pin down without the
apps installed. A Chromium **default** turns the allowlist from a *correctness requirement*
into a *profile-discovery optimization*: even if a specific bundle ID is slightly wrong, the
browser still launches — it only loses per-profile selection, degrading gracefully to
"launch default profile" rather than failing.

### Accepted trade-off

`NSWorkspace.urlsForApplications(toOpen: https://…)` enumerates apps registered as http(s)
handlers. Removing the `.other` allowlist filter means **any** such app is now listed, not
only known browsers. In practice this set is almost entirely browsers (chat/mail apps
register custom schemes like `slack://` / `mailto:`, not http), so the picker stays clean.
This is the explicit intent of the issue's "treat any other browser as Chromium" clause.

## Context (from discovery)

- **Files/components involved:**
  - `TrafficWandCore/Sources/TrafficWandCore/Browsers/BrowserFamily.swift` — the single
    source of truth for classification.
  - `TrafficWandCore/Sources/TrafficWandCore/Browsers/LaunchArguments.swift` — switches on
    family to build the argv tail.
  - `App/Sources/Adapters/WorkspaceBrowserProvider.swift` — `BrowserMerger` (the `.other`
    list filter) and `profileReader(for:)` (family → reader).
  - `App/Sources/Adapters/ProfilePathResolver.swift` — per-bundle-ID Application Support
    sub-paths.
  - Tests: `TrafficWandCore/Tests/TrafficWandCoreTests/...` (Core), and
    `App/Tests/AppTests/BrowserProviderMergeTests.swift` (App).
- **Patterns found:** Core is Foundation-only and exhaustively unit-tested; system access is
  behind protocols (`ProfileReading`, `ProfilePathResolving`). `BrowserFamily` is the lever
  every other component reads.
- **Dependencies identified:** `.other` is referenced in **four non-test source files** —
  `BrowserFamily.swift` (definition), `LaunchArguments.swift` (`case .safari, .other`),
  `WorkspaceBrowserProvider.swift` (filter line + `profileReader` switch), and comments in
  `BrowserLauncher.swift` — **plus three test files** that assert `.other` behavior and will
  break: `LaunchArgumentsTests.swift` (the co-located `BrowserFamilyTests` suite, lines
  35/40/47), `BrowserLauncherCommandTests.swift` (`testUnknownFamilyWithProfileIDUses…`,
  line 149), and `BrowserProviderMergeTests.swift` (the allowlist-filter test, exact-set
  assertion line 96). The two `switch` sites over `BrowserFamily` (`LaunchArguments.swift:37`,
  `WorkspaceBrowserProvider.swift:154`) make removal compile-safe in **sources**, but the
  test edits must be scheduled explicitly.
- **Compile-ordering note:** removing `case other` breaks the App's `case .safari, .other:`
  switches, so the **App target won't compile** until Task 2 fixes them. Therefore Task 1
  (Core) is gated by `task test-core` (the Core SPM package compiles + tests in isolation
  via `swift test`); all App-side compilation and test fixes — including the
  `BrowserLauncherCommandTests` breakage caused by Task 1's `LaunchArguments` change — live
  in Task 2, gated by the full `task test`.

### Verified browser facts

| Browser | Engine | Bundle ID | App Support sub-path | Confidence |
| ------- | ------ | --------- | -------------------- | ---------- |
| Arc | Chromium | `company.thebrowser.Browser` | `Arc/User Data` | Bundle ID verified; profile layout pending device check |
| Zen | **Firefox** | `app.zen-browser.zen` | `zen` | High (bundle ID verified); path needs device check |
| Comet | Chromium | `ai.perplexity.comet` *(likely)* | `Comet/User Data` *(likely)* | Medium — verify on device |
| Dia | Chromium | `company.thebrowser.dia` *(likely)* | `Dia/User Data` *(likely)* | Medium — verify on device |

Unverified bundle IDs/paths do **not** block the core fix — those browsers still launch via
the Chromium default; only their profile discovery depends on a correct path. See
Post-Completion for the device-verification step.

## Development Approach

- **Testing approach:** **TDD (tests first)** — mandated by `CLAUDE.md` for Core changes
  (write the failing test, then implement; all tests pass before moving on).
- Complete each task fully before the next; small, focused changes.
- **CRITICAL: every task includes new/updated tests** (success + edge cases) as separate
  checklist items.
- **CRITICAL: all tests pass before starting the next task.**
- Keep Core free of system dependencies (the no-AppKit import guard in `task test-core`
  must stay green).
- Keep `task lint` clean.
- Update this plan if scope changes during implementation.

## Testing Strategy

- **Unit tests:** required every task. Core via `task test-core` (fast `swift test` loop);
  App via `task test` (`xcodebuild test`).
- **No e2e harness** in this project — manual verification of real-browser launching is
  captured under Post-Completion.

## Progress Tracking

- Mark completed items `[x]` immediately.
- New tasks: `➕` prefix. Blockers: `⚠️` prefix.
- Keep the plan in sync with actual work.

## Solution Overview

The change is conceptually a single move — **make `.chromium` the default family** — that
cascades through every `BrowserFamily` consumer:

1. `BrowserFamily(bundleID:)` fallback → `.chromium`; the `.other` case is deleted; Zen is
   added to the Firefox set.
2. `LaunchArguments` and `WorkspaceBrowserProvider.profileReader(for:)` switches drop
   `.other` from their `case .safari, .other` arms (unknown bundle IDs now hit `.chromium`,
   getting Chromium-style launch + the Chrome profile reader).
3. `BrowserMerger`'s `guard family != .other` filter becomes dead code and is removed —
   every non-self http handler is now listed.
4. `ProfilePathResolver` gains sub-paths for Arc/Comet/Dia/Zen so the named browsers get
   real profile discovery (unknown browsers resolve to `nil` → empty profiles → launch
   default, which is fine).

## Technical Details

- **`BrowserFamily` enum:** remove `case other`. `init(bundleID:)` else-branch sets
  `self = .chromium`. Add `app.zen-browser.zen` to `firefoxBundleIDs`. Update the doc
  comment (the "everything unknown is treated like Safari" line is now false).
- **`LaunchArguments.build`:** `case .safari, .other` → `case .safari`. Chromium arm
  unchanged; unknown families now produce `["--profile-directory=<dir>", url]` **only when a
  profileID is present** — and unknown browsers carry no profileID, so they still emit
  `[url]`. No regression for profile-less launches.
- **`BrowserMerger.merge`:** delete the `guard family != .other else { return nil }` line
  and update the surrounding doc comment (it no longer "filters non-browser http handlers").
- **`WorkspaceBrowserProvider.profileReader(for:)`:** `case .safari, .other` → `case
  .safari` (returns `NoProfilesReader`); `.chromium` arm already returns
  `ChromeProfileReader`, which now also serves unknown browsers.
- **`ProfilePathResolver.subPathsByBundleID`:** add
  `"company.thebrowser.Browser": "Arc/User Data"`,
  `"ai.perplexity.comet": "Comet/User Data"`,
  `"company.thebrowser.dia": "Dia/User Data"` (Chromium), and
  `"app.zen-browser.zen": "zen"` (Firefox). Verify the latter three on a real device.

## What Goes Where

- **Implementation Steps** (checkboxes): all code + test changes in this repo.
- **Post-Completion** (no checkboxes): device verification of unverified bundle IDs/paths
  and real-browser launch smoke tests.

## Implementation Steps

### Task 1: Make Chromium the default family; classify Zen as Firefox (Core)

**Files:**
- Modify: `TrafficWandCore/Sources/TrafficWandCore/Browsers/BrowserFamily.swift`
- Modify: `TrafficWandCore/Sources/TrafficWandCore/Browsers/LaunchArguments.swift`
- Modify: `TrafficWandCore/Tests/TrafficWandCoreTests/LaunchArgumentsTests.swift`

> Note: `BrowserFamily` **is already tested** by a `BrowserFamilyTests` suite **co-located
> inside `LaunchArgumentsTests.swift`** (lines 5–49). Update that suite **in place** — do
> **not** create a new `BrowserFamilyTests.swift` (it would be a duplicate-type compile
> error). Three of its tests currently assert `== .other` (`unknownBundleID` line 35,
> `emptyBundleID` line 40, `caseSensitiveMapping` line 47) and will fail to compile once the
> case is deleted.

- [x] update the `BrowserFamilyTests` suite in `LaunchArgumentsTests.swift`: change the three
      `== .other` expectations (lines 35, 40, 47) to `== .chromium`; add a new assertion that
      `app.zen-browser.zen` maps to `.firefox`; leave Safari/Chrome/Edge/Brave/Vivaldi/
      Chromium/Firefox assertions unchanged — **these fail first (TDD)**
- [x] update the `LaunchArgumentsTests` suite: an unknown bundle ID **with** a profileID now
      emits `["--profile-directory=<id>", url]`; an unknown bundle ID **without** a profile
      still emits `[url]`; Zen with a profile emits `["-P", <name>, url]` — **fail first**
- [x] in `BrowserFamily.swift`: add `"app.zen-browser.zen"` to `firefoxBundleIDs`; change
      the `init` else-branch to `self = .chromium`; remove `case other` **and** its doc
      lines (19–20); update the type/`init` doc comments (no longer "unknown ⇒ Safari")
- [x] in `LaunchArguments.swift`: change `case .safari, .other:` to `case .safari:`; fix the
      stale header doc line 13 ("Safari, unknown families, or any target without a profile →
      `["<url>"]`") — unknown families are Chromium now and **do** get a profile flag when a
      profileID is present
- [x] run `task test-core` — all Core tests + the no-AppKit import guard must pass before
      Task 2 (the App target intentionally does **not** compile yet — its `.other` switches
      are fixed in Task 2)

### Task 2: List unknown browsers, read their profiles as Chromium, restore App compilation (App)

This task fixes the two App-side `case .safari, .other:` switches (restoring compilation
after Task 1 deleted the case), relaxes the picker filter, and updates **all** App tests
that asserted `.other` behavior — including the launcher test that Task 1's `LaunchArguments`
change breaks.

**Files:**
- Modify: `App/Sources/Adapters/WorkspaceBrowserProvider.swift`
- Modify: `App/Sources/Adapters/BrowserLauncher.swift` *(comments only)*
- Modify: `App/Tests/AppTests/BrowserProviderMergeTests.swift`
- Modify: `App/Tests/AppTests/BrowserLauncherCommandTests.swift`

- [x] update `BrowserProviderMergeTests`: rewrite
      `testMergeFiltersNonBrowserHTTPHandlerByAllowlist` → an unknown http handler
      (`com.example.SomeMailApp`) is now **listed** and classified `.chromium`; update the
      exact-set assertion (line 96) to **include** `com.example.SomeMailApp`, and invert/
      remove the `XCTAssertFalse(ids.contains(...))` at line 94; keep self-exclusion and
      dedup assertions — **fail first (TDD)**
      (renamed to `testMergeListsUnknownHTTPHandlerAsChromium`)
- [x] update `BrowserLauncherCommandTests`: rename/repurpose
      `testUnknownFamilyWithProfileIDUsesPlainOpenWithoutNewInstance` → an unknown browser
      **with** a profileID now emits the Chromium new-instance path
      (`-n -a <app> --args --profile-directory=ignored <url>`, i.e. **contains** `-n` and
      `--args`); fix its stale "Same guard for `.other`" comment; leave the **no-profile**
      variant (`testUnknownFamilyNoProfileUsesPlainOpenWithoutNewInstance`) green — **fail
      first (TDD)**
      (renamed to `testUnknownFamilyWithProfileIDUsesChromiumNewInstancePath`)
- [x] add a test: an unknown browser with **no** resolver path → empty profiles, still
      listed (graceful degradation)
      (`testMergeListsUnknownBrowserWithNoResolverPathAndEmptyProfiles`)
- [x] in `WorkspaceBrowserProvider.swift`: remove the
      `guard family != .other else { return nil }` line in `BrowserMerger.merge` and update
      the enum/merge doc comments (no allowlist filter; only self-exclusion + dedup remain)
- [x] in `WorkspaceBrowserProvider.swift`: change `profileReader(for:)`'s
      `case .safari, .other:` to `case .safari:` (the `.chromium` arm already covers
      unknowns via `ChromeProfileReader`)
- [x] in `BrowserLauncher.swift`: refresh the stale `.other` references in the doc comments
      (lines 32, 45, 67, 78) — they describe `.other` as Safari-like; unknown is now Chromium
- [x] run `task test` — App now compiles again; all App + Core tests must pass before Task 3

### Task 3: Add Application Support paths for Arc, Comet, Dia, Zen (App)

**Files:**
- Modify: `App/Sources/Adapters/ProfilePathResolver.swift`
- Modify: `App/Tests/AppTests/BrowserProviderMergeTests.swift`

- [x] update `ProfilePathResolver` tests: add cases asserting the new sub-paths —
      `company.thebrowser.Browser` → `Arc/User Data`, `ai.perplexity.comet` →
      `Comet/User Data`, `company.thebrowser.dia` → `Dia/User Data`,
      `app.zen-browser.zen` → `zen` — **fail first (TDD)**
- [x] in `ProfilePathResolver.swift`: add the four entries to `subPathsByBundleID` (group +
      comment the three Chromium newcomers and the one Firefox-family entry; note the
      Comet/Dia/Zen paths are pending device verification)
- [x] keep the existing "unknown bundle ID → nil" test green (a truly unknown browser still
      resolves to `nil` → empty profiles → launches default)
- [x] run `task test` — all tests must pass before the next task

### Task 4: Verify acceptance criteria

- [x] verify Arc, Dia, Comet are listed in the picker and launch (Chromium family)
      (manual — requires installed browsers + clicking the picker; not automatable in this
      headless environment; classification and profile-path resolution covered by the unit
      tests added in Tasks 1–3)
- [x] verify Zen is listed, classified Firefox, and launches with `-P` when a profile is set
      (manual — requires installed Zen + a configured profile; not automatable here;
      Firefox classification of `app.zen-browser.zen`, `-P` launch args, and `zen` support
      path are covered by the unit tests added in Tasks 1–3)
- [x] verify a hypothetical unknown browser is listed and launches as Chromium (covered by
      the unit tests added in Tasks 2–3: `testMergeListsUnknownHTTPHandlerAsChromium`,
      `testMergeListsUnknownBrowserWithNoResolverPathAndEmptyProfiles`, and
      `testUnknownFamilyWithProfileIDUsesChromiumNewInstancePath`; real-browser check is in
      Post-Completion)
- [x] run the full suite: `task` (generate + build + lint + test-core + test) — **passed**:
      Core 129 tests / 14 suites, 0 failures; App 130 tests, 0 failures; build + lint clean
      (** TEST SUCCEEDED **)
- [x] confirm `task lint` is clean and the no-AppKit guard passes — **`task lint` exit 0,
      no SwiftLint violations**; no-AppKit import guard (part of `task test-core`) passed
      (grep found no AppKit imports in Core)

### Task 5: [Final] Update documentation

- [x] CLAUDE.md reviewed — no inaccurate BrowserFamily description found (only lists the type by name)
- [x] move this plan to `docs/plans/completed/`

## Post-Completion

*Items requiring manual intervention or external systems — informational only.*

**Device verification (do before/at release):**
- Confirm the **bundle IDs** for Comet (`ai.perplexity.comet`?) and Dia
  (`company.thebrowser.dia`?) by inspecting the installed `.app`'s `Info.plist`
  (`mdls -name kMDItemCFBundleIdentifier /Applications/Comet.app`). Correct
  `ProfilePathResolver` / `BrowserFamily` entries if they differ. *(Wrong values only cost
  profile discovery — the browser still launches via the Chromium default.)*
- Confirm the **Application Support sub-paths** for Comet, Dia, and Zen by checking for
  `Local State` (Chromium) / `profiles.ini` (Zen) under the candidate directories.
- Smoke-test launching each of Arc/Dia/Comet/Zen from the picker, with and without a profile
  selected, and confirm the URL opens in the correct browser/profile.

**Picker-noise check:**
- On a machine with non-browser http handlers installed, confirm the picker list stays
  reasonable. If a specific non-browser app shows up and is undesirable, consider a tiny
  denylist (out of scope for this issue).
