#!/usr/bin/env bash
# shellcheck disable=SC2001,SC2129
#
# breaking-change-check.sh — semver + release-note (Bedrock) breaking-change
# analysis for the Dependabot auto-merge workflow
# (.github/workflows/org-dependabot-auto-merge.yml, job: breaking_change_check).
#
# EXTRACTED VERBATIM (grade-A plan #10) from the former inline
# `/tmp/breaking_change_check.sh` heredoc so the logic is committed,
# unit-testable, and shellcheck-covered. The emitted decision is byte-identical
# to that inline heredoc — pure refactor, no behavior change. The disabled codes
# are pre-existing style patterns in the verbatim logic (SC2001 echo|sed, SC2129
# grouped redirects); left as-is to keep behavior provably unchanged.
#
# Runs after `aws-actions/configure-aws-credentials` (needs AWS creds for Bedrock
# + the S3 cache) in the consumer's checkout, which supplies the dependency-usage
# context files (/tmp/dep_usage_*.txt) this script reads. The workflow invokes it
# from the pinned Coalfire-CF/Actions self-checkout (see the workflow header).
#
# Inputs (environment, set by the workflow step `env:` block):
#   DEP_NAME          primary dependency name          (classify.outputs.dep_name)
#   FROM_VERSION      previous version                 (classify.outputs.from_version)
#   TO_VERSION        target version                   (classify.outputs.to_version)
#   ECOSYSTEM         Dependabot package-ecosystem     (classify.outputs.ecosystem)
#   DEPS_B64          base64 TSV of every dep in the PR (grouped-PR support)
#   PARSE_ERROR       "true" if dep list unparseable -> fail closed
#   S3_BUCKET         shared analysis cache bucket     (inputs.s3_cache_bucket)
#   CACHE_TTL_DAYS    cache freshness window           (inputs.cache_ttl_days)
#   BEDROCK_MODEL_ID  Bedrock model id                 (inputs.bedrock_model_id)
#   GH_TOKEN          token for GitHub release-notes API (github.token)
#   GITHUB_REPOSITORY (Actions-provided) owner/repo of the consumer
#   GITHUB_OUTPUT     (Actions-provided) step-output file
#
# Outputs (appended to $GITHUB_OUTPUT):
#   semver_type  has_breaking_changes  confidence  applies_to_repo
#   check_errors  risk_summary
#
set -euo pipefail

# Grouped-PR support: each dependency is analyzed individually and
# folded into aggregates (semver = max, breaking = OR). Bedrock/API
# errors increment CHECK_ERRORS -> decide fails CLOSED to manual
# review (replaces the old silent "defaulting to safe" fail-open).
CHECK_ERRORS=0
AGG_SEMVER="patch"
AGG_BREAKING="false"
AGG_CONF=""
AGG_SUMMARY=""
AGG_APPLIES="false"

semver_rank() {
  case "$1" in major) echo 3;; minor) echo 2;; patch) echo 1;; *) echo 0;; esac
}

