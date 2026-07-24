#!/usr/bin/env bash
#
# release-patch-merge.sh — auto-merge a release-please release PR ONLY when it is
# an unambiguous PATCH-only release (Coalfire-CF/Actions#148). Minor/major keep
# the human gate. Fail-closed: every gate below has a distinct SKIP reason and
# any doubt → SKIP, never merge.
#
# HARD CONSTRAINTS (design invariants, do not "optimize" away):
#   * App-token ONLY. A GITHUB_TOKEN merge fires no `push` event, so the release
#     publish run never triggers → a merged-but-unpublished wedge. Gate 1 refuses
#     to run without an App token (TOKEN_IS_APP=true).
#   * NEVER `gh pr merge --auto`. Armed auto-merge survives a release-please
#     re-roll to a MINOR (TOCTOU). The merge is a compare-and-swap via
#     `--match-head-commit "$HEAD_SHA"`; the head is re-verified first (gate 13).
#   * PR_NUMBER is supplied by release-please's own output — this script NEVER
#     searches for a PR to act on.
#   * All content is read at the PINNED HEAD_SHA / BASE_SHA snapshot, never at a
#     moving ref, so a mid-run force-push cannot change what we evaluated.
#
# Inputs (environment):
#   REPO                    required — owner/name
#   PR_NUMBER               required — the release PR (from release-please output)
#   DRY_RUN                 "true" (default) → WOULD-MERGE, no merge/approve
#   MERGE_METHOD            merge|squash|rebase (default squash)
#   TOKEN_IS_APP            "true" iff GH_TOKEN is a GitHub App token (default false)
#   ALLOW_ZERO_CHECKS       "true" to permit a PR with no checks (default false)
#   RELEASE_FILE_ALLOWLIST  space-separated allowed changed paths
#                           (default: CHANGELOG.md .release-please-manifest.json version.txt)
#   AUTHOR_ALLOWLIST        space-separated trusted author logins
#   RETRY_MAX               transient-read attempts (default 3)
#   CHECKS_GRACE_TRIES      empty-rollup re-poll attempts (default 6)
#   CHECKS_GRACE_SLEEP      seconds between re-polls (default 30; ~3min total)
#   MANIFEST_PATH           default .release-please-manifest.json
#   CHANGELOG_PATH          default CHANGELOG.md
#   RUN_URL                 CI run URL for the audit comment/body (optional)
#
# Output: exactly one decision line on stdout — MERGED #n / WOULD-MERGE #n /
# SKIP #n (<reason>). Exit 0 for any well-formed decision; non-zero only on a
# usage error. A marker comment (<!-- org-release-auto-patch -->) is upserted on
# every decision in BOTH modes (legibility for opted-in repos, #148 review); the
# "zero mutations" guarantee of dry-run scopes to merge/approve, never the comment.
set -euo pipefail

# Shared bounded-retry helper (grade-A #13): all reads go through with_retry.
# shellcheck source=scripts/retry-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/retry-lib.sh"

REPO="${REPO:?REPO required (owner/name)}"
PR_NUMBER="${PR_NUMBER:?PR_NUMBER required (from release-please output)}"
DRY_RUN="${DRY_RUN:-true}"
MERGE_METHOD="${MERGE_METHOD:-squash}"
TOKEN_IS_APP="${TOKEN_IS_APP:-false}"
ALLOW_ZERO_CHECKS="${ALLOW_ZERO_CHECKS:-false}"
RELEASE_FILE_ALLOWLIST="${RELEASE_FILE_ALLOWLIST:-CHANGELOG.md .release-please-manifest.json version.txt}"
AUTHOR_ALLOWLIST="${AUTHOR_ALLOWLIST:-app/coalfire-release coalfire-release[bot]}"
RETRY_MAX="${RETRY_MAX:-3}"
CHECKS_GRACE_TRIES="${CHECKS_GRACE_TRIES:-6}"
CHECKS_GRACE_SLEEP="${CHECKS_GRACE_SLEEP:-30}"
MANIFEST_PATH="${MANIFEST_PATH:-.release-please-manifest.json}"
CHANGELOG_PATH="${CHANGELOG_PATH:-CHANGELOG.md}"
RUN_URL="${RUN_URL:-}"
MARKER="<!-- org-release-auto-patch -->"

log() { echo "[release-patch-merge] $*" >&2; }

