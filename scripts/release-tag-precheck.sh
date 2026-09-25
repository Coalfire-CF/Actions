#!/usr/bin/env bash
#
# release-tag-precheck.sh — detect a pre-existing GitHub release/tag before
# release-please publishes, so a hand-cut tag cannot 422 and silently skip the
# clean tarball, cosign bundles, and Trivy/Gitleaks jobs (release-please.yml).
#
# release-please applies `autorelease: tagged` BEFORE it errors on
# already_exists, which wedges that version permanently. This script runs first,
# never calls release-please, and emits skip/collision/supply-chain outputs so
# the workflow can fail loudly, keep labels retryable when no GitHub release
# exists, and still attach signed artifacts when a colliding release points at
# the same commit as this run. A release/tag at a different commit is fail-closed:
# no cosign/scans, so attestations cannot mix two trees.
#
# Inputs (environment):
#   REPO              required — owner/name
#   HEAD_SHA          required — commit this run would tag (github.sha)
#   MANIFEST_PATH     default .release-please-manifest.json
#   CONFIG_PATH       default release-please-config.json
#   APPLY_LABELS      "true" to mutate autorelease labels (default false)
#   RETRY_MAX         transient-read attempts (default 3)
#   GITHUB_OUTPUT     if set, write workflow outputs
#
# Stdout: one verdict line
#   CLEAR tag=<tag>
#   NO_PUBLISH tag=<tag>
#   COLLISION tag=<tag> tag_sha=<sha> head_sha=<sha> release_exists=<bool>
#   UNSTICK tag=<tag> pr=<n>
#
# Exit 0 always (the workflow owns job failure from `collision=true`).
set -euo pipefail

# shellcheck source=scripts/retry-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/retry-lib.sh"

REPO="${REPO:?REPO required (owner/name)}"
HEAD_SHA="${HEAD_SHA:?HEAD_SHA required}"
MANIFEST_PATH="${MANIFEST_PATH:-.release-please-manifest.json}"
CONFIG_PATH="${CONFIG_PATH:-release-please-config.json}"
APPLY_LABELS="${APPLY_LABELS:-false}"
RETRY_MAX="${RETRY_MAX:-3}"

log() { echo "[release-tag-precheck] $*" >&2; }

# shellcheck disable=SC2317,SC2329
_gh_once() {
  local o err rc=0
  err="$(mktemp)"
  o="$(gh "$@" 2>"$err")" || rc=$?
  if [ "$rc" -eq 0 ]; then
    rm -f "$err"
    printf '%s' "$o"
    return 0
  fi
  if grep -qiE 'HTTP (429|5[0-9][0-9])|rate limit|timeout|timed out|temporar|connection reset|connection refused|no such host|i/o timeout|EOF' "$err"; then
    rm -f "$err"; return "$RETRY_TRANSIENT_RC"
  fi
  rm -f "$err"; return "$rc"
}
gh_read() { with_retry "$RETRY_MAX" 2 20 -- _gh_once "$@"; }

# Read decoded file content at HEAD_SHA; empty if missing.
read_file_at() {
  gh_read api "repos/${REPO}/contents/${1}?ref=${2}" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || true
}

write_output() {
  local k="$1" v="$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n' "$k" "$v" >> "$GITHUB_OUTPUT"
  fi
}

# Peel annotated tags to the commit SHA; pass through commit tags.
peel_tag_sha() {
  local ref_json="$1" obj_type obj_sha peeled
  obj_type="$(printf '%s' "$ref_json" | jq -r '.object.type // empty')"
  obj_sha="$(printf '%s' "$ref_json" | jq -r '.object.sha // empty')"
  if [ "$obj_type" = "tag" ] && [ -n "$obj_sha" ]; then
    peeled="$(gh_read api "repos/${REPO}/git/tags/${obj_sha}" --jq '.object.sha' 2>/dev/null || true)"
    if [ -n "$peeled" ]; then
      printf '%s' "$peeled"
      return 0
    fi
  fi
  printf '%s' "$obj_sha"
}