check_one() {
local DEP_NAME="$1" FROM_VERSION="$2" TO_VERSION="$3"

SAFE_DEP_NAME=$(echo "$DEP_NAME" | sed 's|/|--|g')
SAFE_REPO_NAME=$(echo "$GITHUB_REPOSITORY" | sed 's|/|--|g')
SHARED_CACHE_KEY="analyses/shared/${SAFE_DEP_NAME}/${TO_VERSION}.json"
REPO_CACHE_KEY="analyses/repos/${SAFE_REPO_NAME}/${SAFE_DEP_NAME}/${TO_VERSION}.json"

# -----------------------------------------------------------
# Check S3 cache — shared (changelog) and repo-scoped (applicability)
# -----------------------------------------------------------
SHARED_CACHE_HIT="false"
REPO_CACHE_HIT="false"
SEMVER_TYPE="unknown"
HAS_BREAKING="false"
CONFIDENCE="0"
RISK_SUMMARY=""
APPLIES_TO_REPO="true"

# Check shared cache for universal changelog analysis
CACHED=$(aws s3 cp "s3://${S3_BUCKET}/${SHARED_CACHE_KEY}" /tmp/cached_analysis.json 2>/dev/null && echo "ok" || echo "miss")
if [ "$CACHED" = "ok" ]; then
  BC_EXISTS=$(jq -r '.changelog // empty' /tmp/cached_analysis.json)
  if [ -n "$BC_EXISTS" ]; then
    ANALYZED_AT=$(jq -r '.analyzed_at // ""' /tmp/cached_analysis.json)
    if [ -n "$ANALYZED_AT" ]; then
      ANALYZED_EPOCH=$(date -d "$ANALYZED_AT" +%s 2>/dev/null || date -jf "%Y-%m-%dT%H:%M:%SZ" "$ANALYZED_AT" +%s 2>/dev/null || echo 0)
      NOW_EPOCH=$(date +%s)
      AGE_DAYS=$(( (NOW_EPOCH - ANALYZED_EPOCH) / 86400 ))
      if [ "$AGE_DAYS" -lt "$CACHE_TTL_DAYS" ]; then
        SHARED_CACHE_HIT="true"
        SEMVER_TYPE=$(jq -r '.semver.type // "unknown"' /tmp/cached_analysis.json)
        HAS_BREAKING=$(jq -r '.changelog.breaking // "false"' /tmp/cached_analysis.json)
        CONFIDENCE=$(jq -r '.changelog.confidence // "0"' /tmp/cached_analysis.json)
        RISK_SUMMARY=$(jq -r '.changelog.summary // ""' /tmp/cached_analysis.json)
        echo "Shared cache hit for changelog analysis of ${DEP_NAME}@${TO_VERSION}"
      fi
    fi
  fi
fi

# Check repo-scoped cache for applicability
REPO_CACHED=$(aws s3 cp "s3://${S3_BUCKET}/${REPO_CACHE_KEY}" /tmp/cached_repo_analysis.json 2>/dev/null && echo "ok" || echo "miss")
if [ "$REPO_CACHED" = "ok" ]; then
  REPO_AT=$(jq -r '.analyzed_at // ""' /tmp/cached_repo_analysis.json)
  if [ -n "$REPO_AT" ]; then
    REPO_EPOCH=$(date -d "$REPO_AT" +%s 2>/dev/null || date -jf "%Y-%m-%dT%H:%M:%SZ" "$REPO_AT" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    REPO_AGE_DAYS=$(( (NOW_EPOCH - REPO_EPOCH) / 86400 ))
    if [ "$REPO_AGE_DAYS" -lt "$CACHE_TTL_DAYS" ]; then
      REPO_CACHE_HIT="true"
      APPLIES_TO_REPO=$(jq -r '.applies_to_repo // "true"' /tmp/cached_repo_analysis.json)
      RISK_SUMMARY=$(jq -r '.risk_summary // "'"$RISK_SUMMARY"'"' /tmp/cached_repo_analysis.json)
      echo "Repo cache hit for applicability of ${DEP_NAME}@${TO_VERSION} in ${GITHUB_REPOSITORY}"
    fi
  fi
fi

if [ "$SHARED_CACHE_HIT" = "false" ]; then
  echo "Running breaking change analysis for ${DEP_NAME}: ${FROM_VERSION} -> ${TO_VERSION}"

  # ---------------------------------------------------------
  # Semver analysis
  # ---------------------------------------------------------
  # Strip leading 'v' for comparison
  FROM_CLEAN=$(echo "$FROM_VERSION" | sed 's/^v//')
  TO_CLEAN=$(echo "$TO_VERSION" | sed 's/^v//')

  if [ "$FROM_CLEAN" = "-" ] || [ -z "$FROM_CLEAN" ]; then
    # No previous version available — cannot classify; the
    # fetch-metadata update-type gate in decide still covers majors.
    SEMVER_TYPE="unknown"
  else
  FROM_MAJOR=$(echo "$FROM_CLEAN" | cut -d. -f1)
  TO_MAJOR=$(echo "$TO_CLEAN" | cut -d. -f1)
  FROM_MINOR=$(echo "$FROM_CLEAN" | cut -d. -f2)
  TO_MINOR=$(echo "$TO_CLEAN" | cut -d. -f2)

  if [ "$TO_MAJOR" != "$FROM_MAJOR" ]; then
    SEMVER_TYPE="major"
  elif [ "$TO_MINOR" != "$FROM_MINOR" ]; then
    SEMVER_TYPE="minor"
  else
    SEMVER_TYPE="patch"
  fi
  fi

  echo "Semver: ${FROM_VERSION} -> ${TO_VERSION} = ${SEMVER_TYPE}"

  # ---------------------------------------------------------
  # Fetch release notes from GitHub
  # ---------------------------------------------------------
  RELEASE_NOTES=""

  # Determine the upstream repo for release notes
  UPSTREAM_REPO=""
  case "$ECOSYSTEM" in
    github-actions|github_actions)
      UPSTREAM_REPO="$DEP_NAME"
      ;;
    *)
      # For other ecosystems, try the dep name as a GitHub repo path
      if echo "$DEP_NAME" | grep -qE '^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$'; then
        UPSTREAM_REPO="$DEP_NAME"
      fi
      ;;
  esac

  if [ -n "$UPSTREAM_REPO" ]; then
    # Build list of candidate tags to try.
    # Dependabot often reports bare major versions (e.g. "9") while
    # upstream tags use full semver (e.g. "v9.0.0"), so we expand
    # short versions into .0 and .0.0 suffixes.
    CANDIDATE_TAGS=("${TO_VERSION}" "v${TO_VERSION}" "${TO_CLEAN}")
    DOTS="${TO_CLEAN//[^.]}"
    if [ "${#DOTS}" -eq 0 ]; then
      # Bare major (e.g. "9") — also try 9.0.0, v9.0.0, 9.0, v9.0
      CANDIDATE_TAGS+=("${TO_CLEAN}.0.0" "v${TO_CLEAN}.0.0" "${TO_CLEAN}.0" "v${TO_CLEAN}.0")
    elif [ "${#DOTS}" -eq 1 ]; then
      # Major.minor (e.g. "9.1") — also try 9.1.0, v9.1.0
      CANDIDATE_TAGS+=("${TO_CLEAN}.0" "v${TO_CLEAN}.0")
    fi

    for TAG_FMT in "${CANDIDATE_TAGS[@]}"; do
      NOTES=$(curl -sf --max-time 15 \
        -H "Authorization: token ${GH_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${UPSTREAM_REPO}/releases/tags/${TAG_FMT}" \
        2>/dev/null | jq -r '.body // ""' || echo "")
      if [ -n "$NOTES" ]; then
        echo "Found release notes at tag: ${TAG_FMT}"
        RELEASE_NOTES="$NOTES"
        break
      fi
    done
  fi

  if [ -z "$RELEASE_NOTES" ]; then
    RELEASE_NOTES="No release notes available."
  fi

  # Truncate to ~4000 chars to keep Claude API costs low
  RELEASE_NOTES=$(echo "$RELEASE_NOTES" | head -c 4000)

  # ---------------------------------------------------------
  # Bedrock Converse API analysis
  # ---------------------------------------------------------
  USAGE_CONTEXT=""
  if [ -f "/tmp/dep_usage_${SAFE_DEP_NAME}.txt" ]; then
    USAGE_CONTEXT=$(cat "/tmp/dep_usage_${SAFE_DEP_NAME}.txt")
  fi

  PROMPT=$(jq -n \
    --arg dep "$DEP_NAME" \
    --arg from "$FROM_VERSION" \
    --arg to "$TO_VERSION" \
    --arg semver "$SEMVER_TYPE" \
    --arg notes "$RELEASE_NOTES" \
    --arg usage "$USAGE_CONTEXT" \
    '"You are a dependency update analyzer. Analyze this update and determine if it contains breaking changes.\n\nDependency: " + $dep + "\nFrom: " + $from + "\nTo: " + $to + "\nSemver bump type: " + $semver + "\n\nRelease notes:\n" + $notes + "\n\nThis is how the dependency is currently used in the consuming repository:\n" + $usage + "\n\nRespond with ONLY a JSON object (no markdown fencing):\n{\"breaking\": true/false, \"confidence\": 0.0-1.0, \"risks\": [\"list of specific risks if any\"], \"summary\": \"one sentence summary of whether the breaking changes affect this repo based on the actual usage shown above\", \"applies_to_repo\": true/false}"')

  jq -n \
    --argjson prompt "$PROMPT" \
    '[{
      role: "user",
      content: [{
        text: $prompt
      }]
    }]' > /tmp/bedrock_messages.json

  echo '{"maxTokens":512}' > /tmp/bedrock_config.json

  # Fail CLOSED on Bedrock error (the old fallback silently
  # defaulted to breaking=false — an unanalyzed dep is NOT safe).
  if ! AI_RESPONSE=$(aws bedrock-runtime converse \
    --model-id "$BEDROCK_MODEL_ID" \
    --messages file:///tmp/bedrock_messages.json \
    --inference-config file:///tmp/bedrock_config.json \
    --output json 2>/tmp/bedrock_err.log); then
    echo "::warning::Bedrock analysis FAILED for ${DEP_NAME} — failing closed"
    CHECK_ERRORS=$((CHECK_ERRORS + 1))
    AI_RESPONSE='{"output":{"message":{"content":[{"text":"{\"breaking\":false,\"confidence\":0,\"risks\":[\"API call failed\"],\"summary\":\"Analysis errored — routed to manual review\"}"}]}}}'
  fi

  if [ -s /tmp/bedrock_err.log ]; then
    echo "Bedrock stderr: $(cat /tmp/bedrock_err.log)"
  fi

  # Parse the Bedrock Converse response
  AI_TEXT=$(echo "$AI_RESPONSE" | jq -r '.output.message.content[0].text // "{}"')
  # Strip markdown fences if present, then validate JSON
  AI_TEXT=$(echo "$AI_TEXT" | sed '/^```/d' | sed 's/^[[:space:]]*//')
  if ! echo "$AI_TEXT" | jq empty 2>/dev/null; then
    # Try extracting JSON between first { and last }
    AI_TEXT=$(echo "$AI_TEXT" | sed -n '/^{/,/^}/p' | head -20)
    if ! echo "$AI_TEXT" | jq empty 2>/dev/null; then
      echo "::warning::Failed to parse AI response for ${DEP_NAME} — failing closed"
      CHECK_ERRORS=$((CHECK_ERRORS + 1))
      AI_TEXT='{"breaking":false,"confidence":0,"risks":["Failed to parse AI response"],"summary":"Analysis unparseable — routed to manual review"}'
    fi
  fi
  HAS_BREAKING=$(echo "$AI_TEXT" | jq -r '.breaking // false')
  CONFIDENCE=$(echo "$AI_TEXT" | jq -r '.confidence // 0')
  RISK_SUMMARY=$(echo "$AI_TEXT" | jq -r '.summary // "Analysis unavailable"')
  AI_RISKS=$(echo "$AI_TEXT" | jq -r '.risks // []')
  APPLIES_TO_REPO=$(echo "$AI_TEXT" | jq -r '.applies_to_repo // true')

  # Override: major bump is always flagged regardless of AI
  if [ "$SEMVER_TYPE" = "major" ]; then
    HAS_BREAKING="true"
  fi

  # ---------------------------------------------------------
  # Write shared cache (universal changelog + semver analysis)
  # ---------------------------------------------------------
  # Read existing cache entry (from supply chain check) or start fresh
  if [ -f /tmp/cached_analysis.json ]; then
    EXISTING=$(cat /tmp/cached_analysis.json)
  else
    EXISTING='{}'
  fi

  echo "$EXISTING" | jq \
    --arg dep "$DEP_NAME" \
    --arg ver "$TO_VERSION" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg sv_type "$SEMVER_TYPE" \
    --arg sv_from "$FROM_VERSION" \
    --arg sv_to "$TO_VERSION" \
    --argjson breaking "$([ "$HAS_BREAKING" = "true" ] && echo true || echo false)" \
    --argjson conf "$CONFIDENCE" \
    --arg summary "$RISK_SUMMARY" \
    --argjson risks "$AI_RISKS" \
    '. + {
      dependency: $dep,
      version: $ver,
      analyzed_at: $ts,
      semver: { type: $sv_type, from: $sv_from, to: $sv_to },
      changelog: { breaking: $breaking, confidence: ($conf | tonumber), summary: $summary, risks: $risks }
    }' > /tmp/merged_analysis.json

  aws s3 cp /tmp/merged_analysis.json "s3://${S3_BUCKET}/${SHARED_CACHE_KEY}" \
    --content-type "application/json" --quiet
