#!/usr/bin/env bash
#
# terraform-docs-standard-sweep.sh — migrate repos onto the org terraform-docs
# standard (Azure Verified Modules TFNFR2, "Module Documentation Generation").
#
# Before: README.md is hand-authored prose with a generated block spliced into
# the middle, and CI pushes a commit to the PR branch to refresh it.
# After: README.md is generated in full from _header.md and _footer.md, authors
# regenerate locally with a pinned pre-commit hook, and CI only verifies.
#
# Per repo:
#   1 split README.md at the markers into _header.md / _footer.md
#   2 drop the retired `## Tree` section from _header.md
#   3 add .terraform-docs.yml and .pre-commit-config.yaml
#   4 add the three doc paths to the caller, drop `contents: write`, re-pin
#   5 regenerate with the pinned terraform-docs container
#   6 prove no authored prose was lost, then open a PR
#
# The caller list is REQUIRED and must come from a measured enumeration. Code
# search is not a valid source on this fleet: it 503s mid-survey and has
# returned "1 unique repo" for a query matching hundreds. Enumerate by walking
# /repos/{o}/{r}/contents/... and reading each file (note /git/trees 404s on
# private repos here).
#
# Env:
#   ORG            default "Coalfire-CF"
#   REPOS          space/newline list of repo names           (REPOS or REPOS_FILE required)
#   REPOS_FILE     file with one repo name per line
#   DRY_RUN        "true" (default) plans only; "false" pushes and opens PRs
#   ACTIONS_PIN    40-char SHA of the Actions release to pin  (required if DRY_RUN=false)
#   ACTIONS_TAG    version comment for that SHA, e.g. v0.17.0 (required if DRY_RUN=false)
#   BRANCH         default "chore/terraform-docs-standard"
#   PR_TITLE       default "chore(docs): generate README from _header.md and _footer.md"
#   WORKDIR        default "$HOME/.cache/tf-docs-sweep"
#   TFDOCS_IMAGE   default "quay.io/terraform-docs/terraform-docs:0.20.0"
#   TEMPLATE_DIR   default "<repo root>/templates/terraform-docs"
#   KEEP_CLONES    "true" keeps clones for inspection (default "false")
#
# WORKDIR must NOT be under /tmp. Docker Desktop on macOS does not share /tmp by
# default, so the container mounts an empty directory and terraform-docs reports
# a missing config while appearing to run.
#
# Results: a TSV and a JSON array in WORKDIR, plus a reconciled summary. Every
# repo lands in exactly one outcome; targeted == sum of outcomes or the run
# fails.
set -euo pipefail

ORG="${ORG:-Coalfire-CF}"
DRY_RUN="${DRY_RUN:-true}"
BRANCH="${BRANCH:-chore/terraform-docs-standard}"
PR_TITLE="${PR_TITLE:-chore(docs): generate README from _header.md and _footer.md}"
WORKDIR="${WORKDIR:-$HOME/.cache/tf-docs-sweep}"
TFDOCS_IMAGE="${TFDOCS_IMAGE:-quay.io/terraform-docs/terraform-docs:0.20.0}"
KEEP_CLONES="${KEEP_CLONES:-false}"

CALLER=".github/workflows/org-terraform-docs.yml"
BEGIN_MARK="<!-- BEGIN_TF_DOCS -->"
END_MARK="<!-- END_TF_DOCS -->"

# The three paths README.md is generated FROM. Without them a prose-only edit
# ships a stale README on a green PR and the verify gate is decorative.
DOC_PATHS=("_header.md" "_footer.md" ".terraform-docs.yml")

log()  { echo "$@" >&2; }
die()  { log "FATAL: $*"; exit 2; }

