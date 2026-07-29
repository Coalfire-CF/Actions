#!/usr/bin/env bash
#
# Meta-test for the opt-in flake-rerun branch of the "Run Terratest" step in
# .github/workflows/org-terratest.yml (#236 / WI-3.5).
#
# gotestsum has a hard constraint: in --rerun-fails mode the packages must come from
# --packages and must NOT also be passed positionally after `--` (passing both is an
# error). The single-attempt mode is the opposite: packages ARE positional and
# --packages must be absent. A wrong branch here fails only at runtime on a live
# apply, so this test extracts the step from the YAML and drives it through a mock
# gotestsum that RECORDS its argv, asserting each mode invokes gotestsum correctly.
# Mutation-oriented: the two modes must differ in exactly the packages-passing shape.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WF="${REPO_ROOT}/.github/workflows/org-terratest.yml"

fail() { echo "NOT OK: $1"; exit 1; }
[ -f "$WF" ] || fail "workflow not found at $WF"
command -v ruby >/dev/null || fail "ruby is required (YAML extraction)"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"

RUN="$WORK/run.sh"
ruby -ryaml -e '
  d = YAML.load_file(ARGV[0])
  step = d.fetch("jobs").fetch("terratest").fetch("steps").find { |s| s["name"] == "Run Terratest" }
  abort "Run Terratest step not found" unless step
  print step.fetch("run")
' "$WF" > "$RUN" || fail "could not extract Run Terratest step"
[ -s "$RUN" ] || fail "extracted run script is empty"

# Mock gotestsum: record full argv, always succeed. Mock go/tee so the step body runs.
cat > "$BIN/gotestsum" <<'MOCK'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$GOTESTSUM_ARGV"
exit 0
MOCK
chmod +x "$BIN/gotestsum"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/go"; chmod +x "$BIN/go"
# real tee is fine; keep PATH's tee

run_step() {
  local rerun="$1"
  local ws="$WORK/ws.$RANDOM"; mkdir -p "$ws/test"
  : > "$ws/argv"
  set +e
  OUT="$(
    PATH="$BIN:$PATH" \
    GITHUB_WORKSPACE="$ws" GITHUB_OUTPUT="$ws/out" GOTESTSUM_ARGV="$ws/argv" \
    TEST_DIR="test" TEST_TIMEOUT="30m" RERUN_FAILS="$rerun" \
    bash "$RUN" 2>&1
  )"
  RC=$?
  set -e
  # argv as newline-joined (NUL-delimited -> lines) for grep
  ARGV="$(tr '\0' '\n' < "$ws/argv")"
}

echo "== 1. default (rerun_fails=0): packages positional ./..., NO --rerun-fails, NO --packages =="
run_step "0"
[ "$RC" -eq 0 ] || fail "1: step should succeed, got $RC ($OUT)"
printf '%s\n' "$ARGV" | grep -qx -- '--rerun-fails=0' && fail "1: must NOT pass --rerun-fails when disabled"
printf '%s\n' "$ARGV" | grep -q -- '--rerun-fails' && fail "1: must NOT pass --rerun-fails when disabled"
printf '%s\n' "$ARGV" | grep -q -- '--packages' && fail "1: must NOT pass --packages in single-attempt mode"
printf '%s\n' "$ARGV" | grep -qx -- './...' || fail "1: single-attempt mode must pass ./... positionally"

echo "== 2. rerun_fails=2: --rerun-fails=2 + --packages=./..., and ./... NOT also positional =="
run_step "2"
[ "$RC" -eq 0 ] || fail "2: step should succeed, got $RC ($OUT)"
printf '%s\n' "$ARGV" | grep -qx -- '--rerun-fails=2' || fail "2: expected --rerun-fails=2"
printf '%s\n' "$ARGV" | grep -qx -- '--packages=./...' || fail "2: expected --packages=./..."
# In rerun mode ./... must NOT appear as a bare positional arg (that would be the gotestsum error).
if printf '%s\n' "$ARGV" | grep -qx -- './...'; then
  fail "2: ./... must NOT be a positional arg in rerun mode (gotestsum rejects packages given both ways)"
fi

echo "OK: terratest-rerun.test.sh — both invocation modes correct and mutation-proven"
