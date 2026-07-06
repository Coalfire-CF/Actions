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

# --- item #5: block-style parsing + fail-closed on unparseable (grade-A plan) ---

# block-style config: a valid-YAML reformat must resolve correctly, not silently false
cat > "$work/gate-config-block.yml" <<'EOF'
gates:
  source-pin:
    strict: true
  uses-pin:
    strict: false
  opa:
    # comment inside the block is fine
    strict: false
EOF
eq "block-style strict:true -> true"   "$("$R" source-pin '' "$work/gate-config-block.yml")" "true"
eq "block-style strict:false -> false" "$("$R" uses-pin '' "$work/gate-config-block.yml")" "false"
eq "block-style with comment -> false" "$("$R" opa '' "$work/gate-config-block.yml")" "false"
eq "block-style missing key -> false"  "$("$R" version-band '' "$work/gate-config-block.yml")" "false"

# present-but-unparseable key -> non-zero exit (fail closed), never "false"
cat > "$work/gate-config-broken.yml" <<'EOF'
gates:
  source-pin:
    enabled: yes
  uses-pin: { strict: maybe }
EOF
if out="$("$R" source-pin '' "$work/gate-config-broken.yml" 2>/dev/null)"; then
  fail "present key without parseable strict must exit non-zero (got '$out')"
else
  echo "OK: present key without strict -> fail-closed (non-zero exit)"
fi
if out="$("$R" uses-pin '' "$work/gate-config-broken.yml" 2>/dev/null)"; then
  fail "present key with garbage strict must exit non-zero (got '$out')"
else
  echo "OK: present key with garbage strict -> fail-closed (non-zero exit)"
fi
# caller override still bypasses a broken config (precedence preserved)
eq "caller=true bypasses broken config" "$("$R" source-pin true "$work/gate-config-broken.yml")" "true"

echo "ALL TESTS PASSED"
