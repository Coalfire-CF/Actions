#!/usr/bin/env bash
#
# uses-pin-check.sh — SHA-preferred workflow `uses:` pinning gate.
#
# Standard: RFC-0008 / ADR-0018 (Coalfire-CF/MTCS) — the same SHA-preferred rule
# the source-pin gate applies to Terraform module sources, applied here to
# GitHub Actions / reusable-workflow `uses:` references.
#
# Classifies each `uses:` reference in workflow / composite-action YAML:
#   PASS  — local ref (`uses: ./...`), OR `uses: owner/repo...@<40-hex SHA>`
#           WITH an adjacent `# vX[.Y[.Z]]` release comment.
#   WARN  — `uses: ...@vX[.Y[.Z]]` release/version tag (transitional per
#           RFC-0008; a tag is mutable).
#   FAIL  — `@main`/branch/other mutable ref, a bare SHA WITHOUT the release
#           comment, or a `uses:` with no resolvable ref.
#   SKIP  — `docker://...` image refs (out of scope for this gate).
#
# Advisory-first rollout (STRICT env), identical mechanics to source-pin-check.sh:
#   STRICT=false (default) — FAIL findings emit ::warning; the gate exits 0.
#   STRICT=true            — FAIL findings emit ::error;   the gate exits 1.
# WARN-class always emits ::warning and never affects exit status.
#
# Usage:
#   uses-pin-check.sh [ROOT]                 # ROOT defaults to "."
#   STRICT=true uses-pin-check.sh [ROOT]
#
# Exclusions: vendor/, .terraform/, and this repo's own tests/fixtures/uses-pin/
# meta-test fixtures. Commented example lines (leading '#') are ignored.

set -uo pipefail

ROOT="${1:-.}"
STRICT="${STRICT:-false}"

# Anchor on lines whose first non-space token is `uses:` or `- uses:` (skips
# '#   uses: ...' doc examples, which begin with '#').
matches="$(grep -rnE '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]' "$ROOT" \
  --include='*.yml' \
  --include='*.yaml' \
  --exclude-dir='vendor' \
  --exclude-dir='.terraform' \
  2>/dev/null | grep -vE '/tests/fixtures/uses-pin/' || true)"

fail_count=0
warn_count=0

emit_fail() {
  if [[ "$STRICT" == "true" ]]; then
    echo "::error file=${1},line=${2}::${3}"
  else
    echo "::warning file=${1},line=${2}::[advisory] ${3}"
  fi
  fail_count=$((fail_count + 1))
}

emit_warn() {
  echo "::warning file=${1},line=${2}::${3}"
  warn_count=$((warn_count + 1))
}

while IFS= read -r entry; do
  [ -z "$entry" ] && continue

  file="${entry%%:*}"
  rest="${entry#*:}"
  lineno="${rest%%:*}"
  content="${rest#*:}"

  # Value after `uses:` up to the first whitespace = the ref token.
  val="${content#*uses:}"
  val="$(printf '%s' "$val" | sed -E 's/^[[:space:]]+//')"
  token="${val%%[[:space:]]*}"
  # Strip surrounding quotes if any.
  token="${token%\"}"; token="${token#\"}"
  token="${token%\'}"; token="${token#\'}"

  # Adjacent release comment `# vX[.Y[.Z]]` present on the line?
  has_comment=false
  if printf '%s' "$content" | grep -Eq '#[[:space:]]*v[0-9]+(\.[0-9]+)*'; then
    has_comment=true
  fi

  # Local ref → PASS (resolves at the called workflow's own immutable SHA).
  if [[ "$token" == ./* || "$token" == ../* ]]; then
    continue
  fi

  # Docker image ref → out of scope.
  if [[ "$token" == docker://* ]]; then
    continue
  fi

  if [[ "$token" != *"@"* ]]; then
    emit_fail "$file" "$lineno" "Unpinned 'uses:' reference (no @ref): ${token}"
    continue
  fi

  ref="${token##*@}"

  if [[ "$ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
    if [[ "$has_comment" != "true" ]]; then
      emit_fail "$file" "$lineno" \
        "'uses:' pinned to a bare commit SHA without an adjacent '# vX.Y.Z' release comment (unauditable): ${token}"
    fi
    # else PASS.
  elif [[ "$ref" =~ ^v[0-9]+(\.[0-9]+)*$ ]]; then
    emit_warn "$file" "$lineno" \
      "'uses:' pinned to tag '${ref}'; RFC-0008 prefers that tag's commit SHA + '# ${ref}' comment (tags are mutable). Transitional — warn-only: ${token}"
  else
    emit_fail "$file" "$lineno" \
      "'uses:' pinned to a mutable/branch ref '${ref}' (expected 40-hex SHA + '# vX.Y.Z' comment, or a local ./ ref): ${token}"
  fi
done <<< "$matches"

echo "uses-pin-check: ${fail_count} fail-class, ${warn_count} warn-class finding(s) (STRICT=${STRICT})."

if [[ "$fail_count" -gt 0 && "$STRICT" == "true" ]]; then
  echo "uses-pin-check: FAILED — ${fail_count} unpinned/unauditable 'uses:' reference(s)."
  exit 1
fi

if [[ "$fail_count" -gt 0 || "$warn_count" -gt 0 ]]; then
  echo "uses-pin-check: PASSED (advisory) — findings emitted as warnings; set strict:true to enforce."
  exit 0
fi

echo "uses-pin-check: PASSED — all 'uses:' references SHA-pinned with release comments or local."
exit 0
