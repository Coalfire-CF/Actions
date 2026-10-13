#!/usr/bin/env bash
#
# Meta-test for the test_env input of .github/workflows/ci-terratest.yml.
#
# test_env carries non-secret TEST_* KEY=VALUE lines into the Go test. The parse loop lives
# inline in two steps: "Validate inputs" (fail before cloud login) and "Run Terratest"
# (export into that step only). A reusable workflow checks out the CALLER's repo, so the loop
# cannot move to scripts/. This test extracts both steps from the YAML, drives them with the
# same case table, and checks the structure: the two loop copies are byte-identical, only
# those two steps see the input, and no run: body interpolates it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WF="${REPO_ROOT}/.github/workflows/ci-terratest.yml"
DOC="${REPO_ROOT}/docs/ORG_TERRATEST.md"

fail() { echo "NOT OK: $1"; exit 1; }
[ -f "$WF" ] || fail "workflow not found at $WF"
[ -f "$DOC" ] || fail "doc not found at $DOC"
command -v ruby >/dev/null || fail "ruby is required (YAML extraction)"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"

extract_step() {
  ruby -ryaml -e '
    d = YAML.load_file(ARGV[0])
    step = d.fetch("jobs").fetch("terratest").fetch("steps").find { |s| s["name"] == ARGV[1] }
    abort "step not found: #{ARGV[1]}" unless step
    print step.fetch("run")
  ' "$WF" "$1"
}
VALIDATE="$WORK/validate.sh"; RUNSTEP="$WORK/run.sh"
extract_step "Validate inputs" > "$VALIDATE" || fail "could not extract Validate inputs"
extract_step "Run Terratest" > "$RUNSTEP" || fail "could not extract Run Terratest"
[ -s "$VALIDATE" ] && [ -s "$RUNSTEP" ] || fail "an extracted step is empty"

# Mock gotestsum records that it ran and every TEST_* var it inherited. go is a no-op.
cat > "$BIN/gotestsum" <<'MOCK'
#!/usr/bin/env bash
echo ran > "$MOCK_DIR/called"
# List by NAME (compgen -e): `env | grep` would also match the second line of a multi-line
# value such as INPUT_TEST_ENV itself.
for k in $(compgen -e | grep '^TEST_' | sort); do printf '%s=%s\n' "$k" "${!k}"; done > "$MOCK_DIR/seen"
exit 0
MOCK
chmod +x "$BIN/gotestsum"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/go"; chmod +x "$BIN/go"

CASES=0
# run_validate <test_env value>: sets RC, OUT, GHENV (bytes written to $GITHUB_ENV).
run_validate() {
  local ws="$WORK/v.$RANDOM$RANDOM"; mkdir -p "$ws"; : > "$ws/env"
  OUT="$(GITHUB_ENV="$ws/env" GITHUB_OUTPUT="$ws/out" TEST_MODE=pr TEST_DIR=test \
    TEST_TIMEOUT=30m INPUT_TEST_ENV="$1" bash "$VALIDATE" 2>&1)"
  RC=$?
  GHENV="$(wc -c < "$ws/env" | tr -d ' ')"
}
# run_test_step <test_env value>: sets RC, OUT, CALLED (0/1), SEEN (TEST_* env of gotestsum
# minus the step's own TEST_DIR/TEST_TIMEOUT), GHENV (bytes written to $GITHUB_ENV).
run_test_step() {
  local ws="$WORK/r.$RANDOM$RANDOM"; mkdir -p "$ws/test"; : > "$ws/ghenv"
  OUT="$(cd "$ws" && PATH="$BIN:$PATH" MOCK_DIR="$ws" GITHUB_WORKSPACE="$ws" \
    GITHUB_ENV="$ws/ghenv" GITHUB_OUTPUT="$ws/out" TEST_DIR=test TEST_TIMEOUT=30m RERUN_FAILS=0 \
    INPUT_TEST_ENV="$1" bash "$RUNSTEP" 2>&1)"
  RC=$?
  CALLED=0; [ -f "$ws/called" ] && CALLED=1
  SEEN="$(grep -vE '^TEST_(DIR|TIMEOUT)=' "$ws/seen" 2>/dev/null || true)"
  GHENV="$(wc -c < "$ws/ghenv" | tr -d ' ')"
}

