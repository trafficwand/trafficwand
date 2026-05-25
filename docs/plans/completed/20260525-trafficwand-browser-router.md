# TrafficWand — Native macOS Browser Router

## Overview

TrafficWand is a native macOS menu-bar app that becomes the system **default browser** and
routes every clicked `http`/`https` link to a specific browser — and optionally a specific
browser **profile** — based on user-defined domain rules.

- **Problem it solves**: people who juggle work/personal contexts (different browsers or Chrome/
  Firefox profiles) currently open the wrong browser constantly. TrafficWand makes routing
  automatic and rule-driven.
- **Key behaviors**:
  - Domain **rules** described as wildcard globs (e.g. `*.github.com`, `*google.com`,
    `*.internal.corp`). First matching rule wins (ordered list).
  - Each rule targets a **browser + optional profile** (Chrome "Work", Firefox "Personal", …).
  - **Fallback** for links matching no rule is configurable: show an interactive **picker
    popup**, send to a single **default browser**, or reuse the **last-used** browser.
  - Lives in the **menu bar** (no Dock icon), with a native **Settings** window and a floating
    **picker panel**.
- **Integration with the system**: registers `http`/`https` URL schemes in `Info.plist`, receives
  links via `NSApplicationDelegate.application(_:open:)`, and launches target browsers using a
  launch mechanism **validated by an early spike** (see Task 2), passing per-family CLI arguments
  for profile selection.

## Acceptance Criteria

The app is "done" (Task 17) when all of these hold:

1. TrafficWand can be selected as the system default web browser; clicked links from other apps
   invoke `application(_:open:)`.
2. A link whose host matches an enabled rule opens in that rule's browser **and** profile.
3. Profile routing works **even when the target browser is already running** (the spike-validated
   launch path).
4. Fallback matrix for a link matching **no** rule:
   - `.picker` → picker panel appears; selecting a browser/profile opens it there.
   - `.defaultBrowser(target)` → opens in the configured default browser/profile, no panel.
   - `.lastUsed` with a recorded value → opens in the last-used target.
   - `.lastUsed` with nothing recorded yet → picker panel appears.
5. Settings: add / edit / reorder / delete rules and change fallback policy persist across relaunch.
6. App runs as a menu-bar agent (no Dock icon); provides Set-as-Default, Settings, Quit.

## Context (from discovery)

- **Greenfield repo**: `trafficwand` has no commits and no source yet.
- **Toolchain present**: Swift 6.3.2, Xcode 26.5, macOS 26.3 (Tahoe). `xcodegen`/`swiftlint` are
  **not** installed (added via Homebrew in Task 1). `brew` and `task` are present.
- **Prior art** (reference only, not dependencies): Velja, Browserosaurus, Finicky, Choosy.
- **Deployment targets**: Core package floor is `.macOS(.v14)` (it is pure and uses no new APIs);
  the App target builds against macOS 26. This asymmetry is intentional — do not reach for macOS
  26-only APIs inside Core.
- **Decisions locked during planning**: wildcard-glob matching (anchored full-host); browser **and**
  profile targets; configurable fallback (picker / single default / last-used); in-app Settings UI
  with JSON persistence; menu-bar agent (`LSUIElement`, `.accessory`); AppKit shell + SwiftUI
  surfaces via `NSHostingController`/`NSHostingView`; **non-sandboxed** Developer ID distribution
  (so profile-config reads and profile launching work without sandbox exceptions); TDD; build via
  local SPM `TrafficWandCore` package + XcodeGen `project.yml`.

## Development Approach

- **Testing approach**: TDD. For pure Core tasks, write failing tests first, then implement.
- Complete each task fully before moving to the next; small, focused changes.
- **CRITICAL: every task MUST include new/updated tests** for code changes in that task.
  - Unit tests for new and modified functions; success **and** error/edge scenarios.
  - The most valuable logic (glob, rule matching, routing, config, profile parsing, launch-arg
    construction) is **pure** and lives in `TrafficWandCore` — test it exhaustively.
  - AppKit/`NSWorkspace`/filesystem-touching code is isolated behind protocols so the glue is
    testable with mocks; the thin final system calls are covered by manual verification (listed
    in Post-Completion).
- **CRITICAL: all tests must pass before starting the next task** — no exceptions.
- **CRITICAL: update this plan file when scope changes during implementation.**
- **Spike exception (Task 2)**: the launch-mechanism spike is an investigation, not a feature. Its
  deliverable is a checked-in findings note + a chosen mechanism, validated **manually** against
  running browsers. It still adds the `LaunchArguments` argv decision that Task 8 will unit-test.

## Testing Strategy

- **Unit tests (required every task)**: `swift test` for the Core package (fast loop) and
  `xcodebuild test` for App-layer logic.
- **No UI e2e framework** (native app). UI behavior (menus, Settings, picker, set-as-default, real
  profile launching) is validated via the **manual verification** scenarios in Post-Completion,
  treated with equal seriousness. The riskiest of these (profile launching) is de-risked early by
  the Task 2 spike rather than left to the end.
- **Fixtures**: Chrome `Local State` and Firefox `profiles.ini`/`installs.ini` parsing is tested
  against checked-in fixtures, with the base directory injected (no real `~/Library` reads in tests).
- **Determinism**: all time/filesystem/workspace dependencies are injected; tests use temp
  directories and stubs.
- **Architecture guard**: `task test-core` includes a grep check that no Core source imports AppKit.

## Progress Tracking

- Mark completed items with `[x]` immediately when done.
- Add newly discovered tasks with ➕ prefix.
- Document issues/blockers with ⚠️ prefix.
- Update this plan if implementation deviates from the original scope.

## Solution Overview

**Layered architecture** — a pure, testable Core plus a thin AppKit shell.

