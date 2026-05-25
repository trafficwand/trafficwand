# Spike: Browser launch mechanism for profile routing

**Status:** Decision recorded. Live profile-switching confirmation against a
*running* browser is deferred to Post-Completion manual verification (see the end
of this note). All automatable analysis and the argv contract are final.

**Task:** [Task 2 — Launch-mechanism spike](../plans/20260525-trafficwand-browser-router.md)

**Consumers of this decision:** Task 8 (`TrafficWandCore.LaunchArguments`) and
Task 11 (`App.BrowserLauncher`). The argv contract below is the spec those tasks
implement and unit-test.

---

## 1. The core problem

TrafficWand must open a clicked link in a **specific browser profile**. The only
robust, cross-browser way to select a profile is to pass a per-family CLI flag at
launch (`--profile-directory=…` for Chromium, `-P <name>` for Firefox). So the
question is: **how do we hand argv (profile flag + URL) to the target browser in
a way that works whether or not the browser is already running?**

The trap is `NSWorkspace` + `OpenConfiguration.arguments`:

```swift
let cfg = NSWorkspace.OpenConfiguration()
cfg.arguments = ["--profile-directory=Profile 1", url.absoluteString]
NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: cfg) { _, _ in }
```

`OpenConfiguration.arguments` is delivered to the app **only on a *fresh*
launch** — it becomes the new process's `argv`. If the target browser is
**already running**, Launch Services does *not* spawn a new process; it reactivates
the existing one and routes the request through the normal Apple-Event open path
(`kAEGetURL` / `application(_:open:)`). The `arguments` are **silently dropped**.

Consequence: the very first link to a browser might land in the right profile
(cold start), but every subsequent link — while that browser is running — would
ignore the profile flag and open in whatever profile the running instance feels
like (typically the last-focused window's profile). That is exactly the failure
mode TrafficWand exists to prevent, and it would be intermittent and confusing.
This is **Acceptance Criterion #3**: "Profile routing works even when the target
browser is already running."

So `NSWorkspace.open(...configuration:)` is disqualified as the *primary*
mechanism. We need a path that forces argv to reach the browser's own argument
parser regardless of running state. Chromium and Firefox both implement
**single-instance forwarding**: a *second* process started with a profile flag +
URL parses that argv itself and forwards "open this URL in this profile" to the
already-running primary instance over the browser's own IPC (not via Apple
Events). That is the behavior we must trigger.

---

## 2. Candidate mechanisms

### (a) `NSWorkspace.open(_:withApplicationAt:configuration:)` with `arguments`

```swift
let cfg = NSWorkspace.OpenConfiguration()
cfg.arguments = ["--profile-directory=Profile 1", url.absoluteString]
cfg.createsNewApplicationInstance = false   // default
NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: cfg) { _, err in }
```

- **Cold start (browser not running):** argv delivered → correct profile + URL.
- **Already running:** Launch Services reactivates the existing process; `arguments`
  are dropped; URL is delivered via the Apple-Event open path with **no** profile
  flag → **wrong profile**. ❌
- `createsNewApplicationInstance = true` *would* force a new process (and thus
  argv delivery), but for Chromium/Firefox a forced second instance with the same
  profile dir either errors ("profile already in use") or is reaped after it
  forwards — behavior is browser- and version-dependent and not something we want
  to rely on. Not a clean contract.
- **Verdict:** unreliable for the running-browser case. Rejected as primary.

### (b) `Process` → `/usr/bin/open -na "<App>" --args <profile-flag> <url>`

```swift
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
p.arguments = ["-n", "-a", "Google Chrome", "--args", "--profile-directory=Profile 1", url.absoluteString]
try p.run()
```

- `open -n` requests a **new instance** of the application; `--args` passes
  everything after it to that instance's `argv`. The freshly spawned Chromium/
  Firefox process parses `--profile-directory` / `-P` + URL, sees a primary
  instance is already running, **forwards the open-in-profile request to it via
  the browser's own IPC**, then exits. This is precisely Chromium's and Firefox's
  documented multi-instance forwarding behavior, and it is how Velja /
  Browserosaurus / Finicky / Choosy all achieve profile routing into a running
  browser.
- **Cold start:** the spawned process *is* the primary instance → opens directly
  in the right profile. ✅
- **Already running:** spawned process forwards to the primary → URL opens in the
  requested profile in the running browser. ✅ (the case (a) cannot do)
