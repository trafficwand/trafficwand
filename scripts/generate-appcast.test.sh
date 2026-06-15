#!/usr/bin/env bash
#
# generate-appcast.test.sh — Self-contained assertion tests for the pure XML
# rendering in generate-appcast.sh. No network, Xcode, keychain, sign_update, or
# real EdDSA key required.
#
# The tests source generate-appcast.sh (which only defines functions when sourced,
# never runs main) and drive render_appcast() directly with a STUB signature and
# length, asserting the rendered appcast carries the right enclosure URL,
# sparkle:version, sparkle:shortVersionString, sparkle:edSignature, length, and
# sparkle:minimumSystemVersion. Mirrors verify-release-version.test.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/generate-appcast.sh"

# shellcheck source=generate-appcast.sh disable=SC1091
. "$SUT"

FAILURES=0
TESTS=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    FAILURES=$((FAILURES + 1))
}

pass() {
    printf 'ok: %s\n' "$1"
}

# assert_contains <description> <haystack> <needle>
assert_contains() {
    local desc="$1" haystack="$2" needle="$3"
    TESTS=$((TESTS + 1))
    case "$haystack" in
        *"$needle"*) pass "$desc" ;;
        *) fail "$desc: expected output to contain '$needle'" ;;
    esac
}

# --- Render with stub inputs ----------------------------------------------

STUB_VERSION="52"
STUB_SHORT="0.2.0"
STUB_SIG="StUbSiGnAtUrE1234567890abcdefABCDEF=="
STUB_LENGTH="123456"
STUB_URL="https://github.com/trafficwand/trafficwand/releases/download/v0.2.0/TrafficWand-0.2.0.dmg"
STUB_MIN="26.0"

OUT="$(render_appcast "$STUB_VERSION" "$STUB_SHORT" "$STUB_SIG" "$STUB_LENGTH" "$STUB_URL" "$STUB_MIN")"

# --- Tests ----------------------------------------------------------------

assert_contains "renders sparkle:version from build number" \
    "$OUT" "<sparkle:version>52</sparkle:version>"
assert_contains "renders sparkle:shortVersionString from marketing version" \
    "$OUT" "<sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>"
assert_contains "renders sparkle:minimumSystemVersion 26.0" \
    "$OUT" "<sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>"
assert_contains "enclosure carries the versioned download URL" \
    "$OUT" "url=\"$STUB_URL\""
assert_contains "enclosure carries the stub edSignature" \
    "$OUT" "sparkle:edSignature=\"$STUB_SIG\""
assert_contains "enclosure carries the stub length" \
    "$OUT" "length=\"$STUB_LENGTH\""
assert_contains "title reflects the marketing version" \
    "$OUT" "<title>Version 0.2.0</title>"
assert_contains "declares the sparkle XML namespace" \
    "$OUT" "xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\""

# --- Summary --------------------------------------------------------------

printf '\n%d test(s), %d failure(s)\n' "$TESTS" "$FAILURES"
[ "$FAILURES" -eq 0 ] || exit 1
