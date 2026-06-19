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

TrafficWand is a tiny menu-bar app that becomes your default browser. Click a link
anywhere on your Mac and it opens in the browser — and the profile — you picked for that
kind of link. Write a rule like `*.github.com → Chrome "Work"` once and stop opening links
in the wrong window.

Free, open source, no data collected. macOS 26 (Tahoe) or later.

## Download

**[Download the latest release](../../releases/latest)**, drag TrafficWand to
Applications, and launch it.

## How it works

1. **Make it your default browser** — one click in the menu bar, confirm the macOS prompt.
2. **Write a few rules** — e.g. `*.github.com → Chrome "Work"`, `*figma.com → Arc "Design"`.
   First match wins.
3. **Click links anywhere** — from Slack, Mail, your terminal — each one lands where it
   belongs.

## Features

- **Rules** — match sites with simple wildcards; the first matching rule wins.
- **Profiles** — keep Chrome "Work" and "Personal" cleanly apart (Chromium and Firefox).
- **Aliases** — name a browser+profile once, re-point every rule that uses it in one place.
- **Picker** — no rule yet? A panel asks where the link goes and can remember your choice.
- **Stays out of the way** — menu bar only, no Dock icon.
- **Works with browsers you've already opened** — routes into a running profile, no relaunch.
- **Auto-updates** and collects no data.

Everything is configured in **Settings** — rules, profiles, aliases, and the fallback for
unmatched links.

## FAQ

**How much does it cost?** Free and open source. [Sponsorship](https://github.com/sponsors/trafficwand)
is welcome.

**What data do you collect?** None. The only network activity is checking GitHub for updates.

**Which browsers are supported?** All installed browsers. Profile switching works for the
Chromium family (Chrome, Edge, Brave, Arc, …) and Firefox; Safari is link-only.

**How do I stop using it?** Set another default browser in **System Settings ▸ Desktop &
Dock**, then delete the app — it leaves nothing behind.

**Found a bug or want a feature?** [Open an issue](https://github.com/trafficwand/trafficwand/issues).

## Building from source

Needs [XcodeGen](https://github.com/yonaskolb/XcodeGen),
[SwiftLint](https://github.com/realm/SwiftLint), and [Task](https://taskfile.dev):

```sh
brew install xcodegen swiftlint
git clone https://github.com/trafficwand/trafficwand.git
cd trafficwand && task generate && task run
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for build, release, and architecture details.

## License

MIT — see [LICENSE](LICENSE). © 2026 Ildar Karymov
