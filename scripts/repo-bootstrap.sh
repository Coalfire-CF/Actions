#!/usr/bin/env bash
#
# repo-bootstrap.sh — per-repo worker for the org-repo-bootstrap sweeper
# (.github/workflows/org-repo-bootstrap.yml). Given one target repo, decide
# whether it should receive the org baseline bundle and, in live mode, open a
# single bootstrap PR containing the pinned caller workflows + configs rendered
# from templates/bootstrap/.
#
# GitHub has no native "apply template at repo creation", so this script is the
# convergence mechanism: the sweeper calls it for every candidate repo and it
# either SKIPs (already adopted / opted out / already proposed) or proposes the
# baseline as a PR. PRs are labeled `bootstrap/proposed` + `merge/approved`, so
# the existing reconcile sweeper (scripts/pr-green-merge.sh) lands them once
# their own checks are green — the App is the PR author, admitted via that
# script's AUTHOR_ALLOWLIST.
#
# OPT-OUT CONTRACT (each independently sufficient, checked in this order):
#   - repo archived or fork                      → SKIP (archived|fork)
#   - repo topic `bootstrap-exempt`              → SKIP (topic-exempt)
#   - marker file `.github/.no-bootstrap`        → SKIP (opt-out-file)
#   - already adopted (.github/workflows/org-release.yml present)
#                                                → SKIP (compliant)
#   - an OPEN bootstrap/* PR                     → SKIP (pr-open)
#   - a CLOSED-unmerged bootstrap/* PR           → SKIP (declined) — declining
#     the proposal is itself a durable opt-out; the sweep never re-nags.
#     (A MERGED historical bootstrap PR does not block.)
#
# NEVER OVERWRITES: every rendered path is probed in the target repo first;
# files that already exist are dropped from the delivery (partial adoption keeps
# human edits). Zero remaining files ⇒ SKIP (compliant).
#
# Inputs (environment):
#   TARGET_REPO      required — owner/name
#   ACTIONS_SHA      required — 40-hex commit SHA of the Actions release to pin
#   ACTIONS_VERSION  required — matching tag (e.g. v0.12.1) for the pin comment
#   DRY_RUN          optional — "true" (default) prints the decision and issues
#                    ZERO mutating calls (no clone, no push, no PR, no labels)
#   TEMPLATE_DIR     optional — default <repo-root>/templates/bootstrap
#   PR_LABELS        optional — comma-separated (default
#                    "bootstrap/proposed,merge/approved")
#   BRANCH_PREFIX    optional — default "bootstrap/" (branch: bootstrap/baseline-<version>)
#   VISIBILITY       optional — public|private; detected from metadata if unset
#   IS_TERRAFORM     optional — true|false; detected via languages API if unset
#   WORK_DIR         optional — parent dir for the clone/staging (default mktemp)
#   RETRY_MAX        optional — max attempts for a transient gh read (default 3)
#
# Output: a single decision line on stdout, one of:
#   SKIP <repo> (<reason>)
#   WOULD-BOOTSTRAP <repo> (<n> files)      (DRY_RUN=true)
#   BOOTSTRAPPED <repo> PR#<n>              (DRY_RUN=false)
# Exit 0 for any well-formed decision; non-zero only on usage error or an
# unrecoverable delivery failure.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/retry-lib.sh
. "${SCRIPT_DIR}/retry-lib.sh"

TARGET_REPO="${TARGET_REPO:?TARGET_REPO required (owner/name)}"
ACTIONS_SHA="${ACTIONS_SHA:?ACTIONS_SHA required (40-hex release commit)}"
ACTIONS_VERSION="${ACTIONS_VERSION:?ACTIONS_VERSION required (release tag)}"
DRY_RUN="${DRY_RUN:-true}"
TEMPLATE_DIR="${TEMPLATE_DIR:-${REPO_ROOT}/templates/bootstrap}"
PR_LABELS="${PR_LABELS:-bootstrap/proposed,merge/approved}"
BRANCH_PREFIX="${BRANCH_PREFIX:-bootstrap/}"
RETRY_MAX="${RETRY_MAX:-3}"

case "$ACTIONS_SHA" in
  *[!0-9a-f]*|"") echo "usage: ACTIONS_SHA must be 40-hex" >&2; exit 2 ;;
esac
[ "${#ACTIONS_SHA}" -eq 40 ] || { echo "usage: ACTIONS_SHA must be 40-hex" >&2; exit 2; }
[ -d "$TEMPLATE_DIR" ] || { echo "usage: TEMPLATE_DIR $TEMPLATE_DIR not found" >&2; exit 2; }

log() { echo "[repo-bootstrap] $*" >&2; }

