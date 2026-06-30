#!/usr/bin/env bash
#
# source-pin-check.sh
#
# CF-WAF source-pinning gate. Fails (exit 1) if any Terraform module whose
# source is a github.com/Coalfire-CF/* repo is NOT pinned to a release tag of
# the form vX.Y.Z.
#
# Catches:
#   - floating refs   (no ?ref= at all)
#   - branch refs     (?ref=main, ?ref=module, ?ref=develop, ...)
#   - bare SHAs       (?ref=<hex>)
#   - non-release tags / pre-release / 0.x style refs that are not vMAJOR.MINOR.PATCH
#
# Usage:
#   source-pin-check.sh [ROOT]      # ROOT defaults to "."
#
# Exclusions (per CF-WAF pinning policy): vendored, cached (.terraform), and
# example trees are skipped, plus this repo's own meta-test fixtures
# (tests/fixtures/source-pin/) so the gate does not flag its intentionally
# failing fixtures when scanning this repository.
#
# Output uses GitHub Actions ::error annotations so failures surface inline on
# the offending file/line in a PR.

set -uo pipefail

ROOT="${1:-.}"

# Collect candidate source lines. Anchor on `source = "github.com/Coalfire-CF/`
# so we only inspect real module-source declarations, not prose/comments.
matches="$(grep -rnE 'source[[:space:]]*=[[:space:]]*"github\.com/Coalfire-CF/' "$ROOT" \
  --include='*.tf' \
  --exclude-dir='vendor' \
  --exclude-dir='.terraform' \
  --exclude-dir='example' \
  --exclude-dir='examples' \
  2>/dev/null | grep -vE '/tests/fixtures/source-pin/' || true)"

violations=0

while IFS= read -r entry; do
  [ -z "$entry" ] && continue

  file="${entry%%:*}"
  rest="${entry#*:}"
  lineno="${rest%%:*}"
  content="${rest#*:}"

  # Extract the quoted source URL (first quoted github.com/Coalfire-CF/... value).
  url="$(printf '%s' "$content" | sed -E 's/.*"(github\.com\/Coalfire-CF\/[^"]*)".*/\1/')"

  if [[ "$url" != *"?ref="* ]]; then
    echo "::error file=${file},line=${lineno}::Unpinned Coalfire-CF module source (no ?ref= tag): ${url}"
    violations=$((violations + 1))
    continue
  fi

  ref="${url#*\?ref=}"
  # Strip any trailing subpath / extra query params after the ref value.
  ref="${ref%%[/&]*}"

  if [[ ! "$ref" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "::error file=${file},line=${lineno}::Coalfire-CF module source is not pinned to a release tag (ref='${ref}', expected vX.Y.Z): ${url}"
    violations=$((violations + 1))
  fi
done <<< "$matches"

if [[ "$violations" -gt 0 ]]; then
  echo "source-pin-check: FAILED — ${violations} unpinned Coalfire-CF module source(s) found."
  exit 1
fi

echo "source-pin-check: PASSED — all Coalfire-CF module sources pinned to release tags (vX.Y.Z)."
exit 0
