#!/usr/bin/env bash
#
# sync-workflow-templates.sh <tag> <sha> <out_dir>: render the org starter
# workflows (the "New workflow" picker in every Coalfire-CF repo) from the
# bootstrap caller templates, pinned to a release.
#
# Source: templates/bootstrap/{common,terraform}/.github/workflows/*.yml.tmpl,
# the same callers repo-bootstrap.sh delivers. Output: <out_dir>/<name>.yml plus
# <name>.properties.json, the layout Coalfire-CF/.github/workflow-templates
# expects. Run by the sync-workflow-templates job in internal-release.yml after
# each release, so the starter workflows never fall behind the baseline.
#
# The script owns <out_dir>: any *.yml or *.properties.json it did not render is
# removed, so a renamed or dropped caller does not linger as a stale template.
#
# Prints the number of templates rendered. Exits non-zero if it rendered none, if
# a caller has no properties entry below, or if a placeholder survives.
#
set -euo pipefail

TAG="${1:?usage: sync-workflow-templates.sh <tag vX.Y.Z> <40-hex sha> <out_dir>}"
SHA="${2:?usage: sync-workflow-templates.sh <tag vX.Y.Z> <40-hex sha> <out_dir>}"
OUT="${3:?usage: sync-workflow-templates.sh <tag vX.Y.Z> <40-hex sha> <out_dir>}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "tag must look like v1.2.3, got '${TAG}'" >&2; exit 2; }
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "sha must be 40 lower-case hex, got '${SHA}'" >&2; exit 2; }

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TEMPLATE_DIR="${TEMPLATE_DIR:-${REPO_ROOT}/templates/bootstrap}"
SETS=(common terraform)

# name|description|category for each caller. A new bootstrap caller without an
# entry here is a hard failure, so it cannot ship without a picker entry.
props() {
  case "$1" in
    release-please) echo 'Coalfire: Release Please|Versioned releases and changelog via the org release-please workflow|Automation' ;;
    automation-dependabot-auto-merge) echo 'Coalfire: Dependabot auto-merge|Gated auto-merge for Dependabot PRs via the org reusable workflow|Automation' ;;
    automation-dependabot-refresh) echo 'Coalfire: Dependabot refresh|Generates a grouped dependabot.yml for the repo on each PR|Automation' ;;
    ci-markdown) echo 'Coalfire: Markdown|Lint changed markdown files on PRs via the org reusable workflow|Continuous integration' ;;
    ci-security-gitleaks) echo 'Coalfire: Security Gitleaks|Scan PRs for committed secrets via the org reusable workflow|Code scanning' ;;
    ci-terraform-docs) echo 'Coalfire: Terraform docs|Generate the Terraform module README on PRs via the org reusable workflow|Continuous integration' ;;
    ci-terraform-format) echo 'Coalfire: Terraform format|Check terraform fmt on pushes and PRs via the org reusable workflow|Continuous integration' ;;
    ci-terraform-validate) echo 'Coalfire: Terraform validate|Run terraform validate on PRs via the org reusable workflow|Continuous integration' ;;
    *) echo "" ;;
  esac
}

mkdir -p "$OUT"
rendered=()
for set in "${SETS[@]}"; do
  src="${TEMPLATE_DIR}/${set}/.github/workflows"
  [ -d "$src" ] || continue
  for t in "$src"/*.yml.tmpl; do
    [ -e "$t" ] || continue
    name="$(basename "$t" .yml.tmpl)"
    p="$(props "$name")"
    [ -n "$p" ] || { echo "no properties entry for ${name}; add it to props() in $0" >&2; exit 1; }
    # Starter workflows use $default-branch in place of a literal branch name.
    # shellcheck disable=SC2016 # $default-branch is literal template syntax
    sed -e "s|__ACTIONS_SHA__|${SHA}|g" \
        -e "s|__ACTIONS_VERSION__|${TAG}|g" \
        -e 's|^\([[:space:]]*\)- main$|\1- $default-branch|' \
        -e 's|branches: \[main\]|branches: [$default-branch]|' \
        "$t" > "${OUT}/${name}.yml"
    if grep -q '__[A-Z_]*__' "${OUT}/${name}.yml"; then
      echo "unrendered placeholder in ${name}.yml" >&2; exit 1
    fi
    IFS='|' read -r title desc category <<<"$p"
    jq -n --arg n "$title" --arg d "$desc" --arg c "$category" \
      '{name: $n, description: $d, iconName: "octicon check-circle", categories: [$c]}' \
      > "${OUT}/${name}.properties.json"
    rendered+=("$name")
  done
done

[ "${#rendered[@]}" -gt 0 ] || { echo "no caller templates found under ${TEMPLATE_DIR}" >&2; exit 1; }

# Drop anything this run did not produce (renamed or retired callers).
for f in "$OUT"/*.yml "$OUT"/*.properties.json; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"; base="${base%.properties.json}"; base="${base%.yml}"
  keep=false
  for n in "${rendered[@]}"; do [ "$n" = "$base" ] && keep=true; done
  [ "$keep" = true ] || rm -f "$f"
done

echo "workflow templates at ${TAG}: ${#rendered[@]}"
