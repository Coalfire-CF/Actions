#!/usr/bin/env bash
#
# fleet-audit.sh — read-only Coalfire-CF Actions fleet classifier.
# Live mode enumerates org repos via gh (GET only). Snapshot mode
# (FLEET_AUDIT_SNAPSHOT) classifies a fixture tree for tests.
#
# Stdout: one JSON object per repo (NDJSON). Logs on stderr.
# Exit 0 for well-formed runs (including SKIP rows). Exit 2 on usage error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/retry-lib.sh
. "${SCRIPT_DIR}/retry-lib.sh"

ORG="${ORG:-Coalfire-CF}"
REPO="${REPO:-}"
AUTOMERGE_APP_ID="${AUTOMERGE_APP_ID:-3436395}"
FLEET_AUDIT_SNAPSHOT="${FLEET_AUDIT_SNAPSHOT:-}"
TF_FETCH_CAP="${TF_FETCH_CAP:-80}"

log() { echo "[fleet-audit] $*" >&2; }

usage_exit() { echo "usage: $*" >&2; exit 2; }

command -v jq >/dev/null || usage_exit "jq is required"

if [ -z "$FLEET_AUDIT_SNAPSHOT" ]; then
  [ -n "${ACTIONS_SHA:-}" ] || usage_exit "ACTIONS_SHA required"
  [ -n "${ACTIONS_VERSION:-}" ] || usage_exit "ACTIONS_VERSION required"
  case "$ACTIONS_SHA" in
    *[!0-9a-fA-F]*|"") usage_exit "ACTIONS_SHA must be 40-hex" ;;
  esac
  [ "${#ACTIONS_SHA}" -eq 40 ] || usage_exit "ACTIONS_SHA must be 40-hex"
fi

# Snapshot mode can omit pins for the unreadable-meta case.
ACTIONS_SHA="${ACTIONS_SHA:-0000000000000000000000000000000000000000}"
ACTIONS_VERSION="${ACTIONS_VERSION:-v0.0.0}"

# shellcheck disable=SC2317,SC2329  # invoked indirectly via `with_retry -- _gh_read_once` (SC2317/SC2329 are the version-dependent codes for the same "unreachable/unused function" false positive)
_gh_read_once() {
  local out rc
  set +e
  out="$(gh "$@" 2>/tmp/fleet-audit-gh.err)"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    if grep -qiE 'rate limit|timeout|502|503|secondary rate' /tmp/fleet-audit-gh.err 2>/dev/null; then
      return "$RETRY_TRANSIENT_RC"
    fi
    return "$rc"
  fi
  printf '%s' "$out"
  return 0
}

gh_read() { with_retry 3 2 20 -- _gh_read_once "$@"; }

ver_norm() { printf '%s' "$1" | sed -E 's/^[vV]//'; }

ver_lt() {
  local a b
  a="$(ver_norm "$1")"
  b="$(ver_norm "$2")"
  [ "$a" = "$b" ] && return 1
  [ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n1)" = "$a" ]
}

tag_name() {
  local raw="$1"
  raw="${raw#refs/tags/}"
  printf '%s' "$raw"
}

is_v_tag() {
  printf '%s' "$(tag_name "$1")" | grep -qE '^v[0-9]'
}

add_finding() {
  jq -n --arg id "$1" --arg severity "$2" --arg detail "$3" \
    '{id:$id,severity:$severity,detail:$detail}' >> "$FINDINGS"
}

add_pin() {
  jq -n --arg file "$1" --arg workflow "$2" --arg ref "$3" \
    --arg version "$4" --arg shape "$5" \
    '{file:$file,workflow:$workflow,ref:$ref,version:$version,shape:$shape}' >> "$PINS"
}

pr_login() {
  jq -r '.author.login // .author // ""' <<<"$1" 2>/dev/null || true
}

pr_label_names() {
  jq -r '[.labels[]? | (.name // .)] | .[]' <<<"$1" 2>/dev/null || true
}