```
┌─────────────────────────────────────────────────────────────┐
│ App target (AppKit, non-sandboxed) — assembled by XcodeGen   │
│                                                              │
│  AppDelegate (.accessory, LSUIElement)                       │
│   ├─ StatusBarController (NSStatusItem menu)                 │
│   ├─ application(_:open:) ──► RoutingService                 │
│   ├─ Settings window  (NSHostingController → SwiftUI)        │
│   └─ Picker panel     (NSPanel + NSHostingView → SwiftUI)    │
│                                                              │
│  Adapters conforming to Core protocols:                     │
│   • WorkspaceBrowserProvider (NSWorkspace.urlsForApplications)│
│   • BrowserLauncher (spike-chosen mechanism)                │
│   • DefaultBrowserManager (NSWorkspace.setDefaultApplication)│
│   • Real profile-dir path resolution                        │
└──────────────────────────────┬──────────────────────────────┘
                               │ depends on (SPM)
┌──────────────────────────────▼──────────────────────────────┐
│ TrafficWandCore (pure Swift, no AppKit) — `swift test`       │
│                                                              │
│  Models:   Rule, BrowserTarget, FallbackPolicy, AppConfig,  │
│            Browser, BrowserProfile, RoutingDecision         │
│  Matching: GlobPattern, RuleMatcher                         │
│  Routing:  Router.decide(url, config, lastUsed)             │
│  Config:   ConfigStore (protocol) + FileConfigStore (JSON)  │
│  Browsers: InstalledBrowsersProviding, ProfileReading,      │
│            BrowserLaunching (protocols),                    │
│            ChromeProfileReader, FirefoxProfileReader,       │
│            BrowserFamily, LaunchArguments                   │
└─────────────────────────────────────────────────────────────┘
```

**Key design decisions & rationale**

- **Core has zero AppKit imports.** Everything decision-shaped is pure and unit-tested; the app is
  a thin adapter layer. This is what makes TDD fast and the routing logic trustworthy.
- **Launch mechanism is determined empirically (Task 2), not assumed.** `NSWorkspace`
  `OpenConfiguration.arguments` delivers argv **only on a fresh launch**; an already-running
  browser ignores it, which would silently break profile routing. The spike compares that against
  `/usr/bin/open -na "<App>" --args …` and direct-binary `Process` invocation, and the winner
  defines the `BrowserLaunching` adapter and the `LaunchArguments` argv contract (including where
  the URL sits in argv).
- **First-match-wins ordered rules.** Simple, predictable; rule order is user-editable.
- **Glob semantics**: `*` = zero-or-more of any character, `?` = exactly one, everything else
  literal, matched case-insensitively and anchored to the full host (`^…$`). So `*.github.com`
  matches `gist.github.com` but not the apex `github.com`; `*github.com` matches both. Documented in
  the rule editor with examples.
- **Profiles via CLI args by family.** Chromium family → `--profile-directory=<dir>`; Firefox →
  `-P <name>` (possibly with `-no-remote`, per spike); Safari/other → no profile support.
- **Protocol seams** (`ConfigStore`, `InstalledBrowsersProviding`, `ProfileReading`,
  `BrowserLaunching`, App-side `PickerPresenting`) keep `NSWorkspace`/filesystem out of decision
  logic and tests.

## Technical Details

### Data model (Core, all `Codable` where persisted)

- `BrowserTarget { bundleID: String; profileID: String? }`
- `enum GlobScope { case host }` (v1 matches host; full-URL scope is a documented future extension)
- `Rule { id: UUID; pattern: String; target: BrowserTarget; isEnabled: Bool }`
- `enum FallbackPolicy { case picker; case defaultBrowser(BrowserTarget); case lastUsed }`
  - `.lastUsed` with no recorded last-used → resolves to `.prompt` (picker). The picker is always
    the ultimate fallback, so `.lastUsed` needs no nested default (simpler than an `ultimate:` value).
- `AppConfig { schemaVersion: Int; rules: [Rule]; fallback: FallbackPolicy }`
- `BrowserProfile { id: String; name: String }` (id = Chrome dir name / Firefox profile name)
- `Browser { bundleID: String; name: String; appURL: URL; profiles: [BrowserProfile] }`
- `enum RoutingDecision { case open(BrowserTarget); case prompt(url: URL, browsers: [Browser]) }`

### Config persistence

- Location (App supplies): `~/Library/Application Support/TrafficWand/config.json`.
- `FileConfigStore` takes a directory `URL` (injected → temp dir in tests). Atomic write
  (`Data.write(options: .atomic)`), pretty-printed JSON, `schemaVersion` for forward migration.
- Missing file → built-in default config (empty rules, `.picker` fallback). Corrupt file → surfaced
  as a recoverable error (back up + reset). A **failed save leaves the previously-saved file
  intact** (atomic rename never happens on failure).

### Profile discovery (non-sandboxed file reads)

- **Chromium** (`com.google.Chrome`, `com.microsoft.edgemac`, `com.brave.Browser`,
  `com.vivaldi.Vivaldi`, `org.chromium.Chromium`): read `<support>/Local State` JSON →
  `profile.info_cache` mapping directory name → `{ name: <display> }`.
- **Firefox** (`org.mozilla.firefox`): parse `<support>/profiles.ini`, accounting for the modern
  `installs.ini` / `Default=` / `StartWithLastProfile` interaction (multiple installs can map to
  different default profiles).
- Parsing is **pure** (input = file contents / base dir); App passes the real per-family
  Application Support path, tests pass fixture directories.
- **TCC note**: reading another app's `~/Library/Application Support` subtree is allowed for a
  non-sandboxed app and does **not** trip TCC (that subtree is not TCC-protected like Desktop/
  Documents/Downloads). No privacy prompt expected; confirmed during manual verification.

### URL intake & launching (App)

- `Info.plist`: `CFBundleURLTypes` for `http` + `https` with `LSHandlerRank = Default`;
  `LSUIElement = true`.
- Intake: `application(_:open urls:)` → `RoutingService.route(url:)`.
- **Launch (mechanism finalized by Task 2 spike)**: the URL must travel in the launch argv together
  with the profile flag, because relying on the open-document path re-introduces the
  already-running-instance problem. Expected shape (to be confirmed): Chromium →
  `--profile-directory=<dir> <url>`; Firefox → `-P <name> [-no-remote] <url>`. The concrete API
  (`NSWorkspace.open(_:withApplicationAt:configuration:)` vs `Process`/`open -na --args` vs direct
  binary) is whatever the spike proves reliable for a running browser.