fi

# ---------------------------------------------------------
# Repo-scoped applicability analysis
# On shared cache hit + repo miss, run a lightweight Bedrock
# call that only assesses whether the known breaking changes
# apply to this repo's usage patterns.
# ---------------------------------------------------------
if [ "$SHARED_CACHE_HIT" = "true" ] && [ "$REPO_CACHE_HIT" = "false" ]; then
  echo "Shared cache hit but no repo analysis — running applicability check for ${GITHUB_REPOSITORY}"
  USAGE_CONTEXT=""
  if [ -f "/tmp/dep_usage_${SAFE_DEP_NAME}.txt" ]; then
    USAGE_CONTEXT=$(cat "/tmp/dep_usage_${SAFE_DEP_NAME}.txt")
  fi

  APPLY_PROMPT=$(jq -n \
    --arg dep "$DEP_NAME" \
    --arg from "$FROM_VERSION" \
    --arg to "$TO_VERSION" \
    --arg summary "$RISK_SUMMARY" \
    --arg usage "$USAGE_CONTEXT" \
    '"You are a dependency update analyzer. A previous analysis found these breaking changes:\n\nDependency: " + $dep + "\nFrom: " + $from + "\nTo: " + $to + "\nBreaking change summary: " + $summary + "\n\nHere is how this dependency is actually used in the consuming repository:\n" + $usage + "\n\nBased on the actual usage shown, do the breaking changes affect this repository?\n\nRespond with ONLY a JSON object (no markdown fencing):\n{\"applies_to_repo\": true/false, \"summary\": \"one sentence explaining whether and why the breaking changes affect this specific usage\"}"')

  jq -n \
    --argjson prompt "$APPLY_PROMPT" \
    '[{
      role: "user",
      content: [{
        text: $prompt
      }]
    }]' > /tmp/bedrock_apply_messages.json

  echo '{"maxTokens":256}' > /tmp/bedrock_apply_config.json

  # Applicability errors stay conservative (assume it applies) but
  # do NOT count as CHECK_ERRORS: applies_to_repo never gates the
  # decision, and defaulting to true is already the safe direction.
  APPLY_RESPONSE=$(aws bedrock-runtime converse \
    --model-id "$BEDROCK_MODEL_ID" \
    --messages file:///tmp/bedrock_apply_messages.json \
    --inference-config file:///tmp/bedrock_apply_config.json \
    --output json 2>/tmp/bedrock_apply_err.log \
    || echo '{"output":{"message":{"content":[{"text":"{\"applies_to_repo\":true,\"summary\":\"Unable to assess applicability — defaulting to assume it applies\"}"}]}}}')

  APPLY_TEXT=$(echo "$APPLY_RESPONSE" | jq -r '.output.message.content[0].text // "{}"')
  APPLY_TEXT=$(echo "$APPLY_TEXT" | sed '/^```/d' | sed 's/^[[:space:]]*//')
  if ! echo "$APPLY_TEXT" | jq empty 2>/dev/null; then
    APPLY_TEXT=$(echo "$APPLY_TEXT" | sed -n '/^{/,/^}/p' | head -20)
    if ! echo "$APPLY_TEXT" | jq empty 2>/dev/null; then
      APPLY_TEXT='{"applies_to_repo":true,"summary":"Unable to parse — defaulting to assume it applies"}'
    fi
  fi
  APPLIES_TO_REPO=$(echo "$APPLY_TEXT" | jq -r '.applies_to_repo // true')
  RISK_SUMMARY=$(echo "$APPLY_TEXT" | jq -r '.summary // "'"$RISK_SUMMARY"'"')
