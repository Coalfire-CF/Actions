#!/usr/bin/env bash
#
# Meta-test for scripts/gate-config-resolve.sh (RFC-0010 precedence:
# caller > central > false).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
R="${REPO_ROOT}/scripts/gate-config-resolve.sh"

fail() { echo "NOT OK: $1"; exit 1; }
[ -f "$R" ] || fail "resolver not found at $R"
[ -x "$R" ] || chmod +x "$R"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# central config: source-pin true, others false
cat > "$work/gate-config.yml" <<'EOF'
gates:
  source-pin:   { strict: true }
  uses-pin:     { strict: false }
  version-band: { strict: false }
  opa:          { strict: false }
EOF

eq() { # <desc> <got> <want>
  [ "$2" = "$3" ] || fail "$1: got '$2' want '$3'"
  echo "OK: $1 -> $2"
}

# explicit caller override wins over central
eq "caller=true beats central-false" "$("$R" uses-pin true "$work/gate-config.yml")" "true"
eq "caller=false beats central-true" "$("$R" source-pin false "$work/gate-config.yml")" "false"
# empty caller defers to central
eq "caller='' -> central true"  "$("$R" source-pin '' "$work/gate-config.yml")" "true"
eq "caller='' -> central false" "$("$R" uses-pin '' "$work/gate-config.yml")" "false"
# garbage caller defers to central
eq "caller=garbage -> central true" "$("$R" source-pin 'yes' "$work/gate-config.yml")" "true"
# missing key -> false
eq "missing key -> false" "$("$R" nonexistent '' "$work/gate-config.yml")" "false"
# missing file -> false
eq "missing file -> false" "$("$R" source-pin '' "$work/does-not-exist.yml")" "false"

echo "ALL TESTS PASSED"
