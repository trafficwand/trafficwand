# Picker Panel UX/UI Redesign

## Context

The browser picker panel ("Open Link In…") works but feels unfinished:

1. **Profiles don't look clickable** — they're already `Button`s (`BrowserPickerView.swift:116`)
   but styled `.buttonStyle(.plain)` with no hover, no cursor change, no press feedback.
2. **Browsers show a generic globe** (`Image(systemName: "globe")`) instead of their real app icons,
   even though every `Browser` already carries an `appURL` we can load an icon from.
3. **No way to make a choice stick** — picking a browser is one-shot; there's no
   "Remember choice for this site" affordance, so frequent destinations must be added by hand in Settings.

Decision (confirmed with user): do a **deeper redesign** of the panel — not just the three items above,
but a cohesive pass including hover/press states, real icons, **keyboard arrow-key navigation with a
highlighted selection**, a restyled header/footer, and the remember-choice checkbox. The "remember"
rule matches the **registrable domain + all subdomains** (e.g. `*rockpapershotgun.com`).

**Outcome:** a polished, keyboard- and mouse-friendly picker where every destination is an obviously
clickable, hoverable row with its real icon, and the user can persist a routing rule inline.

## Architecture fit (Core/App split)

- **Core (pure, AppKit-free, TDD):** registrable-domain extraction, remember-rule construction, and
  config upsert-by-pattern. All decision-shaped → unit-tested via `swift test`.
- **App (thin adapters + SwiftUI, tests-with-code):** a `RulePersisting` seam over `ConfigStore`, a
  `BrowserIconProviding` seam over `NSWorkspace`, the `PickerViewModel` changes (remember flag,
  flattened selectable list, keyboard nav), the redesigned `BrowserPickerView`, and wiring.

Reused, do not reinvent:
- `Browser.appURL` (`TrafficWandCore/.../Models/Browser.swift`) → source for `NSWorkspace.shared.icon(forFile:)`.
- `Rule` / `AppConfig` / `ConfigStore` (`TrafficWandCore/.../Models`, `.../Config`) for persistence.
- `GlobPattern` semantics (`*google.com` matches `google.com` **and** subdomains) — the pattern we build.
- Existing test scaffolding: `MockConfigStore` (records saves, `SettingsViewModelTests.swift`),
  `Outcomes` closure-capture (`PickerViewModelTests.swift`), Core `@Suite`/`@Test` style.

## Development Approach

- **Testing:** TDD for Core logic (write failing `swift test` first, then implement); add XCTest
  alongside App view-model/seam code. Pure-visual SwiftUI (icons, hover, layout) is verified manually +
  via `#Preview`, matching the existing "live rendering = Post-Completion manual verification" convention.
- Complete each task fully (code + tests green) before the next. Run `task test-core` / `task test`
  after each. Keep `task lint` clean. Never call `swift`/`xcodebuild`/`xcodegen` directly — go through `task`.
- Keep Core AppKit-free (the `task test-core` grep guard enforces it).

## What Goes Where

- **Implementation Steps** (checkboxes): all code + tests in this repo.
- **Post-Completion** (no checkboxes): live UX verification of hover/keyboard/icon rendering and the
  end-to-end remember-choice flow (panel display is untested by design).

---

## Implementation Steps

### Task 1: Core — registrable-domain extraction + remember-rule builder (TDD)

**Files:**
- Create: `TrafficWandCore/Sources/TrafficWandCore/Matching/RegistrableDomain.swift`
- Create: `TrafficWandCore/Sources/TrafficWandCore/Matching/RememberRule.swift`
- Create: `TrafficWandCore/Tests/TrafficWandCoreTests/RegistrableDomainTests.swift`
- Create: `TrafficWandCore/Tests/TrafficWandCoreTests/RememberRuleTests.swift`

