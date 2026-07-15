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
#
# The helper reads in TWO calls: `gh pr view --json …,headRefOid` (PR metadata,
# no statusCheckRollup — that would need statuses:read) then
# `gh api …/commits/<sha>/check-runs` (CI state, checks:read). The merge itself
# is the REST endpoint `gh api --method PUT …/pulls/N/merge` (NOT `gh pr merge`,
# which cannot exercise ruleset bypass). BYPASS_REVIEW=true merges past an unmet
# required review (the caller is a ruleset bypass actor) but never past an
# explicit CHANGES_REQUESTED.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HELPER="${REPO_ROOT}/scripts/pr-green-merge.sh"

fail() { echo "NOT OK: $1"; exit 1; }
[ -f "$HELPER" ] || fail "helper not found at $HELPER"
[ -x "$HELPER" ] || chmod +x "$HELPER"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"

# ---- Mock gh: records argv to $GH_TRACE; serves `pr view` JSON from
#      $MOCK_PR_JSON and `api …/check-runs` JSON from $MOCK_CHECKS_JSON; performs
#      the REST merge (…/pulls/N/merge); rejects write verbs when
#      $MOCK_REJECT_WRITES=1. Optional pr-view transient/persistent failure sims. ----
cat > "$BIN/gh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_TRACE"
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
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
# Green-gate read: REST check-runs for the head SHA (checks:read).
if [ "$1" = "api" ] && printf '%s' "$*" | grep -q 'check-runs'; then
  if [ "${MOCK_CHECKS_FAIL:-0}" = "1" ]; then
    echo "gh: Resource not accessible by integration (mock)" >&2; exit 1
  fi
  cat "$MOCK_CHECKS_JSON"; exit 0
fi
# The REAL merge path: REST endpoint via `gh api --method PUT .../pulls/N/merge`
# (NOT `gh pr merge`, which cannot exercise ruleset bypass). Treated as a write.
if [ "$1" = "api" ] && printf '%s' "$*" | grep -qE 'pulls/[0-9]+/merge'; then
  if [ "${MOCK_REJECT_WRITES:-0}" = "1" ]; then
    echo "MOCK: REST merge rejected (dry-run must not mutate)" >&2
    exit 1
  fi
  echo '{"merged":true,"message":"Pull Request successfully merged"}'; exit 0
fi
# Any pr write verb (review/edit/close/comment/ready/... and legacy merge):
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

# A write is either a legacy `gh pr <verb>` OR the REST merge (…/pulls/N/merge).
WRITE_VERBS_RE='pr (merge|review|edit|close|comment|ready)|pulls/[0-9]+/merge'

# run_helper <pr_view_json> <checks_json> <dry_run> <reject_writes> [fail_first]
#   [fail_all] -> sets globals OUT, LAST_RC, TRACE. NOT run under command
# substitution (that would subshell away LAST_RC/TRACE). RETRY_MAX=2 keeps the
# retry-path cases fast. BYPASS_REVIEW is passed from ${BR:-false} so a caller can
# prefix `BR=true run_helper …`.
OUT=""; LAST_RC=0; TRACE=""
run_helper() {
  local pv="$1" checks="$2" dry="$3" reject="$4" fail_first="${5:-0}" fail_all="${6:-0}"
  printf '%s' "$pv" > "$WORK/pr.json"
  printf '%s' "$checks" > "$WORK/checks.json"
  : > "$WORK/trace"; : > "$WORK/viewcount"
  PATH="$BIN:$PATH" GH_TRACE="$WORK/trace" MOCK_PR_JSON="$WORK/pr.json" MOCK_CHECKS_JSON="$WORK/checks.json" \
      MOCK_REJECT_WRITES="$reject" MOCK_FAIL_FIRST="$fail_first" MOCK_FAIL_ALL="$fail_all" MOCK_CHECKS_FAIL="${CF:-0}" MOCK_VIEW_COUNT="$WORK/viewcount" \
    PR_NUMBER=123 REPO="Coalfire-CF/some-repo" MERGE_METHOD=squash DRY_RUN="$dry" BYPASS_REVIEW="${BR:-false}" RETRY_MAX=2 \
    bash "$HELPER" > "$WORK/out" 2>/dev/null
  LAST_RC=$?
  OUT="$(cat "$WORK/out")"
  TRACE="$(cat "$WORK/trace")"
}

# ---- PR-view metadata fixtures (author: gh --json reports Dependabot as
#      app/dependabot; reviewDecision null = repo requires no reviews). ----
SHA="deadbeefcafe"
AUTH="\"author\":{\"login\":\"app/dependabot\"},\"reviewDecision\":null"
PV_OPEN="{\"state\":\"OPEN\",\"isDraft\":false,${AUTH},\"headRefOid\":\"${SHA}\"}"
PV_DRAFT="{\"state\":\"OPEN\",\"isDraft\":true,${AUTH},\"headRefOid\":\"${SHA}\"}"
PV_CLOSED="{\"state\":\"MERGED\",\"isDraft\":false,${AUTH},\"headRefOid\":\"${SHA}\"}"
PV_HUMAN="{\"state\":\"OPEN\",\"isDraft\":false,\"author\":{\"login\":\"mallory\"},\"reviewDecision\":null,\"headRefOid\":\"${SHA}\"}"
PV_REVREQ="{\"state\":\"OPEN\",\"isDraft\":false,\"author\":{\"login\":\"app/dependabot\"},\"reviewDecision\":\"REVIEW_REQUIRED\",\"headRefOid\":\"${SHA}\"}"
PV_CHREQ="{\"state\":\"OPEN\",\"isDraft\":false,\"author\":{\"login\":\"app/dependabot\"},\"reviewDecision\":\"CHANGES_REQUESTED\",\"headRefOid\":\"${SHA}\"}"