fi

# ---------------------------------------------------------
# Write repo-scoped cache (applicability analysis)
# ---------------------------------------------------------
if [ "$REPO_CACHE_HIT" = "false" ]; then
  jq -n \
    --arg dep "$DEP_NAME" \
    --arg ver "$TO_VERSION" \
    --arg repo "$GITHUB_REPOSITORY" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson applies "$([ "$APPLIES_TO_REPO" = "true" ] && echo true || echo false)" \
    --arg summary "$RISK_SUMMARY" \
    '{
      dependency: $dep,
      version: $ver,
      repository: $repo,
      analyzed_at: $ts,
      applies_to_repo: $applies,
      risk_summary: $summary
    }' > /tmp/repo_analysis.json

  aws s3 cp /tmp/repo_analysis.json "s3://${S3_BUCKET}/${REPO_CACHE_KEY}" \
    --content-type "application/json" --quiet
fi

# -----------------------------------------------------------
# Fold this dependency into the aggregates
# -----------------------------------------------------------
if [ "$(semver_rank "$SEMVER_TYPE")" -gt "$(semver_rank "$AGG_SEMVER")" ]; then
  AGG_SEMVER="$SEMVER_TYPE"
fi
[ "$HAS_BREAKING" = "true" ]    && AGG_BREAKING="true"
[ "$APPLIES_TO_REPO" = "true" ] && AGG_APPLIES="true"
if [ -z "$AGG_CONF" ] || [ "$(echo "$CONFIDENCE < $AGG_CONF" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
  AGG_CONF="$CONFIDENCE"
fi
AGG_SUMMARY="${AGG_SUMMARY}${DEP_NAME}: ${RISK_SUMMARY} | "
}

