# TrafficWand

**TrafficWand** is a native macOS menu-bar app that becomes your system **default
browser** and routes every clicked `http`/`https` link to the *right* browser — and
optionally the *right* profile — based on simple, user-defined wildcard domain rules.

If you juggle work and personal contexts across different browsers (or different
Chrome/Firefox profiles), TrafficWand stops you from constantly opening the wrong one.
Set it as your default browser once, write a few rules like `*.github.com → Chrome
"Work"`, and every link lands where it belongs.

- Lives quietly in the **menu bar** (no Dock icon).
- **First-match-wins** ordered rules with wildcard globs.
- Targets a **browser + optional profile** per rule (Chrome "Work", Firefox
  "Personal", …).
- Configurable **fallback** for links that match no rule: show a **picker**, send to a
  single **default browser**, or reuse the **last-used** browser.
- Profile routing that works **even when the target browser is already running**.

---

## How it works

When TrafficWand is your default browser, macOS delivers every clicked link to it via
`application(_:open:)`. TrafficWand extracts the host, finds the first enabled rule
whose glob matches, and launches the rule's browser/profile. Links matching no rule
follow your chosen fallback policy.

Profile selection is done by launching the target browser with per-family command-line
arguments (Chromium `--profile-directory=<dir>`, Firefox `-P <name>`) through
`open -n -a <app> --args …`, which reliably forwards the link into the correct profile
of an already-running browser. See [`docs/spikes/launch-mechanism.md`](docs/spikes/launch-mechanism.md)
for the full investigation behind this choice.

---

## Requirements