# ---- gh read wrappers (transient blip → retry via with_retry) ----
# L8/#214: classify on evidence — only retry transient classes (429 rate-limit,
# 5xx, timeouts/conn resets). A definitive 4xx (esp. 404 for an absent manifest)
# is permanent: return 1 so with_retry stops immediately instead of spinning
# RETRY_MAX times. Unknown failures also default permanent (retry-lib philosophy:
# never spin on an unclassifiable error).
# shellcheck disable=SC2317,SC2329  # invoked indirectly via `with_retry -- _gh_once` (SC2317/SC2329 are the version-dependent codes for the same "unreachable/unused function" false positive)
_gh_once() {
  local o err rc
  err="$(mktemp)"
  if o="$(gh "$@" 2>"$err")"; then rm -f "$err"; printf '%s' "$o"; return 0; fi
  rc=$?
  if grep -qiE 'HTTP (429|5[0-9][0-9])|rate limit|timeout|timed out|temporar|connection reset|connection refused|no such host|i/o timeout|EOF' "$err"; then
    rm -f "$err"; return "$RETRY_TRANSIENT_RC"      # transient — retry
  fi
  rm -f "$err"; return "$rc"                          # permanent (4xx / unknown) — no spin
}
gh_read()       { with_retry "$RETRY_MAX" 2 20 -- _gh_once "$@"; }
# Read a repo file's decoded content at a pinned SHA (empty string if absent).
read_file_at() { # <path> <sha>
  gh_read api "repos/${REPO}/contents/${1}?ref=${2}" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || true
}

