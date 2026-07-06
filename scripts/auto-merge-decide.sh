#!/usr/bin/env bash
# shellcheck disable=SC2129
#
# auto-merge-decide.sh — deterministic auto-merge decision gate for the
# Dependabot auto-merge workflow (.github/workflows/org-dependabot-auto-merge.yml,
# job: decide, step "Evaluate checks and decide").
#
# EXTRACTED VERBATIM (grade-A plan #10) from the former inline decide `run:` block
# so the highest-blast-radius, zero-coverage decision logic is committed,
# unit-testable (see tests/auto-merge-decide.test.sh), and shellcheck-covered.
# The emitted decision is byte-identical to that inline block — pure refactor, no
# behavior change. This gate is pure bash (no network / AWS): it reads the
# upstream jobs' outputs from the environment and reduces them to a verdict.
# SC2129 (grouped redirects) is a pre-existing style pattern in the verbatim
# logic; left as-is to keep behavior provably unchanged.
#
# Fail-closed precedence (unchanged): any parse/check error downgrades an approve
# to manual-review; a hard blocker (major / OSV / low-scorecard / breaking) wins
# over manual. First-party org deps waive only the Scorecard gate (RFC-0010).
#
# Inputs (environment, set by the workflow step `env:` block):
#   OSV_CLEAR SCORECARD_PASS SCORECARD_SCORE     (supply_chain_check.outputs.*)
#   SEMVER_TYPE HAS_BREAKING CONFIDENCE RISK_SUMMARY APPLIES_TO_REPO
#                                                (breaking_change_check.outputs.*)
#   DEP_NAME TO_VERSION IS_FIRST_PARTY UPDATE_TYPE_META DEP_GROUP PARSE_ERROR
#                                                (classify.outputs.*)
#   SC_ERRORS BC_ERRORS   per-job check-error counts (fail-closed inputs)
#   GITHUB_OUTPUT GITHUB_STEP_SUMMARY   (Actions-provided) output/summary files
#
# Outputs (appended to $GITHUB_OUTPUT):
#   decision       one of: approve | block | manual
#   risk_level     one of: low | medium | high
#   blocked_labels space-separated blocked/* labels (may be empty)
# Also writes a human-readable decision table to $GITHUB_STEP_SUMMARY.
#
set -euo pipefail

DECISION="approve"
RISK_LEVEL="low"
BLOCKED_LABELS=""
REASONS=""
MANUAL="false"

# Fail CLOSED: any per-dependency check error or parse ambiguity
# means the evaluation is partial — never approve on partial data.
if [ "${PARSE_ERROR:-false}" = "true" ] || [ "${SC_ERRORS:-0}" -gt 0 ] || [ "${BC_ERRORS:-0}" -gt 0 ]; then
  MANUAL="true"
  RISK_LEVEL="high"
  REASONS="${REASONS}\n- Per-dependency checks incomplete (parse_error=${PARSE_ERROR:-false}, supply_chain_errors=${SC_ERRORS:-0}, breaking_check_errors=${BC_ERRORS:-0}) — fail-closed to manual review"
fi

# Authoritative group-aware major gate: fetch-metadata's update-type
# is the MAX semver across every dependency in the PR. Value format
# is "version-update:semver-major" — match the suffix, never a bare
# "major" (that comparison would silently never fire).
if [[ "${UPDATE_TYPE_META:-}" == *"semver-major"* ]]; then
  DECISION="block"
  RISK_LEVEL="high"
  BLOCKED_LABELS="${BLOCKED_LABELS} blocked/major-bump"
  REASONS="${REASONS}\n- Major version bump present in this PR (update-type: ${UPDATE_TYPE_META})"
fi

# Check for blockers
if [ "$OSV_CLEAR" != "true" ]; then
  DECISION="block"
  RISK_LEVEL="high"
  BLOCKED_LABELS="${BLOCKED_LABELS} blocked/known-vuln"
  REASONS="${REASONS}\n- Known vulnerability found in target version"