- Resolving the app by **name** (`-a "Google Chrome"`) is brittle if multiple
  copies exist or the name differs by locale/channel. Prefer resolving the app's
  **path/bundle** ourselves (we already have `appURL` from
  `NSWorkspace.urlsForApplications`) and passing it to `open`:
  `open -n -a "/Applications/Google Chrome.app" --args …`. `open -b <bundleID>`
  is another option but `-b` + `--args` is less predictable than `-a <path>`.
- **Verdict:** reliable for both states. Strong candidate.

### (c) `Process` → direct binary in `Contents/MacOS`

```swift
let exe = appURL.appendingPathComponent("Contents/MacOS/Google Chrome")
let p = Process()
p.executableURL = exe
p.arguments = ["--profile-directory=Profile 1", url.absoluteString]
try p.run()
```

- Functionally equivalent to (b): a fresh browser process is spawned with our argv
  and uses the same single-instance forwarding. ✅ both states.
- **Downsides vs (b):**
  - We must discover the executable name inside `Contents/MacOS/` (usually the
    `CFBundleExecutable` from the bundle's Info.plist; often but **not always**
    the same as the display name — e.g. "Google Chrome", "firefox",
    "Microsoft Edge"). One more failure point.
  - Bypasses Launch Services activation niceties (foregrounding/Dock behavior,
    App Nap exemptions, transient-process bookkeeping). `open` is the
    Apple-blessed front door and handles these for us.
  - The spawned process becomes a **child of TrafficWand**; if it does not fully
    detach we could inherit lifetime/teardown coupling. `open` deliberately
    decouples (the launched app is *not* our child).
- **Verdict:** works, but strictly worse ergonomics than (b). Fallback only.

---

## 3. Decision

**Primary mechanism: (b) `Process` → `/usr/bin/open -n -a <app-path> --args <argv…>`.**

Rationale:

1. **Correct for the running-browser case** (the whole point of the spike), via
   Chromium/Firefox single-instance forwarding — the same approach proven by all
   four prior-art tools (Velja, Browserosaurus, Finicky, Choosy).
2. **Correct for the cold-start case** too (the spawned process becomes the
   primary), so we need only one code path, not a "running vs not" branch.
3. **`open` is the supported front door:** Launch Services handles activation,
   detaching, and process bookkeeping. We avoid guessing the `CFBundleExecutable`
   name (the weak point of (c)).
4. **We pass the resolved app path** (from `NSWorkspace.urlsForApplications`),
   not a display name, eliminating name-ambiguity.

**Fallback mechanism: (c) direct binary.** If a specific browser ever misbehaves
under `open -n` (e.g. refuses `--args` for some channel), we can spawn the
`CFBundleExecutable` directly with the identical argv tail. Same argv contract, so
the Core-level `LaunchArguments` does not change — only the App-level executable
resolution differs. We do **not** implement (c) in v1; it is noted as the escape
hatch.

**(a) `NSWorkspace OpenConfiguration.arguments` is rejected** as a launch path
because it cannot carry argv to an already-running browser.

> Note for the no-profile / Safari path: when a target has **no** profile, there
> is no need to spawn via `open -n`. A plain
> `NSWorkspace.shared.open([url], withApplicationAt: appURL, …)` (or even
> `open -a <app> <url>`) is fine because there is no argv contract to honor —
> the standard open-document path is correct. Task 11 may take that simpler
> branch when `BrowserTarget.profileID == nil`. The argv contract below still
> defines what `LaunchArguments` returns in every case so the builder is uniform
> and fully unit-tested.

---

## 4. The argv contract (the deliverable for Tasks 8 & 11)

`LaunchArguments.build(for: BrowserTarget, url: URL) -> [String]` returns the argv
**tail** — i.e. everything that follows `--args` under mechanism (b), or
everything after the executable under (c). It does **not** include the executable
path, `open`, `-n`, `-a`, or `--args`; those belong to the App-level launcher.

The **URL is always the last element** of the tail. Profile flags come first, then
the URL. This ordering matches every prior-art tool and avoids the URL being
mistaken for a flag value.

### Chromium family

Bundle IDs: `com.google.Chrome`, `com.google.Chrome.beta`,
`com.google.Chrome.canary`, `com.microsoft.edgemac`, `com.brave.Browser`,
`com.vivaldi.Vivaldi`, `org.chromium.Chromium` (allowlist lives in
`BrowserFamily`; extend as needed).

