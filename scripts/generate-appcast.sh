#!/usr/bin/env bash
#
# generate-appcast.sh — EdDSA-sign the release DMG and render appcast.xml.
#
# Renders a single-item Sparkle appcast feed for the current release. The DMG is
# signed with the project's EdDSA private key (read from $SPARKLE_ED_PRIVATE_KEY
# via STDIN, never a CLI arg) using Sparkle's `sign_update` tool. The tool is
# obtained via scripts/sparkle-tools.sh, which pins it to the same version as the
# SPM `from:` constraint (2.9.2) and checksum-verifies it before use.
#
# The enclosure URL points at the PERMANENT, version-specific GitHub Release DMG
# asset (not the /latest/ redirect); the feed URL baked into the app
# (/latest/download/appcast.xml) follows GitHub's 302 to this asset at runtime.
# See docs/spikes/sparkle-updates.md for the full design rationale.
#
# Usage:
#   scripts/generate-appcast.sh                Read versions from the exported
#                                              .app, sign the DMG, render appcast.
#   scripts/generate-appcast.sh -h|--help      Show this help.
#
# Required environment variable (for a full run; NOT needed for the rendering
# unit test, which calls render_appcast directly):
#   SPARKLE_ED_PRIVATE_KEY   The EdDSA private key (output of `generate_keys -x`).
#                            Fed to `sign_update` on STDIN.
#
# This script is structured for testability the same way verify-release-version.sh
# is: the pure XML construction lives in render_appcast(), which takes all inputs
# as arguments and touches neither the network, the keychain, nor sign_update —
# so generate-appcast.test.sh can exercise it with a stub signature/length.

set -euo pipefail

# Pinned Sparkle tooling (SPARKLE_* constants + ensure_sparkle_tools) lives in the
# shared library so the version/checksum has a single source of truth. Sourced via
# a BASH_SOURCE-relative path so it resolves regardless of cwd, and when this file
# is itself sourced by generate-appcast.test.sh. Sourcing has no side effects.
# shellcheck source=sparkle-tools.sh disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sparkle-tools.sh"

# ---------------------------------------------------------------------------
# Release-invariant configuration
# ---------------------------------------------------------------------------

# Base URL of the versioned Release DMG asset. The version-specific path segment
# (v<version>/TrafficWand-<version>.dmg) is appended in main().
RELEASE_DOWNLOAD_BASE="https://github.com/trafficwand/trafficwand/releases/download"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
    cat <<'EOF'
generate-appcast.sh — EdDSA-sign the release DMG and render appcast.xml.

Usage:
  scripts/generate-appcast.sh            Sign dist/TrafficWand-<version>.dmg and
                                         write dist/appcast.xml.
  scripts/generate-appcast.sh -h|--help  Show this help.

Required environment variable:
  SPARKLE_ED_PRIVATE_KEY   EdDSA private key (output of `generate_keys -x`),
                           fed to sign_update on STDIN.

The Sparkle `sign_update` tool is downloaded (pinned + checksum-verified) from
the Sparkle 2.9.2 release tarball. See docs/spikes/sparkle-updates.md.
EOF
}

die() {
    printf 'generate-appcast: error: %s\n' "$1" >&2
    exit 1
}

