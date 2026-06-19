<p align="center">
  <img src=".github/assets/logo.png" alt="TrafficWand" width="160">
</p>
<h1 align="center">TrafficWand</h1>
<p align="center"><strong>Open every link in the right browser.</strong></p>

<p align="center">
  <a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/trafficwand/trafficwand" alt="Latest release"></a>
  <a href="https://github.com/trafficwand/trafficwand/actions/workflows/ci.yml"><img src="https://github.com/trafficwand/trafficwand/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/trafficwand/trafficwand" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/macOS-26%20Tahoe%2B-blue" alt="macOS 26 Tahoe or later">
</p>

TrafficWand is a tiny menu-bar app that becomes your default browser. When you click a
link anywhere on your Mac, it opens in the browser — and the profile — you picked for
that kind of link. Write a rule like `*.github.com → Chrome "Work"` once and stop
opening links in the wrong window.

Set up your rules once and forget about it. TrafficWand is free and open source, and runs
on macOS 26 (Tahoe) or later.

## Download

**[Download the latest release](../../releases/latest)** — grab the `.dmg`, drag
TrafficWand to Applications, and launch it.

It's a notarized Developer ID app, so it opens without Gatekeeper warnings. Requires
macOS 26 (Tahoe) or later.

---

## How it works

1. **Make it your default browser.** One click in the menu bar, then confirm the standard
   macOS prompt. That's it — TrafficWand now receives every link you click.
2. **Write a few rules.** Tell TrafficWand which sites open where, for example
   `*.github.com → Chrome "Work"` or `*figma.com → Arc "Design"`. First match wins.
3. **Click links anywhere.** From Slack, Mail, your terminal, anywhere — each link routes
   to the right browser and the right profile automatically.

Under the hood: when TrafficWand is your default browser, macOS delivers every clicked
link to it via `application(_:open:)`. TrafficWand extracts the host, finds the first
enabled rule whose glob matches, and launches the rule's browser/profile. Links matching
no rule follow your chosen fallback policy.

