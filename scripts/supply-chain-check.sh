#!/usr/bin/env bash
# shellcheck disable=SC2001,SC2034,SC2129,SC2015
# SC2015: the `[ ... ] && [ ... ] || { ...; continue; }` guard-continue is the
# original heredoc idiom, intentional (not if-then-else) — kept byte-identical.
#
# supply-chain-check.sh — OSV + OpenSSF Scorecard supply-chain gate for the
# Dependabot auto-merge workflow (.github/workflows/org-dependabot-auto-merge.yml,
# job: supply_chain_check).
#
# EXTRACTED VERBATIM (grade-A plan #10) from the former inline
# `/tmp/supply_chain_check.sh` heredoc so the logic is committed, unit-testable,
# and shellcheck-covered. The emitted decision is byte-identical to that inline
# heredoc — this is a pure refactor, no behavior change. The disabled codes are
# pre-existing style/warning patterns in the verbatim logic (SC2001 echo|sed,
# SC2034 unused read field, SC2129 grouped redirects); left as-is to keep
# behavior provably unchanged.
#
# Runs after `aws-actions/configure-aws-credentials` (needs AWS creds for the S3
# analysis cache) in the consumer's checkout; the workflow invokes it from the
# pinned Coalfire-CF/Actions self-checkout (see the workflow header comment).
#
# Inputs (environment, set by the workflow step `env:` block):
#   DEP_NAME             primary dependency name       (classify.outputs.dep_name)
#   TO_VERSION           target version                (classify.outputs.to_version)
#   ECOSYSTEM            Dependabot package-ecosystem  (classify.outputs.ecosystem)
#   DEPS_B64             base64 TSV of every dep in the PR (grouped-PR support)
#   PARSE_ERROR          "true" if dep list unparseable -> fail closed
#   S3_BUCKET            shared analysis cache bucket  (inputs.s3_cache_bucket)
#   CACHE_TTL_DAYS       cache freshness window        (inputs.cache_ttl_days)
#   SCORECARD_THRESHOLD  min OpenSSF Scorecard score   (inputs.scorecard_threshold)
#   GITHUB_OUTPUT        (Actions-provided) step-output file
#
# Outputs (appended to $GITHUB_OUTPUT):
#   osv_clear  scorecard_pass  scorecard_score  cache_hit  check_errors
#
set -euo pipefail

# Shared cache read/validate helpers (grade-A #9): fail-safe field reads +
# schema_version/producer validation.
# shellcheck source=scripts/cache-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cache-lib.sh"
# Shared bounded-retry + jitter helper (grade-A #13).
# shellcheck source=scripts/retry-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/retry-lib.sh"

# Tunables for external-call retry (transient-only; fail closed on exhaustion).
RETRY_MAX="${RETRY_MAX:-3}"
RETRY_BASE="${RETRY_BASE:-2}"
RETRY_CAP="${RETRY_CAP:-20}"
# One-time pre-call jitter to de-sync the daily fleet burst (0 disables; the
# workflow sets JITTER_MAX_SECONDS). Runs once per job, before the first call.
jitter_delay "${JITTER_MAX_SECONDS:-0}"

# Grouped-PR support: every dependency in the PR is checked
# individually and folded into AND/OR aggregates. Any per-dep
# query ERROR (as opposed to a clean result) increments
# CHECK_ERRORS and the decide job fails CLOSED to manual review.
CHECK_ERRORS=0
AGG_OSV_CLEAR="true"
AGG_SC_PASS="true"
AGG_SC_SCORE=""
AGG_CACHE_HIT="true"

