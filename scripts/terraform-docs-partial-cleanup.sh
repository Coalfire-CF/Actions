#!/usr/bin/env bash
#
# terraform-docs-partial-cleanup.sh — remove ORPHANED generated content from
# _header.md / _footer.md.
#
# Some repos carried a stale terraform-docs block OUTSIDE their BEGIN/END markers
# (an older generator, or the pre-commit-terraform docs hook with its own
# markers). The marker split correctly preserved that text as authored prose, so
# the migrated README shows Requirements/Providers/Modules/Resources/Inputs/
# Outputs TWICE: once stale from the partial, once freshly generated.
#
# This removes only the orphaned copies. It is REMOVAL-ONLY by construction: the
# output is asserted to be no longer than the input, and the removed line count is
# reported so a human can check it.
#
# What it removes:
#   1  a pre-commit-terraform docs hook block, marker to marker. The opening
#      marker is spelled "BEGINNING OF", not "BEGIN OF".
#   2  a `## <generated-section>` heading plus its table, but ONLY when that
#      table really looks generated: `<a name="..."` anchors, or a
#      registry.terraform.io link, which is what the Resources table uses.
#   3  a `## Tree` section, retired fleet-wide.
#
# The patterns are written literally inside the awk program on purpose. Passing
# them with `awk -v` silently corrupts them: awk processes escape sequences in a
# -v value, so `\]` and `\(` lose their backslashes, the regex becomes invalid,
# awk exits non-zero, and the caller sees "nothing to remove".
#
# Usage:
#   terraform-docs-partial-cleanup.sh <file>...              rewrite in place
#   CHECK=true terraform-docs-partial-cleanup.sh <file>...    report only
set -uo pipefail

CHECK="${CHECK:-false}"
[ "$#" -gt 0 ] || { echo "usage: $0 [CHECK=true] <file>..." >&2; exit 2; }

# The `$0` and `$1` below are awk fields, not shell parameters, so the single
# quotes are required and SC2016 does not apply.
# shellcheck disable=SC2016
AWK_PROG='
function flush_pending() { for (i = 1; i <= np; i++) print pending[i]; np = 0 }
BEGIN { mode = "copy"; np = 0; nrem = 0 }

# 1. pre-commit-terraform docs hook block
mode == "copy" && /<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->/ { mode = "pchook"; nrem++; next }
mode == "pchook" { nrem++; if ($0 ~ /<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->/) mode = "copy"; next }

# 3. Tree section, up to the next h1/h2
mode == "copy" && /^## +Tree[ \t]*$/ { mode = "tree"; nrem++; next }
mode == "tree" { if ($0 ~ /^##? +/) { mode = "copy" } else { nrem++; next } }

# 2. generated section: buffer the heading, decide once the table appears
mode == "copy" && /^## (Requirements|Providers|Modules|Resources|Inputs|Outputs)[ \t]*$/ {
  mode = "maybe"; np = 0; pending[++np] = $0; held = 1; next
}
mode == "maybe" {
  if ($0 ~ /^[ \t]*$/ || $0 ~ /^\|/) {
    pending[++np] = $0
    if ($0 ~ /<a name="(requirement|provider|module|resource|input|output)_/) generated = 1
    if ($0 ~ /\]\(https:\/\/registry\.terraform\.io\//) generated = 1
    next
  }
  if (generated) { nrem += np } else { flush_pending() }
  generated = 0; np = 0; held = 0; mode = "copy"
  if ($0 ~ /^## (Requirements|Providers|Modules|Resources|Inputs|Outputs)[ \t]*$/) { mode = "maybe"; pending[++np] = $0; held = 1; next }
  if ($0 ~ /^## +Tree[ \t]*$/) { mode = "tree"; nrem++; next }
  print; next
}

mode == "copy" { print }

END {
  if (mode == "maybe") { if (generated) nrem += np; else flush_pending() }
  print "___REMOVED___" nrem > "/dev/stderr"
}
'

rc=0
for f in "$@"; do
  [ -f "$f" ] || { echo "not a file: $f" >&2; rc=1; continue; }
  err="$(mktemp)"
  if ! out="$(awk "$AWK_PROG" "$f" 2>"$err")"; then
    echo "REFUSING ${f}: awk failed: $(tr -d '\n' < "$err" | head -c 200)" >&2
    rm -f "$err"; rc=1; continue
  fi
  n_removed="$(sed -n 's/^___REMOVED___//p' "$err")"
  rm -f "$err"
  # An unparseable count means the program did not reach END; never write then.
  case "$n_removed" in
    ""|*[!0-9]*) echo "REFUSING ${f}: no removal count reported" >&2; rc=1; continue ;;
  esac

  in_lines="$(wc -l < "$f" | tr -d ' ')"
  # An empty result is 0 lines, not 1. `printf '%s\n' ""` emits a single newline,
  # which made a legitimately EMPTY partial look like growth and tripped the
  # removal-only guard. Measured on the empty _footer.md of
  # terraform-aws-inventorylambda, managed-ad and trenddsm.
  if [ -z "$out" ]; then
    out_lines=0
  else
    out_lines="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
  fi
  if [ "$out_lines" -gt "$in_lines" ]; then
    echo "REFUSING ${f}: output ${out_lines} > input ${in_lines}, must be removal-only" >&2
    rc=1; continue
  fi

  if [ "$n_removed" -eq 0 ]; then
    echo "  ${f}: nothing to remove"
    continue
  fi
  echo "  ${f}: removed ${n_removed} line(s) of orphaned generated content (${in_lines} -> ${out_lines})"
  [ "$CHECK" = "true" ] || printf '%s\n' "$out" > "$f"
done
exit "$rc"