Profile selection is done by launching the target browser via per-family command-line
arguments — see [Profiles](#profiles) for details.

---

## Features

- **Rules** — tell TrafficWand which sites open in which browser. Rules are evaluated
  top-to-bottom; the first match wins.
- **Work stays at work** — route per profile, so Chrome "Work" and Chrome "Personal" stay
  cleanly separated (and the same for any Chromium- or Firefox-family browser).
- **Aliases** — give a browser+profile a name (e.g. **"Work"**) and re-point every rule
  that uses it in one place.
- **No rule yet?** — a picker panel asks where the link should go, and can remember your
  choice as a new rule.
- **Lives in the menu bar** — no Dock icon, stays out of the way.
- **Works with browsers you've already opened** — links route into a running browser's
  profile, no relaunch.
- **Tells you about updates** — checks for new versions automatically.
- **Free and open source** — collects no data.

The sections below cover [profiles](#profiles), [aliases](#aliases), and the
[fallback policy](#fallback-policy) in detail.

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

For building a **release DMG** (`task dmg`) you additionally need:

- Enrollment in the [Apple Developer Program](https://developer.apple.com/programs/) (for
  a Developer ID Application certificate + notarization access).
- [`create-dmg`](https://github.com/create-dmg/create-dmg), installed via Homebrew:

  ```sh
  brew install create-dmg
  ```

See §Distribution below for the full release setup.

The `.xcodeproj` is **generated** by XcodeGen from `project.yml` and is not committed —
run `task generate` after a fresh clone.

---

## Build & run

All workflows go through the `Taskfile`:

| Command           | What it does                                                                                                  |
| ----------------- | ------------------------------------------------------------------------------------------------------------- |
| `task generate`   | Generate `TrafficWand.xcodeproj` from `project.yml` (XcodeGen).                                               |
| `task build`      | Build the app target (`xcodebuild build`). Accepts an optional `CONFIG` var (default `Debug`; e.g. `CONFIG=Release task build`). |
| `task build-info` | Write `BuildInfo.xcconfig` with the current short git commit hash (auto-run by `build`/`run`/`test`/default).                   |
| `task run`        | Build and launch the app.                                                                                                         |
| `task test`       | Run the app test target (`xcodebuild test`); includes Core via SPM.                                                               |
| `task test-core`  | Run the pure Core package tests (`swift test`) + the no-AppKit guard.                                                             |
| `task lint`       | Run SwiftLint across the repo.                                                                                                    |
| `task dmg`        | Build, sign, notarize, and package the app as a DMG (release — see §Distribution for setup).                                     |
| `task install`    | Release build installed to `/Applications`. Quits any running instance; does not relaunch. (unsigned — Gatekeeper may prompt on first launch) |
| `task install-dev` | Debug build installed to `/Applications`. Quits any running instance; does not relaunch.                                       |
| `task`            | Default: generate + build + lint + all tests.                                                                                     |

Typical first run:

```sh
brew install xcodegen swiftlint
task generate
task build
task run
```

---

## Setting TrafficWand as the default browser

On first launch, TrafficWand shows a short onboarding tour (where to find it in the menu
bar, how to set it as your default browser, and a quick intro to rules and aliases) with a
**Set as Default** button and a shortcut into Settings. It appears only once. You can also
set the default browser manually at any time:

1. Launch TrafficWand (`task run`).
2. Click the TrafficWand item in the macOS menu bar.
3. Choose **"Set as Default Browser…"**.
4. macOS shows its standard "Do you want to change your default web browser?" prompt —
   confirm it.

The menu item shows a checkmark and reads "TrafficWand is your default browser" once it
is the active handler for `http`/`https`. To revert, pick another browser in
**System Settings ▸ Desktop & Dock ▸ Default web browser**.

TrafficWand keeps itself up to date automatically via Sparkle — toggle background checks
in **Settings ▸ General**, or use **"Check for Updates…"** in the menu bar.

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

- **Chromium family** (Chrome, Edge, Brave, Vivaldi, Chromium, Arc, Dia, Comet, Helium,
  and any other non-Firefox browser — Chromium is the catch-all default): selected with
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

Safari has no command-line profile selection, so rules targeting it route the link
without a profile. Every other non-Firefox browser is treated as Chromium and uses
`--profile-directory=<dir>` when a profile is set (unknown browsers simply carry no
profile, so they launch their default).

---

## Aliases

Instead of repeating the same browser/profile across many rules, define a reusable
**alias** — a named binding to a concrete browser + profile (e.g. **"Work"** → Chrome
"Work Profile"). Rules and the default-browser fallback can then target *either* a
concrete browser/profile *or* an alias.

The point is late binding: rules store a *reference* to the alias, not a copy. Re-point
**"Work"** at a different browser in the **Aliases** tab and every rule (and the fallback)
that targets **"Work"** follows the change at once — no rule-by-rule editing.

- Manage aliases in **Settings ▸ Aliases**: a master-detail tab — pick an alias from the
  sidebar list and edit it inline in the detail pane. Edits persist live (the name commits
  when you press Enter or click away; the browser/profile commits on change), so there's no
  Save/Cancel step. **Add** drops in a new alias and selects it.
- In the rule editor and the default-browser fallback, switch the destination between a
  concrete **Browser** and an **Alias**.
- The **picker** lists your aliases too (in an **Aliases** section above the browsers), so
  you can route a one-off link — or *remember* one — to an alias.
- An alias that is still referenced by a rule or the fallback **cannot be deleted** until
  the references are removed — the UI tells you which rules block it.
- If an alias reference is ever dangling (e.g. a hand-edited config), the link safely
  falls through to the **picker** rather than being dropped or misrouted.

When you pick an **alias** in the picker and tick "Remember choice for `<domain>`", the
saved rule references that alias by name — so re-pointing the alias later also re-routes
the remembered site. Picking a concrete **browser/profile** instead remembers that exact
choice.

---

## Fallback policy

For links that match no rule, choose one of:

- **Picker** — a floating panel appears listing your aliases (in an **Aliases** section at
  the top) and your installed browsers (shown with their real app icons) and their
  profiles; pick where the link goes. Navigate with the keyboard (arrow keys move the
  highlight, Return activates the highlighted destination, Esc cancels) or the mouse. Tick
  **"Remember choice for `<domain>`"** before choosing to persist a rule that automatically
  routes that whole domain (apex + subdomains) to the picked destination from then on (an
  alias pick is remembered *as the alias*; a concrete pick as that browser/profile). You can also copy the URL or cancel. The gear in
  the picker header opens Settings on the Rules tab, and **⌘,** opens Settings on the
  General tab — handy when the menu-bar icon is hidden behind the MacBook notch.
- **Single default browser** — the link always opens in one configured browser/profile,
  no panel.
- **Last-used** — the link reuses whichever browser/profile you last routed to. If
  nothing has been recorded yet, the picker is shown.

The picker is always the ultimate fallback.

---

## FAQ

**How much does it cost?**
TrafficWand is free and open source. If you'd like to support it, sponsorship is welcome
via [GitHub Sponsors](https://github.com/sponsors/trafficwand).

**What data do you collect?**
None. The only network activity is checking GitHub for updates.

**What does it require?**
macOS 26 (Tahoe) or later. It's a notarized Developer ID app, so it opens without
Gatekeeper warnings.

**Which browsers and profiles are supported?**
All installed browsers. Profile switching works for the Chromium family (Chrome, Edge,
Brave, Arc, and more) and Firefox; Safari is link-only (no profile selection).

**How do I stop using it?**
Change your default browser back in **System Settings ▸ Desktop & Dock**, then delete the
app — it leaves nothing behind.

**Found a bug or want a feature?**
Open an issue: <https://github.com/trafficwand/trafficwand/issues>.

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

TrafficWand is distributed as a **non-sandboxed Developer ID** app (so it can read
browser profile configs and launch profiles without sandbox exceptions): signed with a
Developer ID Application certificate, **Hardened Runtime** enabled, **notarized** and
stapled by Apple, packaged as a **DMG**.

Building a release DMG requires enrollment in the Apple Developer Program. One-time
setup:

```sh
brew install create-dmg
```

Then provide the four notary credentials. The easiest way is a gitignored
`.dmg.env` file at the repo root — copy the template and fill it in once:

```sh
cp .dmg.env.example .dmg.env
$EDITOR .dmg.env
```

`.dmg.env.example` documents where each value comes from (Team ID, the Developer ID
Application certificate, and the app-specific password). `scripts/build-dmg.sh` sources
`.dmg.env` automatically. Alternatively, export the four vars
(`DEVELOPER_ID_APPLICATION`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD`)
in your shell — in CI they come from environment secrets, so no file is needed there.

Validate the setup without running the full pipeline:

```sh
scripts/build-dmg.sh --preflight
```

Then produce a release:

```sh
task dmg
```

Output lands at `dist/TrafficWand-<version>.dmg`, ready to upload as a GitHub release
asset.

### Updates

Installed copies keep themselves current via [Sparkle](https://sparkle-project.org): the
menu bar exposes a **"Check for Updates…"** item for an on-demand check, and the app also
checks automatically in the background (toggle in **Settings ▸ General**). Updates are
EdDSA-signed and downloaded from the GitHub Releases page, so no manual re-download is
needed once you're on a Sparkle-enabled release.

### Automated releases

Pushing a `v*.*.*` tag does this automatically. The
[`release.yml`](.github/workflows/release.yml) workflow runs the same `task dmg`
pipeline in CI and creates (or updates) the matching GitHub Release with auto-generated
notes and the signed, notarized DMG attached. Bump `MARKETING_VERSION` in `project.yml`
to match the tag before pushing — a mismatch fails the job before the build. Grab the
signed DMG from the [Releases](../../releases) page.

This requires seven repository secrets (Settings → Secrets and variables → Actions): the
four notary credentials above (`DEVELOPER_ID_APPLICATION`, `APPLE_ID`, `APPLE_TEAM_ID`,
`APPLE_APP_SPECIFIC_PASSWORD`) plus, so CI can import the signing identity into a
throwaway keychain, `MACOS_CERTIFICATE_P12_BASE64` (base64 of the exported `.p12`
containing the certificate **and** its private key) and `MACOS_CERTIFICATE_PASSWORD`
(the `.p12` password), plus `SPARKLE_ED_PRIVATE_KEY` (the EdDSA private key used to sign
the update appcast). CI signs the DMG, renders `appcast.xml`, and uploads it as a release
asset; the app's feed URL is the stable `releases/latest/download/appcast.xml` redirect.

---

## License

TrafficWand is released under the MIT License. See [`LICENSE`](LICENSE) for the
full text.
