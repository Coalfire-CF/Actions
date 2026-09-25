#!/usr/bin/env bash
#
# workflow-rename-sweep.sh: move fleet callers off the pre-1.0 org-*.yml
# reusable workflows onto the v1.0.0 names (docs/PIPELINE_NAMING.md).
#
# Modes (MODE=):
#   discover  Walk every non-archived repo in ORG through the contents API and
#             print "<repo>\t<workflow file>" for each workflow whose content
#             calls Coalfire-CF/Actions/.github/workflows/org-*. Code search is
#             not used: it undercounts on this fleet. Prints a scanned/matched
#             count to stderr and fails if nothing was scanned.
#   rewrite   Rewrite one local checkout in TARGET_DIR. No network.
#   apply     For each repo in REPOS_FILE (discover output, or one repo name
#             per line): clone, rewrite, and with DRY_RUN=false push BRANCH
#             and open a PR. DRY_RUN=true (default) prints the diff stat only.
#
# Rewrite rules, per workflow file that calls an org-* reusable:
#   - uses: .../org-<x>.yml@<ref> becomes .../<new>.yml@ACTIONS_PIN # ACTIONS_TAG
#   - actions_ref: <sha> in that file is set to ACTIONS_PIN # ACTIONS_TAG
#   - a caller named after its old bootstrap template (org-release.yml, ...)
#     is renamed to the new template name and gets the template's name:
#   - caller job ids are left alone; they are part of check names
#
# Env:
#   ORG          default Coalfire-CF
#   ACTIONS_PIN  40-hex SHA of the v1.0.0+ release   (rewrite, apply)
#   ACTIONS_TAG  its version, e.g. v1.0.0            (rewrite, apply)
#   TARGET_DIR   checkout to rewrite                  (rewrite)
#   REPOS_FILE   repo list                            (apply)
#   DRY_RUN      true (default) or false              (apply)
#   BRANCH       default chore/actions-v1-workflow-names
#   WORKDIR      default $HOME/.cache/workflow-rename-sweep
#
set -euo pipefail

ORG="${ORG:-Coalfire-CF}"
MODE="${MODE:?MODE required: discover | rewrite | apply}"
DRY_RUN="${DRY_RUN:-true}"
BRANCH="${BRANCH:-chore/actions-v1-workflow-names}"
WORKDIR="${WORKDIR:-$HOME/.cache/workflow-rename-sweep}"
PR_TITLE="${PR_TITLE:-ci: move Actions callers to the v1.0.0 workflow names}"
# Commit identity: the operator's git config when set, else a bot identity, so
# a runner with no global identity can still commit.
GIT_USER_NAME="${GIT_USER_NAME:-$(git config user.name 2>/dev/null || echo "coalfire-workflow-rename-sweep")}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-$(git config user.email 2>/dev/null || echo "workflow-rename-sweep@users.noreply.github.com")}"

log() { echo "[workflow-rename-sweep] $*" >&2; }
die() { log "FATAL: $*"; exit 2; }

# Old reusable stem -> new reusable stem.
new_reusable() {
  case "$1" in
    org-caliper) echo ci-security-caliper ;;
    org-dependabot-auto-merge) echo automation-dependabot-auto-merge ;;
    org-dependabot-reconcile) echo automation-dependabot-reconcile ;;
    org-dependabot) echo automation-dependabot-refresh ;;
    org-gitleaks-pr) echo ci-security-gitleaks ;;
    org-gitleaks-release) echo release-security-gitleaks ;;
    org-jira-sync) echo automation-jira-sync ;;
    org-label-sync) echo automation-label-sync ;;
    org-markdown-lint) echo ci-markdown ;;
    org-opa) echo ci-policy-opa ;;
    org-release-clean) echo release-clean-archive ;;
    org-release) echo release-please ;;
    org-repo-bootstrap) echo automation-repo-bootstrap ;;
    org-slack-notify) echo automation-slack-notify ;;
    org-terraform-apply) echo deploy-terraform-apply ;;
    org-terraform-docs) echo ci-terraform-docs ;;
    org-terraform-fmt) echo ci-terraform-format ;;
    org-terraform-plan) echo deploy-terraform-plan ;;
    org-terraform-source-pin) echo ci-terraform-source-pin ;;
    org-terraform-validate) echo ci-terraform-validate ;;
    org-terraform-version-band) echo ci-terraform-version-band ;;
    org-terraform-version-check) echo automation-terraform-version-check ;;
    org-terratest) echo ci-terratest ;;
    org-trivy-exception-review) echo automation-trivy-exception-review ;;
    # org-trivy.yml never existed upstream; a few callers point at it and fail.
    org-trivy-pr|org-trivy) echo ci-security-trivy ;;
    org-trivy-release) echo release-security-trivy ;;
    *) echo "" ;;
  esac
}