# ---------------------------------------------------------------------------
# Normalize a line for the prose comparison. Two transformations terraform-docs
# applies to authored partials would otherwise read as prose loss:
#
#   1 trailing whitespace is stripped. Measured on terraform-aws-kms, whose
#     README has a line ending "policies. " that renders as "policies.".
#   2 `settings.escape: true` escapes markdown punctuation, so the authored
#     `![Coalfire](coalfire_logo.png)` renders as `coalfire\_logo.png`.
#     Backslashes are dropped from BOTH sides; a genuinely missing line is not
#     resurrected by removing backslashes, so the check stays honest.
# ---------------------------------------------------------------------------
normalize_prose() { sed -e 's/\\//g' -e 's/[[:space:]]*$//' "$1"; }

# ---------------------------------------------------------------------------
# Strip the retired `## Tree` section: from the `## Tree` heading up to the next
# heading of the same or higher level. Bounded to that section on purpose; a
# broader deletion would take unrelated prose with it.
# ---------------------------------------------------------------------------
strip_tree_section() {
  awk '
    /^## +Tree[[:space:]]*$/ { skip = 1; next }
    skip && /^#{1,2} +/      { skip = 0 }
    !skip                    { print }
  ' "$1"
}

# ---------------------------------------------------------------------------
# Assert every non-blank authored line survived into the regenerated README.
# This is the gate that catches prose loss, which is the one failure mode of
# this migration that cannot be undone by a re-run.
# ---------------------------------------------------------------------------
prose_preserved() {
  local authored="$1" rendered="$2" missing=0 line norm_rendered
  norm_rendered="$(mktemp "${TMPDIR:-/tmp}/rendered.XXXXXX")"
  normalize_prose "$rendered" > "$norm_rendered"
  while IFS= read -r line; do
    case "$line" in ""|"<!--"*) continue ;; esac
    grep -Fqx -- "$line" "$norm_rendered" || { missing=$((missing+1)); log "      LOST: ${line:0:90}"; }
  done < <(normalize_prose "$authored")
  rm -f "$norm_rendered"
  [ "$missing" -eq 0 ]
}

# Tests source this file for the pure helpers above. Everything below performs
# side effects (prerequisite checks, cloning, pushing), so stop here when
# sourced as a library.
if [ -n "${TFDOCS_SWEEP_LIB_ONLY:-}" ]; then
  # `return` when sourced; the `exit` is the fallback when run directly.
  # shellcheck disable=SC2317
  return 0 2>/dev/null || exit 0
fi

# ---- Resolve the template source from this repo, not from a guess ----
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_DIR="${TEMPLATE_DIR:-${REPO_ROOT}/templates/terraform-docs}"
TPL_CONFIG="${TEMPLATE_DIR}/.terraform-docs.yml"
TPL_HOOK="${TEMPLATE_DIR}/.pre-commit-config.yaml"
[ -f "$TPL_CONFIG" ] || die "template not found: $TPL_CONFIG"
[ -f "$TPL_HOOK" ]   || die "template not found: $TPL_HOOK"

# ---- Prerequisites ----
command -v gh     >/dev/null 2>&1 || die "gh is required"
command -v git    >/dev/null 2>&1 || die "git is required"
command -v docker >/dev/null 2>&1 || die "docker is required (pinned terraform-docs container)"
docker info >/dev/null 2>&1 || die "docker is installed but not running"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated"

