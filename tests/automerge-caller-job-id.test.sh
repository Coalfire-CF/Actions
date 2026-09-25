#!/usr/bin/env bash
#
# Freezes the auto-merge caller job id. scripts/pr-green-merge.sh excludes check
# runs named "auto-merge / ..." (IGNORE_CHECK_PREFIX) so the decide job's own
# in-flight check does not wedge the green gate PENDING. If a caller's job id
# changes, the PR-time merge never fires. Any workflow rename must keep it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

fail() { echo "NOT OK: $1"; exit 1; }

# shellcheck disable=SC2016  # literal ${...} in the sed pattern is intended
prefix="$(sed -n 's/^IGNORE_CHECK_PREFIX="\${IGNORE_CHECK_PREFIX:-\(.*\) \/ }"$/\1/p' \
  "${REPO_ROOT}/scripts/pr-green-merge.sh")"
[ "$prefix" = "auto-merge" ] || fail "IGNORE_CHECK_PREFIX default is '${prefix}', expected 'auto-merge'"

# Every caller of the reusable auto-merge workflow, found by content, not name.
callers=()
while IFS= read -r f; do callers+=("$f"); done < <(
  grep -rlE '^[^#]*uses: *(\./|Coalfire-CF/Actions/)\.github/workflows/[a-z-]*dependabot-auto-merge\.yml' \
    "${REPO_ROOT}/.github/workflows" "${REPO_ROOT}/templates" | sort)
[ "${#callers[@]}" -ge 2 ] || fail "found ${#callers[@]} auto-merge callers, expected at least 2 (self-caller + template)"

for f in "${callers[@]}"; do
  grep -qE "^  ${prefix}:$" "$f" || fail "${f#"$REPO_ROOT"/}: caller job id is not '${prefix}'"
  echo "OK: ${f#"$REPO_ROOT"/} uses job id '${prefix}'"
done

echo "ALL TESTS PASSED (${#callers[@]} callers)"
