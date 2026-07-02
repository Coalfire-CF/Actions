#!/usr/bin/env bash
#
# source-pin-check.sh — SHA-preferred Terraform source-pinning gate.
#
# Standard: RFC-0008 / ADR-0018 (Coalfire-CF/MTCS) — "SHA-preferred pinning".
#
# Classifies each Terraform module whose `source` is a github.com/Coalfire-CF/*
# repo:
#   PASS  — ?ref=<40-hex commit SHA> WITH an adjacent `# vX.Y.Z` release comment
#           on the same line (the immutable, auditable pin).
#   WARN  — ?ref=vX.Y.Z release tag (transitional per RFC-0008; a git tag is
#           mutable, so it is allowed only during the advisory window).
#   FAIL  — no ?ref=, a branch / non-release ref, or a bare commit SHA WITHOUT
#           the adjacent `# vX.Y.Z` comment (unauditable — the comment is what
#           makes the SHA reviewable).
#
# Advisory-first rollout (uniform across the new CF gates). STRICT controls
# whether FAIL-class findings fail the job:
#   STRICT=false (default) — FAIL findings emit ::warning; the gate exits 0.
#   STRICT=true            — FAIL findings emit ::error;   the gate exits 1.
# WARN-class always emits ::warning and never affects exit status.
#
# Usage:
#   source-pin-check.sh [ROOT]                 # ROOT defaults to "."
#   STRICT=true source-pin-check.sh [ROOT]
#
# Exclusions (per CF pinning policy): vendored, cached (.terraform), and example
# trees are skipped, plus this repo's own tests/fixtures/source-pin/ meta-test
# fixtures (so the gate does not flag its intentionally failing fixtures when it
# scans this repository).
#
# Output uses GitHub Actions ::error / ::warning annotations so findings surface
# inline on the offending file/line in a PR.

set -uo pipefail

ROOT="${1:-.}"
STRICT="${STRICT:-false}"

# Collect candidate source lines. Anchor on `source = "github.com/Coalfire-CF/`
# so we only inspect real module-source declarations, not prose/comments.
matches="$(grep -rnE 'source[[:space:]]*=[[:space:]]*"github\.com/Coalfire-CF/' "$ROOT" \
  --include='*.tf' \
  --exclude-dir='vendor' \
  --exclude-dir='.terraform' \
  --exclude-dir='example' \
  --exclude-dir='examples' \
  2>/dev/null | grep -vE '/tests/fixtures/source-pin/' || true)"

fail_count=0
warn_count=0

emit_fail() {
  # $1=file $2=line $3=message
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

  # Extract the quoted source URL (first quoted github.com/Coalfire-CF/... value).
  url="$(printf '%s' "$content" | sed -E 's/.*"(github\.com\/Coalfire-CF\/[^"]*)".*/\1/')"

  # Does the line carry an adjacent release comment `# vX.Y.Z`?
  has_comment=false
  if printf '%s' "$content" | grep -Eq '#[[:space:]]*v[0-9]+\.[0-9]+\.[0-9]+'; then
    has_comment=true
  fi

  if [[ "$url" != *"?ref="* ]]; then
    emit_fail "$file" "$lineno" "Unpinned Coalfire-CF module source (no ?ref=): ${url}"
    continue
  fi

  ref="${url#*\?ref=}"
  # Strip any trailing subpath / extra query params after the ref value.
  ref="${ref%%[/&]*}"

  if [[ "$ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
    # Commit SHA — PASS only if the adjacent release comment is present.
    if [[ "$has_comment" != "true" ]]; then
      emit_fail "$file" "$lineno" \
        "Coalfire-CF module source pinned to a bare commit SHA without an adjacent '# vX.Y.Z' release comment (unauditable): ${url}"
    fi
    # else: PASS — no output.
  elif [[ "$ref" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # Release tag — transitional WARN (mutable ref).
    emit_warn "$file" "$lineno" \
      "Coalfire-CF module source pinned to release tag '${ref}'; RFC-0008 prefers that tag's commit SHA + '# ${ref}' comment (git tags are mutable). Transitional — warn-only."
  else
    # Branch / non-release / malformed ref.
    emit_fail "$file" "$lineno" \
      "Coalfire-CF module source is not pinned to an immutable SHA (ref='${ref}', expected 40-hex SHA + '# vX.Y.Z' comment): ${url}"
  fi
done <<< "$matches"

echo "source-pin-check: ${fail_count} fail-class, ${warn_count} warn-class finding(s) (STRICT=${STRICT})."

if [[ "$fail_count" -gt 0 && "$STRICT" == "true" ]]; then
  echo "source-pin-check: FAILED — ${fail_count} unpinned/unauditable Coalfire-CF module source(s)."
  exit 1
fi

if [[ "$fail_count" -gt 0 || "$warn_count" -gt 0 ]]; then
  echo "source-pin-check: PASSED (advisory) — findings emitted as warnings; set strict:true to enforce."
  exit 0
fi

echo "source-pin-check: PASSED — all Coalfire-CF module sources SHA-pinned with release comments."
exit 0