# statusCheckRollup classifier — FAIL > PENDING > GREEN (empty → EMPTY). Same
# semantics as pr-green-merge.sh; a transient read error can never read as GREEN.
classify_rollup() { # <json-array>
  printf '%s' "$1" | jq -r '
    if (. == null) or (length == 0) then "EMPTY"
    else
      [ .[] | ((.conclusion // .state // .status // "") | ascii_upcase) ] as $c
      | if   ($c | map(select(. == "FAILURE" or . == "ERROR" or . == "TIMED_OUT" or . == "CANCELLED" or . == "ACTION_REQUIRED" or . == "STARTUP_FAILURE")) | length) > 0 then "FAIL"
        elif ($c | map(select(. == "PENDING" or . == "EXPECTED" or . == "QUEUED" or . == "IN_PROGRESS" or . == "WAITING" or . == "REQUESTED" or . == "")) | length) > 0 then "PENDING"
        else "GREEN" end
    end'
}

# ---- decision emitters (each upserts the marker comment + summary, then exits) ----
DECISION_BODY=""
upsert_comment() { # <decision-text>
  local body id
  body="${MARKER}
**org-release auto-patch** — ${1}
${DECISION_BODY}
_run: ${RUN_URL:-n/a}_"
  # Locate an existing marker comment (edit, never re-post). M6/#203: --paginate so
  # a PR with >30 comments still finds the marker (else the upsert appends a new
  # comment every run). With --paginate the --jq filter runs per page, so emit each
  # matching id and take the last (most recent) rather than a per-page `last`.
  id="$(gh_read api --paginate "repos/${REPO}/issues/${PR_NUMBER}/comments" \
        --jq ".[]|select(.body|contains(\"${MARKER}\"))|.id" 2>/dev/null | tail -n1 || true)"
  if [ -n "$id" ]; then
    gh api -X PATCH "repos/${REPO}/issues/comments/${id}" -f body="$body" >/dev/null 2>&1 || log "comment edit failed (non-fatal)"
  else
    gh api -X POST "repos/${REPO}/issues/${PR_NUMBER}/comments" -f body="$body" >/dev/null 2>&1 || log "comment create failed (non-fatal)"
  fi
}
summarize() { # <decision-text>
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '### org-release auto-patch\n\n%s\n\n%s\n' "$1" "$DECISION_BODY" >> "$GITHUB_STEP_SUMMARY"
  fi
}
finish() { # <decision-line> <comment-text>
  summarize "$2"
  upsert_comment "$2"
  echo "$1"
  exit 0
}
skip()        { finish "SKIP #${PR_NUMBER} ($1)" "SKIP — $1"; }
merged()      { finish "MERGED #${PR_NUMBER}" "MERGED — $1"; }
would_merge() { finish "WOULD-MERGE #${PR_NUMBER}" "WOULD-MERGE (dry-run) — $1"; }

# ================= GATE 1 — App token (HARD) =================
if [ "$TOKEN_IS_APP" != "true" ]; then
  DECISION_BODY="A GitHub App token is required: a GITHUB_TOKEN merge fires no \`push\` event, so the release publish run never triggers (merged-but-unpublished wedge). Configure RELEASE_APP_ID / RELEASE_APP_PRIVATE_KEY to enable."
  skip "no-app-token"
fi

# ================= GATE 2 — snapshot + pin HEAD_SHA =================
SNAP="$(gh_read pr view "$PR_NUMBER" --repo "$REPO" \
  --json state,isDraft,isCrossRepository,headRefName,headRefOid,baseRefName,author,labels,reviewDecision,statusCheckRollup,files)" \
  || { DECISION_BODY="Could not read PR snapshot after retries."; skip "snapshot-unavailable"; }

j() { printf '%s' "$SNAP" | jq -r "$1"; }
STATE="$(j '.state')"; IS_DRAFT="$(j '.isDraft')"; IS_FORK="$(j '.isCrossRepository')"
HEAD_REF="$(j '.headRefName')"; HEAD_SHA="$(j '.headRefOid')"; BASE_REF="$(j '.baseRefName')"
AUTHOR="$(j '.author.login')"; REVIEW="$(j '.reviewDecision // ""')"
[ -n "$HEAD_SHA" ] || { DECISION_BODY="Snapshot missing headRefOid."; skip "snapshot-unavailable"; }

# ================= GATE 3 — open + non-draft =================
[ "$STATE" = "MERGED" ] && skip "already-merged"
[ "$STATE" = "OPEN" ] || skip "not-open"
if [ "$IS_DRAFT" = "true" ]; then skip "draft"; fi

# ================= GATE 4 — not a fork =================
[ "$IS_FORK" = "false" ] || skip "cross-repository"

# ================= GATE 5 — release-please branch → default base =================
DEFAULT_BRANCH="$(gh_read api "repos/${REPO}" --jq '.default_branch' 2>/dev/null || echo "")"
[ -n "$DEFAULT_BRANCH" ] || { DECISION_BODY="Could not resolve default branch."; skip "snapshot-unavailable"; }
[ "$BASE_REF" = "$DEFAULT_BRANCH" ] || skip "wrong-base"
case "$HEAD_REF" in
  "release-please--branches--${BASE_REF}") : ;;
  *) skip "wrong-branch" ;;
esac

# ================= GATE 6 — autorelease: pending label =================
printf '%s' "$SNAP" | jq -e '.labels[]?|select(.name=="autorelease: pending")' >/dev/null 2>&1 \
  || skip "missing-pending-label"

# ================= GATE 7 — author allowlist =================
author_ok=false
for a in $AUTHOR_ALLOWLIST; do [ "$AUTHOR" = "$a" ] && { author_ok=true; break; }; done
[ "$author_ok" = "true" ] || { DECISION_BODY="Author '${AUTHOR}' not in allowlist."; skip "author-not-allowlisted"; }

# ================= GATE 8 — changed files ⊆ allowlist =================
while IFS= read -r f; do
  [ -n "$f" ] || continue
  ok=false
  for a in $RELEASE_FILE_ALLOWLIST; do [ "$f" = "$a" ] && { ok=true; break; }; done
  [ "$ok" = "true" ] || { DECISION_BODY="Changed file outside the release allowlist: \`${f}\`."; skip "unexpected-file"; }
done < <(printf '%s' "$SNAP" | jq -r '.files[].path')

# ================= GATE 9 — manifest patch-only delta (authoritative) =================
# NOTE (deliberate deviation, #148 review R4): BASE_SHA is the base-branch TIP at
# read time, not the PR's recorded baseRefOid. This is equal-or-safer: if base
# advanced since the PR was cut, we compare against the NEWER base manifest — a
# stale PR then reads as non-patch (or no-change) and SKIPs. Do not "fix" this
# back to baseRefOid; the tip is the correct thing to gate a merge-into-tip against.
BASE_SHA="$(gh_read api "repos/${REPO}/commits/${BASE_REF}" --jq '.sha' 2>/dev/null || echo "")"
[ -n "$BASE_SHA" ] || { DECISION_BODY="Could not resolve base SHA."; skip "snapshot-unavailable"; }
BASE_MANIFEST="$(read_file_at "$MANIFEST_PATH" "$BASE_SHA")"
HEAD_MANIFEST="$(read_file_at "$MANIFEST_PATH" "$HEAD_SHA")"
{ [ -n "$BASE_MANIFEST" ] && [ -n "$HEAD_MANIFEST" ]; } || { DECISION_BODY="Release manifest missing at base or head."; skip "missing-manifest"; }
if ! printf '%s' "$BASE_MANIFEST" | jq -e . >/dev/null 2>&1 || ! printf '%s' "$HEAD_MANIFEST" | jq -e . >/dev/null 2>&1; then
  DECISION_BODY="Release manifest is not valid JSON."; skip "missing-manifest"
fi

VERDICT="$(jq -rn --argjson base "$BASE_MANIFEST" --argjson head "$HEAD_MANIFEST" '
  ($head|keys) as $hk
  | if any($hk[]; . as $k | ($base|has($k)|not)) then "FIRST_RELEASE"
    else
      [ $hk[] | {k:., old:$base[.], new:$head[.]} | select(.old != .new) ] as $ch
      | if ($ch|length)==0 then "NO_CHANGE"
        elif any($ch[]; (.old|test("^[0-9]+\\.[0-9]+\\.[0-9]+$")|not) or (.new|test("^[0-9]+\\.[0-9]+\\.[0-9]+$")|not)) then "NOT_PATCH"
        elif all($ch[];
              (.old|capture("^(?<a>[0-9]+)\\.(?<b>[0-9]+)\\.(?<c>[0-9]+)$")) as $o
              | (.new|capture("^(?<a>[0-9]+)\\.(?<b>[0-9]+)\\.(?<c>[0-9]+)$")) as $n
              | ($o.a==$n.a) and ($o.b==$n.b) and (($n.c|tonumber)==($o.c|tonumber)+1))
          then "PATCH_OK" else "NOT_PATCH" end
    end')"

# Extract old/new of the primary changed entry for the audit message.
read -r OLD_VER NEW_VER <<<"$(jq -rn --argjson base "$BASE_MANIFEST" --argjson head "$HEAD_MANIFEST" '
  ([ ($head|keys[]) | select((($base[.]) // "") != $head[.]) ] | (index(".") as $i | if $i!=null then "." else (.[0] // "") end)) as $key
  | "\(($base[$key]) // "?") \(($head[$key]) // "?")"' 2>/dev/null || echo "? ?")"

case "$VERDICT" in
  PATCH_OK)      : ;;
  FIRST_RELEASE) DECISION_BODY="Manifest introduces a new package key — first release needs a human."; skip "first-release" ;;
  NO_CHANGE)     DECISION_BODY="No manifest version changed."; skip "no-version-change" ;;
  *)             DECISION_BODY="Manifest delta is not patch-only (v${OLD_VER} -> v${NEW_VER})."; skip "not-patch-only" ;;
esac

# ================= GATE 10 — changelog consistency belt =================
BASE_CL="$(read_file_at "$CHANGELOG_PATH" "$BASE_SHA")"
HEAD_CL="$(read_file_at "$CHANGELOG_PATH" "$HEAD_SHA")"
ADDED="$(diff <(printf '%s' "$BASE_CL") <(printf '%s' "$HEAD_CL") 2>/dev/null | sed -n 's/^> //p' || true)"
if printf '%s' "$ADDED" | grep -qE '### Features|BREAKING'; then
  DECISION_BODY="Changelog additions advertise Features/BREAKING despite a patch manifest delta."
  skip "inconsistent-changelog"
fi

# ================= GATE 11 — review not blocked (never auto-approve) =================
case "$REVIEW" in
  REVIEW_REQUIRED|CHANGES_REQUESTED) DECISION_BODY="reviewDecision=${REVIEW}."; skip "review-${REVIEW}" ;;
esac

# ================= GATE 12 — checks green (fail closed) =================
ROLLUP="$(printf '%s' "$SNAP" | jq -c '.statusCheckRollup')"
CHECK_STATE="$(classify_rollup "$ROLLUP")"
if [ "$CHECK_STATE" = "EMPTY" ]; then
  # Registration grace: checks may not have attached yet just after PR creation.
  tries=0
  while [ "$CHECK_STATE" = "EMPTY" ] && [ "$tries" -lt "$CHECKS_GRACE_TRIES" ]; do
    [ "$CHECKS_GRACE_SLEEP" -gt 0 ] && sleep "$CHECKS_GRACE_SLEEP"
    tries=$((tries + 1))
    ROLLUP="$(gh_read pr view "$PR_NUMBER" --repo "$REPO" --json statusCheckRollup | jq -c '.statusCheckRollup' 2>/dev/null || echo '[]')"
    CHECK_STATE="$(classify_rollup "$ROLLUP")"
  done
fi
case "$CHECK_STATE" in
  EMPTY)   [ "$ALLOW_ZERO_CHECKS" = "true" ] || { DECISION_BODY="No status checks registered on the PR."; skip "zero-checks"; }; CHECK_STATE="GREEN" ;;
  FAIL)    DECISION_BODY="A required check failed."; skip "checks-fail" ;;
  PENDING)
    # L7/#213: bound the watch so a stuck/never-completing check can't hang the
    # step until the workflow-level timeout. `timeout` exits 124 on deadline →
    # treated as checks-not-green. Fall back to an unbounded watch only where
    # coreutils `timeout` is unavailable (stock macOS); CI runners have it.
    WATCH_TIMEOUT="${CHECKS_WATCH_TIMEOUT:-900}"
    if command -v timeout >/dev/null 2>&1; then
      watch_cmd=(timeout "$WATCH_TIMEOUT" gh pr checks "$PR_NUMBER" --repo "$REPO" --watch --fail-fast)
    else
      watch_cmd=(gh pr checks "$PR_NUMBER" --repo "$REPO" --watch --fail-fast)
    fi
    # `|| watch_rc=$?` keeps set -e from aborting on a non-zero (failed/timeout) watch.
    watch_rc=0
    "${watch_cmd[@]}" >/dev/null 2>&1 || watch_rc=$?
    if [ "$watch_rc" -eq 0 ]; then
      CHECK_STATE="GREEN"
    elif [ "$watch_rc" -eq 124 ]; then
      DECISION_BODY="Checks did not complete within ${WATCH_TIMEOUT}s while watching."
      skip "checks-not-green"
    else
      DECISION_BODY="Checks did not go green (failed while watching)."
      skip "checks-not-green"
    fi ;;
