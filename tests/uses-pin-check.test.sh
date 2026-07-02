#!/usr/bin/env bash
#
# Meta-test for scripts/uses-pin-check.sh (SHA-preferred `uses:` gate, RFC-0008).
#
# Verifies the gate:
#   - STRICT=true on a mixed tree exits 1 and names each FAIL fixture as ::error
#     (fail_main = @main, fail_sha_nocomment = bare SHA w/o comment),
#   - warn_tag (version tag) is emitted as ::warning, never as a fail,
#   - pass_sha (SHA + `# vX`) and pass_local (./ ref) are never flagged,
#   - STRICT=false (advisory) on the same tree exits 0 (warn-only) yet still
#     names the FAIL fixtures as [advisory] warnings,
#   - a pass+warn-only tree exits 0 under STRICT=true.
#
# Fixtures are copied into a temp dir so the script's self-exclusion of
# tests/fixtures/uses-pin/ does not hide them.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHECK="${REPO_ROOT}/scripts/uses-pin-check.sh"
FIXTURES="${SCRIPT_DIR}/fixtures/uses-pin"

fail() { echo "NOT OK: $1"; exit 1; }

[ -f "$CHECK" ] || fail "check script not found at $CHECK"
[ -x "$CHECK" ] || chmod +x "$CHECK"

# ---- Case 1: mixed tree, STRICT=true → FAIL, names the 2 fails as errors ----
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp "${FIXTURES}/pass_sha.yml" "${FIXTURES}/pass_local.yml" "${FIXTURES}/warn_tag.yml" \
   "${FIXTURES}/fail_main.yml" "${FIXTURES}/fail_sha_nocomment.yml" "$work/"

out="$(STRICT=true "$CHECK" "$work" 2>&1)"; code=$?
[ "$code" -eq 1 ] || fail "expected exit 1 on mixed tree (STRICT=true), got $code"
echo "$out" | grep -q "::error .*fail_main.yml"          || fail "fail_main.yml (@main) not flagged as error"
echo "$out" | grep -q "::error .*fail_sha_nocomment.yml" || fail "fail_sha_nocomment.yml not flagged as error"
echo "$out" | grep -q "::warning .*warn_tag.yml"         || fail "warn_tag.yml not emitted as warning"
echo "$out" | grep -q "::error .*warn_tag.yml"           && fail "warn_tag.yml wrongly emitted as error"
echo "$out" | grep -q "pass_sha.yml"                     && fail "pass_sha.yml (SHA + comment) wrongly flagged"
echo "$out" | grep -q "pass_local.yml"                   && fail "pass_local.yml (./ ref) wrongly flagged"
echo "OK: strict mixed tree fails, 2 fails as errors, warn_tag as warning, passes spared (exit $code)"

# ---- Case 2: mixed tree, STRICT=false (advisory) → exit 0, warn-only ----
out2="$(STRICT=false "$CHECK" "$work" 2>&1)"; code2=$?
[ "$code2" -eq 0 ] || fail "expected exit 0 on mixed tree (advisory), got $code2"
echo "$out2" | grep -q "::warning file=.*fail_main.yml.*\[advisory\]" || fail "advisory did not warn on fail_main.yml"
echo "$out2" | grep -q "::error" && fail "advisory mode must not emit ::error"
echo "OK: advisory mixed tree exits 0, fails downgraded to advisory warnings (exit $code2)"

# ---- Case 3: pass + warn only, STRICT=true → exit 0 ----
pwdir="$(mktemp -d)"
cp "${FIXTURES}/pass_sha.yml" "${FIXTURES}/pass_local.yml" "${FIXTURES}/warn_tag.yml" "$pwdir/"
out3="$(STRICT=true "$CHECK" "$pwdir" 2>&1)"; code3=$?
rm -rf "$pwdir"
[ "$code3" -eq 0 ] || fail "expected exit 0 on pass+warn tree (STRICT=true), got $code3 ($out3)"
echo "OK: pass+warn tree passes even under strict (exit $code3)"

echo "ALL TESTS PASSED"