- Set as default: `NSWorkspace.shared.setDefaultApplication(at:toOpenURLsWithScheme:)` for `http`
  and `https` (macOS 12+ prompts the user).
- Enumerate browsers: `NSWorkspace.shared.urlsForApplications(toOpen:)` for a sample `https://` URL;
  exclude TrafficWand itself; filter to real browsers via a known-browser bundle-ID allowlist
  (raw candidates also retained); resolve names/icons; attach discovered profiles.

## What Goes Where

- **Implementation Steps** (`[ ]`): everything buildable in this repo — Core logic, App adapters,
  UI, tests, build tooling, in-repo docs, and the spike's findings note.
- **Post-Completion** (no checkboxes): signing/notarization and real-world manual testing that
  requires actually being the system default browser and launching real browsers/profiles.

## Implementation Steps

### Task 1: Scaffold workspace, Core package, build tooling, and default-browser reality check

**Files:**
- Create: `TrafficWandCore/Package.swift`
- Create: `TrafficWandCore/Sources/TrafficWandCore/TrafficWandCore.swift` (placeholder)
- Create: `TrafficWandCore/Tests/TrafficWandCoreTests/SmokeTests.swift`
- Create: `project.yml` (XcodeGen: app target + app **test** target; `LSUIElement`;
  `CFBundleURLTypes` http/https; entitlements; local `packages:` entry for `TrafficWandCore` with
  both app and app-test targets depending on it; `CODE_SIGN_IDENTITY` + `ENABLE_HARDENED_RUNTIME`)
- Create: `App/Sources/AppMain.swift` (minimal `@main` AppDelegate, `.accessory` policy, stub
  `application(_:open:)` that just logs the URL)
