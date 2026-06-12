#!/bin/sh
# generate_build_info.sh — Issue #39
#
# Writes DictApp/DictApp/BuildInfo.xcconfig with the current HEAD's
# `git describe` so the running app can display its exact release tag (or
# full dev describe). Invoked as a *Build pre-action* on the shared scheme,
# which runs before Xcode resolves build settings — so the value lands in
# THIS build's xcconfig (a Run Script Build Phase would be too late; it only
# validates, see the validation phase added to the app target).
#
# Policy (DESIGN_DOC §2):
#   * HEAD exactly on a tag      -> bare tag         e.g. "v1.3.0"   (clean)
#   * HEAD past the last tag     -> full describe    e.g. "v1.2.0-8-gc7238e0"
#   * No tags at all             -> bare commit SHA  e.g. "c7238e0"
#   * "uncommitted on tag = clean" — we never pass --dirty.
#   * Missing .git / no commits  -> FAIL LOUD (exit 1).
#
# Pre-actions get a minimal environment, so set a sane PATH and use the
# system git shim. SRCROOT is exported by Xcode when the pre-action is
# configured to "Provide build settings from: DictApp"; we fall back to the
# script's own location for standalone runs (manual testing / CI shells).

set -eu

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

# Run git from inside the working copy. Prefer SRCROOT (the app project dir,
# which lives inside the repo); fall back to this script's directory.
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "${SRCROOT:-$script_dir}" 2>/dev/null || cd "$script_dir"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "error: .git unavailable — run from a git working copy (run 'git fetch --tags' before archiving)"
    exit 1
fi

# Resolve the repo root so the output path is correct regardless of whether
# SRCROOT is the repo root or the DictApp/ subdirectory.
repo_root="$(git rev-parse --show-toplevel)"

# Clean: HEAD exactly on a tag -> bare tag (no --dirty, so uncommitted edits
# on a tagged commit still count as clean). Otherwise the full dev describe,
# falling back to a bare abbreviated SHA when no tags exist.
describe="$(git describe --tags --exact-match 2>/dev/null || true)"
if [ -z "$describe" ]; then
    describe="$(git describe --tags --always 2>/dev/null || true)"
fi
if [ -z "$describe" ]; then
    echo "error: git describe produced no output (repository has no commits?)"
    exit 1
fi

out="$repo_root/DictApp/DictApp/BuildInfo.xcconfig"
mkdir -p "$(dirname "$out")"
printf 'GIT_DESCRIBE = %s\n' "$describe" > "$out"
echo "note: wrote GIT_DESCRIBE = $describe to ${out#"$repo_root"/}"
