#!/usr/bin/env bash
#
# pr-template-sweep.sh — one-time org sweep to standardize .github/PULL_REQUEST_TEMPLATE.md
#
# New/empty repos receive the template via the org-repo-bootstrap bundle
# (templates/bootstrap/common/.github/PULL_REQUEST_TEMPLATE.md.tmpl). This
# script handles the other half: repos that ALREADY carry a template, which the
# bootstrap sweeper skips under its never-overwrite rule. It replaces the file
# in place on a branch and opens a PR. Every PR uses the SAME title so the PRs
# can be landed in bulk (see the bulk-pr-approve skill).
#
# No clone: all work goes through the GitHub contents API.
#
# Env / args:
#   ORG            default "Coalfire-CF"
#   TEMPLATE_FILE  path to canonical template (default .github/PULL_REQUEST_TEMPLATE.md)
#   PR_TITLE       default "chore: refresh PR template"
#   BRANCH         default "chore/pr-template-refresh"
#   DRY_RUN        "true" (default) prints intended actions; "false" opens PRs
#   REPOS          optional space/newline list of repo names to limit the sweep
#
# Repo list: if REPOS is unset, every repo in ORG that already has a
# .github/PULL_REQUEST_TEMPLATE.md is targeted.
set -euo pipefail

ORG="${ORG:-Coalfire-CF}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_FILE="${TEMPLATE_FILE:-${REPO_ROOT}/.github/PULL_REQUEST_TEMPLATE.md}"
PR_TITLE="${PR_TITLE:-chore: refresh PR template}"
BRANCH="${BRANCH:-chore/pr-template-refresh}"
DRY_RUN="${DRY_RUN:-true}"
TARGET_PATH=".github/PULL_REQUEST_TEMPLATE.md"

[ -f "$TEMPLATE_FILE" ] || { echo "FATAL: template not found: $TEMPLATE_FILE" >&2; exit 1; }
NEW_B64="$(base64 < "$TEMPLATE_FILE" | tr -d '\n')"

log() { echo "$@" >&2; }

# ---- Resolve target repos ----
if [ -n "${REPOS:-}" ]; then
  mapfile -t REPO_LIST < <(printf '%s' "$REPOS" | tr '[:space:]' '\n' | sort -u)
else
  mapfile -t REPO_LIST < <(
    gh api -X GET search/code \
      -f q="org:${ORG} path:.github filename:PULL_REQUEST_TEMPLATE" \
      -f per_page=100 --paginate --jq '.items[].repository.name' | sort -u
  )
fi
log "Targeting ${#REPO_LIST[@]} repo(s) in ${ORG} (DRY_RUN=${DRY_RUN})"

opened=0 skipped=0 errors=0
for name in "${REPO_LIST[@]}"; do
  [ -n "$name" ] || continue
  repo="${ORG}/${name}"

  # Existing file on the default branch: capture content sha + body together.
  meta="$(gh api "repos/${repo}/contents/${TARGET_PATH}" --jq '{sha:.sha, content:(.content|gsub("\n";""))}' 2>/dev/null || true)"
  file_sha="$(printf '%s' "$meta" | jq -r '.sha // empty' 2>/dev/null || true)"
  if [ -z "$file_sha" ]; then
    log "SKIP ${repo} — no ${TARGET_PATH} on default branch (bootstrap bundle covers empty repos)"
    skipped=$((skipped+1)); continue
  fi
  cur_b64="$(printf '%s' "$meta" | jq -r '.content // empty')"

  # Skip if the current content already equals the canonical template.
  cur_norm="$(printf '%s' "$cur_b64" | base64 -d 2>/dev/null | base64 | tr -d '\n')"
  if [ "$cur_norm" = "$NEW_B64" ]; then
    log "SKIP ${repo} — already up to date"
    skipped=$((skipped+1)); continue
  fi

  if [ "$DRY_RUN" != "false" ]; then
    log "WOULD-UPDATE ${repo} (file sha ${file_sha:0:7})"
    opened=$((opened+1)); continue
  fi

  # Default branch head sha, create branch, update file, open PR.
  base="$(gh api "repos/${repo}" --jq '.default_branch')"
  base_sha="$(gh api "repos/${repo}/git/ref/heads/${base}" --jq '.object.sha')"
  gh api -X POST "repos/${repo}/git/refs" -f ref="refs/heads/${BRANCH}" -f sha="${base_sha}" >/dev/null 2>&1 \
    || log "  branch ${BRANCH} may already exist on ${repo}; continuing"

  if ! gh api -X PUT "repos/${repo}/contents/${TARGET_PATH}" \
        -f message="chore: refresh PR template" \
        -f content="${NEW_B64}" \
        -f sha="${file_sha}" \
        -f branch="${BRANCH}" >/dev/null 2>&1; then
    log "ERROR ${repo} — contents PUT failed"; errors=$((errors+1)); continue
  fi

  if gh pr create --repo "${repo}" --base "${base}" --head "${BRANCH}" \
       --title "${PR_TITLE}" \
       --body "Standardizes \`${TARGET_PATH}\` to the current org default (summary-first, trimmed checklist). Opened by scripts/pr-template-sweep.sh." >/dev/null 2>&1; then
    log "OPENED ${repo}"; opened=$((opened+1))
  else
    log "ERROR ${repo} — pr create failed (branch pushed)"; errors=$((errors+1))
  fi
done

echo "Done. would-update/opened=${opened} skipped=${skipped} errors=${errors} of ${#REPO_LIST[@]}"
