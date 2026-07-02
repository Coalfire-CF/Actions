#!/usr/bin/env bash
#
# gate-config-resolve.sh — resolve a gate's effective `strict` boolean (RFC-0010).
#
# Precedence: caller input ('true'/'false', non-empty) > gates.<key>.strict in
# the central gate-config.yml > false. Any empty/other caller value defers to
# the central default. Prints exactly "true" or "false" on stdout.
#
# Usage:
#   gate-config-resolve.sh <gate-key> <caller-strict> [config-path]
#     <gate-key>       one of: source-pin | uses-pin | version-band | opa
#     <caller-strict>  the caller's `strict` input verbatim ('' = defer)
#     [config-path]    defaults to ./gate-config.yml
#
# The config is the fixed nested-short-key shape:
#   gates:
#     <key>: { strict: <bool> }

set -uo pipefail

KEY="${1:?gate key required}"
CALLER="${2-}"
CONFIG="${3:-gate-config.yml}"

# 1) Explicit caller override wins.
if [ "$CALLER" = "true" ] || [ "$CALLER" = "false" ]; then
  echo "$CALLER"
  exit 0
fi

# 2) Central default for this gate key.
val=""
if [ -f "$CONFIG" ]; then
  # Match the gate's line under gates: and extract its strict boolean.
  line="$(grep -E "^[[:space:]]+${KEY}:[[:space:]]*\{" "$CONFIG" | head -1 || true)"
  val="$(printf '%s' "$line" | grep -oE 'strict:[[:space:]]*(true|false)' | grep -oE '(true|false)' || true)"
fi

# 3) Fall back to false.
if [ "$val" = "true" ]; then
  echo "true"
else
  echo "false"
fi