- macOS 26 (Tahoe) or later for the app.
- **Xcode 26+** (provides the Swift 6 toolchain and `xcodebuild`).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) and
  [SwiftLint](https://github.com/realm/SwiftLint), installed via Homebrew:

  ```sh
  brew install xcodegen swiftlint
  ```

- [Task](https://taskfile.dev) (`task`) as the command runner.

The `.xcodeproj` is **generated** by XcodeGen from `project.yml` and is not committed —
run `task generate` after a fresh clone.

---

## Build & run

All workflows go through the `Taskfile`:

| Command           | What it does                                                                                                  |
| ----------------- | ------------------------------------------------------------------------------------------------------------- |
| `task generate`   | Generate `TrafficWand.xcodeproj` from `project.yml` (XcodeGen).                                               |
| `task build`      | Build the app target (`xcodebuild build`).                                                                    |
| `task build-info` | Write `BuildInfo.xcconfig` with the current short git commit hash (auto-run by `build`/`run`/`test`/default). |
| `task run`        | Build and launch the app.                                                                                     |
| `task test`       | Run the app test target (`xcodebuild test`); includes Core via SPM.                                           |
| `task test-core`  | Run the pure Core package tests (`swift test`) + the no-AppKit guard.                                         |
| `task lint`       | Run SwiftLint across the repo.                                                                                |
| `task`            | Default: generate + build + lint + all tests.                                                                 |

Typical first run:

```sh
brew install xcodegen swiftlint
task generate
task build
task run
```

---

## Setting TrafficWand as the default browser

1. Launch TrafficWand (`task run`).
2. Click the TrafficWand item in the macOS menu bar.
3. Choose **"Set as Default Browser…"**.
4. macOS shows its standard "Do you want to change your default web browser?" prompt —
   confirm it.

The menu item shows a checkmark and reads "TrafficWand is your default browser" once it
is the active handler for `http`/`https`. To revert, pick another browser in
**System Settings ▸ Desktop & Dock ▸ Default web browser**.

---

## Rule syntax

Rules use wildcard globs matched **case-insensitively** against the **full host** of
the link (the matcher is anchored — the whole host must match, not just part of it):

| Token         | Meaning                                              |
| ------------- | --------------------------------------------------- |
| `*`           | zero or more of **any** character (including dots)  |
| `?`           | exactly **one** character                           |
| anything else | matched literally (so `.` is a literal dot)         |

Rules are evaluated **top to bottom; the first enabled rule that matches wins**. Reorder
them in Settings to set priority.

### Examples

| Pattern          | Matches                                  | Does **not** match           |
| ---------------- | ---------------------------------------- | ---------------------------- |
| `*.github.com`   | `gist.github.com`, `api.github.com`      | `github.com` (the apex)      |
| `*github.com`    | `github.com` **and** `gist.github.com`   | `notgithub.org`              |
| `*google.com`    | `google.com`, `mail.google.com`          | `google.co.uk`               |
| `mail.google.com`| `mail.google.com` exactly                | `google.com`, `imap.google.com` |

Key gotcha: `*.github.com` requires a leading subdomain (the `.` is literal), so it does
**not** match the bare apex `github.com`. Use `*github.com` if you want both the apex and
all subdomains.

---

## Profiles

Each rule can target a specific profile within a browser:

- **Chromium family** (Chrome, Edge, Brave, Vivaldi, Chromium): selected with
  `--profile-directory=<dir>`, where `<dir>` is the profile's *directory name* (e.g.
  `Default`, `Profile 1`). TrafficWand discovers these from the browser's `Local State`
  file. Profile routing into a running Chromium browser is **reliable**.
- **Firefox**: selected with `-P <name>`, where `<name>` is the profile name from
  `profiles.ini`. TrafficWand discovers these (honoring `installs.ini` defaulting).

### Launch mechanism (from the spike)

TrafficWand launches browsers via `open -n -a <app path> --args <profile flag> <url>`.
This is the only approach that delivers the profile flag + URL to the browser's own
argument parser regardless of whether the browser is already running — Chromium and
Firefox both forward such a request to their running instance over their own IPC. The
alternatives (`NSWorkspace` `OpenConfiguration.arguments`, direct-binary spawning) were
evaluated and rejected/relegated; the full reasoning, argv contract, and Hardened
Runtime implications are in [`docs/spikes/launch-mechanism.md`](docs/spikes/launch-mechanism.md).

**Firefox caveat:** opening the link in Firefox is reliable, but switching to a
*specific* profile when Firefox is **already running** is **best-effort** — Firefox's
single-instance remoting model may open the link in the already-running profile rather
than spinning up the requested one. (`-no-remote` is deliberately *not* used, because it
breaks the running-instance case entirely.) Chromium has no such limitation.

Safari and any other browser have no command-line profile selection, so rules targeting
them route the link without a profile.

---

## Fallback policy

For links that match no rule, choose one of:

- **Picker** — a floating panel appears listing your installed browsers (shown with their
  real app icons) and their profiles; pick where the link goes. Navigate with the keyboard
  (arrow keys move the highlight, Return activates the highlighted destination, Esc
  cancels) or the mouse. Tick **"Remember choice for `<domain>`"** before choosing to
  persist a rule that automatically routes that whole domain (apex + subdomains) to the
  picked browser/profile from then on. You can also copy the URL or cancel. The gear in
  the picker header opens Settings on the Rules tab, and **⌘,** opens Settings on the
  General tab — handy when the menu-bar icon is hidden behind the MacBook notch.
- **Single default browser** — the link always opens in one configured browser/profile,
  no panel.
- **Last-used** — the link reuses whichever browser/profile you last routed to. If
  nothing has been recorded yet, the picker is shown.

The picker is always the ultimate fallback.

---

## Architecture

TrafficWand is split into two layers:

- **`TrafficWandCore`** — a pure Swift SPM package (Foundation only, **zero AppKit**).
  All the decision logic lives here: glob matching, rule matching, routing decisions,
  config persistence, profile parsing, and launch-argument construction. It is
  exhaustively unit-tested via `swift test`, and a build-time guard
  (`task test-core`) fails if any Core source imports AppKit.
- **App target** — a thin AppKit/SwiftUI shell that adapts the system (`NSWorkspace`,
  `Process`, the filesystem, the menu bar, Settings, and the picker panel) to the Core
  protocols. Assembled by XcodeGen from `project.yml`.

This split keeps the trustworthy, testable logic free of UI and system dependencies; the
app is just glue. See [`CLAUDE.md`](CLAUDE.md) for the protocol seams and contributor
notes.

---

## Distribution

TrafficWand is designed for **non-sandboxed Developer ID distribution** (so it can read
browser profile configs and launch profiles without sandbox exceptions). A release build
is signed with a Developer ID Application certificate, runs with **Hardened Runtime**, is
**notarized** (and stapled) by Apple, and packaged as a **DMG**.

Full signing/notarization/DMG packaging is out of scope for v1 — see the
**Post-Completion** section of the implementation plan for the distribution checklist.

---

## License

TrafficWand is released under the MIT License. See [`LICENSE`](LICENSE) for the
full text.
