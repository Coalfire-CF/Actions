#!/usr/bin/env bash
#
# Publish the draft GitHub Release that release-please created, after the
# release-clean / Trivy / Gitleaks jobs have attached their assets.
#
# Immutable releases reject asset uploads once published (HTTP 422), so the
# release must be a draft while assets upload and published last. That needs
# "draft": true and "force-tag-creation": true in the consumer's
# release-please-config.json (the tag must exist before the draft is published
# so release-please can find the last release).
#
# Env:
#   REPO           owner/name (required)
#   TAG_NAME       release tag (required)
#   CLEAN_RESULT   result of the release-clean job: success | failure | skipped | cancelled
#   REQUIRE_ASSET  asset name suffix that must be attached before publishing
#                  (for example "-clean.tar.gz"); empty skips the check
#
# Exit codes: 0 published, or nothing to do (release already published);
#             1 release missing, release-clean failed, or required asset missing.

set -euo pipefail

: "${REPO:?REPO (owner/name) is required}"
: "${TAG_NAME:?TAG_NAME is required}"
CLEAN_RESULT="${CLEAN_RESULT:-skipped}"
REQUIRE_ASSET="${REQUIRE_ASSET:-}"

# releases/tags/{tag} does not return drafts, so list and filter.
matches="$(gh api --paginate --slurp "repos/${REPO}/releases?per_page=100" |
  jq -c --arg tag "$TAG_NAME" '[.[][] | select(.tag_name == $tag)]')"

count="$(jq 'length' <<< "$matches")"
if [ "$count" -eq 0 ]; then
  echo "::error::No GitHub Release found for ${TAG_NAME} in ${REPO}."
  exit 1
fi
if [ "$count" -gt 1 ]; then
  echo "::error::${count} releases share tag ${TAG_NAME} in ${REPO}; resolve by hand."
  exit 1
fi

release="$(jq -c '.[0]' <<< "$matches")"
is_draft="$(jq -r '.draft' <<< "$release")"
if [ "$is_draft" != "true" ]; then
  immutable="$(jq -r '.immutable // false' <<< "$release")"
  assets="$(jq '.assets | length' <<< "$release")"
  echo "::warning::${TAG_NAME} is already published (immutable=${immutable}, assets=${assets}). Set \"draft\": true and \"force-tag-creation\": true in release-please-config.json so assets upload before publish."
  exit 0
fi

if [ "$CLEAN_RESULT" = "failure" ] || [ "$CLEAN_RESULT" = "cancelled" ]; then
  echo "::error::release-clean ${CLEAN_RESULT}; leaving ${TAG_NAME} as a draft. Re-run the failed jobs, then this one."
  exit 1
fi

if [ -n "$REQUIRE_ASSET" ]; then
  found="$(jq --arg sfx "$REQUIRE_ASSET" '[.assets[].name | select(endswith($sfx))] | length' <<< "$release")"
  if [ "$found" -eq 0 ]; then
    echo "::error::${TAG_NAME} has no asset ending in ${REQUIRE_ASSET}; leaving it as a draft."
    exit 1
  fi
fi

gh release edit "$TAG_NAME" --repo "$REPO" --draft=false --latest >/dev/null

release_id="$(jq -r '.id' <<< "$release")"
if [ "$(gh api "repos/${REPO}/releases/${release_id}" --jq '.draft')" != "false" ]; then
  echo "::error::${TAG_NAME} is still a draft after publish."
  exit 1
fi
echo "Published ${TAG_NAME} ($(jq '.assets | length' <<< "$release") assets)."
