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
# A PR is NEVER merged (defence-in-depth beyond the sweeper's label/state search
# filter) when it is closed/draft, authored by anyone outside AUTHOR_ALLOWLIST
# (the label alone is not trust — a triager can apply it; they cannot forge the
# author), or its reviewDecision is REVIEW_REQUIRED / CHANGES_REQUESTED.
#
# Inputs (environment):
#   PR_NUMBER        required — PR number to evaluate
#   REPO             required — owner/name the PR belongs to (passed to gh --repo)
#   MERGE_METHOD     optional — merge|squash|rebase (default: squash)
#   DRY_RUN          optional — "true" (default) logs the would-merge decision and
#                    performs ZERO mutating calls; "false" performs the merge
#   RETRY_MAX        optional — max attempts for a transient gh read (default: 3)
#   AUTHOR_ALLOWLIST optional — space-separated trusted author logins
#                    (default: "app/dependabot dependabot[bot]")
#
# Output: a single decision line on stdout, one of:
#   MERGED #<n>        (DRY_RUN=false, was GREEN)
#   WOULD-MERGE #<n>   (DRY_RUN=true, was GREEN)
#   SKIP #<n> (<reason>)
# Exit status is 0 for any well-formed decision (including SKIP); non-zero only
# on a usage error or an unrecoverable merge failure.
#
set -euo pipefail

# Shared bounded-retry helper (grade-A #13): gh_read now delegates to with_retry
# rather than carrying its own retry loop (one implementation, not three).
# shellcheck source=scripts/retry-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/retry-lib.sh"

PR_NUMBER="${PR_NUMBER:?PR_NUMBER required}"
REPO="${REPO:?REPO required (owner/name)}"
MERGE_METHOD="${MERGE_METHOD:-squash}"
DRY_RUN="${DRY_RUN:-true}"
RETRY_MAX="${RETRY_MAX:-3}"
# Space-separated allowlist of trusted PR-author logins. NOTE: `gh --json author`
# reports Dependabot as `app/dependabot` (the GitHub App identity); the webhook
# `pull_request.user.login` form is `dependabot[bot]`. Both are accepted so the
# gate matches regardless of representation. A human/triager cannot forge these.
AUTHOR_ALLOWLIST="${AUTHOR_ALLOWLIST:-app/dependabot dependabot[bot]}"

# log to STDERR so a retry message never contaminates a $(gh_read ...) capture.
log() { echo "[pr-green-merge] $*" >&2; }

# _gh_read_once <gh-args...> : run one gh read. Prints stdout + returns 0 on
# success; on any failure logs the last stderr line (STDERR only) and returns
# $RETRY_TRANSIENT_RC so with_retry treats a gh blip as transient (matches the
# prior retry-any-failure behavior).
_gh_read_once() {
  local out errf
  errf="$(mktemp)"
  if out="$(gh "$@" 2>"$errf")"; then
    rm -f "$errf"
    printf '%s' "$out"
    return 0
  fi
  log "gh $* failed: $(tail -n1 "$errf" 2>/dev/null)"
  rm -f "$errf"
  return "$RETRY_TRANSIENT_RC"
}

# gh_read <gh-args...> : bounded-retry gh READ via the shared helper. rc-on-
# failure capture + stderr-only logging are guaranteed by with_retry (re-pinned
# in tests/retry-lib.test.sh). A merge is still issued at most once (never via this).
gh_read() {
  with_retry "$RETRY_MAX" 1 8 -- _gh_read_once "$@"
}

# One combined read: PR state + draft + author + review decision + check rollup.
if ! PR_JSON="$(gh_read pr view "$PR_NUMBER" --repo "$REPO" \
      --json state,isDraft,author,reviewDecision,statusCheckRollup)"; then
  log "SKIP #${PR_NUMBER} (could not read PR — failing closed, no merge)"
  echo "SKIP #${PR_NUMBER} (pr-view-unavailable)"
  exit 0
fi

STATE="$(printf '%s' "$PR_JSON" | jq -r '.state // "UNKNOWN"')"
IS_DRAFT="$(printf '%s' "$PR_JSON" | jq -r '.isDraft // false')"
AUTHOR="$(printf '%s' "$PR_JSON" | jq -r '.author.login // ""')"
REVIEW="$(printf '%s' "$PR_JSON" | jq -r '.reviewDecision // ""')"

if [ "$STATE" != "OPEN" ] || [ "$IS_DRAFT" = "true" ]; then
  log "SKIP #${PR_NUMBER} (state=${STATE} draft=${IS_DRAFT}) — never merge a closed/draft PR"
  echo "SKIP #${PR_NUMBER} (state=${STATE},draft=${IS_DRAFT})"
  exit 0
fi

# Author allowlist (hardening): the sweep must only ever re-drive trusted
# automation PRs. The label alone is insufficient — anyone with triage on a repo
# can apply merge/approved; they cannot forge the PR author. This closes the
# "triager labels an arbitrary PR into a live merge" vector on repos without
# required status checks.
author_ok=false
for a in $AUTHOR_ALLOWLIST; do
  [ "$AUTHOR" = "$a" ] && { author_ok=true; break; }
done
if [ "$author_ok" != "true" ]; then
  log "SKIP #${PR_NUMBER} (author '${AUTHOR}' not in allowlist) — never sweep a non-automation PR"
  echo "SKIP #${PR_NUMBER} (author-not-allowlisted)"
  exit 0
fi

# Review-decision gate. reviewDecision is null when the repo requires no reviews
# (the common wedged-PR case — allowed), APPROVED when a required review is
# satisfied (allowed). REVIEW_REQUIRED means a required review is unmet — GitHub
# would block the merge server-side anyway, so skip to avoid a noisy failed
# merge; CHANGES_REQUESTED is an explicit block. Never merge over either.
if [ "$REVIEW" = "REVIEW_REQUIRED" ] || [ "$REVIEW" = "CHANGES_REQUESTED" ]; then
  log "SKIP #${PR_NUMBER} (reviewDecision=${REVIEW}) — review unmet/blocked, not sweep-eligible"
  echo "SKIP #${PR_NUMBER} (review-${REVIEW})"
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