esac
[ "$CHECK_STATE" = "GREEN" ] || { DECISION_BODY="Checks not green (${CHECK_STATE})."; skip "checks-not-green"; }

# ================= GATE 13 — re-snapshot (TOCTOU) =================
RESNAP="$(gh_read pr view "$PR_NUMBER" --repo "$REPO" --json headRefOid,state,labels,reviewDecision)" \
  || { DECISION_BODY="Could not re-read PR before merge."; skip "snapshot-unavailable"; }
[ "$(printf '%s' "$RESNAP" | jq -r '.headRefOid')" = "$HEAD_SHA" ] || { DECISION_BODY="Head advanced after evaluation (was ${HEAD_SHA})."; skip "head-moved"; }
[ "$(printf '%s' "$RESNAP" | jq -r '.state')" = "OPEN" ] || skip "head-moved"
printf '%s' "$RESNAP" | jq -e '.labels[]?|select(.name=="autorelease: pending")' >/dev/null 2>&1 || skip "head-moved"
case "$(printf '%s' "$RESNAP" | jq -r '.reviewDecision // ""')" in
  REVIEW_REQUIRED|CHANGES_REQUESTED) skip "head-moved" ;;
esac

DECISION_BODY="Patch-only release v${OLD_VER} -> v${NEW_VER}; checks green at ${HEAD_SHA}."

