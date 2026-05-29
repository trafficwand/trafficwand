#!/usr/bin/env bash
#
# verify-release-version.test.sh — Self-contained assertion tests for
# verify-release-version.sh. No network, Xcode, or secrets required.
#
# Uses a temp fixture project file in the real format
# (`    MARKETING_VERSION: "1.2.3"`) so the tests stay independent of the
# repo's current MARKETING_VERSION.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/verify-release-version.sh"

FAILURES=0
TESTS=0

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    FAILURES=$((FAILURES + 1))
}

pass() {
    printf 'ok: %s\n' "$1"
}

# assert_pass <description> <expected-stdout> <tag> <project-file>
# The project-file arg is REQUIRED: every test must point the script at a temp
# fixture. Defaulting it would let an empty PROJECT_FILE silently fall back to
# the repo's live project.yml (the script resolves via ${PROJECT_FILE:-project.yml},
# and `:-` treats "" as unset), coupling the tests to live state.
assert_pass() {
    if [ "$#" -ne 4 ]; then
        fail "assert_pass: requires 4 args (desc, expected, tag, project-file), got $#"
        TESTS=$((TESTS + 1))
        return
    fi
    local desc="$1" expected="$2" tag="$3" file="$4"
    TESTS=$((TESTS + 1))
    local out status
    if out="$(PROJECT_FILE="$file" bash "$SUT" "$tag" 2>/dev/null)"; then
        status=0
    else
        status=$?
    fi
    if [ "$status" -ne 0 ]; then
        fail "$desc: expected exit 0, got $status"
        return
    fi
    if [ "$out" != "$expected" ]; then
        fail "$desc: expected stdout '$expected', got '$out'"
        return
    fi
    pass "$desc"
}

# assert_fail <description> <expected-stderr-substring> <tag> <project-file>
# The project-file arg is REQUIRED (see assert_pass). assert_fail also asserts
# WHICH die() path fired by matching a substring of stderr, so a test can't pass
# for the wrong reason (the script has several distinct exit-1 paths).
assert_fail() {
    if [ "$#" -ne 4 ]; then
        fail "assert_fail: requires 4 args (desc, expected-stderr, tag, project-file), got $#"
        TESTS=$((TESTS + 1))
        return
    fi
    local desc="$1" expected_err="$2" tag="$3" file="$4"
    TESTS=$((TESTS + 1))
    local err status
    if err="$(PROJECT_FILE="$file" bash "$SUT" "$tag" 2>&1 >/dev/null)"; then
        status=0
    else
        status=$?
    fi
    if [ "$status" -eq 0 ]; then
        fail "$desc: expected non-zero exit, got 0"
        return
    fi
    case "$err" in
        *"$expected_err"*) pass "$desc (exit $status)" ;;
        *) fail "$desc: expected stderr to contain '$expected_err', got '$err'" ;;
    esac
}

# --- Fixtures -------------------------------------------------------------

TMPDIR_FIXTURE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_FIXTURE"' EXIT

GOOD_FIXTURE="$TMPDIR_FIXTURE/project.yml"
cat >"$GOOD_FIXTURE" <<'EOF'
name: TrafficWand
settings:
  base:
    MARKETING_VERSION: "1.2.3"
    CURRENT_PROJECT_VERSION: "1"
EOF

NO_VERSION_FIXTURE="$TMPDIR_FIXTURE/no-version.yml"
cat >"$NO_VERSION_FIXTURE" <<'EOF'
name: TrafficWand
settings:
  base:
    CURRENT_PROJECT_VERSION: "1"
EOF

# Empty quoted value: `MARKETING_VERSION: ""` — present but empty.
EMPTY_VERSION_FIXTURE="$TMPDIR_FIXTURE/empty-version.yml"
cat >"$EMPTY_VERSION_FIXTURE" <<'EOF'
name: TrafficWand
settings:
  base:
    MARKETING_VERSION: ""
    CURRENT_PROJECT_VERSION: "1"
EOF

# Unquoted value: `MARKETING_VERSION: 1.2.3` — no surrounding double-quotes.
UNQUOTED_FIXTURE="$TMPDIR_FIXTURE/unquoted.yml"
cat >"$UNQUOTED_FIXTURE" <<'EOF'
name: TrafficWand
settings:
  base:
    MARKETING_VERSION: 1.2.3
    CURRENT_PROJECT_VERSION: "1"
EOF

# Trailing whitespace after the quoted value (must be trimmed).
TRAILING_WS_FIXTURE="$TMPDIR_FIXTURE/trailing-ws.yml"
printf 'name: TrafficWand\nsettings:\n  base:\n    MARKETING_VERSION: "1.2.3"   \n' >"$TRAILING_WS_FIXTURE"

# --- Tests ----------------------------------------------------------------

assert_pass "exact match passes and echoes version" "1.2.3" "1.2.3" "$GOOD_FIXTURE"
assert_pass "v-prefixed match passes" "1.2.3" "v1.2.3" "$GOOD_FIXTURE"
assert_pass "unquoted MARKETING_VERSION matches" "1.2.3" "1.2.3" "$UNQUOTED_FIXTURE"
assert_pass "trailing whitespace is trimmed" "1.2.3" "1.2.3" "$TRAILING_WS_FIXTURE"
assert_fail "mismatch fails" "does not match MARKETING_VERSION" "9.9.9" "$GOOD_FIXTURE"
assert_fail "v-prefixed mismatch fails" "does not match MARKETING_VERSION" "v9.9.9" "$GOOD_FIXTURE"
assert_fail "missing arg fails" "missing required argument" "" "$GOOD_FIXTURE"
assert_fail "bare 'v' tag fails after stripping" "empty after stripping leading 'v'" "v" "$GOOD_FIXTURE"
assert_fail "missing MARKETING_VERSION fails" "MARKETING_VERSION not found" "1.2.3" "$NO_VERSION_FIXTURE"
assert_fail "empty MARKETING_VERSION value fails" "MARKETING_VERSION is empty" "1.2.3" "$EMPTY_VERSION_FIXTURE"
assert_fail "missing project file fails" "project file not found" "1.2.3" "$TMPDIR_FIXTURE/does-not-exist.yml"

# --- Summary --------------------------------------------------------------

printf '\n%d test(s), %d failure(s)\n' "$TESTS" "$FAILURES"
[ "$FAILURES" -eq 0 ] || exit 1
