#!/usr/bin/env bash
#
# stagger-slot.sh <repo-name> — deterministic daily-schedule slot (HH:MM) derived
# from a hash of the repo name (grade-A plan #13). Spreads the fleet's Dependabot
# fanout across the 24h window instead of a shared top-of-window herd.
#
# DETERMINISTIC by design: the same repo name ALWAYS yields the same slot, so
# regenerating a repo's dependabot.yml produces zero diff. No runtime randomness.
set -euo pipefail

name="${1:?repo name required}"
# First 8 hex chars of the SHA-256 → a 32-bit int → minute-of-day in [0,1439].
hex="$(printf '%s' "$name" | sha256sum | cut -c1-8)"
minute=$(( 16#$hex % 1440 ))
printf '%02d:%02d\n' $(( minute / 60 )) $(( minute % 60 ))
