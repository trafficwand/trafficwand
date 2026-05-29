#!/usr/bin/env bash
#
# verify-release-version.sh — Verify that a release tag matches MARKETING_VERSION.
#
# Compares the tag ref (with an optional leading "v" stripped) against the
# MARKETING_VERSION declared in the project file. This keeps project.yml the
# single source of truth for the app version while guaranteeing a pushed tag
# is meaningful — a mismatch is an operator error and should fail loudly before
# the expensive notarized build.
#
# Usage:
#   scripts/verify-release-version.sh <tag> [project-file]
#
# Arguments:
#   <tag>          Release tag ref, e.g. "v0.1.0" or "0.1.0". Leading "v" is stripped.
#   [project-file] Optional path to the project file (default: project.yml).
#                  Overridable via the PROJECT_FILE env var. This indirection
#                  exists so tests can point at a temp fixture instead of the
#                  repo's live project.yml.
#
# Exits 0 and echoes the version on match; exits non-zero with a distinct error
# on missing/empty tag, missing/empty MARKETING_VERSION, or tag≠version mismatch.

set -euo pipefail

die() {
    printf 'verify-release-version: error: %s\n' "$1" >&2
    exit 1
}

main() {
    local tag="${1:-}"
    local project_file="${2:-${PROJECT_FILE:-project.yml}}"

    [ -n "$tag" ] || die "missing required argument: <tag>"

    # Strip an optional leading "v" (e.g. "v0.1.0" -> "0.1.0").
    local tag_version="${tag#v}"
    [ -n "$tag_version" ] || die "tag is empty after stripping leading 'v': '$tag'"

    [ -f "$project_file" ] || die "project file not found: $project_file"

    # Parse the indented, double-quoted YAML line, e.g.
    #     MARKETING_VERSION: "0.1.0"
    # Strip the key, colon, surrounding double-quotes, and surrounding whitespace.
    local raw
    raw="$(grep -E '^[[:space:]]*MARKETING_VERSION[[:space:]]*:' "$project_file" | head -n 1 || true)"
    [ -n "$raw" ] || die "MARKETING_VERSION not found in $project_file"

    local marketing_version="$raw"
    # Drop everything up to and including the first colon.
    marketing_version="${marketing_version#*:}"
    # Trim leading/trailing whitespace.
    marketing_version="${marketing_version#"${marketing_version%%[![:space:]]*}"}"
    marketing_version="${marketing_version%"${marketing_version##*[![:space:]]}"}"
    # Strip surrounding double-quotes if present.
    marketing_version="${marketing_version#\"}"
    marketing_version="${marketing_version%\"}"

    [ -n "$marketing_version" ] || die "MARKETING_VERSION is empty in $project_file"

    if [ "$tag_version" != "$marketing_version" ]; then
        die "tag version '$tag_version' does not match MARKETING_VERSION '$marketing_version' in $project_file"
    fi

    printf '%s\n' "$marketing_version"
}

main "$@"
