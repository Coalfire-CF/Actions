#!/usr/bin/env bash
#
# gate-config-resolve.sh — resolve a gate's effective `strict` boolean (RFC-0010).
#
# Precedence: caller input ('true'/'false', non-empty) > gates.<key>.strict in
# the central gate-config.yml > false. Any empty/other caller value defers to
# the central default. Prints exactly "true" or "false" on stdout.
#
# FAIL-CLOSED CONTRACT (grade-A plan item #5): if the gate key is PRESENT in the
# config but its `strict` value cannot be parsed as true/false — e.g. a
# block-style reformat, a typo'd value, or a missing strict field — the resolver
# exits non-zero instead of silently printing "false". A silent false would
# downgrade a strict gate to advisory fleet-wide (this file is read at @main by
# every gate caller). An ABSENT key still resolves to "false" (documented default).
#
# Usage:
#   gate-config-resolve.sh <gate-key> <caller-strict> [config-path]
#     <gate-key>       one of: source-pin | uses-pin | version-band | opa
#     <caller-strict>  the caller's `strict` input verbatim ('' = defer)
#     [config-path]    defaults to ./gate-config.yml
#
# Accepted config shapes for the central default:
#   gates:
#     <key>: { strict: <bool> }        # inline-flow (canonical)
#   gates:
#     <key>:
#       strict: <bool>                 # block-style (parsed since item #5)

set -uo pipefail

KEY="${1:?gate key required}"
CALLER="${2-}"
CONFIG="${3:-gate-config.yml}"

# 1) Explicit caller override wins.
if [ "$CALLER" = "true" ] || [ "$CALLER" = "false" ]; then
  echo "$CALLER"
  exit 0
fi

# 2) Central default for this gate key (inline-flow or block-style).
val=""
key_present=0
if [ -f "$CONFIG" ]; then
  key_ln="$(grep -nE "^[[:space:]]+${KEY}:([[:space:]{]|$)" "$CONFIG" | head -1 | cut -d: -f1 || true)"
  if [ -n "$key_ln" ]; then
    key_present=1
    key_line="$(sed -n "${key_ln}p" "$CONFIG")"
    if printf '%s\n' "$key_line" | grep -q '{'; then
      # inline-flow: <key>: { strict: bool, ... }
      val="$(printf '%s\n' "$key_line" | grep -oE 'strict:[[:space:]]*(true|false)' | grep -oE '(true|false)' | head -1 || true)"
    else
      # block-style: strict: bool on a more-indented child line, ending at the
      # first non-blank/non-comment line indented at or above the key's level.
      key_indent="$(printf '%s' "$key_line" | sed -E 's/^([[:space:]]*).*/\1/' | awk '{ print length($0) }')"
      [ -n "$key_indent" ] || key_indent=0
      val="$(awk -v start="$key_ln" -v ki="$key_indent" '
        NR <= start { next }
        /^[[:space:]]*$/ { next }
        /^[[:space:]]*#/ { next }
        {
          match($0, /^[[:space:]]*/)
          if (RLENGTH <= ki) exit
          if ($0 ~ /^[[:space:]]*strict:[[:space:]]*true([[:space:]]|#|$)/)  { print "true";  exit }
          if ($0 ~ /^[[:space:]]*strict:[[:space:]]*false([[:space:]]|#|$)/) { print "false"; exit }
        }' "$CONFIG" || true)"
    fi
  fi
fi

# 3) Emit, failing CLOSED on a present-but-unparseable key.
if [ "$val" = "true" ] || [ "$val" = "false" ]; then
  echo "$val"
elif [ "$key_present" -eq 1 ]; then
  echo "::error::gate-config-resolve: gate '${KEY}' is present in ${CONFIG} but its 'strict' value could not be parsed as true/false — failing closed rather than silently downgrading to advisory. Fix the config (inline '{ strict: true|false }' or block-style 'strict: true|false')." >&2
  exit 2
else
  # Absent key (or absent config file) → documented default.
  echo "false"
fi