# -----------------------------------------------------------
# Iterate every dependency in the PR (grouped-PR support)
# -----------------------------------------------------------
DEPS_FILE=/tmp/deps.tsv
printf '%s' "${DEPS_B64:-}" | base64 -d > "$DEPS_FILE" 2>/dev/null || : > "$DEPS_FILE"
if [ "${PARSE_ERROR:-false}" = "true" ] || [ ! -s "$DEPS_FILE" ]; then
  echo "::warning::dependency list unavailable — failing closed"
  CHECK_ERRORS=$((CHECK_ERRORS + 1))
  AGG_SEMVER="unknown"
else
  while IFS=$'\t' read -r -u3 D_NAME D_FROM D_TO || [ -n "${D_NAME:-}" ]; do
    [ -n "$D_NAME" ] && [ "$D_NAME" != "-" ] || { D_NAME=""; continue; }
    echo "=== breaking-change check: ${D_NAME} ${D_FROM} -> ${D_TO} ==="
    check_one "$D_NAME" "$D_FROM" "$D_TO"
    D_NAME=""
  done 3< "$DEPS_FILE"
fi

[ -n "$AGG_CONF" ] || AGG_CONF="0"
echo "semver_type=${AGG_SEMVER}" >> "$GITHUB_OUTPUT"
echo "has_breaking_changes=${AGG_BREAKING}" >> "$GITHUB_OUTPUT"
echo "confidence=${AGG_CONF}" >> "$GITHUB_OUTPUT"
echo "applies_to_repo=${AGG_APPLIES}" >> "$GITHUB_OUTPUT"
echo "check_errors=${CHECK_ERRORS}" >> "$GITHUB_OUTPUT"

# Escape newlines + truncate for GITHUB_OUTPUT
SAFE_SUMMARY=$(echo "$AGG_SUMMARY" | tr '\n' ' ' | head -c 900)
echo "risk_summary=${SAFE_SUMMARY}" >> "$GITHUB_OUTPUT"
