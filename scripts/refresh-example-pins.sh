#!/usr/bin/env bash
#
# refresh-example-pins.sh <tag> <sha>: point the copy-paste caller examples in
# the README and docs at a release. Run by the refresh-example-pins job in
# .github/workflows/internal-release.yml after release-please creates a tag.
#
# Rewrites, in EXAMPLE_PIN_FILES only:
#   Coalfire-CF/Actions/.github/workflows/<file>@<40-hex> # vX.Y.Z
#   actions_ref: <40-hex> # vX.Y.Z
# to <sha> # <tag>. Other pins (third-party actions, composite actions) are left
# alone. tests/example-pin-check.test.sh guards the same lines.
#
# Idempotent. Prints the number of pins now at <tag>, and exits non-zero if it
# found none (the pin format changed and nothing would be kept current).
#
set -euo pipefail

TAG="${1:?usage: refresh-example-pins.sh <tag vX.Y.Z> <40-hex sha>}"
SHA="${2:?usage: refresh-example-pins.sh <tag vX.Y.Z> <40-hex sha>}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "tag must look like v1.2.3, got '${TAG}'" >&2; exit 2; }
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "sha must be 40 lower-case hex, got '${SHA}'" >&2; exit 2; }

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# Keep in sync with FILES in tests/example-pin-check.test.sh.
EXAMPLE_PIN_FILES=(README.md docs/ORG_DEPENDABOT_AUTO_MERGE.md docs/ORG_TERRATEST.md)

total=0
for f in "${EXAMPLE_PIN_FILES[@]}"; do
  p="${REPO_ROOT}/${f}"
  [ -f "$p" ] || continue
  TAG="$TAG" SHA="$SHA" perl -pi -e '
    s{(/Actions/\.github/workflows/[^@\s]*\@)[0-9a-fA-F]{40}([ \t]*#[ \t]*)v\d+\.\d+\.\d+}{$1$ENV{SHA}$2$ENV{TAG}}g;
    s{(actions_ref:[ \t]*)[0-9a-fA-F]{40}([ \t]*#[ \t]*)v\d+\.\d+\.\d+}{$1$ENV{SHA}$2$ENV{TAG}}g;
  ' "$p"
  n="$(grep -cE "(@|actions_ref:[[:space:]]*)${SHA}[[:space:]]*#[[:space:]]*${TAG}([^0-9]|$)" "$p" || true)"
  total=$((total + n))
done

[ "$total" -gt 0 ] || { echo "no example pins found to refresh; did the pin format change?" >&2; exit 1; }
echo "example pins at ${TAG}: ${total}"