# Bounded-retry gh READ (same shape as pr-green-merge.sh). Transient blips retry;
# persistent failure returns non-zero so callers fail CLOSED (SKIP, no delivery).
_gh_read_once() {
  local out errf
  errf="$(mktemp)"
  if out="$(gh "$@" 2>"$errf")"; then
    rm -f "$errf"; printf '%s' "$out"; return 0
  fi
  log "gh $* failed: $(tail -n1 "$errf" 2>/dev/null)"
  rm -f "$errf"
  return "$RETRY_TRANSIENT_RC"
}
gh_read() { with_retry "$RETRY_MAX" 1 8 -- _gh_read_once "$@"; }

# probe_path <path> — 0 the path exists in the target repo, 1 it does not.
# A definitive 404 is "absent"; any other persistent failure is treated as
# "exists" (fail CLOSED: when in doubt, do not deliver/overwrite).
probe_path() {
  local p="$1" errf
  errf="$(mktemp)"
  if gh api "repos/${TARGET_REPO}/contents/${p}" >/dev/null 2>"$errf"; then
    rm -f "$errf"; return 0
  fi
  if grep -qi 'not found' "$errf"; then rm -f "$errf"; return 1; fi
  log "contents probe for ${p} inconclusive: $(tail -n1 "$errf") — treating as existing (fail closed)"
  rm -f "$errf"; return 0
}

# ---- Gate 1: repo metadata (archived / fork / topic / visibility) ----
if ! META="$(gh_read api "repos/${TARGET_REPO}")"; then
  log "SKIP ${TARGET_REPO} (could not read repo metadata — failing closed)"
  echo "SKIP ${TARGET_REPO} (read-unavailable)"
  exit 0
fi
ARCHIVED="$(printf '%s' "$META" | jq -r '.archived // false')"
FORK="$(printf '%s' "$META" | jq -r '.fork // false')"
DETECTED_VISIBILITY="$(printf '%s' "$META" | jq -r '.visibility // "private"')"
DEFAULT_BRANCH="$(printf '%s' "$META" | jq -r '.default_branch // "main"')"
HAS_EXEMPT_TOPIC="$(printf '%s' "$META" | jq -r '(.topics // []) | any(. == "bootstrap-exempt")')"
VISIBILITY="${VISIBILITY:-$DETECTED_VISIBILITY}"

[ "$ARCHIVED" = "true" ] && { echo "SKIP ${TARGET_REPO} (archived)"; exit 0; }
[ "$FORK" = "true" ] && { echo "SKIP ${TARGET_REPO} (fork)"; exit 0; }
[ "$HAS_EXEMPT_TOPIC" = "true" ] && { echo "SKIP ${TARGET_REPO} (topic-exempt)"; exit 0; }

# ---- Gate 2: opt-out marker file ----
if probe_path ".github/.no-bootstrap"; then
  echo "SKIP ${TARGET_REPO} (opt-out-file)"
  exit 0
fi

# ---- Gate 3: adoption probe ----
if probe_path ".github/workflows/org-release.yml"; then
  echo "SKIP ${TARGET_REPO} (compliant)"
  exit 0
fi

# ---- Gate 4: existing bootstrap PRs (open blocks; closed-unmerged = declined) ----
if ! PRS="$(gh_read pr list --repo "$TARGET_REPO" --state all --limit 100 \
      --json headRefName,state,mergedAt)"; then
  log "SKIP ${TARGET_REPO} (could not read PRs — failing closed)"
  echo "SKIP ${TARGET_REPO} (read-unavailable)"
  exit 0
fi
PR_STATE="$(printf '%s' "$PRS" | jq -r --arg pre "$BRANCH_PREFIX" '
  [ .[] | select(.headRefName | startswith($pre)) ] as $b
  | if   ($b | map(select(.state == "OPEN")) | length) > 0 then "open"
    elif ($b | map(select(.state == "CLOSED" and .mergedAt == null)) | length) > 0 then "declined"
    else "none" end')"
[ "$PR_STATE" = "open" ] && { echo "SKIP ${TARGET_REPO} (pr-open)"; exit 0; }
[ "$PR_STATE" = "declined" ] && { echo "SKIP ${TARGET_REPO} (declined)"; exit 0; }

# ---- Classify: terraform (languages API) and visibility ----
if [ -z "${IS_TERRAFORM:-}" ]; then
  if LANGS="$(gh_read api "repos/${TARGET_REPO}/languages")"; then
    IS_TERRAFORM="$(printf '%s' "$LANGS" | jq -r 'has("HCL")')"
  else
    log "languages read failed — classifying as non-terraform (baseline still applies)"
    IS_TERRAFORM=false
  fi
fi

# ---- Render templates (placeholders → real values, .tmpl suffix stripped) ----
WORK_ROOT="${WORK_DIR:-$(mktemp -d)}"
RENDER_DIR="${WORK_ROOT}/render"
rm -rf "$RENDER_DIR"; mkdir -p "$RENDER_DIR"

