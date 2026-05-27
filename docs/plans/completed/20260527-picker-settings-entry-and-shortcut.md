# Picker Settings Entry + ⌘, Shortcut (Issue #21)

## Overview

Issue [#21](https://github.com/tomakado/trafficwand/issues/21): give the picker popup
its own way into Settings, so users can edit rules even when the status-bar icon is
hidden behind the MacBook notch.

Two entry points, both added to the picker popup:

1. **Gear icon** in the top-right of the picker header → opens Settings deep-linked to
   the **Rules** tab (the "edit rules" intent named in the issue).
2. **⌘,** keyboard shortcut, active while the picker has key focus → opens Settings on
   the **General** tab, matching the macOS Preferences convention so the shortcut means
   what the user reflexively expects.

Both entry points **dismiss the picker** on activation. Rationale: opening Settings
brings a normal `NSWindow` forward; the picker is a `.floating` `NSPanel` and would
otherwise stack above (or float beside) the Settings window, which reads as a glitch.
Dismissing also matches Esc's existing semantics — the URL is dropped, and the user can
re-trigger the link from their source app after editing rules.

Plumbing reuses the seam that already exists for the status-bar's About item:
`SettingsWindowController.show(initialTab:)` (`App/Sources/UI/Settings/SettingsWindowController.swift:72`)
already deep-links by tab via the `@Observable` `SettingsSelection`. The work is wiring
a new `(SettingsTab) -> Void` closure from `AppMain` → `PickerPanelController` →
`PickerViewModel` → `BrowserPickerView`.

## Context (from discovery)

- **Files/components involved**
  - `App/Sources/UI/Picker/BrowserPickerView.swift` — gear button in the header, hidden
    button carrying the `⌘,` keyboard shortcut.
  - `App/Sources/UI/Picker/PickerViewModel.swift` — gains an injected
    `onOpenSettings: (SettingsTab) -> Void` and a corresponding `openSettings(tab:)`
    method. This is the testable seam.
  - `App/Sources/UI/Picker/PickerPanelController.swift` — gains an injected
    `openSettings: @MainActor (SettingsTab) -> Void`; wires it into the view model and
    dismisses the panel on invocation.
  - `App/Sources/AppMain.swift` — builds the picker controller with a closure that
    calls `settingsWindowController?.show(initialTab:)`. `makeRoutingService()` is
    currently a `static` helper with no reference to `settingsWindowController`; the
    refactor turns it into an instance method (or threads the opener in as a parameter)
    so it can capture the controller.
  - `App/Tests/AppTests/PickerViewModelTests.swift` — new tests for `openSettings(tab:)`.
- **Related patterns found**
  - `StatusBarController` already takes `onOpenSettings: () -> Void` /
    `onOpenAbout: () -> Void` closures (`App/Sources/UI/StatusBarController.swift:80`)
    — same pattern, just parameterized by tab.
  - `SettingsTab` enum + `SettingsSelection` @Observable holder already power the
    "About TrafficWand…" deep link; we reuse them verbatim.
  - `PickerViewModel` already owns several `onSelect` / `onCancel` / `onCopy` closures;
    adding `onOpenSettings` follows the established convention of routing all decisions
    through injected closures so the view model stays testable without AppKit.
- **Dependencies identified**
  - No new packages. SwiftUI + AppKit + the existing `TrafficWandCore` SPM package.
  - No changes to `TrafficWandCore` — `SettingsTab` lives in App, so the seam stays in
    App.

## Development Approach

- **Testing approach: TDD (tests first)** — every view-model and wiring change starts
  with a failing test under `App/Tests/AppTests/`.
- Complete each task fully before moving to the next.
- Make small, focused changes.
- **CRITICAL: every task MUST include new/updated tests** for code changes in that task.
  Tests cover both success and edge cases.
- **CRITICAL: all tests must pass before starting next task** — no exceptions.
- **CRITICAL: update this plan file when scope changes during implementation.**
- Run `task test-core && task test` after each task.
- Keep `task lint` clean.
- Maintain backward compatibility (no migration concerns — picker has no persisted
  state, gear button is purely additive).

## Testing Strategy

- **Unit tests** (required per task):
  - `PickerViewModel` — `openSettings(tab:)` invokes the injected closure with the
    correct tab argument; success cases for both `.rules` and `.general`.
- **Integration / wiring tests**: a lightweight test exercises `PickerPanelController`
  end-to-end against a fake `BrowserLaunching`/`LastUsedRecording`/`RulePersisting`
  trio plus a recording `openSettings` closure, verifying the controller forwards the
  view model's open-settings call to the injected closure. This mirrors
  `StatusBarControllerAboutTests` in approach (test the wiring, not the AppKit pixels).
- **No new Core tests** — this work is App-side only.
- **Live picker visuals + the `⌘,` keypress reaching the panel**: Post-Completion
  manual verification (the `KeyablePanel` + `.keyboardShortcut` interaction is the
  exact category of thing the codebase already covers manually for the picker).

## Progress Tracking

- Mark completed items with `[x]` immediately when done.
- Add newly discovered tasks with ➕ prefix.
- Document blockers with ⚠️ prefix.
- Update plan if implementation deviates from original scope.
- Keep plan in sync with actual work done.

## Solution Overview

**Design choice 1 — gear in the header, not a footer button.** The footer is the
action row (Copy URL / Cancel) and adding a third button there muddies the primary vs.
secondary signal. A trailing SF Symbol gear in the header mirrors the launcher-popup
convention (Raycast / Alfred / Spotlight-style overlays) and is unobtrusive against the
"Open Link In…" headline.

**Design choice 2 — gear goes to Rules, ⌘, goes to General.** The gear in this surface
is a contextual shortcut to "edit the rules that would route this URL," so Rules is
the right destination. ⌘, is the global Preferences convention; it should land where
the menu bar's `Settings…` lands (effectively General as the canonical entry point) so
the keyboard shortcut is predictable across surfaces.

**Design choice 3 — dismiss the picker when Settings opens.** The picker is a
`.floating` panel; leaving it visible while a normal window appears creates a
stacking-order glitch. Dismissing matches Esc semantics — the URL is dropped, the user
re-clicks if they need it after editing rules. Simple, predictable, no new state to
reason about.

**Design choice 4 — `⌘,` via a zero-frame `Button` + `.keyboardShortcut(",", modifiers: .command)`,
not `onKeyPress`.** SwiftUI's `.onKeyPress` doesn't compose cleanly with modifier
matching; `Button` + `keyboardShortcut` is the standard idiom. **Do not** use
`.hidden()` to remove the button visually — `.hidden()` also removes the view from
SwiftUI's event-delivery hierarchy and the shortcut would silently never register.
The correct pattern is `.opacity(0).allowsHitTesting(false).frame(width: 0, height: 0)`
plus `.accessibilityHidden(true)`, which keeps the button eligible to register its
shortcut while taking zero layout space and being invisible to assistive tech.

**Design choice 5 — `AppMain` exposes a private `openSettings(tab: SettingsTab)`
instance method, mirroring `openAbout` (`App/Sources/AppMain.swift:82`).** The
opener closure passed to the picker is `{ [weak self] tab in self?.openSettings(tab: tab) }`,
matching the existing `[weak self] in self?.openSettings()` capture style for the
status-bar item (`App/Sources/AppMain.swift:52`). Capturing
`[weak settingsWindowController]` directly would only snapshot the property's value
at closure-construction time (Swift captures the *value* of a `var` property, not a
weakly-tracked reference to the property itself), which is a hidden footgun. Going
through `self?.openSettings(tab:)` always reads the live property.

**Design choice 6 — keep `makeRoutingService` static.** Pass the new opener closure
in as a parameter (`makeRoutingService(openSettings:)`) rather than converting the
factory to an instance method. Smaller diff, unrelated refactor avoided.

**Wiring summary:**

```
AppMain.applicationDidFinishLaunching
        │ builds settingsWindowController FIRST
        ▼
AppMain.makeRoutingService(openSettings:)     (still static)
        │ receives closure as parameter
        ▼
PickerPanelController(
    launcher, lastUsedStore, rulePersister, iconProvider,
    openSettings: <closure from AppMain>
)

AppMain passes:
    { [weak self] tab in self?.openSettings(tab: tab) }

AppMain.openSettings(tab:) → settingsWindowController?.show(initialTab: tab)

PickerPanelController.presentPicker → makeViewModel(url:browsers:)
                                       (new internal factory)
        │ VM built with
        ▼  onOpenSettings: { [weak self] tab in
              self?.handleOpenSettings(tab: tab)
           }

BrowserPickerView header gear              → viewModel.openSettings(tab: .rules)
BrowserPickerView zero-frame keyboard btn  → viewModel.openSettings(tab: .general)  (⌘,)
        │
        ▼
PickerPanelController.handleOpenSettings(tab:)
        │ guard !isDismissing
        ▼
openSettings(tab); dismiss()
```

## Technical Details

- **`PickerViewModel.openSettings(tab:)`** — single method, calls
  `onOpenSettings?(tab)`. The closure is optional with a default `nil` so existing
  call sites in tests don't need to change, but the production controller always
  injects a real one.
- **`PickerPanelController.handleOpenSettings(tab:)`** — re-entrancy-guarded by the
  existing `isDismissing` flag (same protection as `handleSelection`), invokes the
  injected opener, then calls `dismiss()` to animate the panel out.
- **Header layout** — `header` becomes an `HStack` with `Spacer()` separating the
  existing title/URL `VStack` from a trailing gear `Button` (`Image(systemName: "gearshape")`,
  `.buttonStyle(.plain)`, `.help("Edit Rules…")` for the tooltip, accessibility label
  "Edit Rules…").
- **Hidden ⌘, button** — placed inside `body` (e.g. at the end of the outer `VStack`)
  as a `Button("", action: …).keyboardShortcut(",", modifiers: .command).hidden().frame(width: 0, height: 0)`
  so the shortcut binds to the picker's responder chain (the panel becomes key, so
  SwiftUI's keyboard-shortcut machinery picks it up) without taking layout space.

## What Goes Where

- **Implementation Steps** (`[ ]` checkboxes): all code changes (view model, controller,
  view, AppMain wiring) and their tests.
- **Post-Completion** (no checkboxes): manual verification of the live picker — gear
  click opens Rules tab, `⌘,` opens General tab, panel dismisses cleanly in both
  cases, the gear is visible at all reasonable picker heights (empty state and full
  list), and the `⌘,` shortcut does not fire when Settings is already key.

## Implementation Steps

### Task 1: PickerViewModel gains `openSettings(tab:)`

**Files:**
- Modify: `App/Sources/UI/Picker/PickerViewModel.swift`
- Modify: `App/Tests/AppTests/PickerViewModelTests.swift`

- [x] write failing test: `PickerViewModel.openSettings(tab: .rules)` invokes the
      injected `onOpenSettings` closure with `.rules`.
- [x] write failing test: `openSettings(tab: .general)` invokes the closure with
      `.general`.
- [x] add `onOpenSettings: ((SettingsTab) -> Void)?` parameter to `PickerViewModel.init`,
      defaulted to `nil`, stored as a private property.
- [x] add `func openSettings(tab: SettingsTab)` that calls `onOpenSettings?(tab)`.
- [x] run `task test` — all picker tests must pass before next task.

### Task 2: BrowserPickerView gear icon + ⌘, shortcut

**Files:**
- Modify: `App/Sources/UI/Picker/BrowserPickerView.swift`

- [x] refactor `header` from `VStack` to an `HStack { titleColumn; Spacer(); gearButton }`,
      preserving the existing title/URL `VStack` as the leading column.
- [x] add the gear `Button` (`Image(systemName: "gearshape")`,
      `.buttonStyle(.plain)`, `.pointerStyle(.link)`, `.help("Edit Rules…")`,
      accessibility label `"Edit Rules…"`) calling
      `viewModel.openSettings(tab: .rules)`.
- [x] add a zero-frame `Button` carrying `.keyboardShortcut(",", modifiers: .command)`
      that calls `viewModel.openSettings(tab: .general)`. **Critical:** modifier the
      button with `.opacity(0).allowsHitTesting(false).frame(width: 0, height: 0)`
      plus `.accessibilityHidden(true)` — **NOT** `.hidden()`. `.hidden()` removes
      the view from SwiftUI's event-delivery hierarchy and the `⌘,` shortcut would
      silently fail to register. Place it inside the picker's outermost `VStack` so
      it participates in the key window's responder chain.
- [x] update the `#Preview` blocks if any compile-time change is needed (none expected
      because `openSettings` is optional and previews pass through `previewViewModel`).
- [x] verify SwiftLint passes: `task lint`.
- [x] verify `task build` succeeds.
- [x] **No new automated tests in this task.** View rendering and keyboard-shortcut
      delivery are explicitly Post-Completion manual verification in this codebase
      (same pattern as `BrowserPickerView`'s live rendering and `KeyablePanel`'s
      keyboard handling). Wiring from view → view model is asserted by Task 1; wiring
      from view model → controller → opener is asserted by Task 3.
- [x] run `task test` — must pass before next task.

### Task 3: PickerPanelController forwards openSettings + dismisses

**Files:**
- Modify: `App/Sources/UI/Picker/PickerPanelController.swift`
- Create: `App/Tests/AppTests/PickerPanelControllerOpenSettingsTests.swift`

**Testable seam:** extract the `PickerViewModel` construction in `presentPicker` into
an internal factory `func makeViewModel(url:browsers:) -> PickerViewModel`. Tests
build a controller with a recording opener, call `makeViewModel(...)` directly to get
the wired VM, then invoke `viewModel.openSettings(tab:)` — exercising the full
view-model → controller → opener chain without driving the live `NSPanel`. This
mirrors the "expose the pure decision, mock the rest" approach used elsewhere
(`StatusMenuState`, `RoutingService` tests).

- [x] write failing test: construct `PickerPanelController` with a recording
      `openSettings` closure + fake launcher/lastUsed/rulePersister/icon provider;
      call `makeViewModel(url:, browsers:)`, then invoke the returned VM's
      `openSettings(tab: .rules)` and assert the recording closure was called once
      with `.rules`.
- [x] write failing test (mirror): same flow with `.general` records `.general`.
- [x] write failing test: directly call `controller.handleOpenSettings(tab: .rules)`
      twice in quick succession (the second call simulates a click during the
      dismiss fade) — the recording closure is invoked **once**. This asserts the
      re-entrancy guard via `isDismissing`, mirroring the protection on
      `handleSelection`.
- [x] add `openSettings: @MainActor (SettingsTab) -> Void` parameter to
      `PickerPanelController.init`; store as private property.
- [x] extract `presentPicker`'s `PickerViewModel(...)` construction into an internal
      `func makeViewModel(url:browsers:) -> PickerViewModel`; call it from
      `presentPicker`. The factory injects
      `onOpenSettings: { [weak self] tab in self?.handleOpenSettings(tab: tab) }`.
- [x] add `func handleOpenSettings(tab: SettingsTab)` (internal, not private — needs
      to be callable from the test target) that guards on `isDismissing`, invokes the
      injected `openSettings(tab)`, then calls `dismiss()`.
- [x] update the class-level doc comment to mention the controller now also routes
      "open settings" requests.
- [x] run `task test` — must pass before next task.

### Task 4: AppMain wires the opener through to SettingsWindowController

**Files:**
- Modify: `App/Sources/AppMain.swift`

- [x] add a `private func openSettings(tab: SettingsTab)` instance method on
      `AppMain`, calling `settingsWindowController?.show(initialTab: tab)`. This
      mirrors the existing `openAbout` (`AppMain.swift:82`) and the existing
      no-argument `openSettings` (`AppMain.swift:75`) — rename the no-argument one
      to `openSettings()` overload if needed, or have the tab-taking form be the
      single implementation that the status-bar `onOpenSettings` closure calls with
      a default tab (whatever today's `show()` resolves to).
- [x] add `openSettings: @MainActor (SettingsTab) -> Void` parameter to
      `makeRoutingService(...)` (keep the function `static`); pass the closure
      through to `PickerPanelController(...)`.
- [x] in `applicationDidFinishLaunching`, after building `settingsWindowController`,
      call `routingService = Self.makeRoutingService(openSettings: { [weak self] tab in
      self?.openSettings(tab: tab) })`. The `[weak self]` capture mirrors the existing
      `onOpenSettings: { [weak self] in self?.openSettings() }` at `AppMain.swift:52`
      and avoids the trap of capturing a `var` property "weakly" (Swift would capture
      its value at construction time, not a live reference).
- [x] update the doc comment on `makeRoutingService` to mention the new opener
      parameter and why it's threaded as a parameter (so the static factory stays
      pure).
- [x] tests for this task: AppMain wiring is not directly unit-tested (matches the
      existing pattern — `applicationDidFinishLaunching` has no test). Wiring is
      covered transitively by Task 3's panel-controller test plus the existing
      `SettingsWindowControllerAboutTests` which already exercises
      `show(initialTab:)`.
- [x] run `task test` and `task test-core` — both must pass.

### Task 5: Verify acceptance criteria

- [x] verify all requirements from Overview are implemented: gear in header opens
      Rules, `⌘,` opens General, both dismiss the picker.
- [x] verify edge cases handled: empty-browsers picker state still shows the gear;
      gear/`⌘,` during dismiss animation is a no-op (re-entrancy guard).
- [x] run full test suite: `task` (default — generate + build + lint + test-core +
      test).
- [x] verify SwiftLint clean: `task lint`.
- [x] no AppKit-import-in-Core regressions (covered automatically by `task test-core`).

### Task 6: Final — Update documentation and move plan

- [x] update `CLAUDE.md` only if a new pattern was introduced (none expected — this
      reuses the existing closure-injection seam pattern). _No new pattern introduced;
      no doc update needed._
- [x] move this plan to `docs/plans/completed/` once all tasks are checked and the
      PR is open.
- [x] PR title reserved: `feat: settings entry point and ⌘, shortcut in picker`
      (closes #21). PR creation deferred to orchestrator.

## Post-Completion

**Manual verification:**

- Trigger the picker (open any external link). Confirm the gear icon renders in the
  top-right of the header.
- Click the gear: Settings window opens on the **Rules** tab; the picker animates out.
- Trigger the picker again. Press `⌘,`: Settings window opens on the **General** tab;
  the picker animates out.
- Trigger the picker, then immediately press `⌘,` (or click the gear) while the
  picker is still animating in / out: no double-invocation, no crash.
- Re-trigger with **zero installed browsers** (empty state) — gear still visible and
  functional.
- Confirm the gear is reachable by VoiceOver and announces "Edit Rules…".
- Confirm `⌘,` has **no effect when no picker is shown** (only the menu bar is
  active): the shortcut belongs to the picker view, not a global hotkey, so it must
  silently do nothing in the menu-bar-only state.

**No external system updates** — this is an in-app UI change. No config schema, no
persisted state, no consumer impact.
