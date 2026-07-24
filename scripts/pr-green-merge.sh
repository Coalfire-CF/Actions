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
# Classification is FAIL > PENDING > GREEN and is computed from the head commit's
# REST check-runs (structured JSON) rather than parsing `gh pr checks` text, so a
# transient API error can never masquerade as GREEN. (Check RUNS only — the fleet
# gates on GitHub Actions checks; reading the GraphQL statusCheckRollup would also
# pull commit statuses and thus require `statuses:read`, which the bypass App does
# not hold; the ruleset requires no status checks either way.) NOTE (option B): the
# auto-merge fallback's adoption of this helper is owned by the #9/#12/#13
# follow-up chain on org-dependabot-auto-merge.yml — this PR does not touch that
# file. The bounded retry below is a minimal transient-blip guard, NOT #13's full
# backoff+jitter; it converges onto #13's shared retry helper when that lands.
#
# A PR is NEVER merged (defence-in-depth beyond the sweeper's label/state search
# filter) when it is closed/draft, authored by anyone outside AUTHOR_ALLOWLIST
# (the label alone is not trust — a triager can apply it; they cannot forge the
# author), or its reviewDecision is CHANGES_REQUESTED (an explicit human block).
# reviewDecision == REVIEW_REQUIRED (an unmet *required* review, e.g. a code-owner
# review a bot can neither give nor be named for) is skipped by default but merged
# when BYPASS_REVIEW=true — the caller is merging AS a ruleset bypass actor (the
# ci-automerge-app Integration or the cs-coalforge team), for which the merge is
# allowed server-side despite the unmet requirement. See MERGE MECHANISM below.
#
# MERGE MECHANISM: the merge is issued via the REST endpoint
# (PUT /repos/{o}/{r}/pulls/{n}/merge, `gh api`), NOT `gh pr merge`. `gh pr merge`
# (GraphQL) refuses when the PR's mergeStateStatus is BLOCKED and does not exercise
# ruleset bypass — verified 2026-07-15 (it was rejected even for an admin+bypass
# user, "base branch policy prohibits the merge"). The REST endpoint honors the
# authenticated actor's bypass entitlement.
#
# Inputs (environment):
#   PR_NUMBER        required — PR number to evaluate
#   REPO             required — owner/name the PR belongs to (passed to gh --repo)
#   MERGE_METHOD     optional — merge|squash|rebase (default: squash)
#   DRY_RUN          optional — "true" (default) logs the would-merge decision and
#                    performs ZERO mutating calls; "false" performs the merge
#   BYPASS_REVIEW    optional — "true" merges a PR whose reviewDecision is
#                    REVIEW_REQUIRED (caller is a bypass actor); "false" (default)
#                    skips it. CHANGES_REQUESTED is skipped regardless.
#   RETRY_MAX        optional — max attempts for a transient gh read (default: 3)
#   AUTHOR_ALLOWLIST optional — space-separated trusted author logins
#                    (default: "app/dependabot dependabot[bot]")
#   IGNORE_CHECK_PREFIX optional — exclude check runs whose name starts with this
#                    from the green gate (default "auto-merge / " — the auto-merge
#                    workflow's own jobs, which are in-flight while it merges). "" disables.
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
BYPASS_REVIEW="${BYPASS_REVIEW:-false}"
RETRY_MAX="${RETRY_MAX:-3}"
# Check runs whose name starts with this prefix are EXCLUDED from the green gate.
# Default excludes the auto-merge workflow's own jobs ("auto-merge / classify",
# "auto-merge / decide", …): when the decide job runs the merge inline, its own
# check run is IN_PROGRESS and notify_failure/remerge are QUEUED, so counting them
# would make the PR-time merge forever self-classify PENDING and never fire. Those
# jobs gate the auto-merge DECISION (upstream), not code correctness, so excluding
# them is safe; the repo's real CI checks still gate. Set to "" to disable.
IGNORE_CHECK_PREFIX="${IGNORE_CHECK_PREFIX:-auto-merge / }"
# Space-separated allowlist of trusted PR-author logins. NOTE: `gh --json author`
# reports GitHub-App authors as `app/<slug>`; the webhook
# `pull_request.user.login` form is `<slug>[bot]`. Both forms are accepted so
# the gate matches regardless of representation. A human/triager cannot forge
# these. Besides Dependabot, the ci-automerge-app itself is trusted: the
# org-repo-bootstrap sweeper authors baseline-adoption PRs as the App and labels
# them merge/approved for this same green-gated pipeline to land.
AUTHOR_ALLOWLIST="${AUTHOR_ALLOWLIST:-app/dependabot dependabot[bot] app/ci-automerge-app ci-automerge-app[bot]}"

