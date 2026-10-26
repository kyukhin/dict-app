#!/bin/sh
# Build phase "Validate GIT_DESCRIBE" (Issues #39, #196), run by the DictApp
# target. Fails the build when the version Settings would show is wrong:
#   - GIT_DESCRIBE must match HEAD (the scheme pre-action
#     generate_build_info.sh wrote it for this commit);
#   - an archive (App Store build) must sit exactly on tag v$MARKETING_VERSION,
#     otherwise Settings would show e.g. "1.3.0-20-gbd22843" instead of "1.4.0".
set -u
cd "$SRCROOT" || { echo "error: cannot cd to SRCROOT"; exit 1; }
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "error: .git unavailable — run from a git working copy (git fetch --tags before archiving)"; exit 1
fi
# Same tag choice as generate_build_info.sh: the release tag of this version
# wins when HEAD carries it, even if other tags point at the same commit.
fresh=""
if [ -n "${MARKETING_VERSION:-}" ] && git tag --points-at HEAD | grep -Fqx "v${MARKETING_VERSION}"; then
  fresh="v${MARKETING_VERSION}"
fi
[ -n "$fresh" ] || fresh="$(git describe --tags --exact-match 2>/dev/null || true)"
[ -n "$fresh" ] || fresh="$(git describe --tags --always 2>/dev/null || true)"
[ -n "$fresh" ] || { echo "error: git describe produced no output"; exit 1; }
if [ "$fresh" != "${GIT_DESCRIBE:-}" ]; then
  echo "error: GIT_DESCRIBE ('${GIT_DESCRIBE:-}') != HEAD ('$fresh') — build pre-action didn't run or wrote a stale value; build via the shared DictApp scheme"; exit 1
fi
case "${ACTION:-}" in
  install|archive)
    if [ "${CONFIGURATION:-}" = Release ]; then
      want="v${MARKETING_VERSION:-}"
      if [ "$fresh" != "$want" ]; then
        echo "error: archiving ${MARKETING_VERSION:-?} needs HEAD tagged $want, but HEAD is '$fresh'. Merge the version bump to master, then: git tag -a $want -m \"${MARKETING_VERSION:-} version of the Dict app.\" && git push origin $want"; exit 1
      fi
    fi
    ;;
esac
echo "note: GIT_DESCRIBE validated = ${GIT_DESCRIBE:-}"