# Old bootstrap caller filename -> "<new filename>|<caller name:>".
new_caller() {
  case "$1" in
    org-release.yml) echo 'release-please.yml|Release: Release Please' ;;
    org-dependabot-auto-merge.yml) echo 'automation-dependabot-auto-merge.yml|Automation: Dependabot auto-merge' ;;
    org-dependabot.yml) echo 'automation-dependabot-refresh.yml|Automation: Dependabot refresh' ;;
    org-gitleaks-pr.yml|org-gitleaks.yml) echo 'ci-security-gitleaks.yml|CI: Security Gitleaks' ;;
    org-trivy-pr.yml|org-trivy.yml) echo 'ci-security-trivy.yml|CI: Security Trivy' ;;
    org-terratest.yml) echo 'ci-terratest.yml|CI: Terratest' ;;
    org-md-lint.yml|org-markdown-lint.yml) echo 'ci-markdown.yml|CI: Markdown' ;;
    org-terraform-docs.yml) echo 'ci-terraform-docs.yml|CI: Terraform docs' ;;
    org-terraform-fmt.yml) echo 'ci-terraform-format.yml|CI: Terraform format' ;;
    org-terraform-validate.yml) echo 'ci-terraform-validate.yml|CI: Terraform validate' ;;
    *) echo "" ;;
  esac
}

USES_RE='Coalfire-CF/Actions/\.github/workflows/org-[a-z-]+\.ya?ml@'

# rewrite_file <path>: rewrite uses: and actions_ref: lines in place.
rewrite_file() {
  local f="$1" stem new
  while IFS= read -r stem; do
    new="$(new_reusable "$stem")"
    [ -n "$new" ] || die "$f: no mapping for ${stem}.yml"
    # Path, ref and any trailing "# vX" comment are replaced together.
    OLD="$stem" NEW="$new" PIN="$ACTIONS_PIN" TAG="$ACTIONS_TAG" perl -pi -e \
      'next if /^\s*#/; s{(Coalfire-CF/Actions/\.github/workflows/)\Q$ENV{OLD}\E\.ya?ml\@[A-Za-z0-9._/-]+(?:[ \t]*#.*)?}{$1$ENV{NEW}.yml\@$ENV{PIN} # $ENV{TAG}}g' \
      "$f"
  done < <(grep -vE '^[[:space:]]*#' "$f" | grep -oE "${USES_RE}" | sed -E 's#.*/(org-[a-z-]+)\.ya?ml@#\1#' | sort -u)
  PIN="$ACTIONS_PIN" TAG="$ACTIONS_TAG" perl -pi -e \
    's{^(\s*actions_ref:\s*)[0-9a-fA-F]{40}.*}{$1$ENV{PIN} # $ENV{TAG}}' "$f"
}

