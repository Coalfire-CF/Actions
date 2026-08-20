#!/usr/bin/env bash
#
# fleet-audit-report.sh — roll fleet-audit NDJSON (stdin) into markdown.
# Truncates to FLEET_AUDIT_MAX_BYTES (default 60000) for GitHub issue bodies.

set -euo pipefail

command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

MAX="${FLEET_AUDIT_MAX_BYTES:-60000}"
ACTIONS_VERSION="${ACTIONS_VERSION:-unknown}"
ACTIONS_SHA="${ACTIONS_SHA:-unknown}"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
cat > "$TMP"

if [ ! -s "$TMP" ]; then
  echo "# Actions fleet audit"
  echo
  echo "No repo rows. Empty enumeration."
  exit 0
fi

# Tolerate trailing whitespace; skip blank lines.
FILTERED="$(mktemp)"
trap 'rm -f "$TMP" "$FILTERED"' EXIT
grep -v '^[[:space:]]*$' "$TMP" > "$FILTERED" || true
[ -s "$FILTERED" ] || {
  echo "# Actions fleet audit"
  echo
  echo "No repo rows. Empty enumeration."
  exit 0
}

counts="$(jq -s '{
  total: length,
  pass: [.[] | select(.status=="PASS")] | length,
  fail: [.[] | select(.status=="FAIL")] | length,
  skip: [.[] | select(.status=="SKIP")] | length,
  exempt: [.[] | select(.exempt==true)] | length
}' "$FILTERED")"

{
  echo "# Actions fleet audit"
  echo
  echo "Pin: \`${ACTIONS_VERSION}\` @ \`${ACTIONS_SHA}\`"
  echo
  echo "| metric | count |"
  echo "| --- | --- |"
  echo "| total | $(jq -r .total <<<"$counts") |"
  echo "| PASS | $(jq -r .pass <<<"$counts") |"
  echo "| FAIL | $(jq -r .fail <<<"$counts") |"
  echo "| SKIP | $(jq -r .skip <<<"$counts") |"
  echo "| bootstrap-exempt | $(jq -r .exempt <<<"$counts") |"
  echo

  ids="$(jq -s -r '[.[].findings[]? | .id] | unique | .[]' "$FILTERED")"
  if [ -z "$ids" ]; then
    echo "No findings."
  else
    echo "## Counts by check"
    echo
    echo "| id | repos |"
    echo "| --- | --- |"
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      n="$(jq -s --arg id "$id" '[.[] | select(any(.findings[]?; .id==$id))] | length' "$FILTERED")"
      echo "| \`${id}\` | ${n} |"
    done <<< "$ids"
    echo
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      echo "## ${id}"
      echo
      echo "| repo | severity | detail |"
      echo "| --- | --- | --- |"
      jq -s -r --arg id "$id" '
        .[] as $r
        | $r.findings[]?
        | select(.id==$id)
        | "| `\($r.repo)` | \(.severity) | \( (.detail // "") | gsub("\\|"; "\\|") ) |"
      ' "$FILTERED"
      echo
    done <<< "$ids"
  fi

  skips="$(jq -s -r '[.[] | select(.status=="SKIP") | .repo] | .[]' "$FILTERED")"
  if [ -n "$skips" ]; then
    echo "## SKIP"
    echo
    echo "| repo | reason |"
    echo "| --- | --- |"
    jq -s -r '.[] | select(.status=="SKIP") | "| `\(.repo)` | \(.skip_reason) |"' "$FILTERED"
    echo
  fi
} > "${TMP}.md"

body="$(cat "${TMP}.md")"
bytes="$(printf '%s' "$body" | wc -c | tr -d ' ')"
if [ "$bytes" -gt "$MAX" ]; then
  printf '%s\n' "${body:0:$((MAX - 80))}"
  echo
  echo "... truncated (${bytes} bytes). Full report is the workflow artifact."
else
  printf '%s\n' "$body"
fi
rm -f "${TMP}.md"
