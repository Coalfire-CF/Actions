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
#   REPOS     optional space/newline list of repo names to limit the sweep
set -euo pipefail

ORG="${ORG:-Coalfire-CF}"
PR_TITLE="${PR_TITLE:-chore: remove README Tree workflow}"
BRANCH="${BRANCH:-chore/remove-tree-readme}"
DRY_RUN="${DRY_RUN:-true}"

# The two files that make a repo a tree-readme consumer.
CALLER_PATH=".github/workflows/tree-readme.yml"
CONFIG_PATH=".github/readmetreerc.yml"
TARGET_PATHS=("$CALLER_PATH" "$CONFIG_PATH")

log() { echo "$@" >&2; }

# ---- Resolve target repos (repos carrying the caller workflow), minus Actions ----
if [ -n "${REPOS:-}" ]; then
  mapfile -t REPO_LIST < <(printf '%s' "$REPOS" | tr '[:space:]' '\n' | grep -v '^$' | grep -vx 'Actions' | sort -u)
else
  mapfile -t REPO_LIST < <(
    gh api -X GET search/code \
      -f q="org:${ORG} path:.github/workflows filename:tree-readme" \
      -f per_page=100 --paginate --jq '.items[].repository.name' \
      | grep -vx 'Actions' | sort -u
  )
fi
log "Targeting ${#REPO_LIST[@]} repo(s) in ${ORG} (DRY_RUN=${DRY_RUN})"
(( ${#REPO_LIST[@]} > 0 )) || { log "No target repos resolved — aborting."; exit 1; }

# Return the blob sha of $path on ref $2 in repo $1, or empty if absent.
file_sha_on_ref() {
  gh api "repos/$1/contents/$2?ref=$3" --jq '.sha' 2>/dev/null || true
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
    [ -n "$(file_sha_on_ref "$repo" "$p" "$base")" ] && present+=("$p")
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
    bsha="$(file_sha_on_ref "$repo" "$p" "$BRANCH")"
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