include_v_in_tag() {
  local cfg="$1"
  if [ -z "$cfg" ]; then
    echo true
    return
  fi
  printf '%s' "$cfg" | jq -r '
    if (.packages["."] | type == "object") and (.packages["."] | has("include-v-in-tag")) then
      .packages["."]["include-v-in-tag"]
    elif has("include-v-in-tag") then
      .["include-v-in-tag"]
    else
      true
    end
    | if . == false then "false" else "true" end
  '
}

version_from_manifest() {
  local mf="$1"
  [ -n "$mf" ] || return 0
  printf '%s' "$mf" | jq -r 'if type == "object" then (.[ "." ] // to_entries[0].value // empty) else empty end'
}

tag_for_version() {
  local version="$1" include_v="$2"
  version="${version#v}"
  if [ "$include_v" = "false" ]; then
    printf '%s' "$version"
  else
    printf 'v%s' "$version"
  fi
}

version_from_title() {
  printf '%s' "$1" | sed -nE 's/.*release[[:space:]]+v?([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n1
}

# release-please publish subjects always include a semver (e.g. "chore(main):
# release 4.4.0"). A bare "chore: release notes" must not count as a publish.
is_release_title() {
  printf '%s' "$1" | grep -qiE '^chore(\([^)]+\))?(!)?:[[:space:]]+release[[:space:]]+v?[0-9]+\.[0-9]+\.[0-9]+'
}

apply_labels() {
  local pr="$1" add="$2" remove="$3"
  [ "$APPLY_LABELS" = "true" ] || return 0
  [ -n "$pr" ] || return 0
  if [ -n "$add" ]; then
    printf '{"labels":["%s"]}' "$add" | gh api -X POST "repos/${REPO}/issues/${pr}/labels" --input - >/dev/null 2>&1 \
      || log "failed to add label '${add}' on #${pr} (non-fatal)"
  fi
  if [ -n "$remove" ]; then
    # Label names contain ":" and a space — percent-encode.
    local enc
    enc="$(printf '%s' "$remove" | sed 's/ /%20/g; s/:/%3A/g')"
    gh api -X DELETE "repos/${REPO}/issues/${pr}/labels/${enc}" >/dev/null 2>&1 || log "failed to remove label '${remove}' on #${pr} (non-fatal)"
  fi
}

emit() {
  local verdict="$1"
  shift
  printf '%s' "$verdict"
  if [ "$#" -gt 0 ]; then printf ' %s' "$@"; fi
  printf '\n'
}

# ---- resolve intended tag from the manifest at HEAD ----
manifest="$(read_file_at "$MANIFEST_PATH" "$HEAD_SHA")"
config="$(read_file_at "$CONFIG_PATH" "$HEAD_SHA")"
include_v="$(include_v_in_tag "$config")"
version="$(version_from_manifest "$manifest")"
tag=""
if [ -n "$version" ]; then
  tag="$(tag_for_version "$version" "$include_v")"
fi

tag_exists=false
release_exists=false
tag_sha=""
tag_ref_json=""
if [ -n "$tag" ]; then
  if tag_ref_json="$(gh_read api "repos/${REPO}/git/ref/tags/${tag}" 2>/dev/null)"; then
    tag_exists=true
    tag_sha="$(peel_tag_sha "$tag_ref_json")"
  fi
  if gh_read api "repos/${REPO}/releases/tags/${tag}" --jq '.id' >/dev/null 2>&1; then
    release_exists=true
  fi
fi

# ---- is this run a release-please publish attempt? ----
commit_json="$(gh_read api "repos/${REPO}/commits/${HEAD_SHA}" --jq '{message: .commit.message}' 2>/dev/null || true)"
commit_subject="$(printf '%s' "$commit_json" | jq -r '.message // empty' | head -n1)"
publish_attempt=false
pr_number=""

if is_release_title "$commit_subject"; then
  publish_attempt=true
fi