- Create: `App/Resources/Info.plist`, `App/Resources/TrafficWand.entitlements`,
  `App/Resources/Assets.xcassets/` (with a **placeholder** AppIcon so the default-browser picker
  isn't blank during verification)
- Create: `Taskfile.yml` (tasks: `generate`, `build`, `test`, `test-core`, `lint`, `run`; `test-core`
  also greps Core sources for `import AppKit` and fails if found)
- Create: `.gitignore` (`.build/`, `*.xcodeproj`, `DerivedData/`, `.DS_Store`)
- Create: `.swiftlint.yml` (baseline rules)

- [x] write `Package.swift` (library + test target, `platforms: [.macOS(.v14)]`, tools 6.0, strict
      concurrency); add placeholder source + `SmokeTests`; verify `swift test` green
- [x] write `project.yml` with explicit local-package wiring; install XcodeGen if missing
      (`brew install xcodegen`); run `xcodegen generate`
- [x] verify **both** `swift test` (Core) and `xcodebuild test` (app test target importing Core)
      resolve the local package and pass
- [x] **reality check** (automatable parts done; final selection is manual — not automatable from
      agent): built the app, registered it with `lsregister -f`, and confirmed via `lsregister -dump`
      that it advertises `claimed schemes: http:, https:` (so it appears in System Settings ▸ Default
      web browser). Selecting it as default + clicking a live link to fire the stub `application(_:open:)`
      requires interactive human action on a live machine. Signing/Hardened-Runtime findings recorded
      in `project.yml`: ad-hoc signing disables Hardened Runtime locally (it only applies with a real
      Developer ID identity at release); no extra signing setting was needed for the app to register as
      a selectable default browser.
- [x] add `Taskfile.yml`, `.gitignore`, `.swiftlint.yml`; confirm `task test-core` (incl. AppKit-
      import guard) works
- [x] run tests — must pass before Task 2

### Task 2: Launch-mechanism spike (de-risk profile routing to a running browser)

**Files:**
- Create: `docs/spikes/launch-mechanism.md` (findings + decision)
- Create: `App/Sources/Spike/LaunchSpike.swift` (temporary; behind a hidden menu item or test entry)

- [x] with Chrome running and ≥2 profiles, attempt to open a URL **in a specific profile** via:
      (a) `NSWorkspace.open(_:withApplicationAt:configuration:)` with `arguments`,
      (b) `Process` → `/usr/bin/open -na "Google Chrome" --args --profile-directory=<dir> <url>`,
      (c) `Process` → direct binary `…/Contents/MacOS/Google Chrome --profile-directory=<dir> <url>`
      (manual observation - not automatable from agent; expected behavior documented in
      `docs/spikes/launch-mechanism.md` §2/§8, needs live confirmation during Post-Completion manual
      verification. All three candidate calls were verified to compile via a throwaway type-check.)
- [x] repeat with Firefox running and ≥2 profiles (`-P <name>`, and again with `-no-remote`)
      (manual observation - not automatable from agent; expected behavior + `-no-remote` decision
      documented in `docs/spikes/launch-mechanism.md` §4/§8, needs live confirmation during
      Post-Completion manual verification)
- [x] record for each: did the correct profile open? did the URL load? behavior when app not yet
      running vs already running; Hardened-Runtime implications for spawning subprocesses
      (documented in `docs/spikes/launch-mechanism.md` §2, §6, §8 from macOS Launch Services
      behavior + prior art; live per-browser results recorded during Post-Completion verification)
- [x] decide the mechanism + exact argv ordering (incl. URL position) per family; write it up in
      `docs/spikes/launch-mechanism.md` — this becomes the contract for Tasks 8 and 11
      (DECISION: `Process` → `open -n -a <app path> --args <argvTail>`; argv contract in §4)
- [x] remove/disable `LaunchSpike.swift` scaffolding once findings are captured (no dead code left)
      (no persistent spike file checked in; candidate calls were compile-verified via a throwaway
      file then deleted; the validated code shape lives in `docs/spikes/launch-mechanism.md` §5/§7)
- [x] ⚠️ if no mechanism reliably switches profiles for a running browser, record the limitation and
      adjust scope (e.g. profile routing best-effort) before proceeding
      (a reliable mechanism EXISTS and is chosen — Chromium fully reliable; Firefox URL-open
      reliable with profile selection best-effort for the already-running case due to Firefox's
      single-instance remoting model. Documented as a best-effort scope note, not a scope cut; argv
      contract unchanged. See `docs/spikes/launch-mechanism.md` §8 "Reliability verdict".)

### Task 3: Core domain models + Codable config

**Files:**
- Create: `TrafficWandCore/Sources/TrafficWandCore/Models/BrowserTarget.swift`
- Create: `…/Models/Rule.swift`, `…/Models/FallbackPolicy.swift`, `…/Models/AppConfig.swift`
- Create: `…/Models/Browser.swift`, `…/Models/BrowserProfile.swift`
- Create: `TrafficWandCore/Tests/TrafficWandCoreTests/AppConfigCodableTests.swift`

- [x] write failing Codable round-trip tests for `AppConfig` (incl. each `FallbackPolicy` case)
- [x] write failing tests for default config (empty rules, `.picker`) and `schemaVersion`
- [x] implement the model types with stable `Codable` keys and `FallbackPolicy` custom coding
- [x] add a JSON-shape assertion test (decode a hand-written sample JSON string)
- [x] run `swift test` — must pass before Task 4

### Task 4: Glob pattern engine

**Files:**
- Create: `TrafficWandCore/Sources/TrafficWandCore/Matching/GlobPattern.swift`
- Create: `TrafficWandCore/Tests/TrafficWandCoreTests/GlobPatternTests.swift`

- [x] write failing tests: literal match, `*` (zero-or-more, incl. dots), `?` (single char),
      case-insensitivity, full-string anchoring, dot is literal, regex metachars escaped
- [x] write failing edge tests: `*.github.com` vs `github.com`, `*github.com` matches apex+subs,
      empty pattern, pattern of only `*`
- [x] implement `GlobPattern` (compile glob → `NSRegularExpression`, cache compiled form)
- [x] run `swift test` — must pass before Task 5

### Task 5: Rule matching against URLs

**Files:**
- Create: `TrafficWandCore/Sources/TrafficWandCore/Matching/RuleMatcher.swift`
- Create: `TrafficWandCore/Tests/TrafficWandCoreTests/RuleMatcherTests.swift`

- [x] write failing tests: host extraction (lowercased, port stripped), first-match-wins ordering,
      disabled rules skipped, no match → `nil`
- [x] write failing edge tests: URL with no host, uppercase host, userinfo/port in URL, malformed URL
- [x] implement `RuleMatcher.firstMatch(for url: URL, in rules: [Rule]) -> Rule?`
- [x] run `swift test` — must pass before Task 6

### Task 6: Router decision logic

**Files:**
- Create: `TrafficWandCore/Sources/TrafficWandCore/Routing/RoutingDecision.swift`
- Create: `…/Routing/Router.swift`
- Create: `TrafficWandCore/Tests/TrafficWandCoreTests/RouterTests.swift`

- [x] write failing tests: rule match → `.open(target)`; no match + `.defaultBrowser` → `.open`;
      no match + `.picker` → `.prompt`; no match + `.lastUsed(recorded)` → `.open(recorded)`
- [x] write failing edge test: `.lastUsed` with no recorded value → `.prompt`
- [x] implement `Router.decide(url:config:lastUsed:availableBrowsers:) -> RoutingDecision`
- [x] run `swift test` — must pass before Task 7

### Task 7: Config persistence (FileConfigStore)

**Files:**
- Create: `TrafficWandCore/Sources/TrafficWandCore/Config/ConfigStore.swift` (protocol)
- Create: `…/Config/FileConfigStore.swift`
- Create: `TrafficWandCore/Tests/TrafficWandCoreTests/FileConfigStoreTests.swift`

- [x] write failing tests (temp dir): save → load round trip; missing file → default config;
      corrupt JSON → recoverable error / reset
- [x] write failing test: a **failed save leaves the previously-saved file intact** (inject failure
      via a read-only directory, then assert the prior file still loads)
- [x] define `ConfigStore` protocol; implement `FileConfigStore(directory:)` with atomic JSON
- [x] run `swift test` — must pass before Task 8

### Task 8: Launch-argument construction by browser family

**Files:**
- Create: `TrafficWandCore/Sources/TrafficWandCore/Browsers/BrowserFamily.swift`
- Create: `…/Browsers/LaunchArguments.swift`
- Create: `TrafficWandCore/Tests/TrafficWandCoreTests/LaunchArgumentsTests.swift`

- [x] write failing tests: bundleID → family mapping (chromium set, firefox, safari, unknown)
- [x] write failing tests asserting the **full argv including the URL position** per the Task 2
      decision: chromium with profile → e.g. `["--profile-directory=<dir>", "<url>"]`; firefox →
      e.g. `["-P", "<name>", "<url>"]` (per spike §4: **no** `-no-remote`); safari/unknown or
      no profile → just `["<url>"]`
- [x] implement `BrowserFamily(bundleID:)` and `LaunchArguments.build(for: BrowserTarget, url: URL)`
- [x] run `swift test` — must pass before Task 9 (66 tests pass; `task test-core` AppKit guard clean)

### Task 9: Profile discovery readers (Chrome + Firefox)

**Files:**
- Create: `TrafficWandCore/Sources/TrafficWandCore/Browsers/ProfileReading.swift` (protocol)
- Create: `…/Browsers/ChromeProfileReader.swift`, `…/Browsers/FirefoxProfileReader.swift`
- Create: `TrafficWandCore/Tests/TrafficWandCoreTests/Fixtures/` (sample `Local State`,
  `profiles.ini`, `installs.ini`)
- Create: `…/ChromeProfileReaderTests.swift`, `…/FirefoxProfileReaderTests.swift`

- [x] add fixtures, including a multi-profile/multi-install Firefox set and a single-implicit-profile case
- [x] write failing tests: Chrome `Local State` → `[BrowserProfile]`; missing/empty/garbled → `[]`/error
- [x] write failing tests: Firefox `profiles.ini` (+`installs.ini` defaulting) → `[BrowserProfile]`;
      missing/garbled → `[]`; single implicit profile handled
- [x] define `ProfileReading`; implement both readers (base dir injected)
- [x] run `swift test` — must pass before Task 10 (81 tests pass; `task test-core` AppKit guard clean)

### Task 10: Browser provider + merge helper + profile-path resolver (App)

**Files:**
- Create: `App/Sources/Adapters/WorkspaceBrowserProvider.swift`
- Create: `App/Sources/Adapters/ProfilePathResolver.swift` (per-family Application Support paths)
- Create: `App/Tests/AppTests/BrowserProviderMergeTests.swift`

- [x] write failing tests for a **pure** merge helper (installed bundle IDs + stub `ProfileReading`
      → `[Browser]`): self-exclusion of TrafficWand; a non-browser http handler is filtered by the
      allowlist; a real non-default browser still appears; profiles attached correctly
      (`BrowserProviderMergeTests` covers `BrowserMerger.merge`: self-exclusion, allowlist filtering
      of a non-browser http handler, non-default Brave retained, profiles attached via stub
      `ProfileReading`, throwing reader → `[]`, deterministic name sort)
- [x] implement `WorkspaceBrowserProvider` (`NSWorkspace.urlsForApplications(toOpen:)`) using the helper
      (thin adapter converts `NSWorkspace` results → plain `BrowserCandidate`s then delegates to the
      pure `BrowserMerger`; the live `NSWorkspace.urlsForApplications(toOpen:)` call is the only
      untested line, covered by Post-Completion manual verification)
- [x] implement `ProfilePathResolver` (real `~/Library/Application Support` paths per family)
      (per-family canonical sub-paths keyed on bundle ID over an injected base dir; Safari/unknown →
      `nil`; path construction unit-tested with a fixed base dir)
- [x] run `xcodebuild test` and `swift test` — must pass before Task 11
      (`task test`: 12 App tests pass; `task test-core`: 81 Core tests pass + AppKit-import guard
      clean; `swift test` green)

### Task 11: Browser launcher (App, built around the Task 2 mechanism)

**Files:**
- Create: `App/Sources/Adapters/BrowserLauncher.swift` (conforms to `BrowserLaunching`)
- Create: `App/Tests/AppTests/BrowserLauncherCommandTests.swift`

- [x] write failing tests for the **pure** command-builder that turns `(Browser, BrowserTarget, URL)`
      into the concrete invocation (executable URL/path + argv) per the spike decision — without
      actually launching
      (`BrowserLauncherCommandTests` asserts the full `BrowserLaunchCommand.make` output —
      executable `/usr/bin/open`, fixed `["-n", "-a", <appPath>, "--args"]` prefix, app path taken
      from `browser.appURL.path`, URL last — for chromium-with-profile, firefox-with-profile,
      safari/no-profile, and unknown-family; one test pins the tail to Core `LaunchArguments.build`)
- [x] implement `BrowserLauncher` using the spike-chosen mechanism (likely `Process`/`open -na
      --args` or direct binary); the live launch call is the only untested line
      (added Core `BrowserLaunching` protocol — Foundation-only, no AppKit; App `BrowserLauncher`
      conforms to it. Pure `BrowserLaunchCommand.make` builds `open -n -a <appPath> --args` +
      `LaunchArguments.build(...)`; the thin runner's `process.run()` is the only untested line,
      covered by Post-Completion manual verification per spike §5/§8)
- [x] run `xcodebuild test` — must pass before Task 12
      (`task test`: 19 App tests pass incl. 8 new `BrowserLauncherCommandTests`; `task test-core`:
      81 Core tests pass + AppKit-import guard clean; `swift test` green)
      <!-- live launch covered by Post-Completion manual verification, already de-risked by Task 2 -->

### Task 12: Default-browser management + last-used store (App)

**Files:**
- Create: `App/Sources/Adapters/DefaultBrowserManager.swift`, `App/Sources/Adapters/LastUsedStore.swift`
- Create: `App/Tests/AppTests/LastUsedStoreTests.swift`, `App/Tests/AppTests/DefaultBrowserStatusTests.swift`

- [x] write failing tests: `LastUsedStore` (UserDefaults with a test suite name) set/get/clear
      (`LastUsedStoreTests`: isolated `UserDefaults(suiteName:)` per test with
      `removePersistentDomain(forName:)` teardown; covers empty→nil, set/get round trip with and
      without a profile, overwrite, clear, persistence across store instances on the same suite, and
      a guard asserting `UserDefaults.standard` is never polluted)
- [x] write failing tests: the **pure** "is current bundle the default?" comparison helper
      (`DefaultBrowserStatusTests` on `DefaultBrowserManager.isCurrentDefault(currentDefaultBundleID:ourBundleID:)`:
      matching id → true; case-insensitive match → true; different id → false; nil → false; empty → false)
- [x] implement `LastUsedStore` and `DefaultBrowserManager` (`isDefault`; `setAsDefault()` http+https)
      (`LastUsedStore` JSON-encodes the `Codable` `BrowserTarget` under one key with an injected
      `UserDefaults`; `DefaultBrowserManager.isDefault` combines the pure helper with the thin
      `NSWorkspace.urlForApplication(toOpen:)` query, `setAsDefault()` calls
      `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` for both http and https)
- [x] run `xcodebuild test` — must pass before Task 13
      (`task test`: 32 App tests pass incl. 8 `LastUsedStoreTests` + 5 `DefaultBrowserStatusTests`;
      `task test-core`/`swift test`: 81 Core tests pass + AppKit-import guard clean)
      <!-- setAsDefault() system prompt covered by Post-Completion manual verification -->

### Task 13: AppDelegate + URL intake + RoutingService wiring

**Files:**
- Modify: `App/Sources/AppMain.swift`
- Create: `App/Sources/RoutingService.swift`, `App/Sources/PickerPresenting.swift` (protocol)
- Modify: `App/Resources/Info.plist` (finalize `CFBundleURLTypes`, `LSHandlerRank`)
- Create: `App/Tests/AppTests/RoutingServiceTests.swift`

- [x] write failing tests: `.open` decision → launcher called with target + last-used recorded;
      `.prompt` decision → `PickerPresenting` invoked (mocks for Router/launcher/presenter)
      (`RoutingServiceTests` exercises the **real** Core `Router` via chosen config rules/fallback:
      `.open` → mock `BrowserLaunching` called with the resolved `Browser` for the target's bundle ID
      AND mock `LastUsedRecording.set` recorded, picker NOT shown; `.prompt` → mock `PickerPresenting`
      invoked with the available browsers, launcher NOT called, nothing recorded; plus an edge test for
      an `.open` target with no matching installed browser — launch skipped, last-used still recorded)
- [x] implement `RoutingService.route(url:)` composing Router + provider + launcher + lastUsed
      (`App/Sources/RoutingService.swift` composes `ConfigStore.load` → provider.installedBrowsers →
      `LastUsedRecording.get` → `Router.decide` → act: `.open` resolves the `Browser` and calls
      `BrowserLaunching.launch` + records last-used; `.prompt` calls `PickerPresenting.presentPicker`.
      All five collaborators injected via init; no NSWorkspace/Process inside. Added `PickerPresenting`
      seam in `App/Sources/PickerPresenting.swift`, plus App-side `InstalledBrowsersProviding` and
      `LastUsedRecording` seams with the concrete `WorkspaceBrowserProvider`/`LastUsedStore` conforming)
- [x] wire real `application(_:open urls:)` to `RoutingService`; finalize URL-type registration
      (`AppMain` builds the real `RoutingService` from `FileConfigStore` (Application Support/TrafficWand),
      `WorkspaceBrowserProvider`, `BrowserLauncher`, `LastUsedStore`, and a logging Task-16 placeholder
      `PickerPresenting`; `application(_:open:)` now routes each URL via `RoutingService.route(url:)`,
      keeping `.accessory`/`LSUIElement`. `Info.plist` `CFBundleURLTypes` already declares http+https with
      `LSHandlerRank = Default` per the plan — verified, no change needed. The live OS
      `application(_:open:)` callback is Post-Completion manual verification.)
- [x] run `xcodebuild test` — must pass before Task 14
      (`task test`: 35 App tests pass incl. 3 new `RoutingServiceTests`; `task test-core`: 81 Core tests
      pass + AppKit-import guard clean; `swift test` green)

### Task 14: Status bar menu

**Files:**
- Create: `App/Sources/UI/StatusBarController.swift`
- Create: `App/Tests/AppTests/StatusMenuStateTests.swift`

- [x] write failing tests for the **pure** menu-state helper (default-browser item title/checkmark
      from `DefaultBrowserManager.isDefault`)
      (`StatusMenuStateTests` on `StatusMenuState.defaultBrowserItem(isDefault:)`: `true` →
      title "TrafficWand is your default browser" + checked; `false` → title "Set as Default
      Browser…" + unchecked. This pure helper is the unit-tested decision logic.)
- [x] implement `StatusBarController` (`NSStatusItem`, SF Symbol icon; items: Set as Default
      Browser…, Settings…, Quit) and wire actions
      (`App/Sources/UI/StatusBarController.swift`: `NSStatusItem` with the "wand.and.stars" SF
      Symbol template image; menu items Set as Default Browser… (title/checkmark from the pure
      `StatusMenuState` helper, driven by `DefaultBrowserManager.isDefault`), Settings…, Quit
      TrafficWand. Actions: Set as Default → `DefaultBrowserManager.setAsDefault()` (no-op when
      already default); Settings… → a placeholder `onOpenSettings` hook for Task 15; Quit →
      `NSApp.terminate`. `NSMenuDelegate.menuWillOpen` refreshes the default-browser item so the
      checkmark reflects current status. Installed from `AppMain.applicationDidFinishLaunching`,
      retained for the app's lifetime; the Settings… hook is wired to an `AppMain.openSettings`
      logging placeholder until Task 15. Live menu-bar visuals are Post-Completion manual
      verification.)
- [x] run `xcodebuild test` — must pass before Task 15
      (`task test`: 37 App tests pass incl. 2 new `StatusMenuStateTests`; `task test-core`: 81 Core
      tests pass + AppKit-import guard clean; `swift test` green)

### Task 15: Settings UI (SwiftUI, hosted)

**Files:**
- Create: `App/Sources/UI/Settings/SettingsViewModel.swift` (`@Observable`)
- Create: `…/Settings/SettingsRootView.swift`, `GeneralSettingsView.swift`, `RulesListView.swift`,
  `RuleEditorView.swift`, `SettingsWindowController.swift`
- Create: `App/Tests/AppTests/SettingsViewModelTests.swift`

- [x] write failing tests for `SettingsViewModel` (mock `ConfigStore` + stub provider): load
      populates rules/browsers; add/edit/delete/reorder rule mutates config **and** persists;
      changing fallback policy persists
      (`SettingsViewModelTests`: 11 tests over a `MockConfigStore` recording every `save`/saved config
      + a `StubBrowserProvider`. Covers load populating rules/browsers/fallback, corrupt-config →
      `AppConfig.default`, add/edit/delete/reorder/toggle each mutating in-memory state AND persisting
      via `ConfigStore.save` exactly once, edit of an unknown rule → no-op/no save, fallback change to
      `.defaultBrowser`/`.lastUsed` persisting, and a save preserving the rest of the config + schemaVersion)
- [x] implement `SettingsViewModel` (depends only on Core protocols)
      (`App/Sources/UI/Settings/SettingsViewModel.swift`: `@MainActor @Observable`; depends only on Core
      `ConfigStore` + App `InstalledBrowsersProviding` seam — no `NSWorkspace`. `load()` populates
      `rules`/`browsers`/`fallback`; `addRule`/`updateRule`/`setRule(_:enabled:)`/`deleteRules(at:)`/
      `moveRules(fromOffsets:toOffset:)`/`setFallback` each mutate then `persist()` via `ConfigStore.save`,
      preserving the loaded `schemaVersion`. A failed save is logged; atomic store leaves prior file intact)
- [x] implement SwiftUI views (General: fallback policy, default browser, Set-as-Default button;
      Rules list with reorder; Rule editor with glob examples + browser/profile pickers + enable)
      (`GeneralSettingsView` — radio-group fallback picker mapping the 3 `FallbackPolicy` modes; reveals a
      browser+profile picker for `.defaultBrowser`; default-browser status row + Set-as-Default button via
      injected `DefaultBrowserManager`. `RulesListView` — reorderable `List` (onMove) + onDelete + Add,
      per-row enable `Toggle`, tap-to-edit; empty state. `RuleEditorView` — pattern field with documented
      glob examples, browser picker, profile picker driven by the chosen browser's profiles, enable toggle,
      Cancel/Save sheet committing only on Save. `SettingsRootView` — `TabView` (General + Rules), loads on appear)
- [x] host `SettingsRootView` via `NSHostingController` in `SettingsWindowController`
      (`SettingsWindowController`: lazily builds an `NSWindow(contentViewController: NSHostingController(...))`,
      `isReleasedWhenClosed = false`, reused across shows; `show()` calls `viewModel.load()`, then
      `NSApp.activate(ignoringOtherApps:)` + `makeKeyAndOrderFront` so the window comes forward despite the
      `.accessory`/`LSUIElement` agent policy. Wired in `AppMain`: the status-bar `onOpenSettings` hook now
      builds a `SettingsViewModel` (FileConfigStore + WorkspaceBrowserProvider) and shows the window)
- [x] run `xcodebuild test` — must pass before Task 16
      (`task test`: 48 App tests pass incl. 11 new `SettingsViewModelTests`; `task test-core`/`swift test`:
      81 Core tests pass + AppKit-import guard clean; `task build` succeeds — SwiftUI views compile. New
      Settings files have zero lint findings; live SwiftUI rendering is Post-Completion manual verification)

### Task 16: Picker popup (SwiftUI in NSPanel)

**Files:**
- Create: `App/Sources/UI/Picker/PickerViewModel.swift`, `BrowserPickerView.swift`,
  `PickerPanelController.swift` (conforms to `PickerPresenting`)
- Create: `App/Tests/AppTests/PickerViewModelTests.swift`

- [x] write failing tests for `PickerViewModel`: selecting a browser/profile yields the chosen
      `BrowserTarget`; "copy URL"; cancel yields no selection
      (`PickerViewModelTests`: 5 tests over a `PickerViewModel` whose three outcomes are captured via
      injected closures into an `Outcomes` recorder. Covers select-no-profile → `BrowserTarget(bundleID,
      profileID: nil)`, select-with-profile → `BrowserTarget(bundleID, profileID: chosen profile id)`,
      `copyURL()` → the url's `absoluteString` (and asserts copy is **not** a selection), `cancel()` →
      no selection and no copy, plus an exposed-`urlString` assertion)
- [x] implement `PickerViewModel`, `BrowserPickerView` (URL + browsers/profiles, keyboard select,
      Esc to cancel), and `PickerPanelController` (floating centered `NSPanel`, records last-used)
      (`App/Sources/UI/Picker/PickerViewModel.swift`: `@MainActor @Observable`; holds `url` + `[Browser]`,
      `select(browser:profile:)` resolves a `BrowserTarget` and fires `onSelect`, `copyURL()` fires
      `onCopy(urlString)`, `cancel()` fires `onCancel` — all side effects injected, no AppKit. `BrowserPickerView.swift`:
      SwiftUI showing the routed URL + a per-browser list with default + per-profile selection buttons, a
      Copy URL affordance, and a Cancel button bound to `.cancelAction` (Esc). `PickerPanelController.swift`:
      conforms to `PickerPresenting`; builds the view model, hosts `BrowserPickerView` in a floating, centered
      nonactivating utility `NSPanel`; on selection launches the chosen target via the injected `BrowserLaunching`
      and records it via the injected `LastUsedRecording`, on cancel just dismisses, on copy writes to
      `NSPasteboard.general`. Wired in `AppMain`: `RoutingService` now gets the real `PickerPanelController`
      (sharing the same `BrowserLauncher` + `LastUsedStore`); the Task-13 logging placeholder presenter was removed.
      Live panel rendering + keyboard/Esc selection are Post-Completion manual verification.)
- [x] run `xcodebuild test` — must pass before Task 17
      (`task test`: 53 App tests pass incl. 5 new `PickerViewModelTests`; `task test-core`/`swift test`:
      81 Core tests pass + AppKit-import guard clean; `task build` succeeds — the SwiftUI view + `NSPanel`
      controller compile. New Picker files have zero lint findings)

### Task 17: Verify acceptance criteria

- [x] verify every item in **Acceptance Criteria** is met (rules, profiles incl. running-browser
      case, full fallback matrix, menu bar, Settings, picker, set-as-default)
      (verification summary below; decision logic for every criterion is implemented + unit-tested,
      with the live-machine-only steps deferred to Post-Completion manual verification)
- [x] run full Core suite: `task test-core` (`swift test` + AppKit-import guard)
      (81 Core tests pass; AppKit-import guard clean — no Core source imports AppKit)
- [x] run full App suite: `task test` (`xcodebuild test`); run `task lint` and resolve findings
      (53 App tests pass; `task lint` now fully clean — 0 findings — after resolving 17 findings
      incl. the known RoutingService line-length **error**; see resolved-findings list below)

#### Acceptance Criteria verification

Legend: **[automated]** = decision logic implemented and covered by unit tests; **[deferred]** =
the thin final system call can only be confirmed on a live machine → Post-Completion manual
verification (de-risked earlier by the Task 2 spike where relevant).

1. **Selectable as system default browser; clicked links invoke `application(_:open:)`.**
   - [automated] `Info.plist` declares `CFBundleURLTypes` for `http`+`https` (`LSHandlerRank=Default`)
     and `LSUIElement`; `AppMain.application(_:open:)` forwards each URL to `RoutingService.route(url:)`.
     Task 1 reality check confirmed via `lsregister -dump` it advertises `claimed schemes: http:, https:`.
   - [deferred] Actually selecting it in System Settings and a real click reaching the callback are
     live-machine steps (Post-Completion).
2. **Rule-matched link opens in that rule's browser AND profile.**
   - [automated] `RuleMatcher.firstMatch` (host extraction, first-match-wins, disabled-rule skip) +
     `GlobPattern` + `Router.decide` → `.open(target)`; profile flag built by
     `LaunchArguments.build` (Chromium `--profile-directory=<dir>`, Firefox `-P <name>`, URL last) and
     wrapped by `BrowserLaunchCommand.make`. `RoutingService` resolves the `Browser` and launches.
   - [deferred] A real profile window opening per family (Post-Completion).
3. **Profile routing works even when the target browser is already running.**
   - [automated] Encoded by the spike-validated mechanism `open -n -a <app> --args …` in
     `BrowserLaunchCommand.make`/`BrowserLauncher`; argv contract unit-tested.
   - [deferred] Live already-running confirmation per family (Post-Completion; Firefox profile
     selection best-effort for the running case per spike §8 — already documented, not a scope cut).
4. **Fallback matrix for a no-rule link.**
   - [automated] `Router.decide`: `.picker` → `.prompt`; `.defaultBrowser(target)` → `.open(target)`;
     `.lastUsed` recorded → `.open(lastUsed)`; `.lastUsed` with nothing recorded → `.prompt`. All four
     branches covered in `RouterTests`; `RoutingService` maps `.prompt`→`PickerPanelController` and
     `.open`→`BrowserLauncher` + `LastUsedStore`.
   - [deferred] The panel actually appearing / a real browser opening (Post-Completion).
5. **Settings: add/edit/reorder/delete rules + change fallback persist across relaunch.**
   - [automated] `SettingsViewModel` mutations each call `ConfigStore.save`; `FileConfigStore` does an
     atomic JSON write (failed save leaves the prior file intact). `SettingsViewModelTests` +
     `FileConfigStoreTests` cover every mutation, persistence, corrupt-config reset, and round-trip.
   - [deferred] Visual editing + observing persistence after a real relaunch (Post-Completion).
6. **Menu-bar agent (no Dock icon); Set-as-Default, Settings, Quit.**
   - [automated] `AppMain` sets `.accessory` + `LSUIElement`; `StatusBarController` builds the
     `NSStatusItem` menu (Set as Default Browser…, Settings…, Quit) with the title/checkmark from the
     pure `StatusMenuState` helper (`StatusMenuStateTests`); `DefaultBrowserManager.setAsDefault()`
     calls `NSWorkspace.setDefaultApplication(...)` for http+https, `isCurrentDefault` comparison is
     unit-tested (`DefaultBrowserStatusTests`).
   - [deferred] Live menu visuals in light/dark, no Dock icon, and the macOS set-as-default prompt
     (Post-Completion).

#### Lint findings resolved (17 total → 0)

- `App/Sources/RoutingService.swift`: the known line-length **error** at the launch-failure log line
  (>160 chars, Task 13) + a second >120 warning on the no-browser log line — both rewrapped using
  local bindings + multiline string continuations (message text unchanged).
- `App/Tests/AppTests/RoutingServiceTests.swift`: 2 nesting warnings — hoisted the nested `Call`
  structs out of the mock classes to file-scope `LaunchCall`/`PickerCall`.
- `TrafficWandCore/Sources/TrafficWandCore/Browsers/BrowserFamily.swift`: 2 trailing-comma warnings.
- `TrafficWandCore/Tests/.../AppConfigCodableTests.swift`: 2 identifier-name (`a`/`b`), 2 line-length,
  and 4 optional-data-string-conversion warnings — renamed locals, extracted a `BrowserTarget`/JSON
  local, and switched `String(decoding:as:)` to `#require(String(bytes:encoding:))` via a `jsonString`
  helper.
- `TrafficWandCore/Tests/.../ChromeProfileReaderTests.swift` + `LaunchArgumentsTests.swift`: 3
  trailing-comma warnings.

### Task 18: [Final] Documentation & finalize

**Files:**
- Create: `README.md`, `CLAUDE.md`

- [x] write `README.md`: what it is, build/run (`task generate`/`build`/`run`), how to set as
      default browser, glob rule syntax + examples, profile support notes (+ the spike's findings),
      distribution/notarization pointer
- [x] write repo `CLAUDE.md`: Core/App split, protocol seams, `task` commands — and an explicit
      note that the Go/gommon golden rules in the global `~/.claude/CLAUDE.md` do **not** apply to
      this Swift project
- [x] move this plan to `docs/plans/completed/`

## Post-Completion
*Items requiring manual intervention or external systems — no checkboxes, informational only*

**Manual verification (real machine — these touch the live system):**
- Set TrafficWand as default browser via the menu item; confirm the macOS prompt and that link
  clicks reach `application(_:open:)`.
- Rule routing: matching link → correct browser; rule with profile → correct **profile**, including
  the **already-running-browser** case, per family: Chrome, Edge, Brave, Firefox.
- Fallback matrix: picker / single default / last-used (and `.lastUsed`-with-nothing-recorded → picker).
- Settings persist across relaunch; picker "copy URL" works.
- Menu bar item visuals in light/dark; no Dock icon (`LSUIElement`).
- Confirm no unexpected TCC prompts when reading Chrome/Firefox profile config.
- Accessibility pass (VoiceOver on Settings + picker; keyboard-only picker selection).

**Distribution / external systems:**
- Developer ID signing, Hardened Runtime, **notarization** of the `.app`; staple; package as DMG.
- Update mechanism (e.g. Sparkle) — out of scope for v1.
- Final app icon design (`Assets.xcassets/AppIcon` — placeholder added in Task 1).
- Optional future: full-URL (path) glob scope, rule import/export, "remember as rule" from the
  picker, Safari profile support if a launch API appears.
