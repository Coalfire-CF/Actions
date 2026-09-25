#!/usr/bin/env bash
#
# Meta-test for scripts/uses-path-exists-check.sh. A mock `gh` serves the PR
# file list, workflow contents at the PR head, and the Actions contents API
# (exists / 404 / 500), so the gate runs offline. Each case asserts the exact
# checked count, so "examined nothing" can never read as "found nothing".

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/uses-path-exists-check.sh"

fail() { echo "NOT OK: $1"; exit 1; }
[ -f "$SCRIPT" ] || fail "uses-path-exists-check.sh not found at $SCRIPT"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"

# Mock gh. MOCK_FILES: PR files JSON. MOCK_WF_DIR: workflow contents by basename.
# MOCK_EXISTING: newline list of "<path>@<ref>" that exist. MOCK_ERR_PATH: a
# path that returns HTTP 500. Anything else under Coalfire-CF/Actions is a 404.
cat > "$BIN/gh" <<'MOCK'
#!/usr/bin/env bash
url=""
for a in "$@"; do case "$a" in repos/*) url="$a" ;; esac; done
case "$url" in
  repos/Coalfire-CF/demo/pulls/*/files*) cat "$MOCK_FILES"; exit 0 ;;
  repos/Coalfire-CF/demo/contents/*)
    f="${url#repos/Coalfire-CF/demo/contents/}"; f="${f%%\?*}"
    cat "$MOCK_WF_DIR/$(basename "$f")"; exit 0 ;;
  repos/Coalfire-CF/Actions/contents/*)
    p="${url#repos/Coalfire-CF/Actions/contents/}"; path="${p%%\?*}"; ref="${p##*ref=}"
    if [ -n "${MOCK_ERR_PATH:-}" ] && [ "$path" = "$MOCK_ERR_PATH" ]; then
      echo "gh: Server Error (HTTP 500)" >&2; exit 1
    fi
    if grep -qxF "${path}@${ref}" "$MOCK_EXISTING"; then echo '{}'; exit 0; fi
    echo '{"message":"Not Found"}'; echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
esac
echo "unexpected gh call: $*" >&2; exit 1
MOCK
chmod +x "$BIN/gh"

NEW=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
mkdir -p "$WORK/wf"
cat > "$WORK/wf/ci.yml" <<EOF
jobs:
  validate:
    uses: Coalfire-CF/Actions/.github/workflows/ci-terraform-validate.yml@${NEW} # v0.19.0
  release:
    uses: Coalfire-CF/Actions/.github/workflows/release-please.yml@${NEW} # v0.19.0
  # uses: Coalfire-CF/Actions/.github/workflows/org-commented.yml@${NEW}
  scan:
    steps:
      - uses: Coalfire-CF/Actions/actions/gitleaks@${NEW}
      - uses: actions/checkout@v4
EOF
printf '[{"filename":".github/workflows/ci.yml","status":"modified"},{"filename":".github/workflows/gone.yml","status":"removed"},{"filename":"README.md","status":"modified"}]' > "$WORK/files.json"

EXISTING="$WORK/existing"
printf '%s\n' ".github/workflows/ci-terraform-validate.yml@${NEW}" "actions/gitleaks@${NEW}" > "$EXISTING"

OUT=""
run() {
  local out="$WORK/out"; : > "$out"
  env "PATH=$BIN:$PATH" REPO=Coalfire-CF/demo PR_NUMBER=7 HEAD_SHA=headsha \
    MOCK_FILES="$WORK/files.json" MOCK_WF_DIR="$WORK/wf" MOCK_EXISTING="$EXISTING" \
    GITHUB_OUTPUT="$out" "$@" bash "$SCRIPT" 2>/dev/null \
    || fail "script exited non-zero"
  OUT="$(cat "$out")"
}
getval() { sed -n "s/^$1=//p" <<< "$OUT" | head -1; }

# 1. One path removed upstream: flagged, the other two pass, comment ignored.
run
[ "$(getval uses_checked)" = "3" ] || fail "case1 checked '$(getval uses_checked)' != 3"
[ "$(getval uses_missing)" = ".github/workflows/release-please.yml@${NEW}" ] \
  || fail "case1 missing '$(getval uses_missing)'"
[ "$(getval uses_error)" = "false" ] || fail "case1 error"
echo "OK: removed reusable workflow is flagged; commented ref and third-party ignored"

# 2. Control: all paths exist -> nothing missing, still 3 checked.
echo ".github/workflows/release-please.yml@${NEW}" >> "$EXISTING"
run
[ "$(getval uses_checked)" = "3" ] || fail "case2 checked"
[ -z "$(getval uses_missing)" ] || fail "case2 missing '$(getval uses_missing)'"
[ "$(getval uses_error)" = "false" ] || fail "case2 error"
echo "OK: control, every path exists -> none missing"

# 3. Non-404 failure fails closed via uses_error, never reported as missing.
run MOCK_ERR_PATH="actions/gitleaks"
[ "$(getval uses_error)" = "true" ] || fail "case3 error not set on HTTP 500"
[ -z "$(getval uses_missing)" ] || fail "case3 500 misreported as missing"
echo "OK: HTTP 500 sets uses_error, not uses_missing"

# 4. PR touches no workflow files -> 0 checked, clean.
printf '[{"filename":"README.md","status":"modified"}]' > "$WORK/files.json"
run
[ "$(getval uses_checked)" = "0" ] || fail "case4 checked"
[ "$(getval uses_error)" = "false" ] || fail "case4 error"
echo "OK: non-workflow PR checks nothing"

# 5. Unreadable file list fails closed.
echo 'not json' > "$WORK/files.json"
run
[ "$(getval uses_error)" = "true" ] || fail "case5 invalid files list not fail-closed"
echo "OK: invalid PR files response fails closed"

echo "ALL TESTS PASSED"
