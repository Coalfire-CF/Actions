#!/usr/bin/env bash
#
# tree-readme-remove-sweep.sh — one-time org sweep to REMOVE the README Tree
# feature from consumer repos.
#
# The README `## Tree` section is being retired fleet-wide (the repo file tree
# is already visible in the GitHub file browser and every IDE). The reusable
# org-tree-readme.yml is first neutered to a no-op so callers stay green; this
# script then deletes the two per-repo files that drive it:
#
#     .github/workflows/tree-readme.yml   (the self-caller)
#     .github/readmetreerc.yml            (the tree config)
#
# It opens one PR per repo, all sharing the same title so they can be landed in
# bulk (see the bulk-pr-approve skill). No clone: all work goes through the
# GitHub contents API. Idempotent: re-runs converge partial state (existing
# branch, already-deleted file, already-open PR) instead of erroring.
#
# The Actions repo is deliberately EXCLUDED — its own dogfood caller, config,
# tests, and the reusable workflow are removed together in a final Actions PR
# once no external callers remain (do not orphan the reusable's last caller).
#
# Env / args:
#   ORG       default "Coalfire-CF"
#   PR_TITLE  default "chore: remove README Tree workflow"
#   BRANCH    default "chore/remove-tree-readme"
#   DRY_RUN   "true" (default) prints intended actions; "false" opens PRs
#   REPOS     REQUIRED space/newline list of repo names to sweep
#   REPOS_FILE  alternative to REPOS: a file with one repo name per line
#
# The caller list is REQUIRED and must come from a measured enumeration. An
# earlier version defaulted to `gh api search/code`, which is not trustworthy on
# this fleet: it 503s mid-survey and has returned "1 unique repo" for a query
# matching hundreds, so the sweep would report success having skipped most
# targets. Enumerate by walking /repos/{o}/{r}/contents/.github/workflows and
# reading each file (note /git/trees 404s on private repos here), then pass the
# result in. Assert the count before running with DRY_RUN=false.
set -euo pipefail

ORG="${ORG:-Coalfire-CF}"
PR_TITLE="${PR_TITLE:-chore: remove README Tree workflow}"
BRANCH="${BRANCH:-chore/remove-tree-readme}"
DRY_RUN="${DRY_RUN:-true}"

# The files that make a repo a tree-readme consumer.
#
# The caller is named `org-tree-readme.yml` in this fleet, NOT `tree-readme.yml`.
# Measured 2026-08-17 across the 167 marker repos: 14 repos call the reusable and
# 2 carry an inlined fork of the updater, and ALL 16 use `org-tree-readme.yml`.
# Zero repos have `tree-readme.yml`. Targeting only that name deleted nothing.
# Both names are listed so the Actions repo's own self-caller is also covered.
CALLER_PATH=".github/workflows/org-tree-readme.yml"
LEGACY_CALLER_PATH=".github/workflows/tree-readme.yml"
CONFIG_PATH=".github/readmetreerc.yml"
TARGET_PATHS=("$CALLER_PATH" "$LEGACY_CALLER_PATH" "$CONFIG_PATH")

log() { echo "$@" >&2; }

# ---- Resolve target repos from the caller list supplied by the operator ----
# Actions is filtered out here as well as documented above: its own caller is
# removed last, in a dedicated PR, so the reusable never loses its last caller
# while it still exists.
if [ -n "${REPOS:-}" ]; then
  RAW_REPOS="$REPOS"
elif [ -n "${REPOS_FILE:-}" ]; then
  [ -f "$REPOS_FILE" ] || { log "REPOS_FILE not found: ${REPOS_FILE}"; exit 2; }
  RAW_REPOS="$(cat "$REPOS_FILE")"
else
  log "Set REPOS or REPOS_FILE to a measured list of tree-readme caller repos."
  log "Code search is not a valid source here (see the header comment)."
  exit 2