check_one() {
local DEP_NAME="$1" TO_VERSION="$2"

# -----------------------------------------------------------
# Normalize dependency name for S3 key (replace / with --)
# -----------------------------------------------------------
SAFE_DEP_NAME=$(echo "$DEP_NAME" | sed 's|/|--|g')
CACHE_KEY="analyses/shared/${SAFE_DEP_NAME}/${TO_VERSION}.json"

# -----------------------------------------------------------
# Check S3 cache (shared — supply chain data is universal)
# -----------------------------------------------------------
CACHE_HIT="false"
OSV_CLEAR="true"
SCORECARD_PASS="true"
SCORECARD_SCORE="0"

CACHED=$(aws s3 cp "s3://${S3_BUCKET}/${CACHE_KEY}" /tmp/cached_analysis.json 2>/dev/null && echo "ok" || echo "miss")
if [ "$CACHED" = "ok" ]; then
  # Validate TTL
  ANALYZED_AT=$(jq -r '.analyzed_at // ""' /tmp/cached_analysis.json)
  if [ -n "$ANALYZED_AT" ]; then
    ANALYZED_EPOCH=$(date -d "$ANALYZED_AT" +%s 2>/dev/null || date -jf "%Y-%m-%dT%H:%M:%SZ" "$ANALYZED_AT" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    AGE_DAYS=$(( (NOW_EPOCH - ANALYZED_EPOCH) / 86400 ))
    if [ "$AGE_DAYS" -lt "$CACHE_TTL_DAYS" ]; then
      if cache_schema_ok /tmp/cached_analysis.json; then
        CACHE_HIT="true"
        # Fail-SAFE reads (grade-A #9): a missing/non-boolean field resolves to
        # the blocking value (not-clear / not-pass), never permissive.
        OSV_CLEAR=$(cache_read_bool /tmp/cached_analysis.json '.osv.clear' false)
        SCORECARD_PASS=$(cache_read_bool /tmp/cached_analysis.json '.scorecard.pass' false)
        SCORECARD_SCORE=$(jq -r '.scorecard.score // "0"' /tmp/cached_analysis.json)
        echo "Cache hit for ${DEP_NAME}@${TO_VERSION} (age: ${AGE_DAYS}d)"
      else
        echo "::warning::Cached object for ${DEP_NAME}@${TO_VERSION} failed schema/producer validation — re-analyzing (treated as miss)"
      fi
    fi
  fi
fi

if [ "$CACHE_HIT" = "false" ]; then
  echo "Cache miss — running live checks for ${DEP_NAME}@${TO_VERSION}"

  # ---------------------------------------------------------
  # OSV.dev vulnerability check
  # ---------------------------------------------------------
  # Map Dependabot ecosystems to OSV ecosystems
  OSV_ECOSYSTEM=""
  case "$ECOSYSTEM" in
    github-actions|github_actions) OSV_ECOSYSTEM="GitHub Actions" ;;
    npm)            OSV_ECOSYSTEM="npm" ;;
    pip)            OSV_ECOSYSTEM="PyPI" ;;
    gomod)          OSV_ECOSYSTEM="Go" ;;
    cargo)          OSV_ECOSYSTEM="crates.io" ;;
    nuget)          OSV_ECOSYSTEM="NuGet" ;;
    *)              OSV_ECOSYSTEM="" ;;
  esac

  OSV_VULNS="[]"
  if [ -n "$OSV_ECOSYSTEM" ]; then
    # Fail CLOSED on query error: a failed OSV call is NOT a clean result.
    # Transient (429/5xx/timeout) retries with backoff+jitter (grade-A #13); a
    # terminal failure still fails closed (CHECK_ERRORS -> decide manual review).
    OSV_PAYLOAD=$(jq -n \
      --arg pkg "$DEP_NAME" \
      --arg ver "$TO_VERSION" \
      --arg eco "$OSV_ECOSYSTEM" \
      '{package: {name: $pkg, ecosystem: $eco}, version: $ver}')
    if ! OSV_RESPONSE=$(with_retry "$RETRY_MAX" "$RETRY_BASE" "$RETRY_CAP" -- \
      http_retryable --max-time 30 \
      -X POST "https://api.osv.dev/v1/query" \
      -H "Content-Type: application/json" \
      -d "$OSV_PAYLOAD"); then
      echo "::warning::OSV query FAILED for ${DEP_NAME}@${TO_VERSION} — failing closed"
      CHECK_ERRORS=$((CHECK_ERRORS + 1))
      OSV_RESPONSE='{"vulns":[]}'
    fi
    OSV_VULNS=$(echo "$OSV_RESPONSE" | jq '.vulns // []')
    VULN_COUNT=$(echo "$OSV_VULNS" | jq 'length')
    if [ "$VULN_COUNT" -gt 0 ]; then
      OSV_CLEAR="false"
      echo "::warning::Found ${VULN_COUNT} known vulnerabilities for ${DEP_NAME}@${TO_VERSION}"
    fi
  else
    echo "No OSV ecosystem mapping for '${ECOSYSTEM}' — skipping OSV check"
  fi

  # ---------------------------------------------------------
  # OpenSSF Scorecard check
  # ---------------------------------------------------------
  # Extract the GitHub owner/repo from the dependency name
  SCORECARD_REPO=""
  case "$ECOSYSTEM" in
    github-actions|github_actions)
      # actions/checkout -> github.com/actions/checkout
      SCORECARD_REPO="github.com/${DEP_NAME}"
      ;;
    npm|pip|gomod|cargo)
      # Attempt to resolve via the dependency name if it looks like a GitHub path
      if echo "$DEP_NAME" | grep -qE '^github\.com/'; then
        SCORECARD_REPO="${DEP_NAME}"
      elif echo "$DEP_NAME" | grep -qE '^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$'; then
        SCORECARD_REPO="github.com/${DEP_NAME}"
      fi
      ;;
  esac

  if [ -n "$SCORECARD_REPO" ]; then
    # Transient retries (grade-A #13); on terminal failure preserve today's
    # conservative fallback — empty object → score 0 → not-pass (blocks, unless
    # first-party-waived). Not a CHECK_ERROR (matches prior behavior).
    SCORECARD_RESPONSE=$(with_retry "$RETRY_MAX" "$RETRY_BASE" "$RETRY_CAP" -- \
      http_retryable --max-time 30 \
      "https://api.securityscorecards.dev/projects/${SCORECARD_REPO}" \
      || echo '{}')
    SCORECARD_SCORE=$(echo "$SCORECARD_RESPONSE" | jq -r '.score // 0')

    if [ "$(echo "$SCORECARD_SCORE < $SCORECARD_THRESHOLD" | bc -l)" -eq 1 ]; then
      SCORECARD_PASS="false"
      echo "::warning::Scorecard ${SCORECARD_SCORE}/10 below threshold ${SCORECARD_THRESHOLD} for ${SCORECARD_REPO}"
    else
      echo "Scorecard ${SCORECARD_SCORE}/10 meets threshold for ${SCORECARD_REPO}"
    fi
  else
    echo "Cannot resolve Scorecard repo for '${DEP_NAME}' — skipping Scorecard check"
    SCORECARD_SCORE="N/A"
  fi

  # ---------------------------------------------------------
  # Write to S3 cache (partial — supply chain fields only)
  # Breaking change check will merge its fields in separately
  # ---------------------------------------------------------
  jq -n \
    --arg schema "$CACHE_SCHEMA_VERSION" \
    --arg producer "$CACHE_PRODUCER" \
    --arg dep "$DEP_NAME" \
    --arg ver "$TO_VERSION" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson osv_clear "$([ "$OSV_CLEAR" = "true" ] && echo true || echo false)" \
    --argjson osv_vulns "$OSV_VULNS" \
    --arg sc_score "$SCORECARD_SCORE" \
    --argjson sc_pass "$([ "$SCORECARD_PASS" = "true" ] && echo true || echo false)" \
    '{
      schema_version: $schema,
      producer: $producer,
      dependency: $dep,
      version: $ver,
      analyzed_at: $ts,
      osv: { clear: $osv_clear, vulns: $osv_vulns },
      scorecard: { score: $sc_score, pass: $sc_pass }
    }' > /tmp/supply_chain_result.json

  aws s3 cp /tmp/supply_chain_result.json "s3://${S3_BUCKET}/${CACHE_KEY}" \
    --content-type "application/json" --quiet
