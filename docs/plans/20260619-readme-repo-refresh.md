# Refine README / Repo (issue #6)

## Overview

Turn the current dense, build-focused `README.md` into a **human-friendly, open-source
project README** that mirrors the structure and voice of the website
([trafficwand.app](https://trafficwand.app)) while carrying the GitHub specifics a good
OSS repo needs (logo, badges, FAQ, contributing guide, download links).

**Problem it solves (scoped accurately):** the existing README is **already a decent
human-facing document** — it leads with a clear pitch and a "How it works" section before
any build detail. The real gaps are narrower: it has **no logo, no badges, no FAQ, no
clear download/install section**, its section order doesn't match the website, and there
is **no `CONTRIBUTING.md`**, so all the build/sign/notarize/CI machinery sits inline in the
README where a casual visitor doesn't need it. This is an **add-the-missing-table-stakes +
reorder + split** job, **not a from-scratch rewrite** — the existing accurate, hard-won
prose (Rule syntax, Profiles, Aliases, Fallback, Setting as default browser) is content to
**preserve and lightly reorder**, not to churn.

**Key benefits:**
- A visitor immediately sees a logo, badges, the pitch, how it works, and a download link.
- Section order matches the website (one source of truth for messaging/voice).
- Build/sign/notarize/CI machinery is relocated to `CONTRIBUTING.md`; a short "Build from
  source" quick-start stays in the README.
- Adds the OSS table-stakes issue #6 asks for: logo, badges, FAQ, CONTRIBUTING.

**How it integrates:** README and CONTRIBUTING are the entry points; they link out to the
existing `docs/spikes/*` and `CLAUDE.md` for deep detail rather than duplicating it.

## Context (from discovery)

- **Website structure to mirror** (verbatim where it helps): Hero ("Open every link in
  the right browser." + tagline + "Free & open-source · macOS 26 Tahoe or later") →
  How it works (3 steps) → Features (grouped) → FAQ (6 Q&As) → CTA ("Put every link in
  its place.") → Footer ("© 2026 Ildar Karymov · MIT License").
- **Files/areas involved:**
  - Modify: `README.md` (16 KB, currently build-doc heavy)
  - Create: `CONTRIBUTING.md`
  - Create: `.github/assets/logo.png` (resized from the app icon)
  - Source asset: `App/Resources/AppIcon.icon/Assets/Gemini_Generated_Image_s4c72ns4c72ns4c7.png`
    (~5 MB — must be downscaled, not committed as-is)
- **Repo metadata** (via `gh repo view`): description `[⚠️ WIP] A menu-bar app which
  routes links to the right browser`; homepage `https://trafficwand.app`; topics
  `browser, macos, macos-app, swift`. Issue #6 asks to refine "description and tags".
- **Badge facts:** CI workflow is named `CI` (`.github/workflows/ci.yml`); release
  workflow `Release`; latest release `v0.4.0`; `MARKETING_VERSION: "0.4.0"`; MIT license.
- **No `CONTRIBUTING.md` and no `.github/assets/` exist yet.**
- **`sips`** (macOS built-in) is available to resize the icon — no new dependency.

## Development Approach

- **Testing approach:** Regular (this is a documentation task — there is **no unit-test
  surface**). "Tests" here means **verification**: Markdown renders correctly on GitHub,
  all internal/external links resolve, image paths resolve, and badges render. Each task
  ends with the relevant verification step instead of unit tests.
- Complete each task fully before moving to the next; make small, focused changes.
- **Preserve information, don't delete it:** technical content removed from README must
  land in `CONTRIBUTING.md` (or already exist in `docs/`/`CLAUDE.md`) before the README
  edit is considered done — no orphaned knowledge.
- Keep voice consistent with the website: plain, direct, second-person. **Do not rewrite
  prose that is already direct and accurate** — light edits for voice/ordering only;
  preserve the existing technical wording (it's correct and hard-won).
- **Split by audience, not topic:** content a *user who downloaded the DMG* needs (setting
  the default browser, a one-line "it auto-updates" note) stays in the README; only
  *contributor/maintainer* machinery (build, sign, notarize, CI secrets) moves to
  CONTRIBUTING.
- `task lint` is Swift-only and unaffected; no code changes in this plan.

## Testing Strategy

- **Unit tests:** N/A — no code changes.
- **Verification per task** (treated with the same rigor as tests — must pass before the
  next task):
  - Render the Markdown locally and eyeball it (`grip README.md` if available, or push to
    a branch and view on GitHub, or open in a Markdown preview).
  - Link check: every relative link (`LICENSE`, `CONTRIBUTING.md`, `docs/...`,
    `.github/...`) resolves to an existing file; every external link (releases page,
    website, Sparkle, XcodeGen, etc.) is well-formed.
  - Image check: `.github/assets/logo.png` exists, is < ~500 KB, and the README `<img>`
    resolves.
  - Badge check: each shields.io / Actions badge URL returns an image (open in browser).
- **E2E tests:** project has none (macOS app, `xcodebuild test` only) — not applicable.

## Progress Tracking

- Mark completed items with `[x]` immediately when done.
- Add newly discovered tasks with ➕ prefix; blockers with ⚠️ prefix.
- Keep this plan in sync with the actual edits.

## Solution Overview

**Architecture of the docs:**

- **`README.md`** — user-first, mirrors the website section order, plus GitHub essentials:
  1. Centered **logo** + project name + one-line tagline.
  2. **Badges** row (latest release, CI, license, platform).
  3. **Hero blurb** — the website hero copy adapted to prose.
  4. **Download / Install** — link to latest release DMG + Gatekeeper note.
  5. **How it works** — the 3 website steps.
  6. **Features** — the website's grouped feature list (Rules, Profiles, Aliases, Picker,
     Menu bar, Works with running browsers, Updates, Free & open source).
  7. **Rule syntax** — **preserve** the existing glob table + examples (genuinely useful
     reference; reorder, don't rewrite).
  8. **Setting TrafficWand as the default browser** — **preserve** the existing
     user-facing steps (current README lines ~96–111); a user who downloaded the DMG needs
     these. Plus a one-line "the app auto-updates via Sparkle (Settings ▸ General)" note.
  9. **FAQ** — the website's 6 Q&As, GitHub-flavored (links to issues, releases).
  10. **Build from source** — *condensed* quick-start (prereqs + the handful of `task`
      commands to clone-build-run); links to `CONTRIBUTING.md` for the full story.
  11. **Contributing / License** — short pointers.
- **`CONTRIBUTING.md`** — the relocated **contributor/maintainer** detail only: full
  requirements, the complete `task` command table, the Core/App architecture section, and
  the **release machinery** (signing/notarization/DMG, the Sparkle *appcast/EdDSA build*
  pipeline, the automated release/secrets flow). Links back to `CLAUDE.md` and
  `docs/spikes/*` for the deepest detail. **User-facing** "set as default browser" steps
  and the "it auto-updates" note stay in the README, not here.
- **`.github/assets/logo.png`** — downscaled app icon, the single image the README header
  references.

**Key design decisions & rationale:**
- *Website is the source of truth for voice/order* → README mirrors it so messaging stays
  consistent and the "Claude's bullshit" (issue #6) is replaced by the site's human copy.
- *Move, don't drop, dev content* → respects that the build/release detail is correct and
  hard-won; it just doesn't belong in front of a casual visitor.
- *Resize the icon, don't commit ~5 MB* → keep the repo lean; `sips` is native.
- *Keep Rule syntax + examples in README* → it's reference users actually want at hand and
  the website only shows a teaser of it.

## Technical Details

- **Logo generation (native, one line):**
  ```sh
  mkdir -p .github/assets
  sips -Z 400 "App/Resources/AppIcon.icon/Assets/Gemini_Generated_Image_s4c72ns4c72ns4c7.png" \
    --out .github/assets/logo.png
  ```
  `-Z 400` caps the longest side at 400 px (preserves aspect ratio). Verify the result is
  comfortably under ~500 KB; drop to `-Z 256` if needed.
- **README header markup** (centered, GitHub-safe HTML):
  ```html
  <p align="center">
    <img src=".github/assets/logo.png" alt="TrafficWand" width="160">
  </p>
  <h1 align="center">TrafficWand</h1>
  <p align="center">Open every link in the right browser.</p>
  ```
- **Badges** (Markdown image links under the header):
  - Latest release: `https://img.shields.io/github/v/release/trafficwand/trafficwand`
    → links to `../../releases/latest`.
  - CI: `https://github.com/trafficwand/trafficwand/actions/workflows/ci.yml/badge.svg`
    → links to the CI workflow.
  - License: `https://img.shields.io/github/license/trafficwand/trafficwand`
    → links to `LICENSE`.
  - Platform: `https://img.shields.io/badge/macOS-26%20Tahoe%2B-blue` (static).
  - **CI-badge caveat:** on a `[⚠️ WIP]` repo the live CI badge can render red and look bad
    on the landing page. Either confirm the default branch is green before adding it, or
    knowingly accept it. The URL form is correct regardless.
- **Download link:** `../../releases/latest` (stable redirect to newest DMG) — same
  relative form already used in the README for the releases page.
- **Repo description/topics** (issue #6 "description and tags"): drop the `[⚠️ WIP]`
  prefix once it's public-ready and tighten wording; topics are already sensible
  (`browser, macos, macos-app, swift`) — consider adding `menu-bar`, `default-browser`,
  `swiftui`. Applied via `gh repo edit` (Post-Completion — it's a metadata change, not a
  file in the repo).

## What Goes Where

- **Implementation Steps** (`[ ]`): the logo asset, the README rewrite, `CONTRIBUTING.md`,
  and link/render verification — all achievable in-repo.
- **Post-Completion** (no checkboxes): repo description/topics edit (`gh repo edit`),
  optional real screenshots (require running the app), and the GitHub "About" sidebar.

## Implementation Steps

### Task 1: Generate the README logo asset

**Files:**
- Create: `.github/assets/logo.png`

- [x] create `.github/assets/` and run the `sips -Z 400 … --out .github/assets/logo.png`
      command (see Technical Details) to downscale the app icon
- [x] verify the output exists and is < ~500 KB (`ls -lh .github/assets/logo.png`); if
      larger, re-run with `-Z 256` (result: 191 KB, 400x400)
- [x] verify it opens as a valid PNG (Quick Look / Preview) (`file` reports valid PNG, 400x400 RGBA)
- [x] confirm the source ~5 MB PNG is **not** added anywhere new (only the resized copy
      is committed) (git status shows only `.github/assets/` untracked; source remains its single tracked copy)

### Task 2: Write CONTRIBUTING.md (relocate developer/maintainer content)

**Files:**
- Create: `CONTRIBUTING.md`
- Reference (read, don't duplicate): `CLAUDE.md`, `docs/spikes/launch-mechanism.md`,
  `docs/spikes/sparkle-updates.md`

- [x] add a short intro: how to report bugs / request features (link to GitHub issues),
      and the English-only + TDD-for-Core working conventions (from `CLAUDE.md`)
- [x] move the **Requirements** section from README (macOS 26, Xcode 26+, XcodeGen,
      SwiftLint, Task, `create-dmg`) into CONTRIBUTING
- [x] move the full **Build & run** `task` command table into CONTRIBUTING
- [x] move the **Architecture** (Core/App split) section into CONTRIBUTING; link to
      `CLAUDE.md` for the protocol seams
- [x] move the **Distribution** (signing/notarization/DMG) + the **Sparkle build/appcast
      pipeline** + **Automated releases** (tag → `release.yml`, the seven secrets) into
      CONTRIBUTING; link to `docs/spikes/sparkle-updates.md`. **Do not** move the
      user-facing "the app auto-updates" note or the "Setting as default browser" steps —
      those stay in the README (Task 4)
- [x] add a "Where things live" pointer paragraph (Core vs App, `docs/spikes/`, `CLAUDE.md`)
- [x] verify every relocated relative link still resolves from the new file's location
      (e.g. `docs/spikes/...`, `.github/workflows/release.yml`, `LICENSE`)
- [x] render-check CONTRIBUTING.md (Markdown preview / GitHub) — headings, tables, code
      blocks all render

### Task 3: Rewrite README.md — header, badges, hero, download

**Files:**
- Modify: `README.md`

- [x] replace the top with the centered logo + `# TrafficWand` + tagline markup
- [x] add the badges row (release, CI, license, platform) with correct link targets
- [x] rewrite the hero blurb in the website's voice ("A tiny menu-bar app that becomes
      your default browser…", "Set up your rules once and stop opening links in the wrong
      window.") — no AI hedging
- [x] add a **Download / Install** section: link to `../../releases/latest`, a one-line
      Gatekeeper note (notarized Developer ID app), and the macOS 26 Tahoe+ requirement
- [x] verify the logo `<img>` and all four badges render (view on a branch / preview)

### Task 4: Rewrite README.md — How it works, Features, Rule syntax, FAQ

**Files:**
- Modify: `README.md`

- [ ] add **How it works** as the website's 3 numbered steps (make it default → write
      rules → click links anywhere)
- [ ] add **Features** mirroring the website groups: Rules (top-to-bottom matching),
      Profiles/"work stays at work", Aliases, Picker ("no rule yet?"), Lives in the menu
      bar, Works with already-open browsers, Update notifications, Free & open source / no
      data collected
- [ ] keep & lightly trim the existing **Rule syntax** glob table + examples (the
      `*.github.com` vs `*github.com` gotcha is worth keeping) — **preserve wording**
- [ ] **preserve** the existing **Setting TrafficWand as the default browser** steps
      (current README ~lines 96–111) — they're user-facing — and add a one-line
      "TrafficWand keeps itself up to date via Sparkle (toggle in Settings ▸ General)" note
- [ ] add a **FAQ** section with the website's 6 Q&As, GitHub-flavored (cost/sponsorship,
      data collection = none, requirements, supported browsers/profiles, how to stop
      using it, found a bug → open an issue)
- [ ] verify internal anchor links (if a table of contents is added) and the FAQ's
      external links (issues, sponsor) resolve

### Task 5: Rewrite README.md — Build from source, Contributing, License, final pass

**Files:**
- Modify: `README.md`

- [ ] add a **condensed** "Build from source" section: prerequisites one-liner
      (`brew install xcodegen swiftlint`, Task) + the minimal clone→`task generate`→
      `task build`→`task run` flow, then "see [CONTRIBUTING.md](CONTRIBUTING.md) for the
      full build, release, and architecture details"
- [ ] add short **Contributing** (link to `CONTRIBUTING.md`) and **License** (MIT, link to
      `LICENSE`) sections; footer line matching the site (`© 2026 Ildar Karymov · MIT`)
- [ ] light voice pass only: trim any genuinely redundant phrasing and ensure
      second-person/direct tone — **do not rewrite already-correct technical prose**
- [ ] **prove no information was lost** with a concrete diff, not a vibe check: list the
      old README's section headings (`git show HEAD:README.md | grep '^#'`) and confirm
      each one is now either retained in the new README or relocated to `CONTRIBUTING.md`
- [ ] full link sweep of README: every relative link (`LICENSE`, `CONTRIBUTING.md`,
      `docs/...`, `.github/...`, releases) and external link resolves
- [ ] **acceptance check (issue #6):** logo ✔, badges ✔, FAQ ✔, human-friendly + website
      ordering ✔, CONTRIBUTING.md exists ✔, no AI filler ✔
- [ ] **final github.com render:** push to a branch and view README + CONTRIBUTING on
      GitHub — confirm badges (incl. the live CI badge), logo, tables, and links all load
      over the network

### Task 6: [Final] Update docs & close out

- [ ] update `CLAUDE.md` only if a new convention emerged (e.g. "user-facing docs live in
      README, contributor docs in CONTRIBUTING") — otherwise skip
- [ ] move this plan to `docs/plans/completed/`
- [ ] reference issue #6 in the PR/commit so it auto-closes on merge

## Post-Completion

*Items requiring manual intervention or external systems — no checkboxes, informational only.*

**Repo metadata (issue #6 "description and tags"):**
- Update the GitHub repo description (drop `[⚠️ WIP]` when public-ready, tighten copy) and
  the "About" sidebar via `gh repo edit trafficwand/trafficwand --description "…"` and
  `--add-topic menu-bar --add-topic default-browser --add-topic swiftui` as desired.
  Homepage is already `https://trafficwand.app`.

**Optional real screenshots:**
- The website shows UI screenshots (profile picker, alias management, the picker panel).
  Capturing equivalents for the README requires running the app (`task run`) and taking
  screenshots manually; if added later, store them under `.github/assets/` and embed them
  in the Features section. Left out of this plan because they can't be produced from a
  static checkout.

**Manual verification:**
- View the merged README and CONTRIBUTING on github.com (not just a local preview) to
  confirm badges, the Actions status badge, and the logo all load over the network.
