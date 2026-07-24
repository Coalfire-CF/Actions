#!/usr/bin/env bash
#
# Characterization meta-test for scripts/auto-merge-decide.sh (grade-A plan #10).
#
# This is a CHARACTERIZATION test: it pins the decision + label baseline the
# auto-merge decide gate produces TODAY, so the extraction from the inline
# heredoc (and any later change, e.g. the #12 label-wiring pass) is regression
# guarded. The gate is pure bash — it reads the upstream jobs' outputs from the
# environment and reduces them to (decision, risk_level, blocked_labels); no
# network / AWS is involved, so it runs fully offline.
#
# Each fixture under tests/fixtures/auto-merge-decide/*.env sets the complete
# input environment for one of the four decision paths and is asserted against
# the exact decision AND blocked_labels the gate emits:
#   major_blocked       -> block   / " blocked/major-bump"
#   osv_blocked         -> block   / " blocked/known-vuln"
#   parse_error_manual  -> manual  / ""            (fail-closed, no blocker)
#   first_party_waiver  -> approve / ""            (Scorecard waived, RFC-0010)
#
# NOTE on blocked/major-bump: both the group-aware UPDATE_TYPE_META gate and the
# aggregate SEMVER_TYPE=major gate detect a major bump, but the gate dedupes
# BLOCKED_LABELS before emitting, so the label appears exactly once (issue #207).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DECIDE="${REPO_ROOT}/scripts/auto-merge-decide.sh"
FIXTURES="${SCRIPT_DIR}/fixtures/auto-merge-decide"

fail() { echo "NOT OK: $1"; exit 1; }

[ -f "$DECIDE" ] || fail "decide script not found at $DECIDE"
[ -x "$DECIDE" ] || chmod +x "$DECIDE"

# run_fixture <fixture.env> — source the fixture env, run the decide gate with
# GITHUB_OUTPUT/GITHUB_STEP_SUMMARY pointed at temp files, print the raw output
# file. Runs in a subshell so each fixture's env is isolated.
run_fixture() {
  local fx="$1" out summ
  out="$(mktemp)"; summ="$(mktemp)"
  (
    set -a
    # shellcheck disable=SC1090
    . "${FIXTURES}/${fx}.env"
    set +a
    GITHUB_OUTPUT="$out" GITHUB_STEP_SUMMARY="$summ" bash "$DECIDE" >/dev/null 2>&1
  ) || { rm -f "$out" "$summ"; fail "${fx}: decide script exited non-zero"; }
  cat "$out"
  rm -f "$out" "$summ"
}

getval() { sed -n "s/^$1=//p" <<< "$2" | head -1; }

# <fixture> <want_decision> <want_blocked_labels> <want_risk>
assert_path() {
  local fx="$1" wd="$2" wbl="$3" wr="$4" raw d bl r
  raw="$(run_fixture "$fx")"
  d="$(getval decision "$raw")"
  bl="$(getval blocked_labels "$raw")"
  r="$(getval risk_level "$raw")"
  [ "$d" = "$wd" ]   || fail "${fx}: decision '${d}' != expected '${wd}'"
  [ "$bl" = "$wbl" ] || fail "${fx}: blocked_labels '${bl}' != expected '${wbl}'"
  [ "$r" = "$wr" ]   || fail "${fx}: risk_level '${r}' != expected '${wr}'"
  echo "OK: ${fx} -> decision=${d} risk=${r} blocked_labels='${bl}'"
}

# ---- The four characterized decision paths (expected-PASS) ----
assert_path major_blocked      block   " blocked/major-bump"                    high
assert_path osv_blocked        block   " blocked/known-vuln"                    high
assert_path parse_error_manual manual  ""                                       high
assert_path first_party_waiver approve ""                                       medium

# ---- Sentinel (expected-FAIL guard): a semver-major bump must NEVER approve ----
# If a future edit wrongly cleared the major gate to merge/approved, this fires.
major_decision="$(getval decision "$(run_fixture major_blocked)")"
[ "$major_decision" != "approve" ] \
  || fail "SENTINEL: semver-major fixture cleared to 'approve' — the major gate no longer fires!"
echo "OK: sentinel — semver-major never approves (decision=${major_decision})"

echo "ALL TESTS PASSED"
