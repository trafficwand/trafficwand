# First-Launch Onboarding Flow

Implements [issue #9](https://github.com/trafficwand/trafficwand/issues/9): a
multi-page screen shown once after a fresh install that (1) points the user to
the menu bar, (2) lets them set TrafficWand as the default browser, (3) explains
rules, (4) explains aliases — and offers a button to open the Rules editor /
Settings.

## Overview

- A **multi-page** onboarding window appears automatically on first launch and
  never again (gated by a `UserDefaults` flag, the same injection pattern as
  `LastUsedStore`).
- **4 pages**, one concept each, advanced with Back / Next, ending on a page
  whose primary button opens Settings deep-linked to the Rules tab:
  1. **Menu bar** — "TrafficWand lives in your menu bar." Visual: a **code-drawn
     illustration rasterized to a static image** via `ImageRenderer` (an actual
     image, non-interactive, treated identically to the screenshot pages).
  2. **Default browser** — "Make TrafficWand your default browser." Visual: a
     real screenshot; plus a **live "Set as Default" button** wired to the
     existing `DefaultBrowserManager`.
  3. **Rules** — "Route links automatically with rules." Visual: a real
     screenshot of the Rules tab.
  4. **Aliases** — "Reuse a browser + profile with aliases." Visual: a real
     screenshot of the Aliases tab. Primary button: **"Open Settings"**
     (deep-links to the Rules tab) — satisfies the issue's "button to open rules
     editor / settings."
- Per the discussion: page 1's illustration is built by us in code and baked to
  an image; the other three screenshots are captured by the user and dropped
  into an asset catalog. Until a real PNG is present, the image view renders a
  drawn placeholder, so the app builds and runs immediately.

## Context (from discovery)

- **`AppMain.applicationDidFinishLaunching`** (`App/Sources/AppMain.swift`) wires
  the whole app and is where the first-launch window is triggered and retained —
  mirrors how `settingsWindowController` / `statusBarController` are built and held.
- **`SettingsWindowController`** (`App/Sources/UI/Settings/SettingsWindowController.swift`)
  is the exact template for the onboarding window: an `NSWindow` hosting SwiftUI
  via `NSHostingController`, activating the accessory app on show. Copy its shape.
- **`DefaultBrowserManager`** (`App/Sources/Adapters/DefaultBrowserManager.swift`)
  already exposes `isDefault` and `setAsDefault(completion:)` — reused as-is by
  the default-browser page (held by the *view*, exactly like `GeneralSettingsView`).
- **Deep-link to Settings**: `SettingsWindowController.show(initialTab:)` +
  `AppMain.openSettings(tab:)` already exist; onboarding's "Open Settings" button
  routes through the same `onOpenSettings` closure threaded into the controller.
- **`LastUsedStore`** (`App/Sources/Adapters/LastUsedStore.swift`) is the pattern
  for the first-launch flag: a struct wrapping an injected `UserDefaults`, single
  key, tested against an isolated `UserDefaults(suiteName:)`.
- **Pure App-side logic is tested in `AppTests`** via `xcodebuild test` (e.g.
  `SettingsViewModel`, `PickerViewModel`, window-controller smoke tests). The
  onboarding navigation view model and store follow this precedent — no Core
  changes (onboarding is UI-shaped, not routing-decision-shaped).
- **Deployment target is macOS 26.0**, so `ImageRenderer` (macOS 13+) is available.
- **No asset catalog exists yet**; resources are folder paths in `project.yml`
  under the `TrafficWand` target's `sources`. A new `.xcassets` must be added there.
- **Preview mocks/fixtures** live in `App/Sources/UI/Previews/PreviewFixtures.swift`
  under `#if DEBUG`, declared `internal` for `@testable import`.

## Development Approach

- **Testing approach**: **TDD** (tests first), matching the repo convention.
- Complete each task fully before moving to the next.
- Make small, focused changes; keep the diff minimal (no speculative abstraction —
  onboarding stays in the App layer, not Core).
- **CRITICAL: every task includes new/updated tests** (success + edge cases);
  tests are a required deliverable, listed as separate checklist items.
- **CRITICAL: all tests pass before starting the next task.**
- Run `task test-core` is **not** needed (no Core changes); run `task test` for
  the App target. Keep `task lint` clean.

## Testing Strategy

- **Unit tests** (`App/Tests/AppTests`, run via `task test`):
  - `OnboardingStore`: flag defaults to "not completed", set→completed, isolated
    `UserDefaults(suiteName:)` so the host's real defaults are never touched
    (mirror `LastUsedStoreTests`).
  - `OnboardingViewModel`: page order/count, `currentIndex`, `isFirst`/`isLast`,
    `next()`/`back()` clamping at bounds, `openSettings()` invokes the injected
    closure, `complete()` marks the store completed and fires `onFinish`.
  - `OnboardingWindowController`: smoke test that it builds and `show()` does not
    crash (mirror `SettingsWindowControllerAboutTests`/`AppSmokeTests`), and that
    closing the window marks onboarding completed.
- **No e2e harness** in this project (AppKit/SwiftUI menu-bar app); the
  `setAsDefault` system prompt and the actual screenshots are Post-Completion
  manual verification.

## Progress Tracking

- Mark completed items `[x]` immediately.
- New tasks get a ➕ prefix; blockers get ⚠️.
- Keep this file in sync if scope shifts.

## Solution Overview

Thin App-layer feature, no Core changes:

- **State/logic (pure, testable):** `OnboardingStore` (first-launch flag over
  injected `UserDefaults`) + `OnboardingViewModel` (`@Observable @MainActor`:
  page list, navigation, completion). The `DefaultBrowserManager` is held by the
  view (as in `GeneralSettingsView`), keeping the view model free of `NSWorkspace`
  and fully testable.
- **Window adapter:** `OnboardingWindowController` mirrors `SettingsWindowController`
  — builds/owns the `NSWindow` hosting `OnboardingRootView`, activates the app,
  and marks completion on window close.
- **Views:** `OnboardingRootView` (paged card: framed image + title + body +
  footer nav + page dots) and a small `FramedScreenshot` view that resolves a
  named asset (or a provided rendered `NSImage`) and falls back to a drawn
  "screenshot goes here" placeholder when absent. `MenuBarIllustration` is the
  SwiftUI illustration for page 1, rasterized via `ImageRenderer`.
- **Assets:** new `App/Resources/Onboarding.xcassets` with imagesets for the
  three real screenshots; the user drops PNGs in later.
- **Wiring:** `AppMain` builds + retains an `OnboardingWindowController` and shows
  it on launch only when `OnboardingStore` reports not-yet-completed.

### Design decisions / rationale

- **App layer, not Core:** onboarding is UI presentation state, not a routing
  decision. Core stays AppKit-free; this matches how `PickerViewModel` /
  `SettingsViewModel` already live in App and are tested in `AppTests`.
- **Image-only visuals (confirmed product requirement):** every page renders a
  flat, non-interactive `Image` (rasterized illustration or screenshot) inside a
  frame — per the explicit requirement that visuals look like screenshots and
  can't be mistaken for live controls. This is why the menu-bar page is drawn in
  SwiftUI and **rasterized via `ImageRenderer`** rather than shown as a live view:
  uniform flat-image treatment is the requirement, not an accident. Live actions
  (Set as Default, Open Settings, Next/Back) live only in the footer.
- **Completion-on-close:** dismissing the window (any path — Done, Open Settings,
  or the red close button) marks onboarding complete, so it shows exactly once.
- **Placeholder fallback:** `FramedScreenshot` renders a drawn placeholder when
  the named asset has no PNG yet, so the feature ships before screenshots exist
  and degrades gracefully if an asset is ever missing.

## Technical Details

- `OnboardingStore`: key `io.tomakado.TrafficWand.onboardingCompleted`,
  `var hasCompletedOnboarding: Bool { get }`, `func markCompleted()`, injected
  `UserDefaults` (default `.standard`).
- `OnboardingPage`: enum `{ menuBar, defaultBrowser, rules, aliases }`,
  `CaseIterable`, exposing `title`, `body`, and an image source
  (`.asset(String)` for screenshots, `.rendered` for the menu-bar illustration).
- `OnboardingViewModel` (`@Observable @MainActor`): `pages: [OnboardingPage]`
  (= `OnboardingPage.allCases`), `currentIndex: Int`, computed `currentPage`,
  `isFirstPage`, `isLastPage`, `progress`; `next()`/`back()` clamp; `openSettings()`
  → `onOpenSettings(.rules)`; `complete()` → `store.markCompleted()` + `onFinish()`.
  Injected: `OnboardingStore`, `onOpenSettings: (SettingsTab) -> Void`,
  `onFinish: () -> Void`.
- `OnboardingWindowController` (`@MainActor`): like `SettingsWindowController` —
  lazy `NSWindow` + `NSHostingController(rootView: OnboardingRootView)`,
  `show()` activates + orders front; `NSWindowDelegate.windowWillClose` calls
  `viewModel.complete()` (idempotent via the store flag).
- `MenuBarIllustration` → `ImageRenderer(content:).nsImage` at a fixed size,
  `scale = 2`, produced once when the menu-bar page appears.
- `project.yml`: add `- path: App/Resources/Onboarding.xcassets` to the
  `TrafficWand` target's `sources`; run `task generate` after.

## What Goes Where

- **Implementation Steps** (checkboxes): all code, tests, asset-catalog scaffold,
  `project.yml` change, and wiring — everything achievable in this repo.
- **Post-Completion** (no checkboxes): capturing the three real screenshots,
  manually verifying the `setAsDefault` system prompt, and eyeballing the flow on
  a clean install.

## Implementation Steps

### Task 1: First-launch flag store

**Files:**
- Create: `App/Sources/Adapters/OnboardingStore.swift`
- Create: `App/Tests/AppTests/OnboardingStoreTests.swift`

- [x] write `OnboardingStoreTests`: default is not-completed; after `markCompleted()` it is completed; uses an isolated `UserDefaults(suiteName:)` and clears it (mirror `LastUsedStoreTests`)
- [x] assert the isolated store leaves `UserDefaults.standard` unchanged (mirror `LastUsedStoreTests.testStoreDoesNotPolluteStandardDefaults`) — guards against a leaked test write silently marking the dev's own install as onboarded
- [x] create `OnboardingStore` wrapping injected `UserDefaults` (default `.standard`), single key, `hasCompletedOnboarding` getter + `markCompleted()`
- [x] run `task test` — must pass before next task

### Task 2: Onboarding pages + navigation view model

**Files:**
- Create: `App/Sources/UI/Onboarding/OnboardingPage.swift`
- Create: `App/Sources/UI/Onboarding/OnboardingViewModel.swift`
- Create: `App/Tests/AppTests/OnboardingViewModelTests.swift`

- [x] write `OnboardingViewModelTests`: exactly 4 pages in order `menuBar, defaultBrowser, rules, aliases`; starts at index 0 (`isFirstPage`); `next()` advances and clamps at last (`isLastPage`); `back()` retreats and clamps at 0; `openSettings()` invokes the injected closure with `.rules`; `complete()` marks the store completed and fires `onFinish`
- [x] create `OnboardingPage` enum (`CaseIterable`) with `title`, `body`, and image-source per page
- [x] create `OnboardingViewModel` (`@Observable @MainActor`) with navigation + `openSettings()` + `complete()`, injecting `OnboardingStore`, `onOpenSettings`, `onFinish`
- [x] run `task test` — must pass before next task

### Task 3: Screenshot/illustration views (`FramedScreenshot` + `MenuBarIllustration`)

**Files:**
- Create: `App/Sources/UI/Onboarding/FramedScreenshot.swift`
- Create: `App/Sources/UI/Onboarding/MenuBarIllustration.swift`
- Create: `App/Resources/Onboarding.xcassets/` (catalog `Contents.json` + three imagesets: `onboarding-default-browser`, `onboarding-rules`, `onboarding-aliases`, each with a `Contents.json` expecting a universal PNG the user adds later)
- Modify: `project.yml` (add the xcassets to the `TrafficWand` target sources)
- Create: `App/Tests/AppTests/OnboardingImageTests.swift`

- [x] write tests: `FramedScreenshot` resolves to a placeholder when the named asset is absent and to the asset/`NSImage` when present (assert the resolution helper's output, e.g. a pure `image(forAsset:) -> NSImage?` returning `nil` → placeholder branch); `MenuBarIllustration` rasterizes to a non-`nil` `NSImage` via `ImageRenderer`
- [x] create `FramedScreenshot` (takes an asset name or a rendered `NSImage`; frames it with border/shadow/caption; falls back to a drawn placeholder when no image resolves; the image is non-interactive)
- [x] create `MenuBarIllustration` SwiftUI view + an `ImageRenderer`-based helper that bakes it to an `NSImage`
- [x] add `App/Resources/Onboarding.xcassets` with the three placeholder imagesets; add it to `project.yml` target sources; run `task generate`
- [x] run `task test` — must pass before next task

### Task 4: Onboarding root view (paged flow)

**Files:**
- Create: `App/Sources/UI/Onboarding/OnboardingRootView.swift`
- Modify: `App/Sources/UI/Previews/PreviewFixtures.swift` (sample `OnboardingViewModel` for `#Preview`, `#if DEBUG`, `internal`)
- Create: `App/Tests/AppTests/OnboardingRootViewTests.swift` (light: constructs the view across pages without crashing; the default-browser page shows a Set-as-Default affordance; the last page's primary action calls `openSettings()`)

- [x] write the view tests (construction across each page index; primary-button wiring on the last page; default-browser button present on page 2)
- [x] create `OnboardingRootView`: shows `currentPage`'s `FramedScreenshot` (rendered illustration for `menuBar`), title, body; footer with Back / Next, page-dot indicator; the `defaultBrowser` page adds a live "Set as Default" button via an injected `DefaultBrowserManager` (held by the view, like `GeneralSettingsView`); the `aliases` (last) page's primary button is "Open Settings" → `viewModel.openSettings()` then closes (kept the "Open Settings" label landing on Rules, as the plan's note permits)
- [x] add a `#Preview` using `PreviewFixtures`
- [x] run `task test` — must pass before next task

### Task 5: Onboarding window controller

**Files:**
- Create: `App/Sources/UI/Onboarding/OnboardingWindowController.swift`
- Create: `App/Tests/AppTests/OnboardingWindowControllerTests.swift`

- [x] write tests (mirror `SettingsWindowControllerAboutTests`/`AppSmokeTests`): controller builds; `show()` doesn't crash; closing the window marks the injected `OnboardingStore` completed and fires `onFinish`
- [x] create `OnboardingWindowController` (`@MainActor`): lazy `NSWindow` hosting `OnboardingRootView`, activates app on `show()`, `NSWindowDelegate.windowWillClose` → `viewModel.complete()`; retains the view model
- [x] run `task test` — must pass before next task

### Task 6: Wire into `AppMain` (show on first launch only)

**Files:**
- Modify: `App/Sources/AppMain.swift`
- Modify (if needed): `App/Tests/AppTests/...` (extend an existing launch/smoke assertion, or add a small gate test if `AppMain` exposes a testable seam; otherwise rely on the controller/store tests + manual verification)

- [x] build **one** `OnboardingStore` instance; inject it into a retained `OnboardingWindowController` along with the `openSettings(tab:)` deep-link closure and an `onFinish` no-op
- [x] gate the `show()` off **that same** store instance (`store.hasCompletedOnboarding == false`), after the rest of the app is wired — single source of truth, no second `OnboardingStore()`
- [x] verify no regression to cold-start link intake (onboarding is presented after `intake.activate`; it does not gate routing) — onboarding wiring is appended *after* the `intake.activate { ... }` call, so the buffered-link flush runs first and unchanged; routing path is untouched
- [x] note: `AppMain.applicationDidFinishLaunching` has no unit-test seam today (matches existing precedent — `AppSmokeTests` only checks Core linkage), so the show-once gate's correctness rides on the `OnboardingStore` + `OnboardingWindowController` tests plus manual verification, not on an `AppMain` test — confirmed: no new AppMain test added; relied on existing store/controller tests, full suite (223 tests) green
- [x] run `task test` — must pass before next task — 223 tests, 0 failures; `task lint` clean

### Task 7: Verify acceptance criteria

- [x] all four issue #9 points covered: menu-bar pointer, set-as-default action, rules explained, button to open Rules/Settings (plus the aliases page) — verified by inspection: `OnboardingPage` has cases `.menuBar/.defaultBrowser/.rules/.aliases`; `OnboardingRootView.showsDefaultBrowserButton(for: .defaultBrowser)` renders a live "Set as Default" button wired to `DefaultBrowserManager.setAsDefault`; the last page's primary button "Open Settings" calls `viewModel.openSettings()` → `onOpenSettings(.rules)` then `complete()`
- [x] onboarding shows on a clean profile and not on subsequent launches (flag works) — verified: `AppMain` builds ONE `OnboardingStore()`, gates `onboardingController.show()` on `store.hasCompletedOnboarding == false`, presented after `intake.activate`; `windowWillClose → complete() → markCompleted()`. Covered by `OnboardingStoreTests` (default not-completed, markCompleted persists, isolated suite, no standard-defaults pollution) + `OnboardingWindowControllerTests.testClosingWindowMarksStoreCompletedAndFiresOnFinish`. AppMain wiring verified by inspection (no test seam, per Task 6 note)
- [x] run full App test suite: `task test` — 223 tests, 0 failures, ** TEST SUCCEEDED **
- [x] run `task lint` clean — no violations

### Task 8: [Final] Documentation + housekeeping

**Files:**
- Modify: `CLAUDE.md` (add an Onboarding subsection under the App/ layer description if the pattern warrants it)
- Modify: `README.md` (only if it documents first-run behavior)

- [ ] update `CLAUDE.md` (unconditional) with the onboarding window/flag pattern and the screenshot-asset convention — this is an architectural seam in the same class as the documented `LinkIntake`/picker/aliases patterns
- [ ] update `README.md` if it covers first-run UX
- [ ] move this plan to `docs/plans/completed/`

## Post-Completion

*Items requiring manual intervention or external systems — informational only.*

**Manual verification:**
- Capture the three real screenshots (default-browser page, Rules tab, Aliases tab)
  and drop the PNGs into the matching imagesets in `App/Resources/Onboarding.xcassets`
  (the views render a placeholder until then).
- Verify the "Set as Default" button triggers the macOS system confirmation prompt
  (cannot be automated; covered by `DefaultBrowserManager`'s existing manual-verify note).
- Run the app from a clean state (new user / cleared `UserDefaults` for the bundle)
  and confirm the flow appears once, navigates correctly, and never reappears.
- Eyeball that the rasterized menu-bar illustration reads as a screenshot (flat,
  framed, non-interactive) and visually matches the screenshot pages' treatment.
