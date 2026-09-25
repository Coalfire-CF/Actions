#!/usr/bin/env bash
#
# uses-path-exists-check.sh: fail closed when a Dependabot PR bumps a first-party
# `uses:` ref to a commit where the referenced path does not exist.
#
# Why: a reusable workflow or composite action can be renamed or removed in a
# release. Dependabot only rewrites the @ref, never the path, so the bump PR
# points callers at a file that is gone. The caller then fails at startup (it
# may report no check-runs at all), and a semver-minor bump would otherwise pass
# every other gate. Used by the decide job in org-dependabot-auto-merge.yml.
#
# For every workflow file the PR adds or modifies, read it at the PR head and
# collect each `<TARGET_REPO>/<path>@<ref>` reference. Then confirm <path> exists
# in TARGET_REPO at <ref> via the contents API.
#
# Inputs (environment):
#   REPO         required, owner/name of the PR's repo
#   PR_NUMBER    required
#   HEAD_SHA     required, PR head commit
#   TARGET_REPO  optional, first-party repo to check (default Coalfire-CF/Actions)
#   GH_TOKEN     token with contents:read + pull-requests:read on REPO
#
# Outputs (appended to $GITHUB_OUTPUT):
#   uses_checked   number of distinct <path>@<ref> references checked
#   uses_missing   space-separated <path>@<ref> references that do not exist
#   uses_error     true when any read failed for a reason other than 404
#
set -euo pipefail

REPO="${REPO:?REPO required}"
PR_NUMBER="${PR_NUMBER:?PR_NUMBER required}"
HEAD_SHA="${HEAD_SHA:?HEAD_SHA required}"
TARGET_REPO="${TARGET_REPO:-Coalfire-CF/Actions}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/stdout}"

log() { echo "[uses-path-exists-check] $*" >&2; }

CHECKED=0
MISSING=""
ERROR="false"

emit() {
  {
    echo "uses_checked=${CHECKED}"
    echo "uses_missing=${MISSING# }"
    echo "uses_error=${ERROR}"
  } >> "$GITHUB_OUTPUT"
}

# gh api prints error bodies on stdout, so never trust stdout on failure.
errf="$(mktemp)"
trap 'rm -f "$errf"' EXIT

if ! files_pages="$(gh api --paginate "repos/${REPO}/pulls/${PR_NUMBER}/files?per_page=100" 2>"$errf")"; then
  log "could not list PR files: $(tail -n1 "$errf")"
  ERROR="true"; emit; exit 0
fi
if ! workflow_files="$(printf '%s' "$files_pages" | jq -sr '
    if length > 0 and all(.[]; type == "array") then
      [ .[][] | select(.status != "removed")
              | select(.filename | test("^\\.github/workflows/[^/]+\\.ya?ml$")) | .filename ]
      | .[]
    else error("unexpected files page shape") end')"; then
  log "invalid PR files response"
  ERROR="true"; emit; exit 0
fi

refs=""
while IFS= read -r wf; do
  [ -n "$wf" ] || continue
  if ! content="$(gh api -H 'Accept: application/vnd.github.raw' \
        "repos/${REPO}/contents/${wf}?ref=${HEAD_SHA}" 2>"$errf")"; then
    log "could not read ${wf}@${HEAD_SHA}: $(tail -n1 "$errf")"
    ERROR="true"; continue
  fi
  # Strip comments first so a commented-out example never counts.
  found="$(printf '%s\n' "$content" | sed 's/#.*$//' \
    | grep -oiE "${TARGET_REPO}/[A-Za-z0-9._/-]+@[A-Za-z0-9._/-]+" || true)"
  [ -n "$found" ] && refs="${refs}${found}"$'\n'
done <<< "$workflow_files"

while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  CHECKED=$((CHECKED + 1))
  rest="${ref#*/*/}"          # <path>@<ref>
  path="${rest%@*}"
  at="${rest##*@}"
  if gh api "repos/${TARGET_REPO}/contents/${path}?ref=${at}" >/dev/null 2>"$errf"; then
    log "ok: ${path}@${at}"
  elif grep -q 'HTTP 404' "$errf"; then
    log "MISSING: ${path} does not exist in ${TARGET_REPO}@${at}"
    MISSING="${MISSING} ${path}@${at}"
  else
    log "could not check ${path}@${at}: $(tail -n1 "$errf")"
    ERROR="true"
  fi
done < <(printf '%s' "$refs" | sort -u)

log "checked ${CHECKED} reference(s); missing: ${MISSING:-none}; error=${ERROR}"
emit