# ---- check-runs fixtures (REST /commits/{sha}/check-runs shape). ----
CK_GREEN='{"check_runs":[{"status":"completed","conclusion":"success"}]}'
CK_EMPTY='{"check_runs":[]}'
CK_RED='{"check_runs":[{"status":"completed","conclusion":"failure"}]}'
CK_PEND='{"check_runs":[{"status":"in_progress","conclusion":null}]}'

# ---- Case 1 (the AC expected-FAIL guard): GREEN + dry-run → WOULD-MERGE, and
#      the recorded trace contains ZERO write verbs (mock also set to reject). ----
run_helper "$PV_OPEN" "$CK_GREEN" true 1
[ "$LAST_RC" -eq 0 ] || fail "dry-run GREEN should exit 0 (got $LAST_RC)"
echo "$OUT" | grep -q "WOULD-MERGE #123" || fail "dry-run GREEN should say WOULD-MERGE (got: $OUT)"
echo "$TRACE" | grep -qE "$WRITE_VERBS_RE" && fail "dry-run issued a WRITE verb: $(echo "$TRACE" | grep -E "$WRITE_VERBS_RE")"
echo "OK: dry-run GREEN → WOULD-MERGE, zero mutating calls (trace clean)"

# ---- Case 2: GREEN + live → MERGED, and exactly one REST merge call recorded
#      (via `gh api --method PUT .../merge`, never `gh pr merge`). ----
run_helper "$PV_OPEN" "$CK_GREEN" false 0
[ "$LAST_RC" -eq 0 ] || fail "live GREEN should exit 0 (got $LAST_RC)"
echo "$OUT" | grep -q "MERGED #123" || fail "live GREEN should MERGE (got: $OUT)"
[ "$(echo "$TRACE" | grep -cE 'pulls/[0-9]+/merge')" -eq 1 ] || fail "live GREEN must issue exactly one REST merge call"
echo "$TRACE" | grep -qE '^pr merge' && fail "live GREEN must NOT use 'gh pr merge' (cannot bypass)"
echo "OK: live GREEN → MERGED, exactly one REST merge call (no gh pr merge)"

# ---- Case 3: no-checks (wedged clean PR) + live → MERGED. ----
run_helper "$PV_OPEN" "$CK_EMPTY" false 0
echo "$OUT" | grep -q "MERGED #123" || fail "live no-checks (wedged) should MERGE (got: $OUT)"
echo "OK: live no-checks (wedged) → MERGED"

# ---- Case 4: red / pending / draft / closed are NEVER merged (even live). ----
run_helper "$PV_OPEN" "$CK_RED" false 0
echo "$OUT" | grep -q "SKIP #123 (checks-FAIL)" || fail "RED should SKIP checks-FAIL (got: $OUT)"
echo "$TRACE" | grep -qE "$WRITE_VERBS_RE" && fail "RED issued a WRITE verb but must never merge"
echo "OK: RED → SKIP (no merge)"
run_helper "$PV_OPEN" "$CK_PEND" false 0
echo "$OUT" | grep -q "SKIP #123 (checks-PENDING)" || fail "PENDING should SKIP checks-PENDING (got: $OUT)"
echo "$TRACE" | grep -qE "$WRITE_VERBS_RE" && fail "PENDING issued a WRITE verb but must never merge"
echo "OK: PENDING → SKIP (no merge)"
run_helper "$PV_DRAFT" "$CK_EMPTY" false 0
echo "$OUT" | grep -q "SKIP #123 (state=OPEN,draft=true)" || fail "DRAFT should SKIP (got: $OUT)"
echo "$TRACE" | grep -qE "$WRITE_VERBS_RE" && fail "DRAFT issued a WRITE verb but must never merge"
echo "OK: DRAFT → SKIP (no merge)"
run_helper "$PV_CLOSED" "$CK_EMPTY" false 0
echo "$OUT" | grep -q "SKIP #123 (state=MERGED,draft=false)" || fail "CLOSED should SKIP (got: $OUT)"
echo "$TRACE" | grep -qE "$WRITE_VERBS_RE" && fail "CLOSED issued a WRITE verb but must never merge"
echo "OK: CLOSED → SKIP (no merge)"

