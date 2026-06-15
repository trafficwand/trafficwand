# Spike: Sparkle in-app updates — keys, signing, notarization, appcast

**Status:** Decision recorded. The reproducible facts (key custody, CI signing
contract, nested-helper notarization verification recipe, appcast format,
bootstrap rule) are final. The one-time `generate_keys` run and the
`SPARKLE_ED_PRIVATE_KEY` repo-secret upload are **operator actions** done at
release-setup time (see §6); they cannot and must not be automated from an agent
because the EdDSA private key must be preserved forever.

**Task:** [Task 6 — Generate EdDSA keys, add the secret, write the spike doc](../plans/20260530-integrate-sparkle-updates.md)

**Consumers of this decision:** Task 6 (operator: real `SUPublicEDKey` in
`Info.plist`), Task 7 (`scripts/generate-appcast.sh` + `release.yml` CI signing),
and Task 8 (nested-helper notarization verification of the exported `.app`).

TrafficWand is distributed outside the App Store as a Developer-ID-signed,
notarized DMG on GitHub Releases. Sparkle 2.x (pinned via SPM `from: "2.9.2"` in
`project.yml`) provides the self-update path. The app is **non-sandboxed** with
Hardened Runtime — the simplest Sparkle case (no installer-launcher XPC service,
no sandbox temporary exceptions, no extra entitlements).

---

## 1. EdDSA key handling and rotation

Sparkle verifies every update with an **EdDSA (Ed25519) signature** that is
independent of Apple code-signing/notarization. The keypair is generated **once**
with Sparkle's `generate_keys` tool (shipped in the Sparkle release tarball,
`bin/generate_keys`).

