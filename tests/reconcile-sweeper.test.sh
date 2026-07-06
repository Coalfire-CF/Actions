#!/usr/bin/env bash
#
# Meta-test for the reconcile sweeper's per-PR green-gate/merge helper
# scripts/pr-green-merge.sh (grade-A plan #14).
#
# The sweep workflow (.github/workflows/org-dependabot-reconcile.yml) is a thin
# loop over `gh search` that delegates every merge decision to this helper, so
# the helper IS the testable safety surface. We drive it through a MOCK `gh`
# shim placed first on PATH that (a) records every invocation and (b) can REJECT
# any write verb — proving the dry-run path issues ZERO mutating calls, and that
# red / pending / draft / closed PRs are never merged.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HELPER="${REPO_ROOT}/scripts/pr-green-merge.sh"

fail() { echo "NOT OK: $1"; exit 1; }
[ -f "$HELPER" ] || fail "helper not found at $HELPER"
[ -x "$HELPER" ] || chmod +x "$HELPER"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"

# ---- Mock gh: records argv to $GH_TRACE; serves pr view JSON from $MOCK_PR_JSON;
#      rejects write verbs (pr merge/review/...) when $MOCK_REJECT_WRITES=1. ----
cat > "$BIN/gh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_TRACE"
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  cat "$MOCK_PR_JSON"; exit 0
fi
# Any write verb (merge/review/edit/close/comment/ready/...):
if [ "$1" = "pr" ] && printf '%s' " merge review edit close comment ready " | grep -q " $2 "; then
  if [ "${MOCK_REJECT_WRITES:-0}" = "1" ]; then
    echo "MOCK: write verb 'gh pr $2' rejected (dry-run must not mutate)" >&2
    exit 1
  fi
  exit 0
fi
exit 0
MOCK
chmod +x "$BIN/gh"

WRITE_VERBS_RE='pr (merge|review|edit|close|comment|ready)'

# run_helper <json> <dry_run> <reject_writes> -> sets globals OUT, LAST_RC, TRACE.
# NOT run under command substitution (that would subshell away LAST_RC/TRACE).
OUT=""; LAST_RC=0; TRACE=""
run_helper() {
  local json="$1" dry="$2" reject="$3"
  printf '%s' "$json" > "$WORK/pr.json"
  : > "$WORK/trace"
  PATH="$BIN:$PATH" GH_TRACE="$WORK/trace" MOCK_PR_JSON="$WORK/pr.json" \
    MOCK_REJECT_WRITES="$reject" \
    PR_NUMBER=123 REPO="Coalfire-CF/some-repo" MERGE_METHOD=squash DRY_RUN="$dry" RETRY_MAX=2 \
    bash "$HELPER" > "$WORK/out" 2>/dev/null
  LAST_RC=$?
  OUT="$(cat "$WORK/out")"
  TRACE="$(cat "$WORK/trace")"
}

GREEN='{"state":"OPEN","isDraft":false,"statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}]}'
NOCHECKS='{"state":"OPEN","isDraft":false,"statusCheckRollup":[]}'
REDJSON='{"state":"OPEN","isDraft":false,"statusCheckRollup":[{"status":"COMPLETED","conclusion":"FAILURE"}]}'
PENDJSON='{"state":"OPEN","isDraft":false,"statusCheckRollup":[{"status":"IN_PROGRESS","conclusion":null}]}'
DRAFTJSON='{"state":"OPEN","isDraft":true,"statusCheckRollup":[]}'
CLOSEDJSON='{"state":"MERGED","isDraft":false,"statusCheckRollup":[]}'

# ---- Case 1 (the AC expected-FAIL guard): GREEN + dry-run → WOULD-MERGE, and
#      the recorded trace contains ZERO write verbs (mock also set to reject). ----
run_helper "$GREEN" true 1
[ "$LAST_RC" -eq 0 ] || fail "dry-run GREEN should exit 0 (got $LAST_RC)"
echo "$OUT" | grep -q "WOULD-MERGE #123" || fail "dry-run GREEN should say WOULD-MERGE (got: $OUT)"
echo "$TRACE" | grep -qE "$WRITE_VERBS_RE" && fail "dry-run issued a WRITE verb: $(echo "$TRACE" | grep -E "$WRITE_VERBS_RE")"
echo "OK: dry-run GREEN → WOULD-MERGE, zero mutating calls (trace clean)"

# ---- Case 2: GREEN + live → MERGED, and exactly one `gh pr merge` recorded. ----
run_helper "$GREEN" false 0
[ "$LAST_RC" -eq 0 ] || fail "live GREEN should exit 0 (got $LAST_RC)"
echo "$OUT" | grep -q "MERGED #123" || fail "live GREEN should MERGE (got: $OUT)"
[ "$(echo "$TRACE" | grep -cE 'pr merge')" -eq 1 ] || fail "live GREEN must issue exactly one 'gh pr merge'"
echo "OK: live GREEN → MERGED, exactly one merge call"

# ---- Case 3: no-checks (wedged clean PR) + live → MERGED. ----
run_helper "$NOCHECKS" false 0
echo "$OUT" | grep -q "MERGED #123" || fail "live no-checks (wedged) should MERGE (got: $OUT)"
echo "OK: live no-checks (wedged) → MERGED"

# ---- Case 4: red / pending / draft / closed are NEVER merged (even live). ----
for scn in "RED:$REDJSON:checks-FAIL" "PENDING:$PENDJSON:checks-PENDING" \
           "DRAFT:$DRAFTJSON:draft=true" "CLOSED:$CLOSEDJSON:state=MERGED"; do
  name="${scn%%:*}"; rest="${scn#*:}"; json="${rest%:*}"; want="${rest##*:}"
  run_helper "$json" false 0
  [ "$LAST_RC" -eq 0 ] || fail "$name should exit 0 (skip, got $LAST_RC)"
  echo "$OUT" | grep -q "SKIP #123" || fail "$name should SKIP (got: $OUT)"
  echo "$TRACE" | grep -qE "$WRITE_VERBS_RE" && fail "$name issued a WRITE verb but must never merge"
  echo "OK: ${name} → SKIP (no merge)  [${want}]"
done

echo "ALL TESTS PASSED"