| Case | argv tail |
| --- | --- |
| With profile (dir = `info_cache` key, e.g. `"Profile 1"`, `"Default"`) | `["--profile-directory=<dir>", "<url>"]` |
| No profile | `["<url>"]` |

- The flag is `--profile-directory=<dir>` where `<dir>` is the **directory name**
  (the key in `Local State` → `profile.info_cache`), *not* the display name. The
  Chrome reader in Task 9 yields directory names as `BrowserProfile.id`.
- `<dir>` values commonly contain a space ("Profile 1"). Because each argv element
  is passed as a **separate array element** to `Process` (no shell), no quoting is
  needed; the space is preserved literally. The `=` form keeps flag and value in a
  single argv element, which is the safest with `open --args`.

### Firefox family

Bundle ID: `org.mozilla.firefox` (plus ESR/Developer variants if added later).

| Case | argv tail |
| --- | --- |
| With profile (name from `profiles.ini`, e.g. `"default-release"`) | `["-P", "<name>", "<url>"]` |
| No profile | `["<url>"]` |

- Firefox selects a profile by **name** via two separate argv tokens: `-P` then
  the name. The name is the `Name=` value in `profiles.ini` (Task 9 yields it as
  `BrowserProfile.id` for Firefox).

#### `-no-remote`: do we need it?

**Decision: do NOT use `-no-remote` for profile routing.**

- `-no-remote` tells the new Firefox process *not* to talk to an existing instance
  — it forces a brand-new, isolated instance. With a running Firefox that holds
  the target profile, `-no-remote -P <name>` typically **fails** with
  "Firefox is already running, but is not responding / profile in use", because
  the profile's lock is held by the running instance. That breaks exactly the
  running-browser case we must support.
- The behavior we *want* is the opposite: let the spawned process **remote into**
  the running instance and ask it to open the URL in `<name>`. That is the default
  (remoting **on**), so we simply omit `-no-remote`.
- Tradeoff: without `-no-remote`, if Firefox is running with profile A and a rule
  targets profile B, Firefox's remoting will open the URL in a window of the
  *already-running* profile-A instance rather than spinning up profile B — Firefox
  shares one running instance across the "default" profile and will not silently
  switch the active profile via remoting in all configurations. This is a known
  Firefox limitation (multiple simultaneous profiles need either separate
  instances via `-no-remote` *and* separate profile locks, or the newer
  per-profile "profile groups"). For TrafficWand v1 we accept the default-remoting
  behavior (URL opens in Firefox, profile selection best-effort) and document the
  limitation. Chromium has no such limitation — `--profile-directory` routes
  correctly into a running instance. This nuance is flagged for the
  running-browser manual verification.

### Safari / unknown / no profile

Bundle ID `com.apple.Safari`, or any bundle ID not in the Chromium/Firefox
allowlists, or any target with `profileID == nil`:

| Case | argv tail |
| --- | --- |
| Always | `["<url>"]` |

Safari has no command-line profile-selection flag, so there is nothing to add. The
launcher may take the simpler `NSWorkspace.open([url], withApplicationAt:)` path
here (see the note in §3).

### Summary table (Task 8 unit-test oracle)

| Family | profileID | `LaunchArguments.build` →  |
| --- | --- | --- |
| Chromium | `"Profile 1"` | `["--profile-directory=Profile 1", "https://x/"]` |
| Chromium | `nil` | `["https://x/"]` |
| Firefox | `"default-release"` | `["-P", "default-release", "https://x/"]` |
| Firefox | `nil` | `["https://x/"]` |
| Safari | (any) | `["https://x/"]` |
| Unknown | (any) | `["https://x/"]` |

The URL element uses `url.absoluteString`.

---

## 5. Concrete code shape (for Task 11)

This is the shape the App-level `BrowserLauncher` will take. No persistent spike
Swift file is checked in (the scaffolding was used only to confirm the calls
compile, then removed — see §7); the contract is captured here.

```swift
// App-side, conforms to Core's BrowserLaunching.
func launch(_ target: BrowserTarget, browser: Browser, url: URL) throws {
    let argvTail = LaunchArguments.build(for: target, url: url)   // Core, pure

    // Primary mechanism (b): open -n -a <app path> --args <argvTail…>
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-n", "-a", browser.appURL.path, "--args"] + argvTail
    try process.run()
    // We do NOT waitUntilExit(); `open` returns immediately and the launched
    // app is detached (not our child).
}
```

