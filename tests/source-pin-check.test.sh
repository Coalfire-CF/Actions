#!/usr/bin/env bash
#
# Meta-test for scripts/source-pin-check.sh
#
# Verifies the gate:
#   - exits 1 when unpinned/branch/sha sources are present,
#   - names each of the three fail fixtures in its output,
#   - does NOT name the valid pass fixture,
#   - exits 0 on a tree containing only the valid (pinned) fixture.
#
# Fixtures are copied into a temp dir before scanning so the script's built-in
# self-exclusion of tests/fixtures/source-pin/ does not hide them from this test.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHECK="${REPO_ROOT}/scripts/source-pin-check.sh"
FIXTURES="${SCRIPT_DIR}/fixtures/source-pin"

fail() { echo "NOT OK: $1"; exit 1; }

[ -x "$CHECK" ] || chmod +x "$CHECK"
[ -f "$CHECK" ] || fail "check script not found at $CHECK"

# ---- Case 1: mixed tree (pass + 3 fails) must FAIL and name only the fails ----
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp "${FIXTURES}/pass.tf" "${FIXTURES}/fail_floating.tf" \
   "${FIXTURES}/fail_branch.tf" "${FIXTURES}/fail_sha.tf" "$work/"

out="$("$CHECK" "$work" 2>&1)"; code=$?

[ "$code" -eq 1 ] || fail "expected exit 1 on mixed tree, got $code"
echo "$out" | grep -q "fail_floating.tf" || fail "fail_floating.tf was not flagged"
echo "$out" | grep -q "fail_branch.tf"   || fail "fail_branch.tf was not flagged"
echo "$out" | grep -q "fail_sha.tf"      || fail "fail_sha.tf was not flagged"
echo "$out" | grep -q "pass.tf"          && fail "pass.tf was wrongly flagged"
echo "OK: mixed tree fails, names the 3 fail fixtures, spares pass.tf (exit $code)"

# ---- Case 2: pass-only tree must PASS ----
passdir="$(mktemp -d)"
cp "${FIXTURES}/pass.tf" "$passdir/"
out2="$("$CHECK" "$passdir" 2>&1)"; code2=$?
rm -rf "$passdir"

[ "$code2" -eq 0 ] || fail "expected exit 0 on pass-only tree, got $code2 ($out2)"
echo "OK: pass-only tree passes (exit $code2)"

echo "ALL TESTS PASSED"
