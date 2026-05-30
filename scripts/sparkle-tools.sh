#!/usr/bin/env bash
#
# sparkle-tools.sh — SOURCED library: pinned Sparkle tooling + downloader.
#
# Single source of truth for the Sparkle binary-tools version/URL/checksum and
# the download → verify → extract logic, shared by:
#   - scripts/generate-appcast.sh        (uses bin/sign_update)
#   - scripts/install-sparkle-tools.sh   (`task sparkle:install` / `sparkle:gen-keys`,
#                                          uses bin/generate_keys)
#
# Source it; do NOT execute. It only defines SPARKLE_* constants and
# ensure_sparkle_tools() — sourcing has no side effects (no network, no extract),
# so generate-appcast.test.sh can safely source generate-appcast.sh which sources
# this file.

# Pin the Sparkle binary tools tarball to the SAME version as the SPM `from:`
# constraint in project.yml (2.9.2). Pinning + checksum keeps the tooling
# reproducible and prevents a supply-chain swap of the signing / key-gen tools.
# Update SPARKLE_TARBALL_SHA256 in lockstep whenever SPARKLE_VERSION is bumped.
SPARKLE_VERSION="2.9.2"
SPARKLE_TARBALL="Sparkle-${SPARKLE_VERSION}.tar.xz"
SPARKLE_TARBALL_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/${SPARKLE_TARBALL}"
# SHA256 of Sparkle-2.9.2.tar.xz, obtained by downloading the GitHub release asset
# above and running `shasum -a 256`.
SPARKLE_TARBALL_SHA256="1cb340cbbef04c6c0d162078610c25e2221031d794a3449d89f2f56f4df77c95"

_sparkle_die() {
    printf 'sparkle-tools: error: %s\n' "$1" >&2
    exit 1
}

# ensure_sparkle_tools <dest-dir>
#
# Idempotently make the pinned Sparkle binary tools available under <dest-dir>:
# download the tarball, verify its SHA256 BEFORE extracting/running anything,
# extract, clear quarantine (best-effort). A <dest-dir>/.sparkle-version marker
# records the installed version, so a stale dir (e.g. after a SPARKLE_VERSION
# bump) is re-fetched rather than silently reused. Prints the path to
# <dest-dir>/bin on stdout; everything else goes to stderr.
ensure_sparkle_tools() {
    local dest_dir="$1"
    local bin_dir="$dest_dir/bin"
    local marker="$dest_dir/.sparkle-version"

    # Fast path: pinned version already installed.
    if [ -x "$bin_dir/sign_update" ] && [ -x "$bin_dir/generate_keys" ] \
        && [ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$SPARKLE_VERSION" ]; then
        printf '%s\n' "$bin_dir"
        return 0
    fi

    command -v curl   >/dev/null 2>&1 || _sparkle_die "curl not found on PATH"
    command -v shasum >/dev/null 2>&1 || _sparkle_die "shasum not found on PATH"

    mkdir -p "$dest_dir"
    local tarball_path="$dest_dir/$SPARKLE_TARBALL"

    printf 'sparkle-tools: downloading %s\n' "$SPARKLE_TARBALL_URL" >&2
    curl -fsSL -o "$tarball_path" "$SPARKLE_TARBALL_URL" \
        || _sparkle_die "failed to download $SPARKLE_TARBALL_URL"

    # Verify the checksum BEFORE extracting/running anything from the tarball.
    local actual
    actual="$(shasum -a 256 "$tarball_path" | awk '{print $1}')"
    if [ "$actual" != "$SPARKLE_TARBALL_SHA256" ]; then
        _sparkle_die "checksum mismatch for $SPARKLE_TARBALL: expected $SPARKLE_TARBALL_SHA256, got $actual"
    fi

    tar -xJf "$tarball_path" -C "$dest_dir" || _sparkle_die "failed to extract $SPARKLE_TARBALL"
    rm -f "$tarball_path"

    # A tool extracted from a downloaded tarball may carry com.apple.quarantine;
    # clear it (best-effort) so the tools run without a Gatekeeper prompt.
    xattr -dr com.apple.quarantine "$dest_dir" >/dev/null 2>&1 || true

    [ -x "$bin_dir/sign_update" ]   || _sparkle_die "sign_update not found/executable at $bin_dir/sign_update"
    [ -x "$bin_dir/generate_keys" ] || _sparkle_die "generate_keys not found/executable at $bin_dir/generate_keys"

    printf '%s\n' "$SPARKLE_VERSION" > "$marker"
    printf '%s\n' "$bin_dir"
}
