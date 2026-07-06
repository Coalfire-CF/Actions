#!/usr/bin/env bash
#
# Meta-test for scripts/source-pin-check.sh (SHA-preferred semantics, RFC-0008).
#
# Verifies the gate:
#   - STRICT=true  on a mixed tree exits 1 and names each FAIL fixture as ::error,
#   - warn_tag (release tag) is emitted as ::warning, never as a fail,
#   - the valid pass fixture (SHA + `# vX.Y.Z`) is never flagged,
#   - STRICT=false (advisory default) on the same tree exits 0 (warn-only) yet
#     still names the FAIL fixtures (as [advisory] ::warning),
#   - a pass+warn-only tree exits 0 even under STRICT=true (no fail-class),
#   - a pass-only tree exits 0 clean.
#
# Fixtures are copied into a temp dir before scanning so the script's built-in
# self-exclusion of tests/fixtures/source-pin/ does not hide them from this test.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHECK="${REPO_ROOT}/scripts/source-pin-check.sh"
FIXTURES="${SCRIPT_DIR}/fixtures/source-pin"

fail() { echo "NOT OK: $1"; exit 1; }

[ -f "$CHECK" ] || fail "check script not found at $CHECK"
[ -x "$CHECK" ] || chmod +x "$CHECK"

# ---- Case 1: mixed tree, STRICT=true → FAIL, names the 3 fails as errors ----
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp "${FIXTURES}/pass.tf" "${FIXTURES}/pass_renovate.tf" "${FIXTURES}/warn_tag.tf" \
   "${FIXTURES}/fail_floating.tf" "${FIXTURES}/fail_branch.tf" "${FIXTURES}/fail_sha.tf" "$work/"

out="$(STRICT=true "$CHECK" "$work" 2>&1)"; code=$?
[ "$code" -eq 1 ] || fail "expected exit 1 on mixed tree (STRICT=true), got $code"
echo "$out" | grep -q "::error .*fail_floating.tf" || fail "fail_floating.tf not flagged as error"
echo "$out" | grep -q "::error .*fail_branch.tf"   || fail "fail_branch.tf not flagged as error"
echo "$out" | grep -q "::error .*fail_sha.tf"      || fail "fail_sha.tf (bare SHA, no comment) not flagged as error"
echo "$out" | grep -q "::warning .*warn_tag.tf"    || fail "warn_tag.tf not emitted as warning"
echo "$out" | grep -q "::error .*warn_tag.tf"      && fail "warn_tag.tf wrongly emitted as error"
echo "$out" | grep -q "pass.tf"                    && fail "pass.tf (SHA + comment) was wrongly flagged"
echo "$out" | grep -q "pass_renovate.tf"           && fail "pass_renovate.tf (Renovate-produced shape) was wrongly flagged"
echo "OK: strict mixed tree fails, 3 fails as errors, warn_tag as warning, pass spared (exit $code)"

# ---- Case 2: mixed tree, STRICT=false (advisory default) → exit 0, warn-only ----
out2="$(STRICT=false "$CHECK" "$work" 2>&1)"; code2=$?
[ "$code2" -eq 0 ] || fail "expected exit 0 on mixed tree (advisory), got $code2"
echo "$out2" | grep -q "::warning file=.*fail_floating.tf.*\[advisory\]" || fail "advisory did not warn on fail_floating.tf"
echo "$out2" | grep -q "::error" && fail "advisory mode must not emit ::error"
echo "OK: advisory mixed tree exits 0, fails downgraded to advisory warnings (exit $code2)"

# ---- Case 3: pass + warn only, STRICT=true → exit 0 (no fail-class) ----
pwdir="$(mktemp -d)"
cp "${FIXTURES}/pass.tf" "${FIXTURES}/warn_tag.tf" "$pwdir/"
out3="$(STRICT=true "$CHECK" "$pwdir" 2>&1)"; code3=$?
rm -rf "$pwdir"
[ "$code3" -eq 0 ] || fail "expected exit 0 on pass+warn tree (STRICT=true), got $code3 ($out3)"
echo "$out3" | grep -q "::warning .*warn_tag.tf" || fail "warn_tag.tf not warned in pass+warn tree"
echo "OK: pass+warn tree passes even under strict (exit $code3)"

# ---- Case 4: pass-only tree → exit 0 clean ----
passdir="$(mktemp -d)"
cp "${FIXTURES}/pass.tf" "$passdir/"
out4="$(STRICT=true "$CHECK" "$passdir" 2>&1)"; code4=$?
rm -rf "$passdir"
[ "$code4" -eq 0 ] || fail "expected exit 0 on pass-only tree, got $code4 ($out4)"
echo "$out4" | grep -q "::warning" && fail "pass-only tree should emit no warnings"
echo "OK: pass-only tree passes clean (exit $code4)"

echo "ALL TESTS PASSED"