fi

# Scorecard gate is waived for first-party org dependencies: the
# Scorecard API has no data for org repos, which would hard-block
# every first-party bump (RFC-0010: same-major first-party bumps
# auto-merge on green CI). OSV/major/breaking gates still apply.
SCORECARD_WAIVED="false"
if [ "$SCORECARD_PASS" != "true" ]; then
  if [ "$IS_FIRST_PARTY" = "true" ]; then
    SCORECARD_WAIVED="true"
    echo "First-party dependency (${DEP_NAME}) — scorecard gate waived"
  else
    DECISION="block"
    RISK_LEVEL="high"
    BLOCKED_LABELS="${BLOCKED_LABELS} blocked/low-scorecard"
    REASONS="${REASONS}\n- OpenSSF Scorecard below threshold (score: ${SCORECARD_SCORE})"
  fi
fi

if [ "$SEMVER_TYPE" = "major" ]; then
  DECISION="block"
  RISK_LEVEL="high"
  BLOCKED_LABELS="${BLOCKED_LABELS} blocked/major-bump"
  REASONS="${REASONS}\n- Major version bump requires manual review"
fi

if [ "$HAS_BREAKING" = "true" ] && [ "$SEMVER_TYPE" != "major" ]; then
  # Breaking change in a non-major bump — extra concerning
  DECISION="block"
  RISK_LEVEL="high"
  BLOCKED_LABELS="${BLOCKED_LABELS} blocked/breaking-change"
  REASONS="${REASONS}\n- Breaking change detected: ${RISK_SUMMARY}"
fi

# Fail-closed precedence: check errors downgrade an approve to
# manual review. An already-blocked PR stays blocked (stronger).
if [ "$MANUAL" = "true" ] && [ "$DECISION" = "approve" ]; then
  DECISION="manual"
fi

# Determine if medium risk (not blocked but warrants attention)
if [ "$DECISION" = "approve" ] && [ "$SEMVER_TYPE" = "minor" ]; then
  RISK_LEVEL="medium"
fi

echo "decision=${DECISION}" >> "$GITHUB_OUTPUT"
echo "risk_level=${RISK_LEVEL}" >> "$GITHUB_OUTPUT"
echo "blocked_labels=${BLOCKED_LABELS}" >> "$GITHUB_OUTPUT"

# Write step summary
{
  echo "## Dependabot Auto-Merge Decision"
  echo ""
  echo "| Field | Value |"
  echo "|-------|-------|"
  echo "| Dependency | \`${DEP_NAME}\` |"
  echo "| Version | \`${TO_VERSION}\` |"
  echo "| Decision | **${DECISION}** |"
  echo "| Risk | ${RISK_LEVEL} |"
  echo "| OSV Clear | ${OSV_CLEAR} |"
  if [ "$SCORECARD_WAIVED" = "true" ]; then
    echo "| Scorecard Pass | waived — first-party (${SCORECARD_SCORE}) |"
  else
    echo "| Scorecard Pass | ${SCORECARD_PASS} (${SCORECARD_SCORE}) |"
  fi
  echo "| First Party | ${IS_FIRST_PARTY} |"
  echo "| Semver (aggregate) | ${SEMVER_TYPE} |"
  echo "| Update Type (max) | ${UPDATE_TYPE_META:-n/a} |"
  echo "| Dependency Group | ${DEP_GROUP:-—} |"
  echo "| Check Errors | supply=${SC_ERRORS:-0} breaking=${BC_ERRORS:-0} parse=${PARSE_ERROR:-false} |"
  echo "| Breaking Changes | ${HAS_BREAKING} |"
  echo "| Applies to Repo | ${APPLIES_TO_REPO} |"
  echo "| Analysis | ${RISK_SUMMARY} |"
  if [ -n "$REASONS" ]; then
    echo ""
    echo "### Blocking Reasons"
    echo -e "$REASONS"
  fi
} >> "$GITHUB_STEP_SUMMARY"
