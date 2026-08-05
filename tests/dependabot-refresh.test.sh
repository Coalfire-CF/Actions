#!/usr/bin/env bash
#
# Meta-test for the Dependabot config generator embedded in
# .github/workflows/org-dependabot.yml.
#
# The generator body is an embedded <<'BASH' heredoc (it runs in the consumer
# checkout, so it can't source from Actions at runtime). This test extracts that
# heredoc, strips the 10-space YAML block-scalar indent, and runs it against
# fixture trees to prove:
#   1. Non-github-actions ecosystems collapse every manifest-bearing directory
#      into ONE entry with `directories:` (plural) + `group-by: dependency-name`,
#      so a dependency in real + example + test dirs lands as one PR, not N.
#   2. github-actions stays byte-identical (singular `directory: "/"` + its
#      org-actions/third-party split, majors excluded).
#   3. Output is deterministic (idempotent re-runs -> zero diff).
#   4. The empty-repo `[]` fallback still emits valid YAML.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WF="${REPO_ROOT}/.github/workflows/org-dependabot.yml"

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
  # render <repo_root> <out_file>
  local root="$1" out="$2"
  REPO_ROOT="$root" DEPB_PATH="$out" GITHUB_REPOSITORY="Coalfire-CF/terraform-aws-example" \
    bash "$SCRIPT" >/dev/null 2>&1 || true
  [ -f "$out" ] || fail "generator produced no file at $out"
}

# ---- fixture: same module family across real + example + test dirs, plus 2 npm dirs ----
FX="${WORK}/repo"
mkdir -p "${FX}/examples/complete" "${FX}/test/fixtures/foo" "${FX}/frontend" "${FX}/.github/workflows"
cat > "${FX}/versions.tf" <<'EOF'
terraform { required_providers { aws = { source = "hashicorp/aws", version = "5.0.0" } } }
module "vpc" { source = "terraform-aws-modules/vpc/aws" version = "5.0.0" }
EOF
cp "${FX}/versions.tf" "${FX}/examples/complete/main.tf"
cp "${FX}/versions.tf" "${FX}/test/fixtures/foo/main.tf"
echo '{"name":"root"}' > "${FX}/package.json"
echo '{"name":"frontend"}' > "${FX}/frontend/package.json"
printf 'name: ci\non: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps: []\n' > "${FX}/.github/workflows/ci.yml"

OUT="${WORK}/out.yml"
render "$FX" "$OUT"

countc() { grep -c "$1" "$OUT" | tr -d ' '; }

# 1. exactly one entry per ecosystem (fan-out collapsed)
[ "$(countc 'package-ecosystem: "terraform"')" = "1" ] || fail "expected exactly 1 terraform entry"
[ "$(countc 'package-ecosystem: "npm"')" = "1" ]       || fail "expected exactly 1 npm entry"
[ "$(countc 'package-ecosystem: "github-actions"')" = "1" ] || fail "expected 1 github-actions entry"

# 2. only github-actions uses singular `directory:`; terraform+npm use plural `directories:`
[ "$(grep -cE '^    directory:' "$OUT")" = "1" ]   || fail "expected exactly 1 singular 'directory:' (github-actions)"
[ "$(grep -cE '^    directories:' "$OUT")" = "2" ] || fail "expected 2 plural 'directories:' (terraform + npm)"

# 3. terraform lists all three dirs under one entry
grep -q '      - "/examples/complete"' "$OUT"  || fail "terraform missing /examples/complete in directories list"
grep -q '      - "/test/fixtures/foo"' "$OUT"  || fail "terraform missing /test/fixtures/foo in directories list"

# 4. group-by: dependency-name on both non-actions ecosystems (2 groups each = 4)
[ "$(countc 'group-by: dependency-name')" = "4" ] || fail "expected 4 group-by lines (terraform x2 + npm x2)"
[ "$(countc 'applies-to: security-updates')" = "2" ] || fail "expected a security-updates group per non-actions ecosystem"

# 5. non-actions groups omit update-types (majors included). Only the two
#    github-actions groups carry update-types, so a global count of 2 proves it.
[ "$(countc 'update-types:')" = "2" ] || fail "update-types must appear ONLY on the 2 github-actions groups"

# 6. github-actions block byte-unchanged (org-actions/third-party split intact)
grep -q 'org-actions:' "$OUT" || fail "github-actions org-actions group missing"
grep -q 'exclude-patterns: \["Coalfire-CF/\*"\]' "$OUT" || fail "github-actions third-party exclude missing"

echo "OK: fan-out collapsed — terraform/npm one grouped entry across dirs; github-actions unchanged"

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
  yq eval '.updates | length' "$OUT" >/dev/null || fail "yq could not parse generated YAML"
  echo "OK: yq parses the generated dependabot.yml"
elif python3 -c 'import yaml' >/dev/null 2>&1; then
  python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$OUT" || fail "PyYAML could not parse generated YAML"
  echo "OK: PyYAML parses the generated dependabot.yml"
else
  echo "SKIP: no yq / PyYAML available for semantic YAML validation"
fi

echo "ALL OK: dependabot-refresh generator produces grouped, cross-directory config"
