#!/usr/bin/env bash
#
# The org markdownlint policy exists twice: the heredoc ci-markdown.yml writes
# into every caller (what the fleet is linted with) and the root
# .markdownlint-cli2.jsonc this repo lints itself with. The parsed configs must
# be equal. Comments and indentation may differ. Coalfire-CF/Actions#375.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EXTRACT="${REPO_ROOT}/scripts/markdownlint-policy-extract.py"
WF="${REPO_ROOT}/.github/workflows/ci-markdown.yml"
ROOT="${REPO_ROOT}/.markdownlint-cli2.jsonc"

fail() { echo "NOT OK: $1"; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

python3 "$EXTRACT" workflow "$WF" > "$WORK/wf.json" || fail "cannot parse the workflow heredoc"
python3 "$EXTRACT" jsonc "$ROOT" > "$WORK/root.json" || fail "cannot parse .markdownlint-cli2.jsonc"

rules=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["config"]))' "$WORK/wf.json")
[ "$rules" -ge 20 ] || fail "workflow heredoc parsed to $rules rule keys; expected at least 20"

diff -u "$WORK/wf.json" "$WORK/root.json" > "$WORK/diff.txt" \
  || { cat "$WORK/diff.txt"; fail "workflow heredoc and .markdownlint-cli2.jsonc differ"; }

python3 - "$WORK/wf.json" <<'PY' || fail "MD013 is not the 120 org rule"
import json, sys
md013 = json.load(open(sys.argv[1]))["config"]["MD013"]
assert md013 == {"line_length": 120, "code_blocks": False, "tables": False}, md013
PY

# Negative control: a rule value change in one copy must be caught.
sed 's/"line_length": 120/"line_length": 100/' "$ROOT" > "$WORK/mutant.jsonc"
python3 "$EXTRACT" jsonc "$WORK/mutant.jsonc" > "$WORK/mutant.json"
if diff -q "$WORK/wf.json" "$WORK/mutant.json" >/dev/null; then
  fail "a changed line_length went undetected"
fi

echo "ok: org markdownlint policy copies agree ($rules rule keys)"