# add_actions_ref <path>: insert "actions_ref: PIN # TAG" for the auto-merge
# uses: line, under its existing with: block or in a new one.
add_actions_ref() {
  PIN="$ACTIONS_PIN" TAG="$ACTIONS_TAG" perl -0pi -e '
    s{^([ \t]+)(uses:[ \t]*Coalfire-CF/Actions/\.github/workflows/automation-dependabot-auto-merge\.yml\@[^\n]*\n)(\1with:[ \t]*\n)?}{
      my ($ind, $uses, $with) = ($1, $2, $3);
      "$ind$uses$ind" . "with:\n$ind  actions_ref: $ENV{PIN} # $ENV{TAG}\n"
    }me' "$1"
}

# rewrite_dir <checkout>: rewrite every matching caller. Prints one line per
# file changed. Returns 3 when nothing matched.
rewrite_dir() {
  local dir="$1" wf="$1/.github/workflows" f base nc target title changed=0
  [ -d "$wf" ] || return 3
  for f in "$wf"/*.yml "$wf"/*.yaml; do
    [ -f "$f" ] || continue
    grep -qE "^[^#]*${USES_RE}" "$f" || continue
    rewrite_file "$f"
    base="$(basename "$f")"
    nc="$(new_caller "$base")"
    if [ -n "$nc" ]; then
      target="${nc%%|*}"; title="${nc#*|}"
      if [ -e "$wf/$target" ]; then
        log "WARN ${base}: ${target} already exists, kept the old filename"
        echo "rewrote ${base}"
      else
        TITLE="$title" perl -pi -e 'if (!$done && s{^name:.*}{name: "$ENV{TITLE}"}) { $done = 1 }' "$f"
        if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
          git -C "$dir" mv ".github/workflows/${base}" ".github/workflows/${target}"
        else
          mv "$f" "$wf/$target"
        fi
        echo "renamed ${base} -> ${target}"
      fi
    else
      echo "rewrote ${base}"
    fi
    changed=$((changed + 1))
  done
  # The auto-merge reusable requires actions_ref (since v0.18.2). Callers
  # bootstrapped earlier lack it, so add it next to the rewritten uses: line.
  for f in "$wf"/*.yml "$wf"/*.yaml; do
    [ -f "$f" ] || continue
    if grep -q 'workflows/automation-dependabot-auto-merge\.yml@' "$f" && ! grep -q 'actions_ref:' "$f"; then
      add_actions_ref "$f"
      grep -q "actions_ref: ${ACTIONS_PIN}" "$f" || die "$(basename "$f"): could not add actions_ref"
      echo "added actions_ref to $(basename "$f")"
    fi
  done
  [ "$changed" -gt 0 ] || return 3
}

discover() {
  local repos scanned=0 matched=0 repo files f content errf
  errf="$(mktemp)"
  repos="$(gh repo list "$ORG" --no-archived --limit 5000 --json name --jq '.[].name')" \
    || die "gh repo list failed"
  [ -n "$repos" ] || die "gh repo list returned no repos"
  while IFS= read -r repo; do
    scanned=$((scanned + 1))
    # gh api prints error bodies on stdout; never parse stdout on failure.
    if ! files="$(gh api "repos/${ORG}/${repo}/contents/.github/workflows" 2>"$errf")"; then
      grep -q 'HTTP 404' "$errf" && continue
      die "${repo}: listing workflows failed: $(tail -n1 "$errf")"
    fi
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      content="$(gh api -H 'Accept: application/vnd.github.raw' \
        "repos/${ORG}/${repo}/contents/.github/workflows/${f}" 2>"$errf")" \
        || die "${repo}/${f}: read failed: $(tail -n1 "$errf")"
      if grep -qE "^[^#]*${USES_RE}" <<< "$content"; then
        printf '%s\t%s\n' "$repo" "$f"
        matched=$((matched + 1))
      fi
    done < <(jq -r '.[] | select(.type == "file") | .name | select(test("\\.ya?ml$"))' <<< "$files")
  done <<< "$repos"
  rm -f "$errf"
  [ "$scanned" -gt 0 ] || die "scanned 0 repos"
  log "scanned ${scanned} repo(s); ${matched} caller file(s) still on org-* names"
}

require_pin() {
  [[ "${ACTIONS_PIN:-}" =~ ^[0-9a-f]{40}$ ]] || die "ACTIONS_PIN must be a 40-hex SHA"
  [[ "${ACTIONS_TAG:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "ACTIONS_TAG must look like v1.0.0"
}

apply() {
  local repos repo dir out opened=0 skipped=0 planned=0 failed=0 url
  [ -f "${REPOS_FILE:-}" ] || die "REPOS_FILE required"
  repos="$(cut -f1 "$REPOS_FILE" | grep -v '^[[:space:]]*$' | sort -u)"
  [ -n "$repos" ] || die "REPOS_FILE has no repos"
  mkdir -p "$WORKDIR"
  while IFS= read -r repo; do
    [ "$repo" = "Actions" ] && { log "SKIP ${repo} (source repo)"; skipped=$((skipped + 1)); continue; }
    dir="${WORKDIR}/${repo}"
    rm -rf "$dir"
    if ! gh repo clone "${ORG}/${repo}" "$dir" -- --depth 1 -q 2>/dev/null; then
      log "FAIL ${repo}: clone"; failed=$((failed + 1)); continue
    fi
    set +e; out="$(rewrite_dir "$dir")"; rc=$?; set -e
    if [ "$rc" -eq 3 ]; then log "SKIP ${repo} (nothing to rewrite)"; skipped=$((skipped + 1)); continue; fi
    [ "$rc" -eq 0 ] || { log "FAIL ${repo}: rewrite rc=${rc}"; failed=$((failed + 1)); continue; }
    git -C "$dir" add -A .github/workflows
    if [ "$DRY_RUN" != "false" ]; then
      log "PLAN ${repo}: $(tr '\n' ';' <<< "$out")"
      planned=$((planned + 1)); continue
    fi
    # A failure here must fail this repo only, not stop the sweep (set -e).
    if ! git -C "$dir" checkout -q -b "$BRANCH" \
       || ! git -C "$dir" -c user.name="${GIT_USER_NAME}" -c user.email="${GIT_USER_EMAIL}" commit -q -m "$PR_TITLE" \
            -m "Coalfire-CF/Actions v1.0.0 renamed its reusable workflows. Moves callers to the new paths, pinned to ${ACTIONS_TAG}. See docs/PIPELINE_NAMING.md in Coalfire-CF/Actions."; then
      log "FAIL ${repo}: branch or commit"; failed=$((failed + 1)); continue
    fi
    if ! git -C "$dir" push -q -u origin "$BRANCH" 2>/dev/null; then
      log "FAIL ${repo}: push"; failed=$((failed + 1)); continue
    fi
    if url="$(gh pr create -R "${ORG}/${repo}" --head "$BRANCH" --title "$PR_TITLE" \
        --body "Coalfire-CF/Actions ${ACTIONS_TAG} renamed its reusable workflows. This moves the callers to the new paths and pins them to \`${ACTIONS_PIN}\`. Rename table: Coalfire-CF/Actions docs/PIPELINE_NAMING.md. Opened by scripts/workflow-rename-sweep.sh." 2>&1)"; then
      echo "${repo}	${url}"; opened=$((opened + 1))
    else
      log "FAIL ${repo}: pr create: ${url}"; failed=$((failed + 1))
    fi
  done <<< "$repos"
  log "targeted $(wc -l <<< "$repos" | tr -d ' '): opened=${opened} planned=${planned} skipped=${skipped} failed=${failed}"
  [ "$failed" -eq 0 ]
}

case "$MODE" in
  discover) discover ;;
  rewrite) require_pin; [ -d "${TARGET_DIR:-}" ] || die "TARGET_DIR required"; rewrite_dir "$TARGET_DIR" ;;
  apply) require_pin; apply ;;
  *) die "unknown MODE ${MODE}" ;;
esac
