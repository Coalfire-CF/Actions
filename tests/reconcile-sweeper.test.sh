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
  # Optional transient-failure simulation: fail the FIRST pr-view call, then
  # succeed — exercises gh_read's retry path end-to-end (F2 regression).
  if [ "${MOCK_FAIL_ALL:-0}" = "1" ]; then
    echo "gh: API rate limit exceeded (mock persistent)" >&2; exit 1
  fi
  if [ "${MOCK_FAIL_FIRST:-0}" = "1" ]; then
    n=0; [ -f "$MOCK_VIEW_COUNT" ] && n="$(cat "$MOCK_VIEW_COUNT")"
    n=$((n + 1)); printf '%s' "$n" > "$MOCK_VIEW_COUNT"
    if [ "$n" -eq 1 ]; then echo "gh: API rate limit exceeded (mock transient)" >&2; exit 1; fi
  fi
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

# run_helper <json> <dry_run> <reject_writes> [fail_first] -> sets globals
# OUT, LAST_RC, TRACE. NOT run under command substitution (that would subshell
# away LAST_RC/TRACE). RETRY_MAX=2 keeps the one retry-path case fast (~1s sleep).
OUT=""; LAST_RC=0; TRACE=""
run_helper() {
  local json="$1" dry="$2" reject="$3" fail_first="${4:-0}" fail_all="${5:-0}"
  : "$fail_all"  # consumed via ${5:-0} in the env line below
  printf '%s' "$json" > "$WORK/pr.json"
  : > "$WORK/trace"; : > "$WORK/viewcount"
  PATH="$BIN:$PATH" GH_TRACE="$WORK/trace" MOCK_PR_JSON="$WORK/pr.json" \
      MOCK_REJECT_WRITES="$reject" MOCK_FAIL_FIRST="$fail_first" MOCK_FAIL_ALL="${5:-0}" MOCK_VIEW_COUNT="$WORK/viewcount" \
    PR_NUMBER=123 REPO="Coalfire-CF/some-repo" MERGE_METHOD=squash DRY_RUN="$dry" RETRY_MAX=2 \
    bash "$HELPER" > "$WORK/out" 2>/dev/null
  LAST_RC=$?
  OUT="$(cat "$WORK/out")"
  TRACE="$(cat "$WORK/trace")"
}

# Scenarios carry author (gh --json reports Dependabot as app/dependabot) and
# reviewDecision (null = repo requires no reviews = the wedged case).
AUTH='"author":{"login":"app/dependabot"},"reviewDecision":null'
GREEN="{\"state\":\"OPEN\",\"isDraft\":false,${AUTH},\"statusCheckRollup\":[{\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\"}]}"
NOCHECKS="{\"state\":\"OPEN\",\"isDraft\":false,${AUTH},\"statusCheckRollup\":[]}"
REDJSON="{\"state\":\"OPEN\",\"isDraft\":false,${AUTH},\"statusCheckRollup\":[{\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\"}]}"
PENDJSON="{\"state\":\"OPEN\",\"isDraft\":false,${AUTH},\"statusCheckRollup\":[{\"status\":\"IN_PROGRESS\",\"conclusion\":null}]}"
DRAFTJSON="{\"state\":\"OPEN\",\"isDraft\":true,${AUTH},\"statusCheckRollup\":[]}"
CLOSEDJSON="{\"state\":\"MERGED\",\"isDraft\":false,${AUTH},\"statusCheckRollup\":[]}"
# F3 hardening scenarios: non-automation author, and an unmet required review.
HUMANJSON='{"state":"OPEN","isDraft":false,"author":{"login":"mallory"},"reviewDecision":null,"statusCheckRollup":[]}'
REVREQJSON='{"state":"OPEN","isDraft":false,"author":{"login":"app/dependabot"},"reviewDecision":"REVIEW_REQUIRED","statusCheckRollup":[]}'

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

# ---- Case 5 (F2 regression): a transient pr-view failure on attempt 1 then a
#      success on attempt 2 must still reach WOULD-MERGE — proves the retry log
#      goes to stderr (not into the captured JSON) and gh_read really retries. ----
run_helper "$GREEN" true 0 1
[ "$LAST_RC" -eq 0 ] || fail "retry path should exit 0 (got $LAST_RC)"
echo "$OUT" | grep -q "WOULD-MERGE #123" || fail "retry path should still WOULD-MERGE (got: $OUT)"
[ "$(echo "$TRACE" | grep -cE 'pr view')" -eq 2 ] || fail "retry path should issue exactly two 'gh pr view' calls"
echo "OK: transient-then-success retry → WOULD-MERGE (log on stderr, JSON uncontaminated)"

# ---- Case 6 (F3): a non-automation author is NEVER swept (even green + live). ----
run_helper "$HUMANJSON" false 0
[ "$LAST_RC" -eq 0 ] || fail "human-authored should exit 0 (skip, got $LAST_RC)"
echo "$OUT" | grep -q "SKIP #123 (author-not-allowlisted)" || fail "human-authored should SKIP author-not-allowlisted (got: $OUT)"
echo "$TRACE" | grep -qE "$WRITE_VERBS_RE" && fail "human-authored issued a WRITE verb but must never merge"
echo "OK: non-automation author → SKIP (author-not-allowlisted)"

# ---- Case 7 (F3): an unmet required review is NEVER swept. ----
run_helper "$REVREQJSON" false 0
[ "$LAST_RC" -eq 0 ] || fail "review-required should exit 0 (skip, got $LAST_RC)"
echo "$OUT" | grep -q "SKIP #123 (review-REVIEW_REQUIRED)" || fail "review-required should SKIP (got: $OUT)"
echo "$TRACE" | grep -qE "$WRITE_VERBS_RE" && fail "review-required issued a WRITE verb but must never merge"
echo "OK: reviewDecision=REVIEW_REQUIRED → SKIP (no merge)"

# ---- Case 8 (F1 regression): pr-view fails on EVERY attempt → gh_read must
#      return non-zero so the caller reaches the pr-view-unavailable fail-closed
#      SKIP (before the fix gh_read returned 0 and that branch was dead code). ----
run_helper "$GREEN" false 0 0 1
echo "$OUT" | grep -q "SKIP #123 (pr-view-unavailable)" || fail "persistent read failure should hit pr-view-unavailable SKIP (got: $OUT)"
echo "$TRACE" | grep -qE "$WRITE_VERBS_RE" && fail "persistent read failure issued a WRITE verb but must never merge"
echo "OK: persistent pr-view failure → SKIP (pr-view-unavailable), fail-closed branch reachable"

echo "ALL TESTS PASSED"