pulls="$(gh_read api "repos/${REPO}/commits/${HEAD_SHA}/pulls" --jq '.' 2>/dev/null || echo '[]')"
# First matching associated PR wins for label repair.
pr_number="$(printf '%s' "$pulls" | jq -r '
  [.[] | select(
    ((.title // "") | test("^chore(\\([^)]+\\))?(!)?:[[:space:]]+release[[:space:]]+v?[0-9]+\\.[0-9]+\\.[0-9]+"; "i"))
    or ([.labels[]?.name] | any(. == "autorelease: pending" or . == "autorelease: tagged"))
  ) | .number] | first // empty
')"
if [ -n "$pr_number" ]; then
  publish_attempt=true
fi
if printf '%s' "$pulls" | jq -e '
  [.[] | .labels[]?.name] | any(. == "autorelease: pending" or . == "autorelease: tagged")
' >/dev/null 2>&1; then
  publish_attempt=true
fi

# Stuck merged PR still labelled pending (a prior 422, or a hand-cut tag while
# the label was never cleared). Any later push would otherwise re-enter
# release-please and 422 again.
stuck_pr=""
stuck_title=""
if [ "$publish_attempt" != "true" ]; then
  pending_json="$(gh pr list --repo "$REPO" --state merged --label "autorelease: pending" --limit 20 --json number,title 2>/dev/null || echo '[]')"
  stuck_pr="$(printf '%s' "$pending_json" | jq -r '.[0].number // empty')"
  stuck_title="$(printf '%s' "$pending_json" | jq -r '.[0].title // empty')"
  if [ -n "$stuck_pr" ]; then
    stuck_ver="$(version_from_title "$stuck_title")"
    if [ -n "$stuck_ver" ] && [ -z "$tag" ]; then
      tag="$(tag_for_version "$stuck_ver" "$include_v")"
      if tag_ref_json="$(gh_read api "repos/${REPO}/git/ref/tags/${tag}" 2>/dev/null)"; then
        tag_exists=true
        tag_sha="$(peel_tag_sha "$tag_ref_json")"
      fi
      if gh_read api "repos/${REPO}/releases/tags/${tag}" --jq '.id' >/dev/null 2>&1; then
        release_exists=true
      fi
    fi
  fi
fi

# ---- defaults ----
skip_release_please=false
collision=false
supply_chain=false
verdict="CLEAR"

# No intended version — let release-please surface its own config error.
if [ -z "$tag" ]; then
  write_output skip_release_please false
  write_output collision false
  write_output supply_chain false
  write_output tag_name ""
  write_output tag_sha ""
  write_output head_sha "$HEAD_SHA"
  write_output tag_exists false
  write_output release_exists false
  write_output pr_number ""
  write_output verdict CLEAR
  emit CLEAR
  exit 0
fi

if [ "$publish_attempt" = "true" ] && [ "$release_exists" = "true" ]; then
  # The 422 case: GitHub Release already exists for this version.
  skip_release_please=true
  collision=true
  verdict=COLLISION
  # Cosign signs the tag tree; Trivy/Gitleaks check out github.sha. Only attach
  # artifacts when those are the same commit — otherwise a hand-cut tag at a
  # different SHA would mix two trees on one release.
  if [ -n "$tag_sha" ] && [ "$tag_sha" = "$HEAD_SHA" ]; then
    supply_chain=true
  else
    supply_chain=false
  fi
  # Unstick so later versions can proceed; the published release is real.
  apply_labels "${pr_number}" "autorelease: tagged" "autorelease: pending"
elif [ "$publish_attempt" = "true" ] && [ "$tag_exists" = "true" ] && [ "$tag_sha" != "$HEAD_SHA" ]; then
  # Tag points at a different commit. Creating a GitHub Release would attach
  # to the wrong tree. Fail closed and do not run release-please.
  skip_release_please=true
  collision=true
  supply_chain=false
  verdict=COLLISION
  # No GitHub Release yet — keep pending so deleting the tag self-heals.
  apply_labels "${pr_number}" "autorelease: pending" "autorelease: tagged"
elif [ "$publish_attempt" != "true" ] && [ -n "$stuck_pr" ] && [ "$release_exists" = "true" ]; then
  skip_release_please=true
  collision=false
  supply_chain=false
  verdict=UNSTICK
  pr_number="$stuck_pr"
  apply_labels "$stuck_pr" "autorelease: tagged" "autorelease: pending"
elif [ "$publish_attempt" != "true" ] && [ -n "$stuck_pr" ] && [ "$tag_exists" = "true" ] && [ "$release_exists" != "true" ]; then
  # Tag-only wedge on a later push: skip release-please so it cannot 422 if a
  # Release is also created later, keep pending, do not fail every push.
  skip_release_please=true
  collision=false
  supply_chain=false
  verdict=UNSTICK
  pr_number="$stuck_pr"
else
  if [ "$publish_attempt" = "true" ]; then
    verdict=CLEAR
  else
    verdict=NO_PUBLISH
  fi
fi

write_output skip_release_please "$skip_release_please"
write_output collision "$collision"
write_output supply_chain "$supply_chain"
write_output tag_name "$tag"
write_output tag_sha "$tag_sha"
write_output head_sha "$HEAD_SHA"
write_output tag_exists "$tag_exists"
write_output release_exists "$release_exists"
write_output pr_number "${pr_number}"
write_output verdict "$verdict"

if [ "$verdict" = "COLLISION" ]; then
  short_tag="${tag_sha:0:12}"
  short_head="${HEAD_SHA:0:12}"
  msg="Tag ${tag} already exists at ${short_tag:-unknown} but this run would have tagged ${short_head}."
  msg="${msg} GitHub Release exists: ${release_exists}."
  msg="${msg} Skipping release-please (avoids 422 already_exists and autorelease: tagged-then-error)."
  if [ "$supply_chain" = "true" ]; then
    msg="${msg} Clean tarball, cosign, Trivy, and Gitleaks will still run against ${tag} (tag commit matches this run)."
  elif [ "$release_exists" = "true" ]; then
    msg="${msg} GitHub Release ${tag} points at a different commit than this run — supply-chain jobs will NOT run (cosign would sign the tag tree while scans would see HEAD). Retarget or delete the tag/release, then retry."
  else
    msg="${msg} No GitHub Release for ${tag} — supply-chain jobs cannot attach assets. Delete the tag (and retry) or create a release for it."
  fi
  echo "::error title=Duplicate release tag::${msg}" >&2
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "## Duplicate release tag"
      echo
      echo "| | |"
      echo "| --- | --- |"
      echo "| Tag | \`${tag}\` |"
      echo "| Existing tag commit | \`${tag_sha:-unknown}\` |"
      echo "| Commit this run would tag | \`${HEAD_SHA}\` |"
      echo "| GitHub Release exists | \`${release_exists}\` |"
      echo "| Supply-chain jobs | \`${supply_chain}\` |"
      echo "| Associated PR | \`${pr_number:-none}\` |"
      echo
      echo "A tag/release created outside release-please collided with the version"
      echo "release-please is about to cut. release-please was **not** invoked,"
      echo "so it cannot apply \`autorelease: tagged\` and then 422."
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  emit COLLISION "tag=${tag}" "tag_sha=${tag_sha:-unknown}" "head_sha=${HEAD_SHA}" "release_exists=${release_exists}"
elif [ "$verdict" = "UNSTICK" ]; then
  echo "::warning title=Stuck release-please PR::Merged PR #${pr_number} is still labelled autorelease: pending while ${tag} already exists. Skipping release-please so later commits cannot 422." >&2
  emit UNSTICK "tag=${tag}" "pr=${pr_number}"
elif [ "$verdict" = "NO_PUBLISH" ]; then
  emit NO_PUBLISH "tag=${tag}"
else
  emit CLEAR "tag=${tag}"
fi
