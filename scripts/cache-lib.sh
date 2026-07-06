#!/usr/bin/env bash
#
# cache-lib.sh — shared S3 analysis-cache read/validate helpers for the
# Dependabot auto-merge workflow (grade-A plan #9). Sourced by
# scripts/supply-chain-check.sh and scripts/breaking-change-check.sh.
#
# Why: the cached supply-chain/breaking-change objects gate the merge decision.
# The pre-#9 reads defaulted missing fields to the PERMISSIVE value
# (`.osv.clear // "true"`, `.scorecard.pass // "true"`, `.changelog.breaking //
# "false"`), so a partial/corrupt/poisoned cache object could silently suppress
# an OSV / scorecard / breaking-change block for the whole TTL window. These
# helpers make reads fail-SAFE and add a schema_version + producer stamp so an
# object of an unrecognized shape or origin is re-analyzed instead of trusted.
#
# Pure bash + jq — no aws / network — so it is unit-tested offline by
# tests/cache-read.test.sh.
#
# This file is sourced (not executed); it defines constants + functions only.

# Bumped whenever the cached object schema changes. A read whose schema_version
# does not match is treated as a cache MISS (re-analyze) — which also means every
# pre-#9 object (no schema_version) is transparently re-analyzed on rollout.
CACHE_SCHEMA_VERSION="1"
# Identity every writer stamps; a read from any other producer is not trusted.
CACHE_PRODUCER="coalfire-org-dependabot-auto-merge"

# cache_schema_ok <file> : exit 0 iff the object carries the expected
# schema_version AND producer. Any mismatch / missing field / unreadable file
# → non-zero (caller treats it as a cache miss and re-analyzes).
cache_schema_ok() {
  local f="$1" sv prod
  [ -f "$f" ] || return 1
  sv="$(jq -r '.schema_version // ""' "$f" 2>/dev/null)" || return 1
  prod="$(jq -r '.producer // ""' "$f" 2>/dev/null)" || return 1
  [ "$sv" = "$CACHE_SCHEMA_VERSION" ] && [ "$prod" = "$CACHE_PRODUCER" ]
}

# cache_read_bool <file> <jq_path> <safe_value> : echo the cached value at
# jq_path ONLY if it is a genuine boolean (true/false); otherwise echo the
# SAFE value. Missing, null, non-boolean, or unreadable → safe (fail closed).
# The safe value is chosen by the caller so a degraded cache blocks/holds a PR,
# never approves it (osv.clear→false, scorecard.pass→false, changelog.breaking→true).
cache_read_bool() {
  local f="$1" path="$2" safe="$3" v
  # Accept the cached value ONLY if it is a genuine JSON boolean. Two traps:
  #   1. jq's `// default` fires on both null AND false, so `.breaking // true`
  #      would coerce a real `false` to `true` — never use `//` here.
  #   2. `jq -r` renders the string "true" and the boolean true identically, so a
  #      type check is required or a poisoned {"clear":"true"} string reads as
  #      clear. We emit the value only when (path|type)=="boolean".
  # Anything else — missing / null / string / number / unreadable — → SAFE value.
  v="$(jq -r "if ((${path}) | type) == \"boolean\" then (${path} | tostring) else \"__INVALID__\" end" "$f" 2>/dev/null)" || v="__INVALID__"
  case "$v" in
    true | false) printf '%s' "$v" ;;
    *)            printf '%s' "$safe" ;;
  esac
}
