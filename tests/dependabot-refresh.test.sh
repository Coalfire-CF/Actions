#!/usr/bin/env bash
#
# Meta-test for the Dependabot config generator embedded in
# .github/workflows/automation-dependabot-refresh.yml.
#
# The generator body is an embedded <<'BASH' heredoc (it runs in the consumer
# checkout, so it can't source from Actions at runtime). This test extracts that
# heredoc, strips the 10-space YAML block-scalar indent, and runs it against
# fixture trees to prove:
#   1. Non-github-actions ecosystems collapse every manifest-bearing directory
#      into ONE entry with `directories:` (plural) + `group-by: dependency-name`,
#      so a dependency in real + test fixture dirs lands as one PR, not N.
#   2. Example dirs are dropped (unless include_examples=true), non-terraform
#      test dirs get one grouped entry, first-party terraform modules share one
#      group, and terraform + test entries carry a PR cap.
#   3. github-actions stays byte-identical (singular `directory: "/"` + its
#      org-actions/third-party split, majors excluded) and daily; the rest weekly.
#   4. Output is deterministic (idempotent re-runs -> zero diff).
#   5. The empty-repo `[]` fallback still emits valid YAML.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WF="${REPO_ROOT}/.github/workflows/automation-dependabot-refresh.yml"

fail() { echo "NOT OK: $1"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---- portability: the STAGGER slot uses sha256sum (absent on macOS) ----
SHIM="${WORK}/shim"; mkdir -p "$SHIM"
if ! command -v sha256sum >/dev/null 2>&1; then
  printf '#!/usr/bin/env bash\nshasum -a 256 "$@"\n' > "${SHIM}/sha256sum"
  chmod +x "${SHIM}/sha256sum"
fi
export PATH="${SHIM}:${PATH}"

# ---- extract the embedded script and strip the 10-space block-scalar indent ----
SCRIPT="${WORK}/dependabot_refresh.sh"
awk '
  /cat > \/tmp\/dependabot_refresh\.sh <<'"'"'BASH'"'"'/ {grab=1; next}
  grab && /^          BASH[[:space:]]*$/ {grab=0}
  grab {print}
' "$WF" | sed 's/^          //' > "$SCRIPT"
[ -s "$SCRIPT" ] || fail "failed to extract embedded generator script from $WF"

render() {
  # render <repo_root> <out_file> [extra env assignments...]
  local root="$1" out="$2"
  shift 2
  env "$@" REPO_ROOT="$root" DEPB_PATH="$out" GITHUB_REPOSITORY="Coalfire-CF/terraform-aws-example" \
    bash "$SCRIPT" >/dev/null 2>&1 || true
  [ -f "$out" ] || fail "generator produced no file at $out"
}

# ---- fixture: same module family across real + example + test dirs, plus 2 npm
#      dirs, a singular and a nested example dir, and a terratest go.mod ----
FX="${WORK}/repo"
mkdir -p "${FX}/examples/complete" "${FX}/example" "${FX}/modules/a/examples/b" \
  "${FX}/test/fixtures/foo" "${FX}/frontend" "${FX}/.github/workflows"
cat > "${FX}/versions.tf" <<'EOF'
terraform { required_providers { aws = { source = "hashicorp/aws", version = "5.0.0" } } }
module "vpc" { source = "terraform-aws-modules/vpc/aws" version = "5.0.0" }
EOF
for d in examples/complete example modules/a/examples/b test/fixtures/foo; do
  cp "${FX}/versions.tf" "${FX}/${d}/main.tf"
done
printf 'module example.com/t\n\ngo 1.26\n' > "${FX}/test/go.mod"
echo '{"name":"root"}' > "${FX}/package.json"
echo '{"name":"frontend"}' > "${FX}/frontend/package.json"
printf 'name: ci\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps: []\n' > "${FX}/.github/workflows/ci.yml"

OUT="${WORK}/out.yml"
render "$FX" "$OUT"

countc() { grep -c -- "$1" "$OUT" | tr -d ' '; }
lineof() { grep -n -- "$1" "$OUT" | head -1 | cut -d: -f1; }

# 1. one entry per ecosystem; gomod only has test dirs, so its one entry is the test entry
[ "$(countc 'package-ecosystem: "terraform"')" = "1" ] || fail "expected exactly 1 terraform entry"
[ "$(countc 'package-ecosystem: "npm"')" = "1" ]       || fail "expected exactly 1 npm entry"
[ "$(countc 'package-ecosystem: "gomod"')" = "1" ]     || fail "expected exactly 1 gomod entry"
[ "$(countc 'package-ecosystem: "github-actions"')" = "1" ] || fail "expected 1 github-actions entry"

# 2. only github-actions uses singular `directory:`; terraform, npm, gomod use plural
[ "$(grep -cE '^    directory:' "$OUT")" = "1" ]   || fail "expected exactly 1 singular 'directory:' (github-actions)"
[ "$(grep -cE '^    directories:' "$OUT")" = "3" ] || fail "expected 3 plural 'directories:' (terraform + npm + gomod)"

# 3. example dirs dropped (plural, singular, nested); root + test fixture kept
[ "$(countc '/examples/complete')" = "0" ]    || fail "/examples/complete should be excluded"
[ "$(countc '"/example"')" = "0" ]            || fail "/example should be excluded"
[ "$(countc '/modules/a/examples/b')" = "0" ] || fail "nested example dir should be excluded"
[ "$(countc '      - "/test/fixtures/foo"')" = "1" ] || fail "terraform missing /test/fixtures/foo"
[ "$(countc '      - "/"')" = "2" ] || fail "expected root listed for terraform and npm"

# 4. test go.mod lands in its own grouped entry, listed exactly once (no overlap)
[ "$(countc '      - "/test"')" = "1" ] || fail "expected /test listed exactly once"
tf_line="$(lineof 'package-ecosystem: "terraform"')"
gomod_line="$(lineof 'package-ecosystem: "gomod"')"
test_line="$(lineof '      - "/test"')"
[ "$test_line" -gt "$gomod_line" ] || fail "/test not under the gomod entry"
[ "$(countc '      gomod-test:')" = "1" ] || fail "gomod-test group missing"

# 5. group-by: terraform x2 + npm x2 + gomod-test-security = 5; one security group per entry = 3
[ "$(countc 'group-by: dependency-name')" = "5" ] || fail "expected 5 group-by lines"
[ "$(countc 'applies-to: security-updates')" = "3" ] || fail "expected a security-updates group per non-actions entry"

# 6. update-types: github-actions x2 + coalfire-modules + gomod-test = 4
[ "$(countc 'update-types:')" = "4" ] || fail "expected 4 update-types lines"

# 7. coalfire-modules sits in the terraform entry, ahead of the terraform group (first match wins)
cf_line="$(lineof '      coalfire-modules:')"
tg_line="$(lineof '      terraform:')"
[ -n "$cf_line" ] && [ -n "$tg_line" ] || fail "coalfire-modules or terraform group missing"
{ [ "$cf_line" -gt "$tf_line" ] && [ "$cf_line" -lt "$tg_line" ]; } || fail "coalfire-modules must precede the terraform group"
[ "$(countc 'patterns: \["\*::github::Coalfire-CF/\*"\]')" = "1" ] || fail "coalfire-modules pattern wrong"

# 8. PR caps on terraform and the test entry only
[ "$(countc 'open-pull-requests-limit: 2')" = "2" ] || fail "expected 2 open-pull-requests-limit lines"

# 9. github-actions daily, everything else weekly
[ "$(countc 'interval: "daily"')" = "1" ]  || fail "expected only github-actions on daily"
[ "$(countc 'interval: "weekly"')" = "3" ] || fail "expected 3 weekly entries"

# 10. github-actions block unchanged (org-actions/third-party split intact)
grep -q 'org-actions:' "$OUT" || fail "github-actions org-actions group missing"
grep -q 'exclude-patterns: \["Coalfire-CF/\*"\]' "$OUT" || fail "github-actions third-party exclude missing"

echo "OK: examples dropped, test deps grouped, first-party modules grouped, caps and cadence set"

# ---- include_examples=true keeps all three example dirs ----
OUTX="${WORK}/outx.yml"
render "$FX" "$OUTX" INCLUDE_EXAMPLES=true
[ "$(grep -cE '"/examples/complete"|"/example"|"/modules/a/examples/b"' "$OUTX" | tr -d ' ')" = "3" ] \
  || fail "include_examples=true should keep all 3 example dirs"
echo "OK: include_examples=true keeps example dirs"

# ---- determinism: same inputs -> byte-identical output ----
OUT2="${WORK}/out2.yml"
render "$FX" "$OUT2"
diff -q "$OUT" "$OUT2" >/dev/null || fail "non-deterministic: two renders of the same tree differ"
echo "OK: deterministic — repeated renders are byte-identical"

# ---- empty-repo fallback: valid YAML with an empty updates list ----
EMPTY="${WORK}/empty"; mkdir -p "$EMPTY"
OUT3="${WORK}/empty.yml"
render "$EMPTY" "$OUT3"
grep -q '^updates:' "$OUT3" || fail "empty-repo output missing 'updates:'"
grep -qE '^\s*\[\]' "$OUT3" || fail "empty-repo output missing '[]' fallback"
echo "OK: empty repo emits valid 'updates: []' fallback"

# ---- best-effort YAML validity (skipped if no parser available) ----
if command -v yq >/dev/null 2>&1; then
  [ "$(yq eval '.updates | length' "$OUT")" = "4" ] || fail "yq: expected 4 update entries"
  echo "OK: yq parses the generated dependabot.yml (4 entries)"
elif python3 -c 'import yaml' >/dev/null 2>&1; then
  python3 -c 'import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); assert len(d["updates"])==4' "$OUT" \
    || fail "PyYAML: could not parse generated YAML or wrong entry count"
  echo "OK: PyYAML parses the generated dependabot.yml (4 entries)"
else
  echo "SKIP: no yq / PyYAML available for semantic YAML validation"
fi

echo "ALL OK: dependabot-refresh generator produces grouped, cross-directory config"