The only line that cannot be exercised in a unit test is `process.run()` (it
spawns a real browser). Task 11 unit-tests the **pure command builder** that
produces `(executableURL, ["-n", "-a", appPath, "--args"] + argvTail)` from
`(Browser, BrowserTarget, URL)`; the live `run()` is covered by Post-Completion
manual verification.

---

## 6. Hardened Runtime / sandbox implications

- **Spawning subprocesses from a Hardened-Runtime app is allowed.** Hardened
  Runtime restricts things like loading unsigned libraries, JIT, and debugging
  the *current* process — it does **not** forbid `Process`/`posix_spawn` of other
  executables. Launching `/usr/bin/open` (an Apple-signed binary) or another
  signed browser binary needs **no special entitlement**.
- There is **no `com.apple.security.cs.allow-...` entitlement required** for
  launching other apps. (The "allow-unsigned-executable-memory" /
  "disable-library-validation" entitlements are about loading code *into our*
  process, not about spawning other processes — not needed here.)
- TrafficWand is **non-sandboxed** (Developer ID, per the plan). With App Sandbox
  there would be extra friction spawning arbitrary binaries; because we are not
  sandboxed, `Process` → `open` is unrestricted.
- Reading other browsers' `~/Library/Application Support` for profile discovery
  (Task 9) is also fine for a non-sandboxed app and is **not** TCC-protected
  (that subtree is not Desktop/Documents/Downloads). No privacy prompt expected.
- As recorded in `project.yml`, local ad-hoc signing disables Hardened Runtime
  anyway; it becomes meaningful only at Developer ID release signing /
  notarization. Either way the conclusion holds: no extra entitlement is needed
  for the launch mechanism.

---

## 7. Spike scaffolding cleanup

Per the plan's "remove/disable `LaunchSpike.swift` scaffolding once findings are
captured (no dead code left)" checkbox: the candidate calls were expressed in
code to confirm the API shapes compile, then **not** persisted. There is **no
`App/Sources/Spike/LaunchSpike.swift` in the committed tree** — the validated code
shape lives in §5 above instead, so the final tree carries no dead spike code.
The existing build (`swift test`, `task test-core`) remains green; no App sources
were modified by this spike.

---

## 8. Deferred: live confirmation (Post-Completion manual verification)

The following require a live machine, real browsers with ≥2 profiles each, and
human observation of which profile window opens — **not automatable from an
agent**. They are expected to confirm the decision above and are part of the
plan's Post-Completion manual verification:

- **Chrome running, ≥2 profiles:** `open -n -a "Google Chrome" --args
  --profile-directory="Profile 1" <url>` opens the URL in *Profile 1* in the
  running Chrome (and likewise for a different profile). **Expected: pass**
  (Chromium forwarding routes by profile dir).
- **Edge / Brave / Vivaldi:** same expectation as Chrome (same Chromium flag).
- **Firefox running, ≥2 profiles:** `open -n -a "Firefox" --args -P <name> <url>`
  opens the URL in Firefox. **Expected: URL opens; profile selection best-effort**
  per the `-no-remote` discussion in §4 (Firefox remoting may open in the
  already-running profile rather than switching). Document the observed behavior;
  if profile switching proves unreliable, mark Firefox profile routing
  "best-effort" in the README per the plan's ⚠️ scope-adjustment checkbox.
- **Cold-start vs already-running** for each: confirm both states route correctly
  for Chromium; record Firefox's behavior in each state.

### Reliability verdict (the ⚠️ checkbox)

Based on documented macOS Launch Services behavior, the documented single-instance
forwarding of Chromium and Firefox, and the convergent prior art (Velja,
Browserosaurus, Finicky, Choosy all use `open -n … --args` / direct-binary
spawning for exactly this):

- **Chromium family — reliable.** `open -n -a <app> --args --profile-directory=<dir>
  <url>` switches profiles correctly for a running browser. No scope change.
- **Firefox — reliable for opening the URL; profile selection is best-effort**
  for the already-running case due to Firefox's single-instance remoting model.
  This is a **scope note**, not a blocker: TrafficWand will still target the
  Firefox profile via `-P <name>`, and it works on cold start; the running-instance
  caveat is documented and surfaced to the user (README + manual verification).
  No code-path change is needed — the argv contract is unchanged.

Net: a reliable mechanism **exists** and is chosen. The only caveat
(Firefox running-instance profile switching) is documented as best-effort rather
than triggering a scope cut.