- [x] write failing `RegistrableDomainTests` covering: `www.x.com`→`x.com`, `news.x.com`→`x.com`,
      `a.b.x.co.uk`→`x.co.uk` (embedded common 2-level suffixes: co.uk, com.au, co.jp, etc.),
      bare `x.com`→`x.com`, single-label host (`localhost`)→nil, IPv4/IPv6 literal→nil, empty→nil
- [x] implement `RegistrableDomain.of(host:) -> String?` (heuristic eTLD+1 with a small embedded
      multi-label-suffix set; document the no-PSL limitation in a doc comment)
- [x] write failing `RememberRuleTests`: a URL with a host yields a `Rule` with pattern
      `*<registrableDomain>`, `isEnabled: true`, and the passed-in `BrowserTarget`; IP-literal host →
      exact-host pattern (no leading `*`); hostless URL (`mailto:`/`file:`) → nil
- [x] implement `RememberRule.rule(forURL:target:) -> Rule?` reusing `RegistrableDomain.of`
- [x] run `task test-core` — must pass (incl. AppKit-import guard) before Task 2

### Task 2: Core — upsert-a-rule-by-pattern on AppConfig (TDD)

**Files:**
- Modify: `TrafficWandCore/Sources/TrafficWandCore/Models/AppConfig.swift`
- Create: `TrafficWandCore/Tests/TrafficWandCoreTests/AppConfigUpsertTests.swift`

- [x] write failing tests: `upserting(_:)` on a config with no matching pattern appends the rule;
      with an existing rule of the same `pattern` it replaces that rule's `target` and re-enables it
      (no duplicate); preserves order of other rules
- [x] implement `func upserting(_ rule: Rule) -> AppConfig` (pure, returns a new value)
- [x] run `task test-core` — must pass before Task 3

### Task 3: App — RulePersisting seam + ConfigRuleStore adapter

**Files:**
- Create: `App/Sources/Adapters/ConfigRuleStore.swift` (defines `protocol RulePersisting` + concrete adapter)
- Create: `App/Tests/AppTests/ConfigRuleStoreTests.swift`

- [x] define `protocol RulePersisting { func remember(url: URL, target: BrowserTarget) }` (App-side seam,
      mirroring `LastUsedRecording`)
- [x] implement `ConfigRuleStore` wrapping a `ConfigStore`: load → `RememberRule.rule(...)` →
      `AppConfig.upserting(...)` → save; swallow + log load/save errors (never crash routing)
- [x] write XCTest with the existing `MockConfigStore` pattern: remembering `https://www.x.com/...` for a
      target saves a config containing a `*x.com` rule with that target
- [x] write tests: remembering the same domain twice updates (not duplicates) the rule; a hostless URL
      saves nothing; a save error is swallowed (no throw)
- [x] run `task test` — must pass before Task 4

### Task 4: App — PickerViewModel: remember flag, flattened selectable list, keyboard nav

**Files:**
- Modify: `App/Sources/UI/Picker/PickerViewModel.swift`
- Modify: `App/Tests/AppTests/PickerViewModelTests.swift`

- [x] add `var rememberChoice: Bool = false` and `var rememberHost: String?` (computed via
      `RegistrableDomain.of` so the label matches exactly what Task 1 persists)
- [x] add a flattened `selectableItems` (ordered `(browser, profile?)` sequence: each browser's
      default row, then its profiles, in display order) and `selectedIndex` (default 0)
- [x] add `moveSelection(by:)` (clamps to `0..<count`) and `activateSelection()` (selects the
      highlighted item)
- [x] change `onSelect` to `(BrowserTarget, _ remember: Bool) -> Void`; `select(browser:profile:)`
      passes `rememberChoice`
- [x] update existing tests for the new `onSelect` signature; add tests: default `rememberChoice`
      is false; select forwards the flag; flattening order; `moveSelection` clamping at both ends;
      `activateSelection` targets the highlighted item; `rememberHost` for sample URLs