pr_is_dependabot() {
  local login
  login="$(pr_login "$1")"
  case "$login" in
    dependabot|'dependabot[bot]'|'app/dependabot') return 0 ;;
  esac
  return 1
}

pr_is_actions_bump() {
  local pr="$1"
  echo "$pr" | jq -e '
    (.headRefName // "" | test("github_actions";"i"))
    or (.title // "" | test("github-actions|Coalfire-CF/Actions";"i"))
    or ([.files[]? | .path // empty] | any(test("^\\.github/workflows/")))
  ' >/dev/null 2>&1
}

pr_has_label() {
  printf '%s' "$(pr_label_names "$1")" | grep -qxF "$2"
}

scan_source_pins() {
  local tfdir="$1"
  [ -d "$tfdir" ] || return 0
  local file lineno content url ref has_comment
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    lineno=0
    while IFS= read -r content || [ -n "$content" ]; do
      lineno=$((lineno + 1))
      printf '%s' "$content" | grep -qE 'source[[:space:]]*=[[:space:]]*"github\.com/Coalfire-CF/' || continue
      url="$(printf '%s' "$content" | sed -E 's/.*"(github\.com\/Coalfire-CF\/[^"]*)".*/\1/')"
      has_comment=false
      if printf '%s' "$content" | grep -Eq '#[[:space:]]*v[0-9]+\.[0-9]+\.[0-9]+'; then
        has_comment=true
      fi
      if [[ "$url" != *"?ref="* ]]; then
        add_finding source-pin-fail fail "unpinned source (no ?ref=): ${url}"
        continue
      fi
      ref="${url#*\?ref=}"
      ref="${ref%%[/&]*}"
      if [[ "$ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
        if [[ "$has_comment" != "true" ]]; then
          add_finding source-pin-fail fail "bare SHA source without # vX.Y.Z: ${url}"
        fi
      elif [[ "$ref" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        add_finding source-pin-warn warn "tag ref ${ref} on ${url}"
      else
        add_finding source-pin-fail fail "mutable source ref='${ref}': ${url}"
      fi
    done < "$file"
  done < <(find "$tfdir" -type f -name '*.tf' 2>/dev/null || true)
}

classify_snapshot() {
  local dir="$1"
  local repo role exempt status skip_reason has_org_release is_terraform
  local wf workflows_dir meta langs
  FINDINGS="$(mktemp)"
  PINS="$(mktemp)"
  : >"$FINDINGS"
  : >"$PINS"

  emit_and_cleanup() {
    local findings_json pins_json
    findings_json="$(jq -s 'unique_by({id,detail})' "$FINDINGS")"
    pins_json="$(jq -s '.' "$PINS")"
    jq -c -n \
      --arg repo "$repo" \
      --arg role "$role" \
      --argjson exempt "$exempt" \
      --arg status "$status" \
      --arg skip_reason "$skip_reason" \
      --argjson is_terraform "$is_terraform" \
      --argjson has_org_release "$has_org_release" \
      --argjson pins "$pins_json" \
      --argjson findings "$findings_json" \
      '{
        repo:$repo, role:$role, exempt:$exempt, status:$status,
        skip_reason:$skip_reason, is_terraform:$is_terraform,
        has_org_release:$has_org_release, pins:$pins, findings:$findings
      }'
    rm -f "$FINDINGS" "$PINS"
  }

  repo="unknown"
  role="consumer"
  exempt=false
  status="SKIP"
  skip_reason="unreadable"
  has_org_release=false
  is_terraform=false

  meta="${dir}/meta.json"
  if [ ! -f "$meta" ]; then
    emit_and_cleanup
    return 0
  fi

  repo="$(jq -r '.nameWithOwner // .full_name // empty' "$meta")"
  [ -n "$repo" ] || { emit_and_cleanup; return 0; }

  if jq -e '.isArchived == true or .archived == true or .isFork == true or .fork == true' "$meta" >/dev/null 2>&1; then
    skip_reason="infra"
    emit_and_cleanup
    return 0
  fi

  case "$repo" in
    "${ORG}/.github"|"${ORG}/.allstar")
      skip_reason="infra"
      emit_and_cleanup
      return 0
      ;;
  esac

  if [ "$repo" = "${ORG}/Actions" ]; then
    role="producer"
  fi

  if jq -e '[.repositoryTopics[]? | .name] + (.topics // []) | index("bootstrap-exempt") != null' "$meta" >/dev/null 2>&1; then
    exempt=true
  fi

  skip_reason=""
  langs="${dir}/languages.json"
  if [ -f "$langs" ] && jq -e '.HCL != null' "$langs" >/dev/null 2>&1; then
    is_terraform=true
  fi

  workflows_dir="${dir}/workflows"
  if [ -f "${workflows_dir}/org-release.yml" ] || [ -f "${workflows_dir}/org-release.yaml" ]; then
    has_org_release=true
  fi

  local -a pin_shas=() pin_vers=()
  local has_remote_actions=false
  if [ -d "$workflows_dir" ]; then
    while IFS= read -r wf; do
      [ -n "$wf" ] || continue
      local lineno=0 content token ref has_comment workflow shape version
      while IFS= read -r content || [ -n "$content" ]; do
        lineno=$((lineno + 1))
        printf '%s' "$content" | grep -qE '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]' || continue
        printf '%s' "$content" | grep -qE '^[[:space:]]*#' && continue
        token="${content#*uses:}"
        token="$(printf '%s' "$token" | sed -E 's/^[[:space:]]+//')"
        token="${token%%[[:space:]]*}"
        token="${token%\"}"; token="${token#\"}"
        token="${token%\'}"; token="${token#\'}"
        [[ "$token" == ./* || "$token" == ../* ]] && continue
        printf '%s' "$token" | grep -qE 'Coalfire-CF/Actions/\.github/workflows/' || continue
        has_remote_actions=true
        workflow="$(printf '%s' "$token" | sed -E 's#.*\.github/workflows/([^@]+)@.*#\1#')"
        ref="${token##*@}"
        has_comment=false
        version=""
        if printf '%s' "$content" | grep -Eq '#[[:space:]]*v[0-9]+(\.[0-9]+)*'; then
          has_comment=true
          version="$(printf '%s' "$content" | sed -E 's/.*#[[:space:]]*(v[0-9]+(\.[0-9]+)*).*/\1/')"
        fi
        case "$workflow" in
          org-terraform-apply.yml|org-terraform-plan.yml|org-terraform-source-pin.yml|org-terraform-version-band.yml)
            add_finding orphan-caller warn "uses ${workflow}"
            ;;
        esac
        if [[ "$ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
          if [[ "$has_comment" != "true" ]]; then
            shape="sha-no-comment"
            add_finding pin-sha-no-comment fail "${wf##*/}@${ref}"
          else
            shape="sha-comment"
            pin_shas+=("$ref")
            pin_vers+=("$version")
            if [ "$role" != "producer" ]; then
              if [ "$ref" != "$ACTIONS_SHA" ] || ver_lt "$version" "$ACTIONS_VERSION"; then
                add_finding pin-lag fail "${version}@${ref:0:8} vs ${ACTIONS_VERSION}@${ACTIONS_SHA:0:8}"
              fi
            fi
          fi
        elif [[ "$ref" =~ ^v[0-9]+$ ]]; then
          shape="bad-ref"
          add_finding pin-bad-ref fail "${workflow}@${ref}"
        elif [[ "$ref" =~ ^v[0-9]+(\.[0-9]+)+$ ]]; then
          shape="bare-tag"
          add_finding pin-bare-tag warn "${workflow}@${ref}"
        else
          shape="bad-ref"
          add_finding pin-bad-ref fail "${workflow}@${ref}"
        fi
        add_pin ".github/workflows/${wf##*/}" "$workflow" "$ref" "$version" "$shape"
      done < "$wf"
    done < <(find "$workflows_dir" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
  fi

  if [ "$role" != "producer" ] && [ "$has_remote_actions" = false ] && [ "$has_org_release" = false ]; then
    add_finding no-caller fail "no Coalfire-CF/Actions uses: and no org-release.yml"
  fi

  local uniq_shas uniq_vers
  if [ "${#pin_shas[@]}" -gt 1 ]; then
    uniq_shas="$(printf '%s\n' "${pin_shas[@]}" | sort -u | wc -l | tr -d ' ')"
    uniq_vers="$(printf '%s\n' "${pin_vers[@]}" | sort -u | wc -l | tr -d ' ')"
    if [ "$uniq_shas" -gt 1 ] || [ "$uniq_vers" -gt 1 ]; then
      add_finding pin-mixed fail "distinct SHAs=${uniq_shas} versions=${uniq_vers}"
    fi
  fi

  if [ "$has_org_release" = true ] && [ "$role" != "producer" ]; then
    local has_dep_wf=false has_am_wf=false
    if [ -f "${workflows_dir}/org-dependabot.yml" ] || [ -f "${workflows_dir}/org-dependabot.yaml" ]; then
      has_dep_wf=true
    fi
    if [ -f "${workflows_dir}/org-dependabot-auto-merge.yml" ] || [ -f "${workflows_dir}/org-dependabot-auto-merge.yaml" ]; then
      has_am_wf=true
    fi
    if [ "$has_dep_wf" = false ] || [ "$has_am_wf" = false ]; then
      add_finding automerge-missing-caller fail "need org-dependabot.yml and org-dependabot-auto-merge.yml callers"
    fi
    if [ ! -f "${dir}/dependabot.yml" ] || ! grep -qE 'package-ecosystem:[[:space:]]*"?github-actions"?' "${dir}/dependabot.yml"; then
      add_finding dependabot-missing-gha fail "dependabot.yml missing github-actions ecosystem"
    fi
  fi

  local prs="${dir}/prs.json"
  if [ -f "$prs" ]; then
    local pr n labels
    while IFS= read -r pr; do
      [ -n "$pr" ] || continue
      n="$(jq -r '.number' <<<"$pr")"
      if pr_is_dependabot "$pr"; then
        labels="$(pr_label_names "$pr" | tr '\n' ',' | sed 's/,$//')"
        if pr_has_label "$pr" "merge/approved"; then
          add_finding automerge-approved-unmerged fail "PR #${n} labeled merge/approved"
        fi
        if pr_has_label "$pr" "merge/blocked"; then
          add_finding automerge-blocked warn "PR #${n} merge/blocked (${labels})"
        fi
        if pr_is_actions_bump "$pr"; then
          if pr_has_label "$pr" "blocked/terraform-no-tests"; then
            add_finding automerge-tf-block-on-actions fail "PR #${n} github-actions bump labeled blocked/terraform-no-tests"
          fi
          if ! pr_has_label "$pr" "merge/approved" \
            && ! pr_has_label "$pr" "merge/blocked" \
            && ! pr_has_label "$pr" "merge/skipped"; then
            add_finding dependabot-unlabeled fail "PR #${n} has no merge/* label"
          fi
        fi
      fi
      local head
      head="$(jq -r '.headRefName // empty' <<<"$pr")"
      if [[ "$head" == bootstrap/* ]] || pr_has_label "$pr" "bootstrap/proposed"; then
        add_finding bootstrap-pr-open warn "PR #${n} ${head}"
      fi
      if [[ "$head" == release-please--branches--* ]]; then
        add_finding release-please-stale fail "PR #${n} ${head}"
      fi
    done < <(jq -c '.[]' "$prs" 2>/dev/null || true)
  fi

  local rules="${dir}/rulesets.json"
  if [ -f "$rules" ]; then
    if jq -e --argjson app "$AUTOMERGE_APP_ID" '
      [.[] | select((.rules // []) | map(.type) | index("pull_request") != null)
          | select(((.bypass_actors // []) | map(.actor_id) | index($app)) | not)
      ] | length > 0
    ' "$rules" >/dev/null 2>&1; then
      add_finding ruleset-no-bypass fail "repo pull_request ruleset missing automerge app ${AUTOMERGE_APP_ID} bypass"
    fi
  fi

  scan_source_pins "${dir}/tf"

  local tags="${dir}/tags.json"
  local releases="${dir}/releases.json"
  local has_vtag=false has_gh_rel=false
  if [ -f "$tags" ]; then
    local t
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      if is_v_tag "$t"; then has_vtag=true; break; fi
    done < <(jq -r '.[] | (.name // .ref // .)' "$tags" 2>/dev/null || true)
  fi
  if [ -f "$releases" ] && jq -e 'length > 0' "$releases" >/dev/null 2>&1; then
    has_gh_rel=true
  fi
  if [ "$has_org_release" = true ] && [ "$has_vtag" = false ]; then
    add_finding release-no-tags fail "org-release.yml present but no v* git tags"
  fi
  if [ "$has_vtag" = true ] && [ "$has_gh_rel" = false ]; then
    add_finding release-tag-no-github-release warn "v* tags present but no GitHub Releases"
  fi

  if [ "$is_terraform" = true ] && [ "$has_org_release" = true ]; then
    local missing=""
    [ -f "${workflows_dir}/org-terraform-validate.yml" ] || [ -f "${workflows_dir}/org-terraform-validate.yaml" ] || missing="${missing} validate"
    [ -f "${workflows_dir}/org-terraform-fmt.yml" ] || [ -f "${workflows_dir}/org-terraform-fmt.yaml" ] || missing="${missing} fmt"
    [ -f "${workflows_dir}/org-terraform-docs.yml" ] || [ -f "${workflows_dir}/org-terraform-docs.yaml" ] || missing="${missing} docs"
    if [ -n "$missing" ]; then
      add_finding terraform-missing-gates fail "adopted terraform repo missing caller(s):${missing}"
    fi
  fi

  if jq -s -e '[.[] | select(.severity == "fail")] | length > 0' "$FINDINGS" >/dev/null 2>&1; then
    status="FAIL"
  else
    status="PASS"
  fi
  emit_and_cleanup
}

# shellcheck disable=SC2329
fetch_snapshot() {
  local dest="$1" target="$2"
  mkdir -p "$dest/workflows" "$dest/tf"
  local meta
  if ! meta="$(gh_read api "repos/${target}")"; then
    return 1
  fi
  printf '%s' "$meta" | jq '{
    nameWithOwner: .full_name,
    default_branch: (.default_branch // "main"),
    isFork: (.fork // false),
    isArchived: (.archived // false),
    repositoryTopics: [(.topics // [])[] | {name: .}]
  }' > "$dest/meta.json"

  local langs
  if langs="$(gh_read api "repos/${target}/languages")"; then
    printf '%s' "$langs" > "$dest/languages.json"
  else
    echo '{}' > "$dest/languages.json"
  fi

  local listing path b64
  if listing="$(gh_read api "repos/${target}/contents/.github/workflows")"; then
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      printf '%s' "$path" | grep -qE '\.ya?ml$' || continue
      b64="$(gh_read api "repos/${target}/contents/${path}" --jq '.content // empty' || true)"
      [ -n "$b64" ] || continue
      printf '%s' "$b64" | tr -d '\n ' | base64 -d > "$dest/workflows/$(basename "$path")" 2>/dev/null \
        || printf '%s' "$b64" | tr -d '\n ' | base64 --decode > "$dest/workflows/$(basename "$path")"
    done < <(printf '%s' "$listing" | jq -r '.[]? | select(.type=="file") | .path')
  fi

  b64="$(gh_read api "repos/${target}/contents/.github/dependabot.yml" --jq '.content // empty' || true)"
  if [ -n "${b64:-}" ]; then
    printf '%s' "$b64" | tr -d '\n ' | base64 -d > "$dest/dependabot.yml" 2>/dev/null \
      || printf '%s' "$b64" | tr -d '\n ' | base64 --decode > "$dest/dependabot.yml"
  fi

  if jq -e '.HCL != null' "$dest/languages.json" >/dev/null 2>&1; then
    local root
    if root="$(gh_read api "repos/${target}/contents/")"; then
      while IFS= read -r path; do
        [ -n "$path" ] || continue
        b64="$(gh_read api "repos/${target}/contents/${path}" --jq '.content // empty' || true)"
        [ -n "$b64" ] || continue
        printf '%s' "$b64" | tr -d '\n ' | base64 -d > "$dest/tf/$(basename "$path")" 2>/dev/null \
          || printf '%s' "$b64" | tr -d '\n ' | base64 --decode > "$dest/tf/$(basename "$path")"
      done < <(printf '%s' "$root" | jq -r '.[]? | select(.type=="file" and (.name | endswith(".tf"))) | .path' | head -n "$TF_FETCH_CAP")
    fi
  fi

  local prs
  if prs="$(gh_read pr list -R "$target" --state open --limit 100 --json number,title,author,labels,headRefName)"; then
    printf '%s' "$prs" > "$dest/prs.json"
  else
    echo '[]' > "$dest/prs.json"
  fi

  local tags
  if tags="$(gh_read api "repos/${target}/git/matching-refs/tags/v")"; then
    printf '%s' "$tags" | jq '[.[] | {name: .ref}]' > "$dest/tags.json"
  else
    echo '[]' > "$dest/tags.json"
  fi

  local rel
  if rel="$(gh_read api "repos/${target}/releases?per_page=5")"; then
    printf '%s' "$rel" | jq '[.[] | {tagName}]' > "$dest/releases.json" 2>/dev/null || echo '[]' > "$dest/releases.json"
  else
    echo '[]' > "$dest/releases.json"
  fi

  local rules
  if rules="$(gh_read api "repos/${target}/rulesets?includes_parents=false")"; then
    printf '%s' "$rules" > "$dest/rulesets.json"
  else
    echo '[]' > "$dest/rulesets.json"
  fi
  return 0
}

if [ -n "$FLEET_AUDIT_SNAPSHOT" ]; then
  classify_snapshot "$FLEET_AUDIT_SNAPSHOT"
  exit 0
fi

command -v gh >/dev/null || usage_exit "gh is required"

REPOS=""
if [ -n "$REPO" ]; then
  printf '%s' "$REPO" | grep -qE '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || usage_exit "REPO must be owner/name"
  REPOS="$REPO"
else
  # shellcheck disable=SC2317,SC2329  # invoked indirectly via `with_retry -- _list_repos` (SC2317/SC2329 are the version-dependent codes for the same "unreachable/unused function" false positive)
  _list_repos() {
    gh repo list "$ORG" --limit 1000 --no-archived \
      --json nameWithOwner,isFork \
      --jq '.[] | select(.isFork | not) | .nameWithOwner' 2>/dev/null || return "$RETRY_TRANSIENT_RC"
  }
  if ! REPOS="$(with_retry 3 2 20 -- _list_repos)"; then
    log "gh repo list failed after retries"
    exit 1
  fi
  REPOS="$(printf '%s\n' "$REPOS" | grep -vE "^${ORG}/(\.github|\.allstar)$" || true)"
fi

log "org=${ORG} scope=${REPO:-<org>} pin=${ACTIONS_VERSION}@${ACTIONS_SHA}"

rc=0
while IFS= read -r target; do
  [ -n "$target" ] || continue
  log "classify ${target}"
  snap="$(mktemp -d)"
  if ! fetch_snapshot "$snap" "$target"; then
    jq -c -n --arg repo "$target" '{
      repo:$repo, role:"consumer", exempt:false, status:"SKIP",
      skip_reason:"unreadable", is_terraform:false, has_org_release:false,
      pins:[], findings:[]
    }'
    rm -rf "$snap"
    continue
  fi
  classify_snapshot "$snap" || rc=1
  rm -rf "$snap"
done <<< "$REPOS"

exit "$rc"
