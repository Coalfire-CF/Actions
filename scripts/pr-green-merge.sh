#!/usr/bin/env bash
#
# pr-green-merge.sh — shared green-gate + direct-merge for one Dependabot PR
# (grade-A plan #14). Single source of truth for "is this PR safe to merge right
# now, and if so merge it" used by the reconcile sweeper
# (.github/workflows/org-dependabot-reconcile.yml).
#
# It re-applies the SAME green gate as the auto-merge fallback
# (org-dependabot-auto-merge.yml "Approve and auto-merge" step) — no failing and
# no pending check — re-checking freshness live rather than trusting a label:
#   FAIL   — any check failed / errored / timed-out / cancelled / action-required
#   PENDING— any check queued / in-progress / expected (not yet complete)
#   GREEN  — all checks complete & non-failing, OR no checks configured (the
#            wedged-PR case: a clean PR on a repo with no required status checks,
#            which is exactly what this sweeper exists to converge)
# Classification is FAIL > PENDING > GREEN and is computed from the PR's
# statusCheckRollup (structured JSON) rather than parsing `gh pr checks` text, so
# a transient API error can never masquerade as GREEN. NOTE (option B): the
# auto-merge fallback's adoption of this helper is owned by the #9/#12/#13
# follow-up chain on org-dependabot-auto-merge.yml — this PR does not touch that
# file. The bounded retry below is a minimal transient-blip guard, NOT #13's full
# backoff+jitter; it converges onto #13's shared retry helper when that lands.
#
# A closed or draft PR is NEVER merged (defence-in-depth beyond the sweeper's
# label/state search filter).
#
# Inputs (environment):
#   PR_NUMBER     required — PR number to evaluate
#   REPO          required — owner/name the PR belongs to (passed to gh --repo)
#   MERGE_METHOD  optional — merge|squash|rebase (default: squash)
#   DRY_RUN       optional — "true" (default) logs the would-merge decision and
#                 performs ZERO mutating calls; "false" performs the merge
#   RETRY_MAX     optional — max attempts for a transient gh read (default: 3)
#
# Output: a single decision line on stdout, one of:
#   MERGED #<n>        (DRY_RUN=false, was GREEN)
#   WOULD-MERGE #<n>   (DRY_RUN=true, was GREEN)
#   SKIP #<n> (<reason>)
# Exit status is 0 for any well-formed decision (including SKIP); non-zero only
# on a usage error or an unrecoverable merge failure.
#
set -euo pipefail

PR_NUMBER="${PR_NUMBER:?PR_NUMBER required}"
REPO="${REPO:?REPO required (owner/name)}"
MERGE_METHOD="${MERGE_METHOD:-squash}"
DRY_RUN="${DRY_RUN:-true}"
RETRY_MAX="${RETRY_MAX:-3}"

log() { echo "[pr-green-merge] $*"; }

# Bounded-retry wrapper for a transient gh READ failure (rate blips / 5xx). Only
# used for read calls; a merge is issued at most once. Prints command stdout on
# success; returns the last non-zero code after RETRY_MAX attempts.
gh_read() {
  local out rc attempt=1
  while :; do
    if out="$(gh "$@" 2>/dev/null)"; then
      printf '%s' "$out"
      return 0
    fi
    rc=$?
    if [ "$attempt" -ge "$RETRY_MAX" ]; then
      log "gh $* failed after ${attempt} attempt(s) (rc=${rc})"
      return "$rc"
    fi
    log "transient gh read failure (attempt ${attempt}/${RETRY_MAX}); retrying"
    attempt=$((attempt + 1))
    sleep "$attempt"
  done
}

# One combined read: PR state + draft flag + structured check rollup.
if ! PR_JSON="$(gh_read pr view "$PR_NUMBER" --repo "$REPO" --json state,isDraft,statusCheckRollup)"; then
  log "SKIP #${PR_NUMBER} (could not read PR — failing closed, no merge)"
  echo "SKIP #${PR_NUMBER} (pr-view-unavailable)"
  exit 0
fi

STATE="$(printf '%s' "$PR_JSON" | jq -r '.state // "UNKNOWN"')"
IS_DRAFT="$(printf '%s' "$PR_JSON" | jq -r '.isDraft // false')"

if [ "$STATE" != "OPEN" ] || [ "$IS_DRAFT" = "true" ]; then
  log "SKIP #${PR_NUMBER} (state=${STATE} draft=${IS_DRAFT}) — never merge a closed/draft PR"
  echo "SKIP #${PR_NUMBER} (state=${STATE},draft=${IS_DRAFT})"
  exit 0
fi

# Green gate: FAIL > PENDING > GREEN over the statusCheckRollup. Empty rollup
# (no checks configured) classifies GREEN — the wedged-PR case.
CHECK_STATE="$(printf '%s' "$PR_JSON" | jq -r '
  [ .statusCheckRollup[]? | ((.conclusion // .state // .status // "") | ascii_upcase) ] as $c
  | if   ($c | map(select(. == "FAILURE" or . == "ERROR" or . == "TIMED_OUT" or . == "CANCELLED" or . == "ACTION_REQUIRED" or . == "STARTUP_FAILURE")) | length) > 0 then "FAIL"
    elif ($c | map(select(. == "PENDING" or . == "EXPECTED" or . == "QUEUED" or . == "IN_PROGRESS" or . == "WAITING" or . == "REQUESTED" or . == "")) | length) > 0 then "PENDING"
    else "GREEN" end')"

if [ "$CHECK_STATE" != "GREEN" ]; then
  log "SKIP #${PR_NUMBER} (checks ${CHECK_STATE}) — leave for auto-merge/next event"
  echo "SKIP #${PR_NUMBER} (checks-${CHECK_STATE})"
  exit 0
fi

if [ "$DRY_RUN" != "false" ]; then
  log "WOULD-MERGE #${PR_NUMBER} (checks GREEN) — dry-run, no mutation performed"
  echo "WOULD-MERGE #${PR_NUMBER}"
  exit 0
fi

log "MERGE #${PR_NUMBER} (checks GREEN) via --${MERGE_METHOD}"
gh pr merge "$PR_NUMBER" "--${MERGE_METHOD}" --repo "$REPO"
echo "MERGED #${PR_NUMBER}"