- [x] run `task test` — must pass before Task 5

### Task 5: App — Browser icon provider seam

**Files:**
- Create: `App/Sources/Adapters/BrowserIconProvider.swift`

- [x] define `protocol BrowserIconProviding { func icon(for browser: Browser) -> NSImage }`
- [x] implement `WorkspaceBrowserIconProvider` using `NSWorkspace.shared.icon(forFile: browser.appURL.path)`
      at a fixed display size
- [x] (no automated test — system/visual; the seam exists so the view can be previewed with a stub;
      covered by Post-Completion manual verification)

### Task 6: App — redesign BrowserPickerView

**Files:**
- Modify: `App/Sources/UI/Picker/BrowserPickerView.swift`

- [x] replace `BrowserRow` with row views driven by `selectableItems`: real app icon (from injected
      `BrowserIconProviding`) for browser rows, indented smaller icon for profile sub-rows
- [x] add hover highlight (`.onHover` → highlight fill) + pointer cursor (`.pointerStyle(.link)`) +
      press feedback (custom `ButtonStyle`); show the keyboard-`selectedIndex` row highlighted
      (hover takes visual precedence when the mouse is over a row)
- [x] add a `Toggle("Remember choice for \(host)", isOn: $viewModel.rememberChoice)`
      (`.toggleStyle(.checkbox)`), shown only when `rememberHost != nil`, placed above the footer
- [x] wire keyboard nav: `.focusable()` + focus on appear; `.onKeyPress(.upArrow/.downArrow)` →
      `moveSelection`, `.onKeyPress(.return)` → `activateSelection`; Esc still cancels
- [x] restyle header/footer for cohesion (link glyph, spacing/typography hierarchy); add `#Preview`s
      with a stub icon provider + sample browsers (with/without profiles)
- [x] (live rendering verified in Post-Completion; no unit test for the view itself)

### Task 7: App — wire persistence + icons through the controller

**Files:**
- Modify: `App/Sources/UI/Picker/PickerPanelController.swift`
- Modify: `App/Sources/AppMain.swift`

- [x] add `rulePersister: RulePersisting` and `iconProvider: BrowserIconProviding` to
      `PickerPanelController.init`; pass the icon provider into `BrowserPickerView`
- [x] update `handleSelection` to accept `remember: Bool`; when true, call
      `rulePersister.remember(url:target:)` before launching
- [x] in `AppMain.makeRoutingService`, hoist `FileConfigStore` into a shared `let configStore`, pass it
      to both `RoutingService` and `ConfigRuleStore(configStore:)`; construct `WorkspaceBrowserIconProvider()`
- [x] run `task test` — must pass before Task 8

### Task 8: Verify acceptance criteria
- [ ] verify the three asks: profiles hover/are obviously clickable; browsers show real icons;
      remember-choice persists a `*domain` rule
- [ ] verify keyboard nav (arrows + Return), highlight, Esc-cancel, Copy URL still work
- [ ] run `task test-core`, `task test`, `task lint` — all green
- [ ] `task build` succeeds

### Task 9: [Final] Docs + plan housekeeping
- [ ] note the new seams (`RulePersisting`, `BrowserIconProviding`) in `CLAUDE.md` "Protocol seams" if warranted
- [ ] move this plan to `docs/plans/completed/`

## Post-Completion
*Manual verification — the live `NSPanel` rendering + keyboard handling are untested by design.*

- `task run`, trigger a link, and confirm: real browser icons render; rows highlight on hover with a
  link cursor and press feedback; arrow keys move the highlight and Return opens it; Esc cancels.
- Check the remember-choice checkbox, pick a browser, then open another URL on the **same domain and a
  subdomain** — both should route automatically without the picker. Confirm a `*domain` rule now appears
  in Settings → Rules and is editable like any hand-made rule.
- Sanity-check registrable-domain edge cases live if convenient (e.g. a `*.co.uk` site).
