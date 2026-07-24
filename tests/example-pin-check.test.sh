#!/usr/bin/env bash
#
# Guard for the copy-paste caller examples (#221). The README/docs pin
# Coalfire-CF/Actions reusable workflows by SHA with a `# vX.Y.Z` tag comment;
# that comment is fleet-wide onboarding guidance and silently drifts every
# release. This test fails when any example's tag comment does not match the
# current release in .release-please-manifest.json, so a release that forgets to
# refresh the examples is caught in CI rather than shipping N releases behind.
#
# NOTE: this checks the `# vX.Y.Z` comment (the visible-drift symptom). The 40-hex
# SHA must be refreshed to the new release tag's commit by hand alongside it — a
# release cannot know its own tag SHA at release-PR time, so it cannot be
# auto-bumped without introducing a SHA/tag mismatch.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

fail() { echo "NOT OK: $1"; exit 1; }

VER="$(jq -r '."."' "${REPO_ROOT}/.release-please-manifest.json" 2>/dev/null)"
[ -n "$VER" ] && [ "$VER" != "null" ] || fail "could not read version from .release-please-manifest.json"
WANT="v${VER}"

FILES=(README.md docs/ORG_DEPENDABOT_AUTO_MERGE.md)
# Lines that pin an Actions reusable workflow (or actions_ref) with a version tag comment.
PIN_RE='(/Actions/\.github/workflows/[^@]*@[0-9a-fA-F]{40}|actions_ref:[[:space:]]*[0-9a-fA-F]{40})[[:space:]]*#[[:space:]]*v[0-9]+\.[0-9]+\.[0-9]+'

bad=0
checked=0
for f in "${FILES[@]}"; do
  [ -f "${REPO_ROOT}/${f}" ] || continue
  while IFS= read -r line; do
    tag="$(printf '%s' "$line" | sed -nE 's/.*#[[:space:]]*(v[0-9]+\.[0-9]+\.[0-9]+).*/\1/p')"
    [ -n "$tag" ] || continue
    checked=$((checked + 1))
    if [ "$tag" != "$WANT" ]; then
      echo "  ${f}: example pins ${tag}, expected ${WANT} -> ${line}"
      bad=1
    fi
  done < <(grep -hoE "$PIN_RE" "${REPO_ROOT}/${f}" 2>/dev/null || true)
done

[ "$checked" -gt 0 ] || fail "no example pins found — did the pin format change? (loosen PIN_RE)"
[ "$bad" -eq 0 ] || fail "example pin(s) out of date vs manifest ${WANT} — refresh the README/docs caller examples on release (#221)"
echo "OK: all ${checked} example pin(s) advertise ${WANT}"
echo "ALL TESTS PASSED"