# ================= GATE 14 — merge (CAS) or dry-run =================
if [ "$DRY_RUN" != "false" ]; then
  would_merge "patch-only v${OLD_VER} -> v${NEW_VER}; checks green at ${HEAD_SHA}"
fi

MERGE_BODY="Auto-merged by org-release auto_release_patch policy: patch-only release v${OLD_VER} -> v${NEW_VER}; checks green at ${HEAD_SHA}; run ${RUN_URL:-n/a} (Coalfire-CF/Actions#148)"
MERGE_ERR="$(mktemp)"
if gh pr merge "$PR_NUMBER" --repo "$REPO" "--${MERGE_METHOD}" --match-head-commit "$HEAD_SHA" --body "$MERGE_BODY" 2>"$MERGE_ERR"; then
  rm -f "$MERGE_ERR"
  merged "patch-only v${OLD_VER} -> v${NEW_VER}"
fi
ERRTXT="$(cat "$MERGE_ERR" 2>/dev/null)"; rm -f "$MERGE_ERR"
log "merge failed: ${ERRTXT}"
if printf '%s' "$ERRTXT" | grep -qiE '405|409|head.*match|Base branch was modified|not mergeable|Merge already in progress'; then
  DECISION_BODY="Merge raced another update (head moved / already merging): ${ERRTXT}"
  skip "merge-raced"
fi
DECISION_BODY="Merge call failed: ${ERRTXT}"
skip "merge-failed"
