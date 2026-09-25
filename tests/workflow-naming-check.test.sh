#!/usr/bin/env bash
#
# Meta-test for scripts/workflow-naming-check.sh. Builds one good workflow and a
# set of single-defect variants; the good one must pass and each variant must
# fail with its own message. Ends with the real .github/workflows passing.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHECK="${REPO_ROOT}/scripts/workflow-naming-check.sh"

fail() { echo "NOT OK: $1"; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

good() {
  cat <<'EOF'
name: "CI: Terraform validate"
on:
  workflow_call:
jobs:
  verify:
    name: Validate Terraform configuration
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
  notify-failure:
    name: Notify on failure
    needs: verify
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
EOF
}

# case <label> <filename> <expected message> <sed expression or empty>
case_run() {
  local label="$1" file="$2" want="$3" expr="$4" dir="$WORK/$1" out rc
  mkdir -p "$dir"
  if [ -n "$expr" ]; then good | sed -e "$expr" > "$dir/$file"; else good > "$dir/$file"; fi
  out="$(bash "$CHECK" "$dir" 2>&1)"; rc=$?
  if [ -z "$want" ]; then
    [ "$rc" -eq 0 ] || fail "${label}: expected pass, got rc=${rc}: ${out}"
  else
    [ "$rc" -ne 0 ] || fail "${label}: expected failure, passed"
    grep -qF "$want" <<< "$out" || fail "${label}: missing '${want}' in: ${out}"
  fi
  echo "OK: ${label}"
}

case_run good          ci-terraform-validate.yml ""                                   ""
case_run bad-filename  org-terraform-validate.yml "filename must be"                  ""
case_run bad-prefix    ci-terraform-validate.yml "name must start with 'CI: '"        's/^name: .*/name: "Terraform Validate"/'
case_run bad-job-id    ci-terraform-validate.yml "job id 'verify_tf'"                 's/^  verify:/  verify_tf:/'
case_run no-job-name   ci-terraform-validate.yml "job 'notify-failure' needs a name"  '/name: Notify on failure/d'
case_run lower-name    ci-terraform-validate.yml "job 'verify' needs a name"          's/name: Validate Terraform/name: validate Terraform/'
case_run run-name      ci-terraform-validate.yml "must omit run-name"                 's/^on:/run-name: x\non:/'

# Duplicate display names across two files.
mkdir -p "$WORK/dup"; good > "$WORK/dup/ci-a.yml"; good > "$WORK/dup/ci-b.yml"
out="$(bash "$CHECK" "$WORK/dup" 2>&1)" && fail "dup: expected failure"
grep -qF "duplicate workflow name" <<< "$out" || fail "dup: missing message: $out"
echo "OK: duplicate names"

# Empty directory is an error, not a pass.
mkdir -p "$WORK/empty"
bash "$CHECK" "$WORK/empty" >/dev/null 2>&1 && fail "empty dir passed"
echo "OK: empty dir fails"

# The repo itself.
out="$(bash "$CHECK" "${REPO_ROOT}/.github/workflows" 2>&1)" || fail "repo workflows: ${out}"
echo "OK: repo workflows (${out})"
echo "ALL TESTS PASSED"
