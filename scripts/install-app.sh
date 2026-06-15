#!/usr/bin/env bash
#
# install-app.sh — Quit any running TrafficWand instance and install the
# freshly-built app bundle into /Applications (or INSTALL_DIR).
#
# Usage:
#   scripts/install-app.sh <configuration>
#
# Arguments:
#   <configuration>   Xcode build configuration, e.g. "Debug" or "Release".
#                     Must match the configuration used in the preceding build.
#
# Env-var seams (for testing — mirrors verify-release-version.sh's PROJECT_FILE pattern):
#   APP_PATH     Override the source bundle path; skips xcodebuild resolution.
#   INSTALL_DIR  Override the destination directory (default: /Applications).
#   QUIT_CMD     Override the quit command (default: pkill -x TrafficWand).
#   CODESIGN_CMD Override the re-sign command (default: ad-hoc deep re-sign).
#
# The script is intentionally not responsible for building the app; callers
# (i.e. the Taskfile) ensure the build runs first.

set -euo pipefail

die() {
    printf 'install-app: error: %s\n' "$1" >&2
    exit 1
}

main() {
    # All paths are repo-root-relative; anchor to the repo root regardless of
    # the invocation directory (CI, a subdirectory, the Taskfile target, etc.).
    # Mirrors generate-appcast.sh and verify-release-version.sh.
    # When APP_PATH / INSTALL_DIR are injected (tests), they are absolute, so
    # the cd has no effect on the test-seam paths.
    cd "$(dirname "$0")/.."

    local config="${1:-}"

    [ -n "$config" ] || die "missing required argument: <configuration>
Usage: install-app.sh <configuration>
  e.g. install-app.sh Debug
       install-app.sh Release"

    # --- Resolve source bundle path -----------------------------------------
    local app_path="${APP_PATH:-}"

    if [ -z "$app_path" ]; then
        # Resolve via xcodebuild build settings (non-building query).
        local settings
        settings="$(xcodebuild \
            -project TrafficWand.xcodeproj \
            -scheme TrafficWand \
            -configuration "$config" \
            -showBuildSettings)"

        # Single awk pass over the build-settings output; handles values with
        # spaces (e.g. a product name like "Traffic Wand.app") because awk reads
        # from the first non-whitespace character after "= " to end-of-line.
        local built_products_dir full_product_name
        while IFS= read -r _line; do
            # Strip leading whitespace so that keys like
            # PRECOMPS_INCLUDE_HEADERS_FROM_BUILT_PRODUCTS_DIR do not
            # accidentally match the BUILT_PRODUCTS_DIR pattern.
            local _trimmed="${_line#"${_line%%[! ]*}"}"
            case "$_trimmed" in
                BUILT_PRODUCTS_DIR\ =\ *) built_products_dir="${_trimmed#*= }" ;;
                FULL_PRODUCT_NAME\ =\ *)  full_product_name="${_trimmed#*= }" ;;
            esac
        done < <(printf '%s\n' "$settings")

        [ -n "$built_products_dir" ] || die "could not resolve BUILT_PRODUCTS_DIR from xcodebuild"
        [ -n "$full_product_name" ]  || die "could not resolve FULL_PRODUCT_NAME from xcodebuild"

        app_path="$built_products_dir/$full_product_name"
    fi

    # --- Verify source bundle exists ----------------------------------------
    [ -d "$app_path" ] || die "source bundle not found or is not a directory: $app_path"

    local bundle_name
    bundle_name="$(basename "$app_path")"

    # --- Prepare destination ------------------------------------------------
    local install_dir="${INSTALL_DIR:-/Applications}"
    [ -n "$install_dir" ] || die "INSTALL_DIR resolved to empty string"
    mkdir -p "$install_dir"

    # --- Quit running instance ----------------------------------------------
    # QUIT_CMD is injectable so tests can assert the step ran without killing
    # a real process. The || true swallows the exit code only (pkill exits 1
    # when no matching process is found, which is fine).
    # eval is required: the default "pkill -x TrafficWand" is multi-word and
    # must be split into command + arguments by the shell, not passed as a
    # single token. eval also handles injected multi-word test commands
    # (e.g. FAKE_QUIT_CMD="touch $QUIT_MARKER") correctly.
    eval "${QUIT_CMD:-pkill -x TrafficWand}" 2>/dev/null || true

    # --- Replace bundle -----------------------------------------------------
    # rm -rf first ensures a clean replacement (not a merge into an existing
    # bundle); ditto preserves extended attributes and bundle structure.
    rm -rf "$install_dir/$bundle_name"
    ditto "$app_path" "$install_dir/$bundle_name"

    local installed_bundle="$install_dir/$bundle_name"

    # --- Re-sign for local launch -------------------------------------------
    # Local builds are ad-hoc signed (CODE_SIGN_IDENTITY "-") with Hardened
    # Runtime still flagged on. Hardened Runtime enables Library Validation,
    # which refuses to load the embedded Sparkle.framework: an independently
    # ad-hoc-signed framework has no Team ID matching the (also team-less) host
    # app, so dyld aborts at launch with "Library not loaded ... different Team
    # IDs". Re-signing the whole bundle ad-hoc WITHOUT the runtime flag drops
    # Library Validation, so the framework loads. Release builds (`task dmg`)
    # sign everything with one Developer ID identity and are unaffected — this
    # re-sign is local-install-only.
    #
    # eval mirrors the QUIT_CMD seam: the default is multi-word and must be
    # split into command + args by the shell. CODESIGN_CMD is injectable so
    # tests can assert the step ran without invoking the real codesign (which
    # would reject the fake fixture bundles). The bundle path is appended as a
    # separately-quoted eval argument so paths with spaces survive.
    local entitlements="App/Resources/TrafficWand.entitlements"
    eval "${CODESIGN_CMD:-codesign --force --deep --sign - --entitlements \"\$entitlements\"}" "\"\$installed_bundle\""

    printf 'Installed: %s\n' "$installed_bundle"
}

main "$@"