fi
mapfile -t REPO_LIST < <(printf '%s' "$RAW_REPOS" | tr '[:space:]' '\n' | grep -v '^$' | grep -vx 'Actions' | sort -u)
log "Targeting ${#REPO_LIST[@]} repo(s) in ${ORG} (DRY_RUN=${DRY_RUN})"
(( ${#REPO_LIST[@]} > 0 )) || { log "No target repos resolved — aborting."; exit 1; }

# Return the blob sha of $path on ref $3 in repo $1, or empty if absent.
#
# The EXIT STATUS decides, not the output. `gh api --jq` writes its error JSON to
# STDOUT, so the previous `|| true` form returned `{"message":"Not Found",...}`
# for a missing file and every path read as PRESENT. That made the dry run report
# "19 of 19, 0 skipped" while `tree-readme.yml` existed in no repo at all.
# A sha is also sanity-checked as hex, so an unexpected body can never be passed
# to a DELETE as if it were a blob sha.
file_sha_on_ref() {
  local out
  out="$(gh api "repos/$1/contents/$2?ref=$3" --jq '.sha' 2>/dev/null)" || return 1
  case "$out" in
    ""|*[!0-9a-f]*) return 1 ;;
    *) printf '%s' "$out" ;;
  esac
}

opened=0 skipped=0 errors=0
for name in "${REPO_LIST[@]}"; do
  [ -n "$name" ] || continue
  repo="${ORG}/${name}"
  base="$(gh api "repos/${repo}" --jq '.default_branch' 2>/dev/null || true)"
  if [ -z "$base" ]; then
    log "ERROR ${repo} — could not resolve default branch"; errors=$((errors+1)); continue
  fi

  # What is actually present on the default branch? (Assert presence, don't assume.)
  present=()
  for p in "${TARGET_PATHS[@]}"; do
    if file_sha_on_ref "$repo" "$p" "$base" >/dev/null; then present+=("$p"); fi
  done
  if (( ${#present[@]} == 0 )); then
    log "SKIP ${repo} — neither file present on ${base} (already removed)"
    skipped=$((skipped+1)); continue
  fi

  if [ "$DRY_RUN" != "false" ]; then
    log "WOULD-REMOVE ${repo} — ${present[*]}"
    opened=$((opened+1)); continue
  fi

  # ---- Idempotent branch delivery ----
  # Create the working branch off the default head if it does not exist yet.
  if ! gh api "repos/${repo}/git/ref/heads/${BRANCH}" >/dev/null 2>&1; then
    base_sha="$(gh api "repos/${repo}/git/ref/heads/${base}" --jq '.object.sha')"
    if ! gh api -X POST "repos/${repo}/git/refs" -f ref="refs/heads/${BRANCH}" -f sha="${base_sha}" >/dev/null 2>&1; then
      log "ERROR ${repo} — could not create branch ${BRANCH}"; errors=$((errors+1)); continue
    fi
  fi

  # Delete each target file that still exists ON THE BRANCH (re-run safe: a file
  # already gone from the branch is skipped, not re-deleted).
  del_err=0
  for p in "${TARGET_PATHS[@]}"; do
    bsha="$(file_sha_on_ref "$repo" "$p" "$BRANCH")" || continue
    [ -n "$bsha" ] || continue
    if ! gh api -X DELETE "repos/${repo}/contents/${p}" \
          -f message="chore: remove README Tree workflow (${p##*/})" \
          -f sha="${bsha}" \
          -f branch="${BRANCH}" >/dev/null 2>&1; then
      log "ERROR ${repo} — delete failed for ${p}"; del_err=1; break
    fi
  done
  if [ "$del_err" = "1" ]; then errors=$((errors+1)); continue; fi

  # Open a PR only if one is not already open for this branch.
  existing_pr="$(gh pr list --repo "${repo}" --head "${BRANCH}" --state open --json number --jq '.[0].number' 2>/dev/null || true)"
  if [ -n "$existing_pr" ]; then
    log "UPDATED ${repo} — existing PR #${existing_pr}"; opened=$((opened+1)); continue
  fi
  if gh pr create --repo "${repo}" --base "${base}" --head "${BRANCH}" \
       --title "${PR_TITLE}" \
       --body "Removes the retired README Tree feature: deletes \`${CALLER_PATH}\` and \`${CONFIG_PATH}\`. The repo file tree is already visible in the GitHub file browser and every IDE; the reusable org-tree-readme.yml is now a no-op. Opened by scripts/tree-readme-remove-sweep.sh." >/dev/null 2>&1; then
    log "OPENED ${repo}"; opened=$((opened+1))
  else
    log "ERROR ${repo} — pr create failed (branch pushed)"; errors=$((errors+1))
  fi
done

echo "Done. would-remove/opened=${opened} skipped=${skipped} errors=${errors} of ${#REPO_LIST[@]}"