# ---- Case 5 (F2 regression): a transient pr-view failure on attempt 1 then a
#      success on attempt 2 must still reach WOULD-MERGE — proves the retry log
#      goes to stderr (not into the captured JSON) and gh_read really retries. ----
run_helper "$PV_OPEN" "$CK_GREEN" true 0 1
[ "$LAST_RC" -eq 0 ] || fail "retry path should exit 0 (got $LAST_RC)"
echo "$OUT" | grep -q "WOULD-MERGE #123" || fail "retry path should still WOULD-MERGE (got: $OUT)"
[ "$(echo "$TRACE" | grep -cE 'pr view')" -eq 2 ] || fail "retry path should issue exactly two 'gh pr view' calls"
echo "OK: transient-then-success retry → WOULD-MERGE (log on stderr, JSON uncontaminated)"

# ---- Case 6 (F3): a non-automation author is NEVER swept (even green + live). ----
run_helper "$PV_HUMAN" "$CK_GREEN" false 0
[ "$LAST_RC" -eq 0 ] || fail "human-authored should exit 0 (skip, got $LAST_RC)"
echo "$OUT" | grep -q "SKIP #123 (author-not-allowlisted)" || fail "human-authored should SKIP author-not-allowlisted (got: $OUT)"
echo "$TRACE" | grep -qE "$WRITE_VERBS_RE" && fail "human-authored issued a WRITE verb but must never merge"
echo "OK: non-automation author → SKIP (author-not-allowlisted)"

# ---- Case 7 (F3): an unmet required review is NEVER swept WITHOUT bypass. ----
run_helper "$PV_REVREQ" "$CK_GREEN" false 0
[ "$LAST_RC" -eq 0 ] || fail "review-required should exit 0 (skip, got $LAST_RC)"
echo "$OUT" | grep -q "SKIP #123 (review-REVIEW_REQUIRED)" || fail "review-required should SKIP (got: $OUT)"
echo "$TRACE" | grep -qE "$WRITE_VERBS_RE" && fail "review-required issued a WRITE verb but must never merge"
echo "OK: reviewDecision=REVIEW_REQUIRED (no bypass) → SKIP (no merge)"

# ---- Case 8 (F1 regression): pr-view fails on EVERY attempt → gh_read must
#      return non-zero so the caller reaches the pr-view-unavailable fail-closed
#      SKIP (before the fix gh_read returned 0 and that branch was dead code). ----
run_helper "$PV_OPEN" "$CK_GREEN" false 0 0 1
echo "$OUT" | grep -q "SKIP #123 (pr-view-unavailable)" || fail "persistent read failure should hit pr-view-unavailable SKIP (got: $OUT)"
echo "$TRACE" | grep -qE "$WRITE_VERBS_RE" && fail "persistent read failure issued a WRITE verb but must never merge"
echo "OK: persistent pr-view failure → SKIP (pr-view-unavailable), fail-closed branch reachable"

# ---- Case 9 (bypass): BYPASS_REVIEW=true + REVIEW_REQUIRED + green → MERGED via
#      the REST endpoint. This is the fleet fix — the App is a ruleset bypass
#      actor, so an unmet code-owner review no longer blocks the merge. ----
BR=true run_helper "$PV_REVREQ" "$CK_GREEN" false 0
[ "$LAST_RC" -eq 0 ] || fail "bypass REVIEW_REQUIRED should exit 0 (got $LAST_RC)"
echo "$OUT" | grep -q "MERGED #123" || fail "bypass REVIEW_REQUIRED should MERGE (got: $OUT)"
[ "$(echo "$TRACE" | grep -cE 'pulls/[0-9]+/merge')" -eq 1 ] || fail "bypass merge must issue exactly one REST merge call"
echo "OK: BYPASS_REVIEW=true + REVIEW_REQUIRED → MERGED (REST, bypasses code-owner)"

# ---- Case 10 (bypass safety): BYPASS_REVIEW=true + CHANGES_REQUESTED → SKIP.
#      An explicit human "changes requested" is never overridden, bypass or not. ----
BR=true run_helper "$PV_CHREQ" "$CK_GREEN" false 0
[ "$LAST_RC" -eq 0 ] || fail "bypass CHANGES_REQUESTED should exit 0 (skip, got $LAST_RC)"
echo "$OUT" | grep -q "SKIP #123 (review-CHANGES_REQUESTED)" || fail "CHANGES_REQUESTED must SKIP even in bypass mode (got: $OUT)"
echo "$TRACE" | grep -qE "$WRITE_VERBS_RE" && fail "CHANGES_REQUESTED issued a WRITE verb but must never merge"
echo "OK: BYPASS_REVIEW=true + CHANGES_REQUESTED → SKIP (human block never overridden)"

# ---- Case 11 (bypass + check-runs unreadable): fail closed, never merge. ----
BR=true CF=1 run_helper "$PV_REVREQ" "$CK_GREEN" false 0
echo "$OUT" | grep -q "SKIP #123 (check-runs-unavailable)" || fail "unreadable check-runs should fail closed (got: $OUT)"
echo "$TRACE" | grep -qE 'pulls/[0-9]+/merge' && fail "unreadable check-runs must never merge"
echo "OK: bypass + unreadable check-runs → SKIP (fail closed, no merge)"

echo "ALL TESTS PASSED"
