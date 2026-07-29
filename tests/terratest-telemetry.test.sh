#!/usr/bin/env bash
#
# Meta-test for the "Emit telemetry record" step in
# .github/workflows/org-terratest.yml (#235 / WI-2.2).
#
# Like the sweep test, the emit logic lives INLINE in the workflow run: body, so
# this test EXTRACTS it from the YAML (it can never drift from what ships) and
# runs it directly with a temp GITHUB_WORKSPACE and canned JUnit XML. Every
# assertion is mutation-proven: we feed the input that SHOULD flip the outcome
# and confirm it does.
#
# Invariants:
#   1. Green XML + exit 0 → result=pass, counts computed (passed = tests-fail-err-skip).
#   2. Failing XML + non-zero exit → result=fail, counts reflect failures.
#   3. result is derived from the EXIT CODE, not the XML: a green-looking XML with a
#      non-zero exit still records result=fail (silent-green guard).
#   4. Killed run (no XML at all) → still emits a record, have_report=false,
#      counts=null, keyed by the commit SHA (the run does not vanish).
#   5. The record is valid JSON, schema-tagged, and keyed by the commit SHA.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WF="${REPO_ROOT}/.github/workflows/org-terratest.yml"

fail() { echo "NOT OK: $1"; exit 1; }
[ -f "$WF" ] || fail "workflow not found at $WF"
command -v jq   >/dev/null || fail "jq is required"
command -v ruby >/dev/null || fail "ruby is required (YAML extraction)"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

EMIT="$WORK/emit.sh"
ruby -ryaml -e '
  d = YAML.load_file(ARGV[0])
  step = d.fetch("jobs").fetch("terratest").fetch("steps").find { |s| s["name"] == "Emit telemetry record" }
  abort "emit step not found" unless step
  print step.fetch("run")
' "$WF" > "$EMIT" || fail "could not extract emit step"
[ -s "$EMIT" ] || fail "extracted emit script is empty"

SHA="abc123def4567890abc123def4567890abc123de"

# run_emit <xml-or-empty> <exit_code> ; sets RC, and RECORD (path to record json)
run_emit() {
  local xml="$1" exit_code="$2"
  local ws="$WORK/ws.$RANDOM"; mkdir -p "$ws"
  if [ -n "$xml" ]; then printf '%s' "$xml" > "$ws/terratest-results.xml"; fi
  set +e
  OUT="$(
    GITHUB_WORKSPACE="$ws" \
    RESULT_SHA="$SHA" RUN_REPO="Coalfire-CF/terraform-aws-demo" RUN_ID="42" RUN_ATTEMPT="1" \
    RUN_URL="https://github.com/Coalfire-CF/terraform-aws-demo/actions/runs/42" \
    TEST_MODE="pr" TEST_DIR="test" TF_VERSION="1.15.7" GO_VERSION="1.26" \
    EXIT_CODE="$exit_code" \
    bash "$EMIT" 2>&1
  )"
  RC=$?
  set -e
  RECORD="$ws/terratest-record.json"
}

XML_PASS='<testsuites tests="5" failures="0" errors="0" time="12.5"><testsuite skipped="1"></testsuite></testsuites>'
XML_FAIL='<testsuites tests="5" failures="2" errors="1" time="30.0"><testsuite skipped="0"></testsuite></testsuites>'

echo "== 1. green XML + exit 0 → pass, counts correct =="
run_emit "$XML_PASS" "0"
[ "$RC" -eq 0 ] || fail "1: emit should succeed, got $RC ($OUT)"
[ "$(jq -r .result "$RECORD")" = "pass" ] || fail "1: result should be pass"
[ "$(jq -r .counts.passed "$RECORD")" = "4" ] || fail "1: passed should be 5-0-0-1=4, got $(jq -r .counts.passed "$RECORD")"
[ "$(jq -r .counts.skipped "$RECORD")" = "1" ] || fail "1: skipped should be 1"
[ "$(jq -r .duration_seconds "$RECORD")" = "12.5" ] || fail "1: duration should be 12.5"

echo "== 2. failing XML + non-zero exit → fail, counts reflect failures =="
run_emit "$XML_FAIL" "1"
[ "$RC" -eq 0 ] || fail "2: emit itself should still succeed, got $RC"
[ "$(jq -r .result "$RECORD")" = "fail" ] || fail "2: result should be fail"
[ "$(jq -r .counts.failures "$RECORD")" = "2" ] || fail "2: failures should be 2"
[ "$(jq -r .counts.passed "$RECORD")" = "2" ] || fail "2: passed should be 5-2-1-0=2"

echo "== 3. result derives from EXIT CODE, not XML (silent-green guard) =="
run_emit "$XML_PASS" "1"   # green-looking XML but the gate exit was non-zero
[ "$(jq -r .result "$RECORD")" = "fail" ] || fail "3: a green XML with non-zero exit must record fail"

echo "== 4. killed run (no XML) still emits a record, have_report=false, counts=null =="
run_emit "" "1"
[ "$RC" -eq 0 ] || fail "4: emit should succeed even with no XML, got $RC ($OUT)"
[ "$(jq -r .have_report "$RECORD")" = "false" ] || fail "4: have_report should be false"
[ "$(jq -r '.counts == null' "$RECORD")" = "true" ] || fail "4: counts should be null with no report"
[ "$(jq -r .commit_sha "$RECORD")" = "$SHA" ] || fail "4: record must still be keyed by the commit SHA"
[ "$(jq -r .result "$RECORD")" = "fail" ] || fail "4: no-XML + non-zero exit is a fail"

echo "== 5. record is valid, schema-tagged, SHA-keyed JSON =="
run_emit "$XML_PASS" "0"
jq -e 'type=="object"' "$RECORD" >/dev/null || fail "5: not a JSON object"
[ "$(jq -r .schema "$RECORD")" = "terratest-posture/v1" ] || fail "5: schema tag missing"
[ "$(jq -r .commit_sha "$RECORD")" = "$SHA" ] || fail "5: not keyed by commit SHA"
[ "$(jq -r .repo "$RECORD")" = "Coalfire-CF/terraform-aws-demo" ] || fail "5: repo missing"

echo "OK: terratest-telemetry.test.sh — record emission correct and mutation-proven"
