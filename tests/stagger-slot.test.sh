#!/usr/bin/env bash
#
# Meta-test for scripts/stagger-slot.sh (grade-A plan #13, rider 2): the per-repo
# Dependabot schedule offset must be DETERMINISTIC (idempotent re-runs → zero
# diff) and SPREAD across the day (no degenerate all-in-one-bin hash).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
S="${REPO_ROOT}/scripts/stagger-slot.sh"

fail() { echo "NOT OK: $1"; exit 1; }
[ -x "$S" ] || chmod +x "$S"

# ---- format: HH:MM, valid ranges ----
slot="$("$S" Coalfire-CF/terraform-aws-rds)"
echo "$slot" | grep -qE '^([01][0-9]|2[0-3]):[0-5][0-9]$' || fail "slot '$slot' is not valid HH:MM"
echo "OK: slot format is valid HH:MM ($slot)"

# ---- determinism: same name → same slot across repeated invocations ----
a="$("$S" foo/bar)"; b="$("$S" foo/bar)"; c="$("$S" foo/bar)"
[ "$a" = "$b" ] && [ "$b" = "$c" ] || fail "not deterministic: $a / $b / $c"
echo "OK: deterministic — same repo name yields the same slot ($a) on every run"

# ---- spread: 100 synthetic names must not all collapse into one bucket ----
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
for i in $(seq 1 100); do "$S" "Coalfire-CF/repo-${i}"; done > "$tmp"
distinct_slots="$(sort -u "$tmp" | wc -l | tr -d ' ')"
distinct_hours="$(cut -d: -f1 "$tmp" | sort -u | wc -l | tr -d ' ')"
[ "$distinct_slots" -gt 1 ] || fail "degenerate: all 100 names mapped to ONE slot"
[ "$distinct_hours" -gt 4 ] || fail "poor spread: only ${distinct_hours} distinct hours across 100 names"
echo "OK: spread — 100 names → ${distinct_slots} distinct slots across ${distinct_hours} hours (not degenerate)"

# ---- distinct names generally differ (sanity, not a hard uniqueness guarantee) ----
[ "$("$S" org/alpha)" != "$("$S" org/omega)" ] || fail "two very different names collided (suspicious hash)"
echo "OK: distinct names map to distinct slots (org/alpha != org/omega)"

echo "ALL TESTS PASSED"