# render_appcast <version> <short_version> <ed_signature> <length> <enclosure_url> <minimum_system_version>
#
# PURE renderer: builds the appcast XML from its arguments and prints it on
# stdout. No network, no keychain, no sign_update — so the unit test can drive it
# with a stub signature/length. <version> is the CFBundleVersion (sparkle:version,
# the monotonic build number); <short_version> is CFBundleShortVersionString
# (sparkle:shortVersionString, the marketing version). <minimum_system_version> is
# LSMinimumSystemVersion read from the exported .app (which derives it from
# project.yml's deploymentTarget). The title mirrors the marketing version. pubDate
# is RFC-822, as Sparkle expects.
render_appcast() {
    local version="$1"
    local short_version="$2"
    local ed_signature="$3"
    local length="$4"
    local enclosure_url="$5"
    local minimum_system_version="$6"

    local pub_date
    pub_date="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"

    cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>TrafficWand</title>
    <item>
      <title>Version ${short_version}</title>
      <pubDate>${pub_date}</pubDate>
      <sparkle:version>${version}</sparkle:version>
      <sparkle:shortVersionString>${short_version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${minimum_system_version}</sparkle:minimumSystemVersion>
      <enclosure url="${enclosure_url}" sparkle:edSignature="${ed_signature}" length="${length}" type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF
}

# ---------------------------------------------------------------------------
# Version + .app introspection
# ---------------------------------------------------------------------------

# Must match build-dmg.sh's EXPORT_DIR / APP_PATH so we read versions from the
# exact .app that was built, signed, and packaged into the DMG.
APP_PATH="build/export/TrafficWand.app"

# read_plist_key <key> — read a key from the exported .app's Info.plist.
read_plist_key() {
    local key="$1"
    local value
    value="$(defaults read "$PWD/$APP_PATH/Contents/Info" "$key" 2>/dev/null)" \
        || die "could not read $key from $APP_PATH/Contents/Info.plist"
    [ -n "$value" ] || die "$key is empty in $APP_PATH/Contents/Info.plist"
    printf '%s\n' "$value"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    # All paths are repo-root-relative; anchor to the repo root regardless of the
    # invocation directory (CI, a subdirectory, the Taskfile target, etc.).
    cd "$(dirname "$0")/.."

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "unknown argument: $1 (try --help)"
                ;;
        esac
    done

    [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ] \
        || die "required environment variable not set: SPARKLE_ED_PRIVATE_KEY"

    [ -d "$APP_PATH" ] || die "exported .app not found: $APP_PATH (run 'task dmg' first)"

    # Validate the embedded EdDSA public key is real, not the build template
    # placeholder. A release shipped with `__PUBLIC_ED_KEY__` would carry a public
    # key that can never validate any update's signature — a silent updater
    # footgun. Fail loudly here instead.
    local public_ed_key
    public_ed_key="$(read_plist_key SUPublicEDKey)"
    if [ "$public_ed_key" = "__PUBLIC_ED_KEY__" ]; then
        die "SUPublicEDKey in $APP_PATH is the unreplaced placeholder __PUBLIC_ED_KEY__ — set the real EdDSA public key in App/Resources/Info.plist before releasing"
    fi

    # sparkle:version = CFBundleVersion (monotonic build number);
    # sparkle:shortVersionString = CFBundleShortVersionString (marketing version,
    # identical to MARKETING_VERSION and thus the DMG filename's version segment).
    # minimum_system_version = LSMinimumSystemVersion (project.yml deploymentTarget,
    # substituted at build time) — single source of truth, not a duplicated constant.
    local bundle_version short_version minimum_system_version
    bundle_version="$(read_plist_key CFBundleVersion)"
    short_version="$(read_plist_key CFBundleShortVersionString)"
    minimum_system_version="$(read_plist_key LSMinimumSystemVersion)"

    local version="$short_version"
    local dmg_path="dist/TrafficWand-$version.dmg"
    [ -f "$dmg_path" ] || die "DMG not found: $dmg_path (run 'task dmg' first)"

    # Stage the Sparkle tools in a temp dir wiped on exit. Interpolate the path
    # into the trap string NOW (define-time), not as a `$tools_dir` reference: the
    # EXIT trap fires after main() returns, where the function-local tools_dir is
    # out of scope and would be an "unbound variable" fatal under `set -u`.
    local tools_dir
    tools_dir="$(mktemp -d)"
    # shellcheck disable=SC2064  # intentional: expand tools_dir at define-time
    trap "rm -rf '$tools_dir'" EXIT

    local bin_dir sign_update
    bin_dir="$(ensure_sparkle_tools "$tools_dir")"
    sign_update="$bin_dir/sign_update"

    # Sign the DMG. The private key goes in on STDIN (--ed-key-file -); the `-s`
    # CLI form is deprecated since Sparkle 2.2.2 (leaks the key into `ps`).
    # Output is a single line: sparkle:edSignature="…" length="…".
    printf 'generate-appcast: signing %s\n' "$dmg_path" >&2
    local sign_output
    sign_output="$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" \
        | "$sign_update" --ed-key-file - "$dmg_path")" \
        || die "sign_update failed for $dmg_path"

    # Parse the edSignature and length attributes out of the sign_update output.
    local ed_signature length
    ed_signature="$(printf '%s\n' "$sign_output" \
        | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
    length="$(printf '%s\n' "$sign_output" \
        | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
    [ -n "$ed_signature" ] || die "could not parse sparkle:edSignature from sign_update output: $sign_output"
    [ -n "$length" ] || die "could not parse length from sign_update output: $sign_output"

    local enclosure_url="$RELEASE_DOWNLOAD_BASE/v$version/TrafficWand-$version.dmg"

    local output_path="dist/appcast.xml"
    render_appcast "$bundle_version" "$short_version" "$ed_signature" "$length" "$enclosure_url" \
        "$minimum_system_version" > "$output_path"

    printf 'generate-appcast: → %s (version=%s, shortVersion=%s, length=%s)\n' \
        "$output_path" "$bundle_version" "$short_version" "$length" >&2
}

# Only run main when executed directly, NOT when sourced. The test sources this
# file to call render_appcast() in isolation, mirroring how the project keeps
# pure logic independently testable.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