# log to STDERR so a retry message never contaminates a $(gh_read ...) capture.
log() { echo "[pr-green-merge] $*" >&2; }

# _gh_read_once <gh-args...> : run one gh read. Prints stdout + returns 0 on
# success; on any failure logs the last stderr line (STDERR only) and returns
# $RETRY_TRANSIENT_RC so with_retry treats a gh blip as transient (matches the
# prior retry-any-failure behavior).
# shellcheck disable=SC2317,SC2329  # invoked indirectly via `with_retry -- _gh_read_once` (SC2317/SC2329 are the version-dependent codes for the same "unreachable/unused function" false positive)
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

# PR metadata read: state + draft + author + review decision + head SHA. We do
# NOT request statusCheckRollup here — that GraphQL field aggregates check runs
# AND commit statuses, so it demands BOTH `checks:read` and `statuses:read`; the
# ci-automerge-app bypass identity carries `checks:read` only. Check state is read
# separately below via the REST check-runs endpoint (checks:read alone). These
# fields (state/isDraft/author/reviewDecision/headRefOid) need only pull_requests
# read, which the App has.
if ! PR_JSON="$(gh_read pr view "$PR_NUMBER" --repo "$REPO" \
      --json state,isDraft,author,reviewDecision,headRefOid)"; then
  log "SKIP #${PR_NUMBER} (could not read PR — failing closed, no merge)"
  echo "SKIP #${PR_NUMBER} (pr-view-unavailable)"
  exit 0
fi

STATE="$(printf '%s' "$PR_JSON" | jq -r '.state // "UNKNOWN"')"
IS_DRAFT="$(printf '%s' "$PR_JSON" | jq -r '.isDraft // false')"
AUTHOR="$(printf '%s' "$PR_JSON" | jq -r '.author.login // ""')"
REVIEW="$(printf '%s' "$PR_JSON" | jq -r '.reviewDecision // ""')"
HEAD_SHA="$(printf '%s' "$PR_JSON" | jq -r '.headRefOid // ""')"

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
# L6/#212: read into an array (word-split, NO pathname expansion). An unquoted
# `for a in $AUTHOR_ALLOWLIST` globs — and `dependabot[bot]` is a valid glob
# ([bot] is a char class), so a matching file in CWD would corrupt the token and
# make a trusted author wrongly fail the allowlist.
read -ra _allow <<< "$AUTHOR_ALLOWLIST"
for a in "${_allow[@]}"; do
  [ "$AUTHOR" = "$a" ] && { author_ok=true; break; }
done
if [ "$author_ok" != "true" ]; then
  log "SKIP #${PR_NUMBER} (author '${AUTHOR}' not in allowlist) — never sweep a non-automation PR"
  echo "SKIP #${PR_NUMBER} (author-not-allowlisted)"
  exit 0
fi

# Review-decision gate. reviewDecision is null when the repo requires no reviews
# (the common wedged-PR case — allowed), APPROVED when a required review is
# satisfied (allowed).
#   CHANGES_REQUESTED — an explicit human block. NEVER merged, even in bypass mode:
#     a bypass actor could technically override it, but "a reviewer said no" is not
#     something automation may steamroll.
#   REVIEW_REQUIRED  — a *required* review is unmet (e.g. a code-owner review a bot
#     can neither give nor be a CODEOWNER for). Skipped by default (a non-bypass
#     caller would be blocked server-side anyway); merged when BYPASS_REVIEW=true,
#     because the caller merges AS a ruleset bypass actor and the merge is allowed.
if [ "$REVIEW" = "CHANGES_REQUESTED" ]; then
  log "SKIP #${PR_NUMBER} (reviewDecision=CHANGES_REQUESTED) — explicit human block, never overridden"
  echo "SKIP #${PR_NUMBER} (review-CHANGES_REQUESTED)"
  exit 0
fi
if [ "$REVIEW" = "REVIEW_REQUIRED" ] && [ "$BYPASS_REVIEW" != "true" ]; then
  log "SKIP #${PR_NUMBER} (reviewDecision=REVIEW_REQUIRED) — required review unmet; set BYPASS_REVIEW=true to merge as a ruleset bypass actor"
  echo "SKIP #${PR_NUMBER} (review-REVIEW_REQUIRED)"
  exit 0
fi

