#!/usr/bin/env bash
#
# build-dmg.sh — Build, sign, notarize, and package TrafficWand as a DMG.
# See --help for usage, required env vars, and tool dependencies.

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
    cat <<'EOF'
build-dmg.sh — Build, sign, notarize, and package TrafficWand as a DMG.

Usage:
  scripts/build-dmg.sh              Full pipeline: archive → sign → notarize → DMG.
  scripts/build-dmg.sh --preflight  Validate env vars, tools, and signing identity, then exit.
  scripts/build-dmg.sh -h|--help    Show this help.

Required environment variables (for both --preflight and full run):
  DEVELOPER_ID_APPLICATION   Full identity name, e.g.
                             "Developer ID Application: Jane Doe (TEAMID1234)"
  APPLE_ID                   Apple ID email used for notarization.
  APPLE_TEAM_ID              10-character team identifier.
  APPLE_APP_SPECIFIC_PASSWORD  App-specific password for notarization
                               (generated at appleid.apple.com).

Instead of exporting these in your shell, copy .dmg.env.example to .dmg.env
at the repo root and fill it in once — this script sources it automatically.
.dmg.env is gitignored. (In CI, set the four vars as environment secrets; the
file won't exist there, so the script falls back to the environment.)

Tools required on PATH:
  xcodebuild, xcrun (notarytool, stapler), codesign, security, create-dmg, ditto, spctl.
EOF
}