case "$WORKDIR" in
  /tmp/*|/private/tmp/*)
    die "WORKDIR must not be under /tmp: Docker Desktop mounts it empty, so terraform-docs would silently render nothing" ;;
esac

if [ "$DRY_RUN" != "false" ] && [ "$DRY_RUN" != "true" ]; then
  die "DRY_RUN must be exactly \"true\" or \"false\" (got: ${DRY_RUN})"
fi

if [ "$DRY_RUN" = "false" ]; then
  [ -n "${ACTIONS_PIN:-}" ] || die "ACTIONS_PIN is required when DRY_RUN=false"
  [ -n "${ACTIONS_TAG:-}" ] || die "ACTIONS_TAG is required when DRY_RUN=false"
  case "$ACTIONS_PIN" in
    *[!0-9a-f]*|"") die "ACTIONS_PIN must be a lowercase 40-char hex SHA (got: ${ACTIONS_PIN})" ;;
  esac
  [ "${#ACTIONS_PIN}" -eq 40 ] || die "ACTIONS_PIN must be 40 chars, a full SHA (got ${#ACTIONS_PIN})"
fi

# ---- Target list ----
if [ -n "${REPOS:-}" ]; then
  RAW_REPOS="$REPOS"
elif [ -n "${REPOS_FILE:-}" ]; then
  [ -f "$REPOS_FILE" ] || die "REPOS_FILE not found: ${REPOS_FILE}"
  RAW_REPOS="$(cat "$REPOS_FILE")"
else
  log "Set REPOS or REPOS_FILE to a measured list of repos to migrate."
  log "Code search is not a valid source here (see the header comment)."
  exit 2
fi
mapfile -t REPO_LIST < <(printf '%s' "$RAW_REPOS" | tr '[:space:]' '\n' | grep -v '^$' | sort -u)
(( ${#REPO_LIST[@]} > 0 )) || die "no target repos resolved"

mkdir -p "$WORKDIR"
RESULTS_TSV="${WORKDIR}/results.tsv"
RESULTS_JSON="${WORKDIR}/results.json"
: > "$RESULTS_TSV"

log "terraform-docs standard sweep"
log "  org        ${ORG}"
log "  targets    ${#REPO_LIST[@]}"
log "  dry run    ${DRY_RUN}"
log "  workdir    ${WORKDIR}"
log "  image      ${TFDOCS_IMAGE}"
[ "$DRY_RUN" = "false" ] && log "  pin        ${ACTIONS_PIN} # ${ACTIONS_TAG}"

# outcome <repo> <status> <detail>
outcome() { printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >> "$RESULTS_TSV"; }

# ---------------------------------------------------------------------------
# Patch the caller workflow in place.
#   - re-pin the reusable to the released SHA with a version comment
#   - drop `contents: write` (the workflow no longer writes)
#   - add the three doc paths, but ONLY if a paths: filter already exists.
#     22 of the measured callers have no paths: filter at all, so they already
#     run on every PR; adding a 3-entry list there would NARROW them and stop
#     the check running on .tf changes.
# ---------------------------------------------------------------------------
patch_caller() {
  local f="$1" pin="$2" tag="$3" tmp
  tmp="$(mktemp "${WORKDIR}/caller.XXXXXX")"

  if grep -qE '^ *paths:' "$f"; then
    # Find the last entry of the paths: list, then insert after it, reusing that
    # entry's indentation so the emitted YAML matches the file it lands in.
    local last_entry ind
    last_entry="$(awk '/^ *paths:/{f=1;next} f&&/^ *- /{n=NR} f&&!/^ *- /&&n{exit} END{print n+0}' "$f")"
    [ "$last_entry" -gt 0 ] || { log "      could not locate paths: entries"; rm -f "$tmp"; return 1; }
    ind="$(sed -n "${last_entry}p" "$f" | sed 's/[^ ].*//')"
    {
      sed -n "1,${last_entry}p" "$f"
      printf '%s# README.md is generated from these, so a prose-only or config-only\n' "$ind"
      printf '%s# edit must run the check too. Without them a stale README ships green.\n' "$ind"
      printf '%s- "%s"\n' "$ind" "${DOC_PATHS[0]}"
      printf '%s- "%s"\n' "$ind" "${DOC_PATHS[1]}"
      printf '%s- "%s"\n' "$ind" "${DOC_PATHS[2]}"
      sed -n "$((last_entry+1)),\$p" "$f"
    } > "$tmp"
    mv "$tmp" "$f"
  fi

  # Drop contents: write. The verify-only workflow needs no write access.
  # `pull-requests: write` is left alone; it is not this migration's business.
  sed -i.bak '/^ *contents: *write *$/d' "$f" && rm -f "${f}.bak"

  # Re-pin. Rewrite the whole uses: line so a stale trailing comment cannot
  # survive next to a new SHA.
  sed -i.bak -E \
    "s|(uses: *)${ORG}/Actions/\.github/workflows/org-terraform-docs\.yml@[0-9a-fA-F]+.*|\1${ORG}/Actions/.github/workflows/org-terraform-docs.yml@${pin} # ${tag}|" \
    "$f" && rm -f "${f}.bak"

  grep -q "org-terraform-docs.yml@${pin}" "$f"
}

