# Fix: Link is not followed if TrafficWand isn't running

Addresses [#16](https://github.com/trafficwand/trafficwand/issues/16) — "Link is not
followed if TrafficWand isn't running."

## Overview

When TrafficWand is **not already running**, clicking an `http(s)` link launches the app
but the link is never routed — the browser the link was destined for never opens.

**Root cause — a macOS cold-start URL race.** On a cold launch the sequence is:

1. LaunchServices starts TrafficWand and posts a `kAEGetURL` Apple Event for the clicked link.
2. AppKit dispatches that event to `AppMain.application(_:open:)`.
3. But `routingService` is only constructed inside `applicationDidFinishLaunching`
   (`App/Sources/AppMain.swift:72`).

If the open-URL callback fires before `applicationDidFinishLaunching` has finished wiring
`routingService`, the guard at `AppMain.swift:87`
(`guard let routingService else { … "dropping" }`) **silently drops the link**. When the
app is *already* running, `routingService` exists and the link routes fine — which is why
the bug only manifests on cold start.

> **Note on the exact ordering.** macOS *usually* defers the modern `application(_:open:)`
> callback until after `applicationDidFinishLaunching` returns, so the precise sequence
> that trips the guard isn't 100% certain from code alone. The **buffer + flush** fix is
> deliberately robust to *either* interpretation (link arrives early → buffered; link
> arrives late → routes normally), so we don't have to win that argument to fix the bug.
> Task 3 still captures `os_log` evidence on a real cold start to confirm which ordering
> actually occurs, so the manual verification is meaningful rather than assumed.

**Fix (chosen approach: Buffer + flush).** Make URL intake resilient to event ordering: if
a link arrives before the routing pipeline is ready, **buffer** it; once the pipeline is
built in `applicationDidFinishLaunching`, **flush** the buffered links through routing in
arrival order. This upholds the project's stated **"never drop a link"** principle at the
intake boundary (the same principle `RoutingService` already enforces downstream).

**Key benefit:** cold-start links route exactly like warm-start links, with no dependence
on the precise ordering of `application(_:open:)` vs `applicationDidFinishLaunching`, and
correct handling even when several links arrive during launch.

## Context (from discovery)

- **Files/components involved:**
  - `App/Sources/AppMain.swift` — the `@main` `NSApplicationDelegate`; owns
    `application(_:open:)` (intake) and `applicationDidFinishLaunching` (wiring). Current
    drop site: `AppMain.swift:87-90`.
  - `App/Sources/RoutingService.swift` — `route(url:)` is the single routing entry point;
    **unchanged** by this fix.
  - `App/Tests/AppTests/` — App test target (`xcodebuild test`), mirrors `App/Sources`.
- **Related patterns found:**
  - The App layer consistently pushes decision-shaped logic behind small seams
    (`PickerPresenting`, `RulePersisting`, `InstalledBrowsersProviding`, …) so it can be
    unit-tested with mocks while `NSWorkspace`/`Process`/AppKit stay in thin adapters.
  - `RoutingService` already documents and enforces the **"never drop a link"** principle
    (corrupt config → `AppConfig.default`; unresolvable target → picker). This bug is the
    one place a link *can* still be dropped — at intake, before routing.
- **Dependencies identified:**
  - `AppMain` cannot be instantiated cleanly in a unit test (it is `@main` and needs a live
    `NSApplication`). Therefore the buffer/flush *logic* must live in a small testable type,
    with `AppMain` reduced to thin glue over it.

## Development Approach

- **Testing approach: TDD (tests first).** For the new `LinkIntake` seam, write the failing
  test first, then implement.
- complete each task fully before moving to the next
- make small, focused changes
- **CRITICAL: every task MUST include new/updated tests** for code changes in that task
  - write unit tests for new functions/methods
  - write unit tests for modified functions/methods
  - tests cover both success and edge/error scenarios
- **CRITICAL: all tests must pass before starting next task** — no exceptions
- run tests after each change (`task test-core` for the fast loop where applicable;
  `task test` for the App target)
- maintain backward compatibility — intake behavior when the service is already ready must
  be byte-for-byte equivalent to today's path

## Testing Strategy

- **unit tests**: required for every task.
  - The buffer/flush logic is tested directly against `LinkIntake` (no AppKit / no
    `NSApplication` needed), covering: accept-before-ready buffers; activate flushes in
    arrival order; accept-after-ready routes immediately; activate with empty buffer is a
    no-op; idempotence/no double-flush.
- **e2e tests**: the project has no automated UI/e2e harness. The true end-to-end signal
  (quit app → click a link → correct browser opens) is a **manual** cold-start verification
  documented under Post-Completion (requires an installed build; cannot be unit-tested).

## Progress Tracking

- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix
- update plan if implementation deviates from original scope

## Solution Overview

Introduce a tiny, `@MainActor`, fully unit-testable **`LinkIntake`** type in the App layer
that decouples *receiving* a link from *being able to route* it:

- **Before ready:** `accept(url)` appends to an internal `pending` buffer.
- **Becoming ready:** `activate(route:)` installs the routing closure and immediately
  flushes every buffered URL through it, in arrival order, then clears the buffer.
- **After ready:** `accept(url)` routes immediately via the installed closure.

`AppMain` then becomes thin glue:

- holds a single `let intake = LinkIntake()` for the app's lifetime;
- `application(_:open:)` → `urls.forEach(intake.accept)` (no more guard-drop);
- `applicationDidFinishLaunching` → **as its last statement, after all wiring (updater,
  settings, `routingService`, `statusBarController`) is built**, calls
  `intake.activate { url in service.route(url: url) }`, capturing the **local
  `service`** value (see rationale below).

**Design decisions & rationale:**

- **Why a separate `LinkIntake` and not buffer fields on `AppMain`?** `AppMain` is the
  `@main` delegate — not unit-testable without a live `NSApplication`. Extracting the queue
  follows the established App-layer pattern (logic behind a testable seam; AppKit stays in
  thin glue) and is exactly what makes TDD possible here.
- **Why flush in arrival order?** Multiple links can be delivered during launch (e.g. a
  batch open); preserving order matches user expectation and is trivially testable.
- **Why a closure (`route:`) rather than injecting `RoutingService`?** Keeps `LinkIntake`
  ignorant of routing types (it just moves `URL`s), and lets `AppMain` hand in routing
  without `LinkIntake` depending on it — minimal coupling.
- **Why flush *last* in `applicationDidFinishLaunching`?** The flush runs **synchronously**
  on the launch stack. A buffered link that resolves to `.prompt` presents the picker
  immediately; if flushed before `statusBarController` is built (it's created *after*
  `routingService` today), the picker could appear while the app is still half-constructed.
  Flushing as the method's final statement guarantees a fully-wired app first.
- **Why capture the local `service` (not `[weak self]`)?** The closure is owned by `intake`,
  which is owned by `self` — capturing `self` strongly would risk a cycle, and `[weak self]`
  works but yields an awkward double-optional (`self?.routingService?`). Capturing the local
  `let service` value sidesteps the cycle entirely: no `self` in the closure, no optional
  chaining, and `service` is the same `@MainActor RoutingService` instance assigned to the
  property.
- **Why no locking?** `LinkIntake` is `@MainActor`, and **both** call sites
  (`application(_:open:)` and `applicationDidFinishLaunching`) are main-thread AppKit
  delegate callbacks. Under Swift 6 (`SWIFT_VERSION: "6.0"` in `project.yml`) the actor
  isolation is compiler-enforced, so `pending` needs no lock or `DispatchQueue` — adding one
  would be over-engineering.

## Technical Details

`LinkIntake` (new, `App/Sources/LinkIntake.swift`):

```swift
@MainActor
final class LinkIntake {
    private var route: ((URL) -> Void)?
    private var pending: [URL] = []

    /// Accept a link: route now if ready, otherwise buffer until `activate`.
    func accept(_ url: URL) {
        if let route { route(url) } else { pending.append(url) }
    }

    /// Install the routing handler and flush any buffered links, in arrival order.
    /// Idempotent: a second call after activation is a no-op (the handler is already
    /// installed and the buffer is empty), so callers needn't track activation state.
    func activate(route: @escaping (URL) -> Void) {
        guard self.route == nil else { return }   // already activated
        self.route = route
        let buffered = pending
        pending.removeAll()
        buffered.forEach(route)
    }
}
```

Lock-free by design: `@MainActor` isolation (Swift 6, compiler-enforced) plus both call
sites being main-thread delegate callbacks means `pending` is only ever touched on the main
thread. The `guard self.route == nil` makes a second `activate` a genuine no-op and keeps
the documented "safe to call once" contract honest. Note `pending` is cleared **before**
the flush, so a link that arrives re-entrantly *during* the flush (an `accept` triggered
from within a flushed route) routes immediately via the now-installed `self.route` rather
than being appended to a buffer that's about to be discarded.

Processing flow (cold start): `application(_:open:)` → `intake.accept(url)` → buffered →
`applicationDidFinishLaunching` builds `routingService` → `intake.activate { route }` →
buffered link flushed → `RoutingService.route(url:)` → browser opens.

Processing flow (warm start): service already active → `intake.accept(url)` routes
immediately. Equivalent to today's behavior.

## What Goes Where

- **Implementation Steps** (`[ ]` checkboxes): the `LinkIntake` type + its tests, the
  `AppMain` rewiring, acceptance verification, and doc updates — all inside this repo.
- **Post-Completion** (no checkboxes): the manual cold-start verification on an installed
  build, which requires quitting the running agent and clicking a real link.

## Implementation Steps

### Task 1: Add `LinkIntake` buffer/flush seam (TDD)

**Files:**
- Create: `App/Sources/LinkIntake.swift`
- Create: `App/Tests/AppTests/LinkIntakeTests.swift`

- [x] write failing test: `accept(url)` before `activate` buffers the URL (nothing routed yet)
- [x] write failing test: `activate(route:)` flushes a single buffered URL to the route closure
- [x] write failing test: multiple buffered URLs flush in **arrival order**
- [x] write failing test: `accept(url)` **after** `activate` routes immediately (no buffering)
- [x] write failing test: `activate` with an empty buffer routes nothing (no-op) and later
      `accept`s still route
- [x] write failing test: **warm-path equivalence** — after `activate`, N sequential
      `accept`s each route immediately, in order, with nothing buffered
- [x] write failing test: **double `activate`** — a second `activate` after activation is a
      no-op (does not re-flush, does not replace routing behavior)
- [x] write failing test: **re-entrant accept during flush** — if a flushed route synchronously
      calls `accept` again, that URL routes immediately (not lost to the cleared buffer)
- [x] create `App/Sources/LinkIntake.swift` with the `@MainActor final class LinkIntake`
      (`accept` / `activate`, with the `guard self.route == nil` idempotence guard) as
      specified in Technical Details
- [x] mirror the existing App test style: `@MainActor final class LinkIntakeTests: XCTestCase`
      with `@testable import TrafficWand` (see `RoutingServiceTests.swift`)
- [x] run App tests (`task test`) — all `LinkIntakeTests` must pass before Task 2

### Task 2: Rewire `AppMain` intake through `LinkIntake` (remove the drop)

**Files:**
- Modify: `App/Sources/AppMain.swift`

- [ ] add a `private let intake = LinkIntake()` property (retained for the app's lifetime),
      with a doc comment explaining the cold-start buffering it provides
- [ ] in `application(_:open:)`, replace the `guard let routingService … dropping` block
      with `for url in urls { Self.logger.log("Routing URL: …"); intake.accept(url) }`
      (keep the existing per-URL log line)
- [ ] capture the routing pipeline into a **local** in `applicationDidFinishLaunching`:
      assign `let service = Self.makeRoutingService(...)` and set `routingService = service`
- [ ] **as the final statement of `applicationDidFinishLaunching`** (after `statusBarController`
      is built — see Critical #1 / "flush *last*" rationale), call
      `intake.activate { url in service.route(url: url) }` capturing the local `service`
      value (no `self`, no `[weak self]`) so buffered launch links flush only once the app
      is fully wired
- [ ] remove the now-dead "Received URLs before routing service was ready; dropping." error
      path and update the `application(_:open:)` doc comment to describe buffer-until-ready
- [ ] update the file-level doc comment (lines 5–13) to note that intake buffers links that
      arrive before the routing pipeline is ready (cold-start safety)
- [ ] run App tests (`task test`) — full suite must pass before Task 3
- [ ] confirm `task lint` is clean

### Task 3: Verify acceptance criteria

- [ ] verify the Overview symptom is addressed: a link arriving before `routingService`
      exists is buffered and routed, not dropped (covered by `LinkIntakeTests`)
- [ ] verify warm-start behavior is unchanged: `accept` after `activate` routes immediately
- [ ] verify edge case: several links arriving during launch all route, in order
- [ ] **capture launch-ordering evidence:** on a real cold start (app quit), watch the
      `intake` `os_log` category in Console.app and confirm the buffered link is logged and
      then routed after launch — this confirms *which* ordering actually occurs (see the
      "Note on the exact ordering" in Overview) and proves the symptom is gone
- [ ] run full App test suite: `task test`
- [ ] run Core tests + import guard: `task test-core`
- [ ] confirm `task lint` is clean

### Task 4: [Final] Update documentation

**Files:**
- Modify: `CLAUDE.md` (add `LinkIntake` to the App-layer URL-intake description)
- Modify: this plan file (move on completion)

- [ ] add `LinkIntake` to the CLAUDE.md App-layer description for consistency with the
      other documented seams: URL intake flows `AppMain.application(_:open:)` → `LinkIntake`
      (buffers links that arrive before the pipeline is ready, flushes on launch-finish) →
      `RoutingService`
- [ ] move this plan to `docs/plans/completed/`

## Post-Completion

*Items requiring manual intervention or external systems — no checkboxes, informational only.*

**Manual verification (the true end-to-end signal — cannot be unit-tested):**

1. Build & install the change: `task install-dev` (quits any running instance; installs to
   `/Applications`, no relaunch).
2. Ensure TrafficWand is **not running** (it will not relaunch after `install-dev`).
3. Ensure TrafficWand is the default `http(s)` handler (set in Settings if needed — note
   this may require launching it once to configure, then quitting again).
4. With the app **quit**, click an `http(s)` link (e.g. from Mail, Notes, or
   `open https://example.com` after confirming the default handler) — or trigger a link
   that matches a configured rule.
5. **Expected:** TrafficWand launches **and** the link routes to the correct browser /
   shows the picker per the matching rule — no dropped link.
6. Repeat the warm-start case (app already running) to confirm no regression.

**Notes:**
- `os_log` category `intake` ("Routing URL: …") can be watched in Console.app to confirm the
  buffered link is processed after launch.