# accept <label> <input> <expected key count> <expected exported lines (sorted, \n-joined)>
accept() {
  local label="$1" input="$2" n="$3" want="$4"
  CASES=$((CASES + 1))
  run_validate "$input"
  [ "$RC" -eq 0 ] || fail "$label: Validate should accept, rc=$RC: $OUT"
  printf '%s\n' "$OUT" | grep -qx "test_env: ${n} key(s) validated" \
    || fail "$label: Validate expected '${n} key(s) validated', got: $OUT"
  [ "$GHENV" -eq 0 ] || fail "$label: Validate wrote ${GHENV} byte(s) to GITHUB_ENV"
  run_test_step "$input"
  [ "$RC" -eq 0 ] || fail "$label: Run step should accept, rc=$RC: $OUT"
  [ "$CALLED" -eq 1 ] || fail "$label: gotestsum was not called"
  [ "$SEEN" = "$want" ] || fail "$label: gotestsum saw [$SEEN], want [$want]"
  [ "$GHENV" -eq 0 ] || fail "$label: Run step wrote ${GHENV} byte(s) to GITHUB_ENV"
  echo "ok - accept: $label"
}

# reject <label> <input> <expected error substring>
reject() {
  local label="$1" input="$2" msg="$3"
  CASES=$((CASES + 1))
  run_validate "$input"
  [ "$RC" -ne 0 ] || fail "$label: Validate should reject, got rc=0: $OUT"
  printf '%s\n' "$OUT" | grep -qF -- "$msg" || fail "$label: Validate error missing '$msg': $OUT"
  run_test_step "$input"
  [ "$RC" -ne 0 ] || fail "$label: Run step should reject, got rc=0: $OUT"
  printf '%s\n' "$OUT" | grep -qF -- "$msg" || fail "$label: Run error missing '$msg': $OUT"
  [ "$CALLED" -eq 0 ] || fail "$label: gotestsum must not run on rejected input"
  echo "ok - reject: $label"
}

echo "== structure =="
CASES=$((CASES + 1))
# shellcheck disable=SC2016 # Ruby source; #{...} is Ruby interpolation, not shell
STRUCT="$(ruby -ryaml -e '
  d = YAML.load_file(ARGV[0])
  inp = (d["on"] || d[true]).fetch("workflow_call").fetch("inputs").fetch("test_env")
  abort "test_env must be type string" unless inp["type"] == "string"
  abort "test_env default must be empty" unless inp["default"] == ""
  steps = d.fetch("jobs").values.flat_map { |j| j["steps"] || [] }
  abort "examined 0 steps" if steps.empty?
  runs = steps.select { |s| s["run"] }
  refs = steps.select { |s| s.to_yaml.include?("inputs.test_env") }.map { |s| s["name"] }
  in_run = runs.count { |s| s["run"].include?("inputs.test_env") }
  m = /^ *# >>> test_env parse.*?^ *# <<< test_env parse$/m
  blocks = runs.map { |s| s["run"][m] }.compact
  abort "expected 2 parse blocks, found #{blocks.size}" unless blocks.size == 2
  abort "parse blocks differ" unless blocks[0] == blocks[1]
  abort "parse block too short" unless blocks[0].lines.size > 20
  puts "steps=#{steps.size} runs=#{runs.size} refs=#{refs.join(",")} in_run=#{in_run} block_lines=#{blocks[0].lines.size}"
' "$WF" 2>&1)" || fail "structure: $STRUCT"
echo "$STRUCT"
printf '%s' "$STRUCT" | grep -q 'refs=Validate inputs,Run Terratest ' \
  || fail "structure: inputs.test_env must be referenced by exactly Validate inputs and Run Terratest"
printf '%s' "$STRUCT" | grep -q ' in_run=0 ' || fail "structure: a run: body interpolates inputs.test_env"
echo "ok - structure"

# The doc example, parsed as YAML, is exactly what a caller would send.
# shellcheck disable=SC2016 # Ruby source with a literal Markdown fence
DOC_INPUT="$(ruby -ryaml -e '
  blocks = File.read(ARGV[0]).scan(/^```yaml\n(.*?)^```/m).map(&:first)
  hit = blocks.find { |b| b.include?("test_env: |") } or abort "no test_env example in doc"
  print YAML.safe_load(hit).fetch("with").fetch("test_env")