# ---------------------------------------------------------------------------
# Migrate one repo. Prints its outcome; never exits the whole run.
# ---------------------------------------------------------------------------
migrate_repo() {
  local name="$1" repo="${ORG}/$1" dir="${WORKDIR}/clones/$1"
  local base readme begin_line end_line

  base="$(gh api "repos/${repo}" --jq '.default_branch' 2>/dev/null)" \
    || { outcome "$name" ERROR "cannot resolve default branch"; return; }

  rm -rf "$dir"; mkdir -p "$(dirname "$dir")"
  git clone --quiet --depth 1 --branch "$base" \
    "https://github.com/${repo}.git" "$dir" 2>/dev/null \
    || { outcome "$name" ERROR "clone failed"; return; }

  readme="${dir}/README.md"
  [ -f "$readme" ] || { outcome "$name" SKIP "no root README.md"; return; }

  # ---- Idempotency / already compliant ----
  if [ -f "${dir}/.terraform-docs.yml" ] && [ -f "${dir}/_header.md" ]; then
    outcome "$name" COMPLIANT "config and partials already present"
    return
  fi

  # ---- Marker structure. Refuse anything ambiguous rather than guess. ----
  local nb ne
  nb="$(grep -c "^${BEGIN_MARK}\$" "$readme" || true)"
  ne="$(grep -c "^${END_MARK}\$" "$readme" || true)"
  if [ "$nb" -eq 0 ] && [ "$ne" -eq 0 ]; then
    outcome "$name" SKIP "no generated markers"; return
  fi
  if [ "$nb" -ne 1 ] || [ "$ne" -ne 1 ]; then
    outcome "$name" MANUAL "marker count begin=${nb} end=${ne}, expected 1/1"; return
  fi
  begin_line="$(grep -n "^${BEGIN_MARK}\$" "$readme" | cut -d: -f1)"
  end_line="$(grep -n "^${END_MARK}\$" "$readme" | cut -d: -f1)"
  if [ "$begin_line" -ge "$end_line" ]; then
    outcome "$name" MANUAL "markers reversed (${begin_line} >= ${end_line})"; return
  fi

  # ---- Existing partials must never be silently overwritten ----
  local p
  for p in _header.md _footer.md; do
    if [ -s "${dir}/${p}" ]; then
      outcome "$name" MANUAL "${p} already exists with content"; return
    fi
  done

  [ -f "${dir}/${CALLER}" ] || { outcome "$name" MANUAL "no ${CALLER}"; return; }

  # ---- Split. Header is everything before BEGIN, footer everything after END.
  #      Verified byte-identical against the kms reference implementation. ----
  local authored="${WORKDIR}/authored-${name}.md"
  if [ "$begin_line" -gt 1 ]; then
    sed -n "1,$((begin_line-1))p" "$readme" > "${dir}/_header.md"
  else
    # BEGIN on line 1 means there is no header prose. Do NOT let sed compute the
    # range: BSD sed treats `1,0p` as "print line 1", so on macOS this wrote the
    # BEGIN marker itself into _header.md and the render then emitted an escaped
    # `<!-- BEGIN\_TF\_DOCS -->` inside the generated block. Measured on
    # smarshgov-aws.
    : > "${dir}/_header.md"
  fi
  sed -n "$((end_line+1)),\$p"   "$readme" > "${dir}/_footer.md"

  # Neither partial may contain a generated marker; that would nest the block.
  for p in _header.md _footer.md; do
    if grep -qE "^<!-- (BEGIN|END)_TF_DOCS -->\$" "${dir}/${p}"; then
      outcome "$name" MANUAL "${p} contains a generated marker after the split"; return
    fi
  done
  cat "${dir}/_header.md" "${dir}/_footer.md" > "$authored"

  # Drop the retired `## Tree` section (expected side effect of the split).
  local tree_before tree_after
  tree_before="$(grep -c '^## Tree[[:space:]]*$' "${dir}/_header.md" || true)"
  if [ "$tree_before" -gt 0 ]; then
    strip_tree_section "${dir}/_header.md" > "${dir}/_header.md.new"
    mv "${dir}/_header.md.new" "${dir}/_header.md"
    tree_after="$(grep -c '^## Tree[[:space:]]*$' "${dir}/_header.md" || true)"
    [ "$tree_after" -eq 0 ] || { outcome "$name" MANUAL "Tree section survived the strip"; return; }
    # The stripped Tree section is intentionally gone, so it must not be
    # required to survive the prose check.
    cat "${dir}/_header.md" "${dir}/_footer.md" > "$authored"
  fi

  # ---- Standard files ----
  cp "$TPL_CONFIG" "${dir}/.terraform-docs.yml"
  if [ -e "${dir}/.pre-commit-config.yaml" ]; then
    log "      ${name}: .pre-commit-config.yaml exists, left as is"
  else
    cp "$TPL_HOOK" "${dir}/.pre-commit-config.yaml"
  fi

  # ---- Caller ----
  local pin="${ACTIONS_PIN:-0000000000000000000000000000000000000000}"
  local tag="${ACTIONS_TAG:-DRY_RUN}"
  patch_caller "${dir}/${CALLER}" "$pin" "$tag" \
    || { outcome "$name" MANUAL "caller patch failed"; return; }
  if grep -qE '^ *contents: *write *$' "${dir}/${CALLER}"; then
    outcome "$name" MANUAL "contents: write survived"; return
  fi

  # ---- Render with the pinned container ----
  if ! docker run --rm -v "${dir}:/w" -w /w "$TFDOCS_IMAGE" \
        markdown table -c .terraform-docs.yml . >/dev/null 2>"${WORKDIR}/render-${name}.err"; then
    outcome "$name" ERROR "render failed: $(tr -d '\n' < "${WORKDIR}/render-${name}.err" | tail -c 160)"
    return
  fi

  # ---- The render must have produced exactly one generated block ----
  local rb re
  rb="$(grep -c "^${BEGIN_MARK}\$" "$readme" || true)"
  re="$(grep -c "^${END_MARK}\$" "$readme" || true)"
  if [ "$rb" -ne 1 ] || [ "$re" -ne 1 ]; then
    outcome "$name" ERROR "rendered README has begin=${rb} end=${re}, expected 1/1"; return
  fi

  # ---- Prose preservation. The gate that matters. ----
  if ! prose_preserved "$authored" "$readme"; then
    outcome "$name" MANUAL "authored prose lost in render, repo left unpushed"; return
  fi

  # ---- Nested marker READMEs: report only. ----
  # Measured: 64 of the 65 nested marker READMEs are regenerated by nothing at
  # all (only terraform-google-iap-ingress passes recursive: true). The
  # canonical config sets recursive.enabled: false, so nested dirs get no config
  # and terraform-docs never touches them. Starting to generate them is a
  # separate decision, not this migration's.
  local nested
  nested="$(cd "$dir" && grep -rl --include=README.md "^${BEGIN_MARK}\$" . 2>/dev/null | grep -cv '^\./README.md$' || true)"
  if [ "$nested" -gt 0 ]; then
    log "      ${name}: ${nested} nested marker README(s) left untouched"
    if grep -qE '^ *recursive: *true' "${dir}/${CALLER}"; then
      outcome "$name" MANUAL "caller sets recursive: true and has ${nested} nested README(s); needs nested partials"
      return
    fi
  fi

  # ---- Report or deliver ----
  local changed
  changed="$(cd "$dir" && git status --porcelain | wc -l | tr -d ' ')"
  if [ "$changed" -eq 0 ]; then
    outcome "$name" COMPLIANT "render produced no change"; return
  fi

  if [ "$DRY_RUN" != "false" ]; then
    outcome "$name" WOULD-MIGRATE "${changed} file(s) changed, ${nested} nested untouched"
    return
  fi

  (
    cd "$dir"
    git checkout -q -b "$BRANCH"
    git add -A
    git -c user.name="${GIT_AUTHOR_NAME:-$(gh api user --jq .login)}" \
        -c user.email="${GIT_AUTHOR_EMAIL:-$(gh api user --jq .login)@users.noreply.github.com}" \
        commit -q -F - <<COMMIT
${PR_TITLE}

README.md is now generated in full from _header.md and _footer.md (Azure
Verified Modules TFNFR2). Edit the partials, never README.md. CI verifies and
no longer pushes a commit to the PR branch.

Regenerate locally:

    pre-commit run --all-files

Rendered with ${TFDOCS_IMAGE}. Authored prose was compared line by line before
and after the render; the retired \`## Tree\` section is dropped on purpose.
COMMIT
    git push -q --set-upstream origin "$BRANCH" 2>/dev/null
  ) || { outcome "$name" ERROR "commit or push failed"; return; }

  local existing
  existing="$(gh pr list --repo "$repo" --head "$BRANCH" --state open --json number --jq '.[0].number' 2>/dev/null || true)"
  if [ -n "$existing" ]; then
    outcome "$name" PR-EXISTS "#${existing}"; return
  fi
  local url
  if url="$(gh pr create --repo "$repo" --base "$base" --head "$BRANCH" \
              --title "$PR_TITLE" \
              --body "Migrates this repo onto the org terraform-docs standard (Azure Verified Modules TFNFR2). \`README.md\` is generated in full from \`_header.md\` and \`_footer.md\`; CI verifies instead of pushing to the branch. Rendered with \`${TFDOCS_IMAGE}\`. Authored prose was compared line by line before and after the render. Opened by scripts/terraform-docs-standard-sweep.sh." 2>&1)"; then
    outcome "$name" OPENED "$url"
  else
    outcome "$name" ERROR "pr create failed: $(printf '%s' "$url" | tr -d '\n' | tail -c 160)"
  fi
}

# ---- Run ----
for name in "${REPO_LIST[@]}"; do
  log "  -> ${name}"
  migrate_repo "$name" || outcome "$name" ERROR "unhandled failure"
done

[ "$KEEP_CLONES" = "true" ] || rm -rf "${WORKDIR}/clones"

# ---- Machine-readable results ----
awk -F'\t' 'BEGIN{print "["} {
  gsub(/\\/,"\\\\",$3); gsub(/"/,"\\\"",$3)
  printf "%s  {\"repo\":\"%s\",\"status\":\"%s\",\"detail\":\"%s\"}", (NR>1?",\n":""), $1, $2, $3
} END{print "\n]"}' "$RESULTS_TSV" > "$RESULTS_JSON"

# ---- Reconcile: every target must appear exactly once ----
echo
echo "--- outcomes ---"
awk -F'\t' '{print $2}' "$RESULTS_TSV" | sort | uniq -c | sort -rn
rows="$(wc -l < "$RESULTS_TSV" | tr -d ' ')"
echo "targeted=${#REPO_LIST[@]} recorded=${rows}"
echo "results: ${RESULTS_TSV}"
echo "         ${RESULTS_JSON}"
if [ "$rows" -ne "${#REPO_LIST[@]}" ]; then
  echo "RECONCILE FAIL: recorded ${rows} outcomes for ${#REPO_LIST[@]} targets" >&2
  exit 1
fi
if grep -qE '	(ERROR|MANUAL)	' "$RESULTS_TSV"; then
  echo
  echo "--- needs attention ---"
  grep -E '	(ERROR|MANUAL)	' "$RESULTS_TSV"
fi
