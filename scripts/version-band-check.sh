#!/usr/bin/env bash
#
# version-band-check.sh — enforce the org-wide Terraform version band.
#
# Standard: RFC-0004 / ADR-0013 (Coalfire-CF/MTCS). Band = [FLOOR, CEILING),
# e.g. ">= 1.15.7, < 2.0.0". This gate asserts every first-party Terraform
# version declaration a repo carries sits inside that band and is bounded.
#
# Checks, across the scanned tree (excluding vendor/, .terraform/, example(s)/,
# and this repo's own tests/fixtures/version-band/):
#   - .terraform-version files              — content must be a concrete version in band.
#   - CI `terraform_version:` pins (YAML)   — concrete version in band.
#   - Terraform `required_version = "..."`  — must be UPPER-bounded (contains '<'
#                                             or '~>'); its lower/concrete bound
#                                             must sit in band. Open-ended
#                                             constraints (e.g. ">= 1.15.7") fail.
#
# Advisory-first rollout (STRICT env), same mechanics as the pin gates:
#   STRICT=false (default) — findings emit ::warning; exit 0.
#   STRICT=true            — findings emit ::error;   exit 1.
#
# Usage:  version-band-check.sh <ROOT> <FLOOR> <CEILING>
#   e.g.  version-band-check.sh . 1.15.7 2.0.0
#         STRICT=true version-band-check.sh . 1.15.7 2.0.0

set -uo pipefail

ROOT="${1:-.}"
FLOOR="${2:?floor version required (e.g. 1.15.7)}"
CEILING="${3:?ceiling version required (e.g. 2.0.0)}"
STRICT="${STRICT:-false}"

fail_count=0
emit_fail() {
  if [[ "$STRICT" == "true" ]]; then
    echo "::error file=${1},line=${2}::${3}"
  else
    echo "::warning file=${1},line=${2}::[advisory] ${3}"
  fi
  fail_count=$((fail_count + 1))
}

# Portable dotted-numeric compare: ver_lt A B → success (0) iff A < B.
ver_lt() {
  local a="$1" b="$2" i x y
  local IFS=.
  # shellcheck disable=SC2206
  local -a A=($a) B=($b)
  for i in 0 1 2; do
    x="${A[i]:-0}"; y="${B[i]:-0}"
    # Guard against non-numeric segments.
    [[ "$x" =~ ^[0-9]+$ ]] || x=0
    [[ "$y" =~ ^[0-9]+$ ]] || y=0
    if (( x < y )); then return 0; fi
    if (( x > y )); then return 1; fi
  done
  return 1  # equal → not less-than
}

# in_band V → success iff FLOOR <= V < CEILING.
in_band() { ! ver_lt "$1" "$FLOOR" && ver_lt "$1" "$CEILING"; }

skip_path() { [[ "$1" == *"/tests/fixtures/version-band/"* ]]; }

# ---- 1. .terraform-version files -------------------------------------------
while IFS= read -r vf; do
  [ -z "$vf" ] && continue
  skip_path "$vf" && continue
  v="$(tr -d '[:space:]' < "$vf")"
  if [[ ! "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    emit_fail "$vf" 1 ".terraform-version is not a concrete X.Y.Z version: '${v}'"
  elif ! in_band "$v"; then
    emit_fail "$vf" 1 ".terraform-version '${v}' is outside the band [>= ${FLOOR}, < ${CEILING})"
  fi
done < <(find "$ROOT" -type f -name '.terraform-version' \
  -not -path '*/vendor/*' -not -path '*/.terraform/*' \
  -not -path '*/example/*' -not -path '*/examples/*' 2>/dev/null)

# ---- 2. CI terraform_version: pins -----------------------------------------
while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  file="${entry%%:*}"; rest="${entry#*:}"; lineno="${rest%%:*}"; content="${rest#*:}"
  skip_path "$file" && continue
  # Ignore commented lines.
  printf '%s' "$content" | grep -Eq '^[[:space:]]*#' && continue
  val="$(printf '%s' "$content" | sed -E "s/.*terraform_version:[[:space:]]*//; s/[\"' ]//g; s/#.*//")"
  # Skip expression/interpolated pins and empty values.
  [[ -z "$val" || "$val" == *'${{'* ]] && continue
  if [[ ! "$val" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    emit_fail "$file" "$lineno" "terraform_version pin is not a concrete X.Y.Z version: '${val}'"
  elif ! in_band "$val"; then
    emit_fail "$file" "$lineno" "terraform_version '${val}' is outside the band [>= ${FLOOR}, < ${CEILING})"
  fi
done < <(grep -rnE 'terraform_version:[[:space:]]*[^[:space:]]' "$ROOT" \
  --include='*.yml' --include='*.yaml' \
  --exclude-dir='vendor' --exclude-dir='.terraform' \
  --exclude-dir='example' --exclude-dir='examples' 2>/dev/null)

# ---- 3. Terraform required_version constraints -----------------------------
while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  file="${entry%%:*}"; rest="${entry#*:}"; lineno="${rest%%:*}"; content="${rest#*:}"
  skip_path "$file" && continue
  constraint="$(printf '%s' "$content" | sed -E 's/.*required_version[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/')"
  [ -z "$constraint" ] && continue

  # Must be upper-bounded: a '<' operator or a '~>' pessimistic constraint.
  if [[ "$constraint" != *"<"* && "$constraint" != *"~>"* ]]; then
    emit_fail "$file" "$lineno" "required_version '${constraint}' is open-ended (no upper bound); RFC-0004 requires a ceiling (< ${CEILING} or ~>)"
    continue
  fi
  # The first concrete version in the constraint is the effective lower/anchor bound.
  low="$(printf '%s' "$constraint" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
  if [ -n "$low" ]; then
    # Normalize to X.Y.Z for comparison.
    [[ "$low" =~ ^[0-9]+\.[0-9]+$ ]] && low="${low}.0"
    if ! in_band "$low"; then
      emit_fail "$file" "$lineno" "required_version '${constraint}' anchors at ${low}, outside the band [>= ${FLOOR}, < ${CEILING})"
    fi
  fi
done < <(grep -rnE 'required_version[[:space:]]*=' "$ROOT" \
  --include='*.tf' \
  --exclude-dir='vendor' --exclude-dir='.terraform' \
  --exclude-dir='example' --exclude-dir='examples' 2>/dev/null)

echo "version-band-check: ${fail_count} finding(s) against band [>= ${FLOOR}, < ${CEILING}) (STRICT=${STRICT})."

if [[ "$fail_count" -gt 0 && "$STRICT" == "true" ]]; then
  echo "version-band-check: FAILED — ${fail_count} out-of-band/open-ended Terraform version declaration(s)."
  exit 1
fi
if [[ "$fail_count" -gt 0 ]]; then
  echo "version-band-check: PASSED (advisory) — findings emitted as warnings; set strict:true to enforce."
  exit 0
fi
echo "version-band-check: PASSED — all Terraform version declarations are in band."
exit 0
