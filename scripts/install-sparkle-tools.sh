#!/usr/bin/env bash
#
# install-sparkle-tools.sh — download the pinned Sparkle binary tools into .sparkle/.
#
# Idempotent: re-running is a no-op once the pinned version is present. Backs
# `task sparkle:install` and (transitively, via deps) `task sparkle:gen-keys`.
# The tools (bin/sign_update, bin/generate_keys) land in .sparkle/bin/, which is
# gitignored. Version/checksum/download logic lives in scripts/sparkle-tools.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=sparkle-tools.sh disable=SC1091
. "$SCRIPT_DIR/sparkle-tools.sh"

# Install under the repo root so the location is stable regardless of cwd.
cd "$SCRIPT_DIR/.."

bin_dir="$(ensure_sparkle_tools ".sparkle")"
printf 'Sparkle %s tools ready in %s\n' "$SPARKLE_VERSION" "$bin_dir" >&2