fi

# -----------------------------------------------------------
# Fold this dependency into the aggregates
# -----------------------------------------------------------
[ "$OSV_CLEAR" = "true" ]      || AGG_OSV_CLEAR="false"
[ "$SCORECARD_PASS" = "true" ] || AGG_SC_PASS="false"
[ "$CACHE_HIT" = "true" ]      || AGG_CACHE_HIT="false"
if [ "$SCORECARD_SCORE" != "N/A" ]; then
  if [ -z "$AGG_SC_SCORE" ] || [ "$(echo "$SCORECARD_SCORE < $AGG_SC_SCORE" | bc -l)" -eq 1 ]; then
    AGG_SC_SCORE="$SCORECARD_SCORE"
  fi
fi
}

# -----------------------------------------------------------
# Iterate every dependency in the PR (grouped-PR support)
# -----------------------------------------------------------
DEPS_FILE=/tmp/deps.tsv
printf '%s' "${DEPS_B64:-}" | base64 -d > "$DEPS_FILE" 2>/dev/null || : > "$DEPS_FILE"
if [ "${PARSE_ERROR:-false}" = "true" ] || [ ! -s "$DEPS_FILE" ]; then
  echo "::warning::dependency list unavailable — failing closed"
  CHECK_ERRORS=$((CHECK_ERRORS + 1))
else
  # `|| [ -n "$D_NAME" ]` processes a final line with no trailing
  # newline; fd 3 keeps loop input safe from stdin-reading commands.
  while IFS=$'\t' read -r -u3 D_NAME D_FROM D_TO || [ -n "${D_NAME:-}" ]; do
    [ -n "$D_NAME" ] && [ "$D_NAME" != "-" ] || { D_NAME=""; continue; }
    echo "=== supply-chain check: ${D_NAME}@${D_TO} ==="
    check_one "$D_NAME" "$D_TO"
    D_NAME=""
  done 3< "$DEPS_FILE"
fi

[ -n "$AGG_SC_SCORE" ] || AGG_SC_SCORE="N/A"
echo "osv_clear=${AGG_OSV_CLEAR}" >> "$GITHUB_OUTPUT"
echo "scorecard_pass=${AGG_SC_PASS}" >> "$GITHUB_OUTPUT"
echo "scorecard_score=${AGG_SC_SCORE}" >> "$GITHUB_OUTPUT"
echo "cache_hit=${AGG_CACHE_HIT}" >> "$GITHUB_OUTPUT"
echo "check_errors=${CHECK_ERRORS}" >> "$GITHUB_OUTPUT"