# Green gate: read the head commit's check runs via REST (checks:read) and
# classify FAIL > PENDING > GREEN, EXCLUDING check runs named with
# IGNORE_CHECK_PREFIX (the auto-merge workflow's own jobs — see var comment; when
# the decide job merges inline, its own check is IN_PROGRESS and would otherwise
# wedge the gate PENDING forever). No (remaining) check runs classifies GREEN — the
# wedged-PR case (a clean PR on a repo with no gating checks). We read check RUNS
# only (GitHub Actions checks — what the fleet gates on); legacy commit statuses
# are not consulted, since the ruleset requires no status checks and reading them
# would need `statuses:read` the bypass App does not hold. A blank HEAD_SHA (never
# expected on an OPEN PR) fails closed.
if [ -z "$HEAD_SHA" ]; then
  log "SKIP #${PR_NUMBER} (no head SHA — failing closed, no merge)"
  echo "SKIP #${PR_NUMBER} (no-head-sha)"
  exit 0
fi
if ! CHECKS_JSON="$(gh_read api "repos/${REPO}/commits/${HEAD_SHA}/check-runs?per_page=100")"; then
  log "SKIP #${PR_NUMBER} (could not read check-runs — failing closed, no merge)"
  echo "SKIP #${PR_NUMBER} (check-runs-unavailable)"
  exit 0
fi
CHECK_STATE="$(printf '%s' "$CHECKS_JSON" | jq -r --arg ign "$IGNORE_CHECK_PREFIX" '
  [ .check_runs[]?
    | select(($ign == "") or ((.name // "") | startswith($ign) | not))
    | ((.conclusion // .status // "") | ascii_upcase) ] as $c
  | if   ($c | map(select(. == "FAILURE" or . == "ERROR" or . == "TIMED_OUT" or . == "CANCELLED" or . == "ACTION_REQUIRED" or . == "STARTUP_FAILURE")) | length) > 0 then "FAIL"
    elif ($c | map(select(. == "QUEUED" or . == "IN_PROGRESS" or . == "PENDING" or . == "WAITING" or . == "REQUESTED" or . == "")) | length) > 0 then "PENDING"
    else "GREEN" end')"

if [ "$CHECK_STATE" != "GREEN" ]; then
  log "SKIP #${PR_NUMBER} (checks ${CHECK_STATE}) — leave for auto-merge/next event"
  echo "SKIP #${PR_NUMBER} (checks-${CHECK_STATE})"
  exit 0
fi

BYPASS_NOTE=""
[ "$REVIEW" = "REVIEW_REQUIRED" ] && BYPASS_NOTE=", bypassing REVIEW_REQUIRED"

if [ "$DRY_RUN" != "false" ]; then
  log "WOULD-MERGE #${PR_NUMBER} (checks GREEN${BYPASS_NOTE}) — dry-run, no mutation performed"
  echo "WOULD-MERGE #${PR_NUMBER}"
  exit 0
fi

# Merge via the REST endpoint (see MERGE MECHANISM in the header): `gh pr merge`
# refuses a BLOCKED PR and does not exercise ruleset bypass; PUT .../merge does.
# M5/#202: compare-and-swap on the head SHA pinned at green-gate time. The REST
# endpoint's `sha` requires the PR head to still match at merge time; if a commit
# was pushed (or the head otherwise moved) between our classification and now,
# GitHub returns 409 and refuses — so we can never merge unreviewed/unchecked code
# that landed after the gate. A 409 is a benign race → clean SKIP, not an error.
log "MERGE #${PR_NUMBER} (checks GREEN${BYPASS_NOTE}) via REST --${MERGE_METHOD}, CAS sha=${HEAD_SHA}"
MERGE_ERR="$(mktemp)"
if gh api --method PUT "repos/${REPO}/pulls/${PR_NUMBER}/merge" \
     -f "merge_method=${MERGE_METHOD}" -f "sha=${HEAD_SHA}" >/dev/null 2>"$MERGE_ERR"; then
  rm -f "$MERGE_ERR"
  echo "MERGED #${PR_NUMBER}"
  exit 0
fi
ERRTXT="$(cat "$MERGE_ERR" 2>/dev/null)"; rm -f "$MERGE_ERR"
if printf '%s' "$ERRTXT" | grep -qiE '409|Head branch was modified|did not match|Conflict'; then
  log "SKIP #${PR_NUMBER} (head moved after green-gate; CAS sha=${HEAD_SHA} rejected): ${ERRTXT}"
  echo "SKIP #${PR_NUMBER} (head-moved)"
  exit 0
fi
log "MERGE FAILED #${PR_NUMBER}: ${ERRTXT}"
exit 1
