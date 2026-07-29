#!/usr/bin/env bash
#
# Meta-test for the if:always() NAT Elastic IP sweep step in
# .github/workflows/org-terratest.yml (#273 / WI-1.3).
#
# The sweep logic lives INLINE in the workflow's `run:` body (not a scripts/*.sh)
# on purpose: a reusable workflow cannot reliably fetch its own repo's helper
# scripts at the calling ref — github.job_workflow_sha is empty for cross-repo
# reusable-workflow calls (see the workflow header), so github.sha would resolve
# to the CALLER's commit and 404. The inline block is therefore the testable
# safety surface. This test EXTRACTS that block from the YAML (so the test can
# never drift from what actually ships) and drives it through a MOCK `aws` shim
# placed first on PATH, which serves canned describe-* JSON and records every
# release-address call.
#
# Every assertion is mutation-proven: for each safety property we also run the
# scenario that SHOULD trip it and confirm the outcome flips. A check that passes
# no matter what the sweep does is worse than no check (CLAUDE.md silent-green).
#
# Invariants covered:
#   1. Positive control: describe-regions returning 0 is a HARD FAIL, not a clean
#      sweep (an empty enumeration must never read as "found 0 problems").
#   2. Clean case: an unassociated address tagged THIS RunId is released; exit 0.
#   3. Idempotent: release-address returning InvalidAllocationID.NotFound = success.
#   4. Still-associated tagged address = incomplete teardown = HARD FAIL, and the
#      doomed release-address call is NOT attempted.
#   5. Real release failure (AccessDenied, e.g. missing ec2:ReleaseAddress) = HARD FAIL.
#   6. Scoping: an unassociated orphan tagged a DIFFERENT RunId is left untouched.
#   7. Inverted sanity: terratest !success + 0 matches → warns (does not silently
#      report clean), but does not itself fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WF="${REPO_ROOT}/.github/workflows/org-terratest.yml"

fail() { echo "NOT OK: $1"; exit 1; }
[ -f "$WF" ] || fail "workflow not found at $WF"
command -v jq   >/dev/null || fail "jq is required"
command -v ruby >/dev/null || fail "ruby is required (YAML extraction)"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"

# ---- Extract the inline sweep script from the YAML, verbatim. -----------------
SWEEP="$WORK/sweep.sh"
ruby -ryaml -e '
  d = YAML.load_file(ARGV[0])
  job = d.fetch("jobs").fetch("nat-eip-sweep")
  step = job.fetch("steps").find { |s| s["name"] == "Sweep NAT EIPs belonging to this run" }
  abort "sweep step not found" unless step
  print step.fetch("run")
' "$WF" > "$SWEEP" || fail "could not extract sweep step from $WF"
[ -s "$SWEEP" ] || fail "extracted sweep script is empty"

# ---- Mock aws: serves describe-regions / describe-addresses from env-pointed
#      JSON files, records release-address allocation IDs to $AWS_TRACE, and
#      returns a configurable error string for a given allocation. ----
cat > "$BIN/aws" <<'MOCK'
#!/usr/bin/env bash
svc="$1"; cmd="$2"; shift 2
case "$svc $cmd" in
  "sts get-caller-identity")
    echo '{"Arn":"arn:aws-us-gov:sts::358745275192:assumed-role/github-action-test-role/x"}' ;;
  "ec2 describe-regions")
    cat "$MOCK_REGIONS_JSON" ;;
  "ec2 describe-addresses")
    cat "$MOCK_ADDRESSES_JSON" ;;
  "ec2 release-address")
    # parse --allocation-id <id>
    alloc=""
    while [ $# -gt 0 ]; do [ "$1" = "--allocation-id" ] && { alloc="$2"; shift 2; continue; }; shift; done
    printf '%s\n' "$alloc" >> "$AWS_TRACE"
    if [ -n "${MOCK_RELEASE_ERR:-}" ]; then echo "$MOCK_RELEASE_ERR" >&2; exit 1; fi
    ;;
  *) echo "mock aws: unhandled '$svc $cmd'" >&2; exit 2 ;;
esac
MOCK
chmod +x "$BIN/aws"

REGIONS_OK="$WORK/regions_ok.json";   echo '{"Regions":[{"RegionName":"us-gov-west-1"}]}' > "$REGIONS_OK"
REGIONS_EMPTY="$WORK/regions_empty.json"; echo '{"Regions":[]}' > "$REGIONS_EMPTY"

# Build an addresses JSON: $1=AllocationId $2=RunId-tag-value $3=AssociationId(or "null")
addr() {
  local id="$1" rid="$2" assoc="$3"
  local a='null'; [ "$assoc" != "null" ] && a="\"$assoc\""
  printf '{"AllocationId":"%s","PublicIp":"1.2.3.4","AssociationId":%s,"Tags":[{"Key":"RunId","Value":"%s"}]}' "$id" "$a" "$rid"
}
addrs_json() { printf '{"Addresses":[%s]}' "$1" > "$2"; }

RID="1000-1"  # matches env RUN_ID we pass in

