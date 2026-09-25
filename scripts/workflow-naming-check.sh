#!/usr/bin/env bash
#
# workflow-naming-check.sh: enforce the cs-delta workflow naming contract
# (cs-delta docs/pipeline-naming.md, lint rule 20) on this repo's workflows.
#
#   filename      <category>-<purpose>.yml, lower kebab-case
#   name:         "<Category>: <purpose>", unique across files
#   job id        lower kebab-case
#   job name:     required, starts with an upper-case letter
#   run-name      omitted for ci, automation and reusable workflows
#
# Usage: workflow-naming-check.sh [dir]   (default .github/workflows)
# Prints one line per violation and exits 1 if any, else prints the count
# checked and exits 0. A directory with no workflows is an error.
#
set -euo pipefail

DIR="${1:-.github/workflows}"

category_title() {
  case "$1" in
    ci) echo "CI" ;; automation) echo "Automation" ;; setup) echo "Setup" ;;
    deploy) echo "Deploy" ;; ops) echo "Ops" ;; destroy) echo "Destroy" ;;
    release) echo "Release" ;; internal) echo "Internal" ;; reusable) echo "Reusable" ;;
    *) echo "" ;;
  esac
}

shopt -s nullglob
files=("$DIR"/*.yml "$DIR"/*.yaml)
[ "${#files[@]}" -gt 0 ] || { echo "no workflows found in ${DIR}"; exit 1; }

errors=0
names_seen=""
err() { echo "$1"; errors=$((errors + 1)); }

for f in "${files[@]}"; do
  base="$(basename "$f")"
  category=""
  if [[ "$base" =~ ^(ci|automation|setup|deploy|ops|destroy|release|internal|reusable)-([a-z0-9]+-)*[a-z0-9]+\.yml$ ]]; then
    category="${BASH_REMATCH[1]}"
  else
    err "${base}: filename must be <category>-<purpose>.yml in lower kebab-case"
  fi

  display="$(sed -n 's/^name:[[:space:]]*//p' "$f" | head -1 | sed -e 's/^["'\'']//' -e 's/["'\'']$//')"
  if [ -z "$display" ]; then
    err "${base}: workflow name: is required"
  else
    case $'\n'"$names_seen" in
      *$'\n'"$display"$'\n'*) err "${base}: duplicate workflow name '${display}'" ;;
    esac
    names_seen="${names_seen}${display}"$'\n'
    if [ -n "$category" ]; then
      want="$(category_title "$category"): "
      [[ "$display" == "$want"* ]] || err "${base}: name must start with '${want}'"
    fi
  fi

  if [[ "$category" =~ ^(ci|automation|reusable)$ ]] && grep -q '^run-name:' "$f"; then
    err "${base}: ${category} workflows must omit run-name"
  fi

  # Job ids and names: first indented key level under the top-level jobs: key.
  while IFS=$'\t' read -r job_id job_name; do
    [[ "$job_id" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]] \
      || err "${base}: job id '${job_id}' must be lower kebab-case"
    job_name="${job_name#\"}"; job_name="${job_name#\'}"
    # shellcheck disable=SC2016  # literal ${{ prefix of a GitHub expression
    [[ "$job_name" =~ ^[A-Z] ]] || [[ "$job_name" == '${{'* ]] \
      || err "${base}: job '${job_id}' needs a name: starting with an upper-case letter"
  done < <(awk '
    /^jobs:[[:space:]]*$/ { inj = 1; next }
    inj && /^[^[:space:]#]/ { inj = 0 }
    !inj { next }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
      match($0, /^[[:space:]]*/); ind = RLENGTH
      if (jind == 0 && $0 ~ /^[[:space:]]+[A-Za-z0-9_-]+:[[:space:]]*$/) jind = ind
      if (ind == jind && $0 ~ /^[[:space:]]+[A-Za-z0-9_-]+:[[:space:]]*$/) {
        if (id != "") print id "\t" nm
        id = $0; sub(/^[[:space:]]+/, "", id); sub(/:[[:space:]]*$/, "", id); nm = ""; bind = 0; next
      }
      if (id != "" && ind > jind) {
        if (bind == 0) bind = ind
        if (ind == bind && $0 ~ /^[[:space:]]+name:/) { nm = $0; sub(/^[[:space:]]+name:[[:space:]]*/, "", nm) }
      }
    }
    END { if (id != "") print id "\t" nm }' "$f")
done

if [ "$errors" -gt 0 ]; then
  echo "${errors} naming violation(s) in ${#files[@]} workflow(s)"
  exit 1
fi
echo "OK: ${#files[@]} workflow(s) follow the naming contract"
