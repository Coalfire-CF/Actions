#!/usr/bin/env bash
#
# Meta-test for scripts/version-band-check.sh (RFC-0004 / ADR-0013).
# Band under test: [>= 1.15.7, < 2.0.0].
#
# Builds temp trees inline (a shared .terraform-version filename cannot coexist
# across cases in one dir) and asserts PASS/FAIL + strict behavior.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHECK="${REPO_ROOT}/scripts/version-band-check.sh"
FLOOR="1.15.7"; CEILING="2.0.0"

fail() { echo "NOT OK: $1"; exit 1; }
[ -f "$CHECK" ] || fail "check script not found at $CHECK"
[ -x "$CHECK" ] || chmod +x "$CHECK"

root="$(mktemp -d)"; trap 'rm -rf "$root"' EXIT

# ---- PASS tree: concrete .terraform-version + bounded required_version ----
pass="$root/pass"; mkdir -p "$pass"
printf '1.15.7\n' > "$pass/.terraform-version"
cat > "$pass/main.tf" <<'EOF'
terraform {
  required_version = ">= 1.15.7, < 2.0.0"
}
EOF
cat > "$pass/pessimistic.tf" <<'EOF'
terraform {
  required_version = "~> 1.15.7"
}
EOF
out="$(STRICT=true "$CHECK" "$pass" "$FLOOR" "$CEILING" 2>&1)"; code=$?
[ "$code" -eq 0 ] || fail "PASS tree unexpectedly failed (exit $code): $out"
echo "$out" | grep -q "::error" && fail "PASS tree emitted an error: $out"
echo "OK: in-band concrete + bounded/pessimistic constraints pass (exit $code)"

# ---- PASS: ceiling-only required_version (upper-bounded, no lower anchor) — issue #209 ----
ceil="$root/ceil"; mkdir -p "$ceil"
cat > "$ceil/main.tf" <<'EOF'
terraform {
  required_version = "< 2.0.0"
}
EOF
out="$(STRICT=true "$CHECK" "$ceil" "$FLOOR" "$CEILING" 2>&1)"; code=$?
[ "$code" -eq 0 ] || fail "ceiling-only constraint should pass under strict, got $code: $out"
echo "$out" | grep -q "::error" && fail "ceiling-only constraint emitted an error: $out"
echo "OK: ceiling-only required_version '< 2.0.0' passes under strict (exit $code)"

# ---- FAIL: below floor (.terraform-version) ----
low="$root/low"; mkdir -p "$low"; printf '1.14.9\n' > "$low/.terraform-version"
out="$(STRICT=true "$CHECK" "$low" "$FLOOR" "$CEILING" 2>&1)"; code=$?
[ "$code" -eq 1 ] || fail "below-floor tree should fail under strict, got $code"
echo "$out" | grep -q "::error .*.terraform-version" || fail "below-floor not flagged: $out"
echo "OK: below-floor .terraform-version fails under strict (exit $code)"

# ---- FAIL: above ceiling (terraform_version: in CI yaml) ----
high="$root/high"; mkdir -p "$high/.github/workflows"
cat > "$high/.github/workflows/ci.yml" <<'EOF'
jobs:
  plan:
    with:
      terraform_version: '2.1.0'
EOF
out="$(STRICT=true "$CHECK" "$high" "$FLOOR" "$CEILING" 2>&1)"; code=$?
[ "$code" -eq 1 ] || fail "above-ceiling tree should fail under strict, got $code"
echo "$out" | grep -q "::error .*ci.yml" || fail "above-ceiling terraform_version not flagged: $out"
echo "OK: above-ceiling terraform_version pin fails under strict (exit $code)"

# ---- FAIL: open-ended required_version ----
open="$root/open"; mkdir -p "$open"
cat > "$open/main.tf" <<'EOF'
terraform {
  required_version = ">= 1.15.7"
}
EOF
out="$(STRICT=true "$CHECK" "$open" "$FLOOR" "$CEILING" 2>&1)"; code=$?
[ "$code" -eq 1 ] || fail "open-ended constraint should fail under strict, got $code"
echo "$out" | grep -qi "open-ended" || fail "open-ended not reported: $out"
echo "OK: open-ended required_version fails under strict (exit $code)"

# ---- Advisory: same open-ended tree exits 0 with a warning ----
out="$(STRICT=false "$CHECK" "$open" "$FLOOR" "$CEILING" 2>&1)"; code=$?
[ "$code" -eq 0 ] || fail "advisory mode should exit 0, got $code"
echo "$out" | grep -q "::error" && fail "advisory mode must not emit ::error: $out"
echo "$out" | grep -q "::warning file=.*main.tf.*\[advisory\]" || fail "advisory did not warn: $out"
echo "OK: advisory mode warns and exits 0 (exit $code)"

echo "ALL TESTS PASSED"