REPO_NAME="${TARGET_REPO#*/}"
STAGGER_SLOT="$(bash "${SCRIPT_DIR}/stagger-slot.sh" "$REPO_NAME")"

render_set() { # $1 = template subset dir (common|terraform|private)
  local src="${TEMPLATE_DIR}/$1"
  [ -d "$src" ] || return 0
  ( cd "$src" && find . -type f -name '*.tmpl' -print0 ) | while IFS= read -r -d '' rel; do
    local_rel="${rel#./}"; out_rel="${local_rel%.tmpl}"
    mkdir -p "$(dirname "${RENDER_DIR}/${out_rel}")"
    sed -e "s|__ACTIONS_SHA__|${ACTIONS_SHA}|g" \
        -e "s|__ACTIONS_VERSION__|${ACTIONS_VERSION}|g" \
        -e "s|__STAGGER_SLOT__|${STAGGER_SLOT}|g" \
        "${src}/${local_rel}" > "${RENDER_DIR}/${out_rel}"
  done
}
render_set common
[ "$IS_TERRAFORM" = "true" ] && render_set terraform
[ "$VISIBILITY" = "private" ] && render_set private

# ---- Never overwrite: drop any rendered path that already exists remotely ----
FILES=()
while IFS= read -r -d '' f; do
  rel="${f#./}"
  if probe_path "$rel"; then
    log "dropping ${rel} — already exists in ${TARGET_REPO} (never overwrite)"
    rm -f "${RENDER_DIR}/${rel}"
  else
    FILES+=("$rel")
  fi
done < <(cd "$RENDER_DIR" && find . -type f -print0)

COUNT="${#FILES[@]}"
if [ "$COUNT" -eq 0 ]; then
  echo "SKIP ${TARGET_REPO} (compliant)"
  exit 0
fi

if [ "$DRY_RUN" != "false" ]; then
  log "WOULD-BOOTSTRAP ${TARGET_REPO}: ${FILES[*]}"
  echo "WOULD-BOOTSTRAP ${TARGET_REPO} (${COUNT} files)"
  exit 0
fi

# ---- Deliver: clone, branch, copy, push, PR ----
BRANCH="${BRANCH_PREFIX}baseline-${ACTIONS_VERSION}"
CLONE="${WORK_ROOT}/repo"
rm -rf "$CLONE"
git clone --depth 1 "https://x-access-token:${GH_TOKEN:-}@github.com/${TARGET_REPO}.git" "$CLONE" >&2
(
  cd "$CLONE"
  git checkout -b "$BRANCH" >&2
  for rel in "${FILES[@]}"; do
    mkdir -p "$(dirname "$rel")"
    cp "${RENDER_DIR}/${rel}" "$rel"
  done
  git config user.name "coalfire-org-bootstrap[bot]" >&2
  git config user.email "org-bootstrap@users.noreply.github.com" >&2
  git add -A >&2
  git commit -m "chore(ci): bootstrap org baseline workflows (${ACTIONS_VERSION})" >&2
  git push origin "HEAD:${BRANCH}" >&2
)

# Labels must exist before `gh pr create --label`; create-if-missing guards.
IFS=',' read -ra LABELS <<< "$PR_LABELS"
LABEL_ARGS=()
for l in "${LABELS[@]}"; do
  gh label create "$l" --repo "$TARGET_REPO" --color "0E8A16" \
    --description "org repo bootstrap" >/dev/null 2>&1 || true
  LABEL_ARGS+=(--label "$l")
done

PR_BODY="$(cat <<EOF
## Org baseline bootstrap (${ACTIONS_VERSION})

This PR was opened automatically by the org repo-bootstrap sweeper
([docs](https://github.com/Coalfire-CF/Actions/blob/main/docs/ORG_REPO_BOOTSTRAP.md)).
It adds the standard Coalfire-CF Actions baseline, pinned to release
${ACTIONS_VERSION} (\`${ACTIONS_SHA}\`):

$(printf -- '- `%s`\n' "${FILES[@]}")

Merging is safe: files that already existed in this repo were left untouched.
If this repo should not carry the baseline, close this PR (the sweeper will
never re-open it), add the \`bootstrap-exempt\` topic, or commit
\`.github/.no-bootstrap\`.

**Follow-up:** add \`.github/CODEOWNERS\` — Allstar will remind you.
EOF
)"

PR_URL="$(gh pr create --repo "$TARGET_REPO" --base "$DEFAULT_BRANCH" --head "$BRANCH" \
  --title "chore(ci): bootstrap org baseline workflows (${ACTIONS_VERSION})" \
  --body "$PR_BODY" "${LABEL_ARGS[@]}")"
PR_NUM="${PR_URL##*/}"

echo "BOOTSTRAPPED ${TARGET_REPO} PR#${PR_NUM}"