' "$DOC")" || fail "could not parse the doc example"
# $(...) strips the trailing newline; re-add it so the case is a real YAML | block value.
DOC_INPUT="${DOC_INPUT}"$'\n'

ARN='arn:aws-us-gov:acm-pca:us-gov-west-1:123456789012:certificate-authority/abc-123'
NL=$'\n'

echo "== accepted =="
accept "default empty" "" 0 ""
accept "single pair" "TEST_ACM_PCA_ARN=${ARN}" 1 "TEST_ACM_PCA_ARN=${ARN}"
accept "YAML block trailing newline" "TEST_A=1${NL}TEST_B=2${NL}" 2 "TEST_A=1${NL}TEST_B=2"
accept "blank interior line" "TEST_A=1${NL}${NL}TEST_B=2" 2 "TEST_A=1${NL}TEST_B=2"
accept "whitespace-only line" "TEST_A=1${NL}   	 ${NL}TEST_B=2" 2 "TEST_A=1${NL}TEST_B=2"
accept "doc example (indented YAML block)" "$DOC_INPUT" 2 \
  "TEST_ACM_PCA_ARN=arn:aws-us-gov:acm-pca:us-gov-west-1:123456789012:certificate-authority/example${NL}TEST_TLS_EXTERNAL_DNS_NAME=splunk.example.com"
accept "value containing =" "TEST_Q=a=b==c" 1 "TEST_Q=a=b==c"
accept "value with spaces kept verbatim" "TEST_S= two  words " 1 "TEST_S= two  words "
accept "empty value" "TEST_X=" 1 "TEST_X="

# Injection probes: shell syntax in a value is data, never executed.
PWN="$WORK/pwned"
accept "injection: command substitution" "TEST_I=\$(touch ${PWN})" 1 "TEST_I=\$(touch ${PWN})"
accept "injection: quote break" "TEST_J=\"; touch ${PWN}; echo \"" 1 "TEST_J=\"; touch ${PWN}; echo \""
accept "injection: backticks" "TEST_K=\`touch ${PWN}\`" 1 "TEST_K=\`touch ${PWN}\`"
[ ! -e "$PWN" ] || fail "injection: a probe executed (marker file exists)"

# Values never reach the log; key names do.
CASES=$((CASES + 1))
SECRETISH="not-for-logs-7f3a9c"
run_validate "TEST_V=${SECRETISH}"
printf '%s' "$OUT" | grep -qF "$SECRETISH" && fail "log: Validate printed a value"
run_test_step "TEST_V=${SECRETISH}"
printf '%s' "$OUT" | grep -qF "$SECRETISH" && fail "log: Run step printed a value"
printf '%s' "$OUT" | grep -qx "test_env: exported TEST_V" || fail "log: Run step should name the key"
echo "ok - values not logged, key names logged"

echo "== rejected =="
reject "newline in value (continuation line)" "TEST_A=first${NL}second" "line 2: expected KEY=VALUE"
reject "carriage return" "TEST_A=1"$'\r' "line 1: carriage return not allowed"
reject "CR-only line" "TEST_A=1${NL}"$'\r'"${NL}TEST_B=2" "line 2: carriage return not allowed"
reject "no equals" "TEST_A" "line 1: expected KEY=VALUE"
reject "lowercase key" "test_a=1" "line 1: key must match"
reject "missing TEST_ prefix" "AWS_REGION=us-east-1" "line 1: key must match"
reject "bare TEST_" "TEST_=1" "line 1: key must match"
reject "leading space before key" "  TEST_A=1" "line 1: key must match"
reject "empty key" "=1" "line 1: key must match"
reject "reserved TEST_DIR" "TEST_DIR=../../etc" "TEST_DIR is reserved"
reject "reserved TEST_MODE" "TEST_MODE=release" "TEST_MODE is reserved"
reject "reserved TEST_TIMEOUT" "TEST_TIMEOUT=99h" "TEST_TIMEOUT is reserved"
reject "duplicate key" "TEST_A=1${NL}TEST_B=2${NL}TEST_A=3" "line 3: duplicate key TEST_A"
reject "bad line after good ones" "TEST_A=1${NL}TEST_B=2${NL}oops" "line 3: expected KEY=VALUE"

echo "OK: terratest-test-env.test.sh - ${CASES} cases, 0 failures"