die() {
    printf 'build-dmg: error: %s\n' "$1" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

preflight() {
    # Required env vars — fail on the FIRST missing variable, naming it.
    local var
    for var in DEVELOPER_ID_APPLICATION APPLE_ID APPLE_TEAM_ID APPLE_APP_SPECIFIC_PASSWORD; do
        if [ -z "${!var:-}" ]; then
            die "required environment variable not set: $var"
        fi
    done

    # Required tools on PATH.
    command -v xcodebuild  >/dev/null 2>&1 || die "xcodebuild not found on PATH (install Xcode)"
    command -v create-dmg  >/dev/null 2>&1 || die "create-dmg not found on PATH (brew install create-dmg)"
    command -v codesign    >/dev/null 2>&1 || die "codesign not found on PATH"
    command -v security    >/dev/null 2>&1 || die "security not found on PATH"
    command -v ditto       >/dev/null 2>&1 || die "ditto not found on PATH"
    command -v spctl       >/dev/null 2>&1 || die "spctl not found on PATH"

    # notarytool comes from Xcode; probe via --version to confirm the active
    # xcode-select Xcode is recent enough to provide the subcommand.
    if ! xcrun notarytool --version >/dev/null 2>&1; then
        die "xcrun notarytool unavailable (check 'xcode-select -p' points to a recent Xcode)"
    fi

    # Signing identity must be importable into the codesigning keychain.
    if ! security find-identity -v -p codesigning | grep -F -q "$DEVELOPER_ID_APPLICATION"; then
        die "signing identity not found in keychain: $DEVELOPER_ID_APPLICATION"
    fi
}

# ---------------------------------------------------------------------------
# Build pipeline
# ---------------------------------------------------------------------------

# Paths used throughout the pipeline. Keep in one place so future refactors
# only need to touch this block.
PROJECT="TrafficWand.xcodeproj"
SCHEME="TrafficWand"
CONFIGURATION="Release"
ARCHIVE_PATH="build/TrafficWand.xcarchive"
EXPORT_DIR="build/export"
EXPORT_OPTIONS_PLIST="build/ExportOptions.plist"
APP_PATH="$EXPORT_DIR/TrafficWand.app"
APP_ZIP="build/TrafficWand.zip"
# Clean staging directory containing ONLY the signed/notarized/stapled .app
# for create-dmg to package. EXPORT_DIR also holds xcodebuild byproducts
# (ExportOptions.plist with team-ID + cert CN, DistributionSummary.plist,
# Packaging.log) which must not ship inside the DMG.
DMG_STAGING_DIR="build/dmg-staging"

# Resolve MARKETING_VERSION from the project so the DMG filename has a single
# source of truth (project.yml → MARKETING_VERSION). Prints the version on
# stdout so the caller can capture it via command substitution.
resolve_version() {
    local ver
    ver=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ MARKETING_VERSION /{print $2; exit}')
    if [ -z "${ver:-}" ]; then
        die "could not resolve MARKETING_VERSION from xcodebuild -showBuildSettings"
    fi
    printf '%s\n' "$ver"
}

# Emit build/ExportOptions.plist via heredoc. signingCertificate uses the
# full identity name from $DEVELOPER_ID_APPLICATION (which carries the
# team-ID-bearing common name) so the right cert is selected unambiguously
# even when multiple Developer ID Application certs share a keychain.
write_export_options() {
    cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$APPLE_TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>$DEVELOPER_ID_APPLICATION</string>
</dict>
</plist>
EOF
}

# Submit an artifact (.zip or .dmg) to Apple notary service and wait for the
# result. On failure, fetch and print the submission log before re-raising so
# the operator sees the root cause (entitlement issue, signature problem, etc.)
# without a second round-trip.
#
# SECURITY NOTE: APPLE_APP_SPECIFIC_PASSWORD is passed as a notarytool CLI
# arg, which makes it visible via `ps` on multi-user hosts. On single-user
# macOS and single-tenant GitHub Actions runners (the documented use cases)
# this is safe — macOS defaults to hiding command-line args from other users
# (kern.ps_argsv=0). Env-var-based auth was chosen deliberately so the same
# script works locally and in GitHub Actions Secrets without a separate
# `xcrun notarytool store-credentials` step. Do NOT run this script on a
# shared/multi-user host without first migrating to
# `xcrun notarytool store-credentials` + `--keychain-profile`.
notarize() {
    local artifact="$1"
    local submit_output submit_exit submission_id status

    printf 'build-dmg: submitting %s to notary service...\n' "$artifact"

    # Capture combined stdout+stderr so we can extract the submission ID even
    # when notarytool fails. --output-format json would be cleaner but adds a
    # jq dependency for a one-off parse — awk is sufficient here. Initialise
    # submit_exit=0 and append `|| submit_exit=$?` so `set -e` stays active.
    submit_exit=0
    submit_output=$(xcrun notarytool submit "$artifact" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD" \
        --wait 2>&1) || submit_exit=$?

    printf '%s\n' "$submit_output"

    # Strip trailing whitespace from awk-parsed values so a future format
    # tweak (e.g. "Accepted " with a stray space) doesn't break the compare.
    status=$(printf '%s\n' "$submit_output" \
        | awk -F': ' '/^  *status:/{sub(/[[:space:]]+$/, "", $2); print $2; exit}')
    submission_id=$(printf '%s\n' "$submit_output" \
        | awk -F': ' '/^  *id:/{sub(/[[:space:]]+$/, "", $2); print $2; exit}')

    if [ "$submit_exit" -ne 0 ] || [ "$status" != "Accepted" ]; then
        if [ -n "${submission_id:-}" ]; then
            printf 'build-dmg: notarization failed (status=%s, exit=%d); fetching log for %s\n' \
                "${status:-unknown}" "$submit_exit" "$submission_id" >&2
            xcrun notarytool log "$submission_id" \
                --apple-id "$APPLE_ID" \
                --team-id "$APPLE_TEAM_ID" \
                --password "$APPLE_APP_SPECIFIC_PASSWORD" >&2 || true
        fi
        die "notarization did not reach Accepted status (got: ${status:-unknown}) for $artifact"
    fi
}

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------

main() {
    # All paths in this script are repo-root-relative, so anchor the working
    # directory to the repo root regardless of where the script is invoked
    # from (CI, a subdirectory, the Taskfile target, etc.).
    cd "$(dirname "$0")/.."

    # Load credentials from a gitignored .dmg.env at the repo root if present,
    # so the four vars don't have to be exported in every shell. Copy
    # .dmg.env.example to .dmg.env and fill it in once. `set -a` exports every
    # assignment in the sourced file. In CI no such file exists (it's
    # gitignored), so this is skipped and the vars come from the environment.
    if [ -f .dmg.env ]; then
        set -a
        # shellcheck disable=SC1091
        . ./.dmg.env
        set +a
    fi

    local mode="full"
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --preflight)
                mode="preflight"
                shift
                ;;
            *)
                die "unknown argument: $1 (try --help)"
                ;;
        esac
    done

    preflight

    if [ "$mode" = "preflight" ]; then
        exit 0
    fi

    # build/ is fully ephemeral — wipe it so stale intermediates from a prior
    # run cannot leak into this one. dist/ is the deliverable directory and is
    # preserved across runs (each release writes a new VERSION-stamped DMG).
    rm -rf build/
    mkdir -p build dist

    local version
    version=$(resolve_version)
    printf 'build-dmg: building TrafficWand %s\n' "$version"

    # Archive. CODE_SIGN_IDENTITY overrides project.yml's ad-hoc default so
    # the in-archive signature uses the real Developer ID cert. Do NOT pass
    # --timestamp / OTHER_CODE_SIGN_FLAGS here — exportArchive re-signs from
    # scratch using ExportOptions.plist and applies timestamp + hardened
    # runtime automatically for method=developer-id.
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination 'platform=macOS' \
        -archivePath "$ARCHIVE_PATH" \
        CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"

    write_export_options

    # Export. This is the authoritative shipping signature.
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_DIR" \
        -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

    # Verify the exported .app. NO --deep (deprecated); --strict already
    # walks nested code (frameworks, helpers) unconditionally.
    codesign --verify --strict --verbose=2 "$APP_PATH"

    # Notarize the .app. notarytool requires a flat archive (zip), so wrap
    # the .app with ditto. --keepParent preserves the .app bundle structure
    # inside the zip (matches Apple's guidance for notarytool submissions).
    # No separate cleanup needed: `rm -rf build/` at script start handles it.
    ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
    notarize "$APP_ZIP"

    # Staple the ticket onto the .app itself (not the zip). The zip was only
    # the transport for notarization; the shipping artifact is the .app.
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"

    # Fast-fail Gatekeeper assessment against the .app. Catches a malformed
    # ticket before spending another ~5 min on the DMG notarization round-trip.
    # Note: .app uses --type execute, the DMG below uses --type open — that's
    # intentional and the two types are not interchangeable.
    spctl --assess --type execute -vv "$APP_PATH"

    # Build the DMG. Layout is v1 (no background image): centered icon, an
    # /Applications drop-link beside it. --no-internet-enable disables the
    # deprecated "internet-enabled disk image" flag (which Apple removed
    # support for in modern macOS anyway).
    local dmg_path="dist/TrafficWand-$version.dmg"
    # create-dmg fails if the target already exists; the deliverable dir is
    # preserved across runs so we must clear any same-version artifact here.
    rm -f "$dmg_path"
    # Stage ONLY the signed/notarized/stapled .app into a clean directory so
    # create-dmg does not ship EXPORT_DIR siblings (ExportOptions.plist,
    # DistributionSummary.plist, Packaging.log) inside the DMG. ditto
    # preserves resource forks, extended attributes, and ACLs cleanly.
    rm -rf "$DMG_STAGING_DIR"
    mkdir -p "$DMG_STAGING_DIR"
    ditto "$APP_PATH" "$DMG_STAGING_DIR/TrafficWand.app"
    create-dmg \
        --volname "TrafficWand $version" \
        --window-pos 200 120 \
        --window-size 720 340 \
        --icon-size 100 \
        --icon "TrafficWand.app" 200 170 \
        --app-drop-link 480 170 \
        --no-internet-enable \
        "$dmg_path" \
        "$DMG_STAGING_DIR/"

    # Sign the DMG itself with the Developer ID cert. create-dmg produces an
    # UNSIGNED disk image; notarizing + stapling attaches a ticket but does NOT
    # add a code signature, so `spctl --assess --context context:primary-signature`
    # would reject it with "no usable signature". Sign BEFORE notarizing so the
    # notarization ticket is keyed to the signed image. No --options runtime /
    # entitlements here: hardened runtime applies to executables, not disk images.
    codesign --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$dmg_path"

    # Notarize and staple the DMG itself, so Gatekeeper passes 100% offline
    # regardless of whether the user mounts the DMG or extracts the .app first.
    notarize "$dmg_path"
    xcrun stapler staple "$dmg_path"
    xcrun stapler validate "$dmg_path"

    # Final Gatekeeper assessment against the DMG. DMGs use --type open while
    # .app bundles use --type execute (see the spctl call above) — intentional,
    # do not unify: the two assessment types check different code paths.
    spctl --assess --type open --context context:primary-signature -vv "$dmg_path"

    # Final summary. `du -h` reports a human-readable size; -d 0 keeps it to
    # the file itself (no recursion since this is a single file).
    local size
    size=$(du -h "$dmg_path" | awk '{print $1}')
    printf '\nbuild-dmg: → %s (%s)\n' "$dmg_path" "$size"
}

main "$@"