- **Generate once (operator, locally):**
  ```sh
  task sparkle:gen-keys
  ```
  This downloads the pinned Sparkle tools if needed (`task sparkle:install`, into
  the gitignored `.sparkle/`) and runs `generate_keys`. On first run it creates the
  keypair and stores the **private key in the macOS login Keychain** (item: "Private
  key for signing Sparkle updates", service `https://sparkle-project.org`). It prints
  the **public key** to stdout. The private key never leaves the Keychain unless
  explicitly exported. (Equivalent to running `.sparkle/bin/generate_keys` directly.)

- **Public key → `Info.plist`:** put the printed public key in
  `App/Resources/Info.plist` under `SUPublicEDKey`. Until the operator does this,
  the value is the placeholder `__PUBLIC_ED_KEY__` (intentionally non-functional;
  do **not** replace it from an agent — see §6).

- **Export the private key for CI:**
  ```sh
  .sparkle/bin/generate_keys -x sparkle_private_key.txt
  ```
  `-x <file>` exports the existing private key to a file. The contents of that
  file become the GitHub Actions repo secret **`SPARKLE_ED_PRIVATE_KEY`**
  (Settings → Secrets and variables → Actions). Delete the local export file
  afterward; the authoritative copy stays in the Keychain.

- **Key custody / rotation — the rule that matters:** the EdDSA private key must
  be **preserved forever**. There is no recovery mechanism: lose it and you can no
  longer sign updates that already-installed apps will accept. "Rotation" is not
  in-place — it means **shipping a new public key in a new app version**: build a
  release whose `Info.plist` carries the new `SUPublicEDKey`, signed with the
  *old* key (so existing installs accept that one update), after which the new key
  governs. Old (compromised/lost) keys cannot be recovered, only superseded going
  forward. Treat the Keychain private key and the `SPARKLE_ED_PRIVATE_KEY` secret
  as long-lived, irreplaceable credentials.

---

## 2. CI signing of the DMG (`sign_update`)

Each release's DMG gets an EdDSA signature via Sparkle's `sign_update` tool, run
in `release.yml` / `scripts/generate-appcast.sh` (Task 7).

- **Private key via stdin, not CLI arg.** Pass the key on **stdin**:
  ```sh
  printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | ./bin/sign_update --ed-key-file - dist/TrafficWand-<v>.dmg
  ```
  The `-s <key>` CLI-argument form is **deprecated since Sparkle 2.2.2** (it leaks
  the key into the process table / `ps`), so we feed it through stdin instead.
  `sign_update` prints the `sparkle:edSignature="…"` and `length="…"` attributes
  that go straight into the appcast `<enclosure>`.

- **Pin the tool to the SPM version.** The `sign_update` (and `generate_keys`)
  binaries come from the **Sparkle release tarball pinned to the same version as
  the SPM `from:` constraint** — currently **2.9.2** (`project.yml` `packages:` →
  `Sparkle`). Download that exact tarball
  (`Sparkle-2.9.2.tar.xz` from the Sparkle GitHub release), **verify its
  checksum** before use, and run the tools from it. Pinning + checksum keeps the
  signer reproducible and prevents a supply-chain swap of the signing tool.

- **Quarantine.** A tool extracted from a downloaded tarball may carry
  `com.apple.quarantine`; clear it before running if present:
  ```sh
  xattr -dr com.apple.quarantine <extracted-sparkle-dir>
  ```

---

## 3. Nested-XPC / Autoupdate notarization verification (the canonical failure)

Sparkle embeds nested code inside the app bundle —
`Contents/Frameworks/Sparkle.framework`, and inside it the **`Autoupdate`**
helper (`Autoupdate.app` / `Updater.app`) and **`XPCServices`**
(`Downloader.xpc`, `Installer.xpc` on sandboxed apps). The **canonical Sparkle
notarization failure** is a nested helper that lacks the **Hardened Runtime**
flag and/or a **secure timestamp** — notarization rejects the bundle, or
Gatekeeper rejects the updated app after an in-place update.

Our existing pipeline (`xcodebuild archive` → `exportArchive` with deep nested
Developer-ID signing → notarize) signs these helpers correctly, but this is
**verified explicitly** on the exported `.app` (Task 8), not assumed:

1. **Each nested binary has Hardened Runtime + secure timestamp.** For the
   framework and every embedded helper / XPC service:
   ```sh
   codesign -dvvv "TrafficWand.app/Contents/Frameworks/Sparkle.framework"
   codesign -dvvv "TrafficWand.app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
   codesign -dvvv "TrafficWand.app/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
   # plus any *.xpc under Sparkle.framework/.../XPCServices/
   ```
   Confirm in the output: `flags=…(runtime)` (Hardened Runtime enabled) **and** a
   `Timestamp=` line (secure timestamp present, not `Timestamp=none`). A nested
   item missing `runtime` or showing `Timestamp=none` is the failure mode to fix.

2. **Gatekeeper assessment passes** on the whole exported app:
   ```sh
   spctl --assess --type execute -vvv "TrafficWand.app"
   ```
   Expect `accepted` / `source=Notarized Developer ID`.

Run these against the **exported, notarized** `.app` (post `exportArchive` +
`staple`), since that is what users actually run and what the in-place updater
swaps in.

---

## 4. Appcast hosting and format

Sparkle reads an **`appcast.xml`** feed to discover updates. We host it as a
**GitHub Release asset**, not GitHub Pages / a `gh-pages` branch.

- **Feed URL (stable, baked into the app).** `Info.plist` `SUFeedURL` is the
  redirect URL
  `https://github.com/trafficwand/trafficwand/releases/latest/download/appcast.xml`.
  At runtime Sparkle follows GitHub's **302** from `/latest/download/` to the
  newest release's `appcast.xml` asset (verified against Sparkle issues #1450 /
  #1461 — the redirect is followed correctly for the *feed* fetch).

- **Enclosure URL (permanent, version-specific).** Each appcast `<item>`'s
  `<enclosure url>` points at the **versioned** Release asset
  `https://github.com/trafficwand/trafficwand/releases/download/v<version>/TrafficWand-<version>.dmg`
  (not the `/latest/` redirect). The appcast only needs the single latest `<item>`
  for update detection.

- **Hand-render the appcast; do NOT use `generate_appcast`.** The *only* known
  GitHub-redirect pitfall is in Sparkle's `generate_appcast` **tool**, which
  mishandles the redirect feed URL. We avoid it by **hand-rendering `appcast.xml`**
  in `scripts/generate-appcast.sh` (Task 7) with an explicit versioned enclosure
  URL and the `sign_update` output spliced in.

- **`<item>` field mapping:**

  | Appcast field | Source |
  | --- | --- |
  | `sparkle:version` | built `.app` `CFBundleVersion` (commit-count build number, §5) |
  | `sparkle:shortVersionString` | `CFBundleShortVersionString` = `MARKETING_VERSION` |
  | `sparkle:minimumSystemVersion` | `26.0` (matches `project.yml` deploymentTarget) |
  | `<enclosure url>` | versioned Release DMG (above) |
  | `<enclosure sparkle:edSignature>` | from `sign_update` (§2) |
  | `<enclosure length>` | from `sign_update` (DMG byte length) |

  CI uploads `appcast.xml` alongside the DMG as a release asset
  (`gh release upload --clobber`), after which `/latest/download/appcast.xml`
  serves it automatically.

---

## 5. Bootstrap note (first Sparkle-enabled release)

A `v0.1.0` release / build `1` already exists and **predates Sparkle** (no
updater embedded). Therefore:

- The **first Sparkle-enabled release must use `MARKETING_VERSION` strictly
  greater than `0.1.0`** (e.g. `0.2.0`). Its CI-derived `CFBundleVersion` (commit
  count, `git rev-list --count HEAD`) will already exceed `1`, so Sparkle's
  numeric `sparkle:version` comparison is monotonic and never reads a frozen `1`.
- Pre-Sparkle `0.1.0` installs have **no updater** and must be upgraded **manually
  one last time**. Only `0.2.0+` installs self-update from then on.
- Remember to bump `MARKETING_VERSION` in `project.yml` before tagging, per the
  existing `verify-release-version.sh` tag/version check.

---

## 6. Operator / external actions (NOT automated)

These are intentionally **not** performed by tooling or an agent; they involve an
irreplaceable credential and external system settings:

- **`generate_keys` + real `SUPublicEDKey`:** the operator runs
  `task sparkle:gen-keys` once, puts the printed public key in `Info.plist`, and
  keeps the private key in the Keychain (see §1). The committed `Info.plist` retains
  the placeholder `__PUBLIC_ED_KEY__` until then — losing the private key would break
  all future update signing, so this stays a manual key-custody step.
- **`SPARKLE_ED_PRIVATE_KEY` repo secret:** the operator adds the exported private
  key as a GitHub Actions secret (Settings → Secrets and variables → Actions).
  This is an external GitHub settings action.
- **Post-first-release check:** confirm
  `https://github.com/trafficwand/trafficwand/releases/latest/download/appcast.xml`
  resolves (302 → newest release's asset).

---

## 7. Hardened Runtime / entitlements

- **No entitlement changes.** The app is non-sandboxed with Hardened Runtime.
  Sparkle's nested framework / Autoupdate / XPC services are signed + notarized as
  part of the existing archive → exportArchive → notarize pipeline. The only added
  obligation is the explicit nested-helper verification in §3.
- DMG feeds get **no delta updates** (deltas apply to zipped `.app` bundles) — a
  full DMG is downloaded each update. Acceptable for a small menu-bar app.
- If a future release sandboxes the app, Sparkle will then require the
  installer-launcher XPC service + entitlements — out of scope here.
