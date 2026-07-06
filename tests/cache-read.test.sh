#!/usr/bin/env bash
#
# Meta-test for scripts/cache-lib.sh (grade-A plan #9): fail-SAFE cache field
# reads + schema_version/producer validation.
#
# Pins the hardened behavior:
#   - a valid object (schema_version + producer match) is accepted; a genuine
#     boolean field reads through as-is;
#   - a MISSING / non-boolean field reads as the caller's SAFE value (osv.clear
#     and scorecard.pass → false = not-clear/not-pass; changelog.breaking → true
#     = breaking), so a partial/corrupt cache blocks or holds a PR, never approves;
#   - an object with the wrong producer, an unknown schema_version, or NO schema
#     stamp at all (every pre-#9 object) fails cache_schema_ok → the caller treats
#     it as a miss and re-analyzes.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB="${REPO_ROOT}/scripts/cache-lib.sh"
FIX="${SCRIPT_DIR}/fixtures/cache-read"

fail() { echo "NOT OK: $1"; exit 1; }
[ -f "$LIB" ] || fail "cache-lib.sh not found at $LIB"
# shellcheck source=scripts/cache-lib.sh
. "$LIB"

eq() { # <desc> <got> <want>
  [ "$2" = "$3" ] || fail "$1: got '$2' want '$3'"
  echo "OK: $1 -> $2"
}

# ---- schema/producer validation (cache_schema_ok) ----
cache_schema_ok "$FIX/complete_clean.json"  || fail "complete_clean should pass schema_ok"
echo "OK: complete_clean passes schema_ok"
cache_schema_ok "$FIX/missing_fields.json"  || fail "missing_fields (valid stamp) should pass schema_ok"
echo "OK: missing_fields (valid stamp, no data fields) passes schema_ok"
cache_schema_ok "$FIX/vuln.json"            || fail "vuln (valid stamp) should pass schema_ok"
echo "OK: vuln (valid stamp) passes schema_ok"
! cache_schema_ok "$FIX/wrong_producer.json"  || fail "wrong_producer must FAIL schema_ok"
echo "OK: wrong_producer fails schema_ok (rejected → re-analyze)"
! cache_schema_ok "$FIX/unknown_schema.json"  || fail "unknown_schema must FAIL schema_ok"
echo "OK: unknown_schema fails schema_ok (rejected → re-analyze)"
! cache_schema_ok "$FIX/legacy_no_schema.json" || fail "legacy (no stamp) must FAIL schema_ok"
echo "OK: legacy pre-#9 object (no stamp) fails schema_ok (transparently re-analyzed)"
! cache_schema_ok "$FIX/does-not-exist.json"   || fail "missing file must FAIL schema_ok"
echo "OK: missing file fails schema_ok"

# ---- fail-SAFE field reads (cache_read_bool <file> <path> <safe>) ----
# Present, genuine booleans read through as-is.
eq "clean osv.clear=true"        "$(cache_read_bool "$FIX/complete_clean.json" '.osv.clear' false)"       "true"
eq "clean scorecard.pass=true"   "$(cache_read_bool "$FIX/complete_clean.json" '.scorecard.pass' false)"  "true"
eq "clean changelog.breaking=false" "$(cache_read_bool "$FIX/complete_clean.json" '.changelog.breaking' true)" "false"
# Legitimate not-clear / not-pass / breaking read through.
eq "vuln osv.clear=false"        "$(cache_read_bool "$FIX/vuln.json" '.osv.clear' false)"                  "false"
eq "vuln changelog.breaking=true" "$(cache_read_bool "$FIX/vuln.json" '.changelog.breaking' true)"         "true"
# MISSING fields resolve to the SAFE value — the live bug #9 fixes (pre-#9 these
# defaulted PERMISSIVE: osv.clear→"true", scorecard.pass→"true", breaking→"false").
eq "missing osv.clear -> SAFE false"        "$(cache_read_bool "$FIX/missing_fields.json" '.osv.clear' false)"       "false"
eq "missing scorecard.pass -> SAFE false"   "$(cache_read_bool "$FIX/missing_fields.json" '.scorecard.pass' false)"  "false"
eq "missing changelog.breaking -> SAFE true" "$(cache_read_bool "$FIX/missing_fields.json" '.changelog.breaking' true)" "true"
# TYPE STRICTNESS: a quoted "true"/"false" STRING is NOT a boolean → SAFE. `jq -r`
# renders string "true" and boolean true identically, so without a type check a
# poisoned {"clear":"true"} string would read as clear. Must route to SAFE.
eq "string osv.clear='true' -> SAFE false"       "$(cache_read_bool "$FIX/string_booleans.json" '.osv.clear' false)"       "false"
eq "string scorecard.pass='false' -> SAFE false" "$(cache_read_bool "$FIX/string_booleans.json" '.scorecard.pass' false)"  "false"
eq "string changelog.breaking='false' -> SAFE true" "$(cache_read_bool "$FIX/string_booleans.json" '.changelog.breaking' true)" "true"

echo "ALL TESTS PASSED"
