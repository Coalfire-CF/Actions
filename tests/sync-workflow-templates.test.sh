#!/usr/bin/env bash
#
# Guard for scripts/sync-workflow-templates.sh: the org starter workflows in
# Coalfire-CF/.github/workflow-templates are rendered from the bootstrap caller
# templates. Checks that every caller renders, is pinned to the given SHA and
# tag, carries a properties file, uses $default-branch, and that stale files in
# the output dir are removed. A new bootstrap caller with no props() entry fails.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SYNC="${REPO_ROOT}/scripts/sync-workflow-templates.sh"
TAG="v9.9.9"
SHA="0123456789abcdef0123456789abcdef01234567"

fail() { echo "NOT OK: $1"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
out="${work}/workflow-templates"
mkdir -p "$out"
touch "${out}/coalfire-org-release.yml" "${out}/coalfire-org-release.properties.json"

bash "$SYNC" "$TAG" "$SHA" "$out" >/dev/null || fail "sync exited non-zero"

want=0
for t in "${REPO_ROOT}"/templates/bootstrap/{common,terraform}/.github/workflows/*.yml.tmpl; do
  [ -e "$t" ] || continue
  want=$((want + 1))
  name="$(basename "$t" .yml.tmpl)"
  y="${out}/${name}.yml"
  [ -f "$y" ] || fail "${name}.yml not rendered"
  [ -f "${out}/${name}.properties.json" ] || fail "${name}.properties.json missing"
  jq -e '.name and .description and (.categories|length>0)' "${out}/${name}.properties.json" >/dev/null \
    || fail "${name}.properties.json incomplete"
  grep -q "@${SHA} # ${TAG}" "$y" || fail "${name}.yml not pinned to ${SHA} # ${TAG}"
  if grep -q '__[A-Z_]*__' "$y"; then fail "${name}.yml has an unrendered placeholder"; fi
  if grep -qE '(- main$|\[main\])' "$y"; then fail "${name}.yml has a literal main branch"; fi
done
[ "$want" -gt 0 ] || fail "no bootstrap caller templates found"

got="$(find "$out" -name '*.yml' | wc -l | tr -d ' ')"
[ "$got" -eq "$want" ] || fail "rendered ${got} yml files, want ${want}"
[ ! -e "${out}/coalfire-org-release.yml" ] || fail "stale template not removed"
[ ! -e "${out}/coalfire-org-release.properties.json" ] || fail "stale properties not removed"

# A caller with no props() entry must fail the sync.
fake="${work}/tpl"
mkdir -p "${fake}/common/.github/workflows"
printf 'uses: x@__ACTIONS_SHA__ # __ACTIONS_VERSION__\n' > "${fake}/common/.github/workflows/brand-new.yml.tmpl"
if TEMPLATE_DIR="$fake" bash "$SYNC" "$TAG" "$SHA" "${work}/o2" >/dev/null 2>&1; then
  fail "sync accepted a caller with no properties entry"
fi

echo "ok: ${want} workflow templates rendered and pinned"