# run_sweep <summary> <regions_json> <addresses_json> <terratest_result>
#   sets globals: RC, OUT (stdout+stderr), TRACE (released allocation ids)
run_sweep() {
  local regions="$2" addrs="$3" result="$4"
  local trace="$WORK/trace.$$"; : > "$trace"
  local summary="$WORK/summary.$$"; : > "$summary"
  set +e
  OUT="$(
    PATH="$BIN:$PATH" \
    MOCK_REGIONS_JSON="$regions" MOCK_ADDRESSES_JSON="$addrs" \
    MOCK_RELEASE_ERR="${MOCK_RELEASE_ERR:-}" \
    AWS_TRACE="$trace" \
    RUN_ID="$RID" TERRATEST_RESULT="$result" AWS_REGION="us-gov-west-1" \
    GITHUB_STEP_SUMMARY="$summary" \
    bash "$SWEEP" 2>&1
  )"
  RC=$?
  set -e
  TRACE="$(cat "$trace")"
}

echo "== 1. positive control: 0 regions is a hard fail (not clean) =="
addrs_json "" "$WORK/a.json"
MOCK_RELEASE_ERR="" run_sweep "" "$REGIONS_EMPTY" "$WORK/a.json" "success"
[ "$RC" -ne 0 ] || fail "1: empty describe-regions must FAIL, got exit 0 (silent-green)"
echo "$OUT" | grep -q "control failed" || fail "1: expected control-failed error"
# mutation: same input but a WORKING control (1 region) and no addresses → clean pass
MOCK_RELEASE_ERR="" run_sweep "" "$REGIONS_OK" "$WORK/a.json" "success"
[ "$RC" -eq 0 ] || fail "1(mut): working control + 0 tagged addresses should pass, got $RC"

echo "== 2. clean case: unassociated + my RunId is released, exit 0 =="
addrs_json "$(addr alloc-mine "$RID" null)" "$WORK/b.json"
MOCK_RELEASE_ERR="" run_sweep "" "$REGIONS_OK" "$WORK/b.json" "success"
[ "$RC" -eq 0 ] || fail "2: clean release should exit 0, got $RC"
[ "$TRACE" = "alloc-mine" ] || fail "2: expected release of alloc-mine, trace='$TRACE'"

echo "== 3. idempotent: NotFound counts as success =="
addrs_json "$(addr alloc-gone "$RID" null)" "$WORK/c.json"
MOCK_RELEASE_ERR="An error occurred (InvalidAllocationID.NotFound) when calling ReleaseAddress" \
  run_sweep "" "$REGIONS_OK" "$WORK/c.json" "success"
[ "$RC" -eq 0 ] || fail "3: InvalidAllocationID.NotFound must be success, got $RC"
echo "$OUT" | grep -q "already released" || fail "3: expected 'already released' note"

echo "== 4. still-associated = incomplete teardown = hard fail, NO release attempted =="
addrs_json "$(addr alloc-assoc "$RID" eipassoc-123)" "$WORK/d.json"
MOCK_RELEASE_ERR="" run_sweep "" "$REGIONS_OK" "$WORK/d.json" "failure"
[ "$RC" -ne 0 ] || fail "4: associated address must FAIL, got exit 0"
echo "$OUT" | grep -q "Incomplete teardown" || fail "4: expected incomplete-teardown error"
[ -z "$TRACE" ] || fail "4: must NOT attempt release on an associated address, trace='$TRACE'"

echo "== 5. real release failure (AccessDenied / missing ec2:ReleaseAddress) = hard fail =="
addrs_json "$(addr alloc-denied "$RID" null)" "$WORK/e.json"
MOCK_RELEASE_ERR="An error occurred (UnauthorizedOperation) when calling ReleaseAddress" \
  run_sweep "" "$REGIONS_OK" "$WORK/e.json" "success"
[ "$RC" -ne 0 ] || fail "5: a denied release must FAIL, got exit 0 (silent-green)"
echo "$OUT" | grep -q "release failed" || fail "5: expected release-failed error"

echo "== 6. scoping: an orphan tagged a DIFFERENT RunId is left untouched =="
addrs_json "$(addr alloc-other 9999-9 null)" "$WORK/f.json"
MOCK_RELEASE_ERR="" run_sweep "" "$REGIONS_OK" "$WORK/f.json" "success"
[ "$RC" -eq 0 ] || fail "6: unrelated orphan should not fail us, got $RC"
[ -z "$TRACE" ] || fail "6: must NOT touch an address tagged another run, trace='$TRACE'"

echo "== 7. inverted sanity: terratest failed + 0 matches → warn, not silent-clean =="
addrs_json "" "$WORK/g.json"
MOCK_RELEASE_ERR="" run_sweep "" "$REGIONS_OK" "$WORK/g.json" "failure"
[ "$RC" -eq 0 ] || fail "7: 0-match warn path should not itself fail, got $RC"
echo "$OUT" | grep -q "selector may be broken" || fail "7: expected selector-may-be-broken warning"
# mutation: terratest SUCCESS + 0 matches is the normal clean case → NO warning
MOCK_RELEASE_ERR="" run_sweep "" "$REGIONS_OK" "$WORK/g.json" "success"
echo "$OUT" | grep -q "selector may be broken" && fail "7(mut): must NOT warn on the clean success+0 case"

echo "OK: nat-eip-sweep.test.sh — all invariants held and mutation-proven"
