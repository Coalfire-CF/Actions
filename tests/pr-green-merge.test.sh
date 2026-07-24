#!/usr/bin/env bash
#
# Meta-test for scripts/pr-green-merge.sh (grade-A #14). A mock `gh` shim records
# every invocation and serves PR snapshot + check-runs fixtures, so the full
# green-gate + merge path runs offline. Focus of this suite (M5/#202): the merge
# is a compare-and-swap — the REST merge carries `sha=$HEAD_SHA` (head pinned at
# green-gate time), and a 409 (head moved) is a clean SKIP, never a merge of
# newer/unreviewed code.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/pr-green-merge.sh"

fail() { echo "NOT OK: $1"; exit 1; }
[ -f "$SCRIPT" ] || fail "pr-green-merge.sh not found at $SCRIPT"
[ -x "$SCRIPT" ] || chmod +x "$SCRIPT"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"
HEAD_SHA="headsha111"

# ---- mock gh: pr view (snapshot) + api (check-runs GET / merge PUT) + argv trace ----
cat > "$BIN/gh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_TRACE"
sub="$1 ${2:-}"
case "$sub" in
  "pr view") cat "$MOCK_PRJSON"; exit 0 ;;
  "api "*|"api")
    # A merge is `gh api --method PUT .../merge …`; anything else is the read.
    for a in "$@"; do
      if [ "$a" = "PUT" ]; then
        if [ -n "${MOCK_MERGE_ERR:-}" ]; then echo "$MOCK_MERGE_ERR" >&2; exit 1; fi
        exit 0
      fi
    done
    cat "$MOCK_CHECKS"; exit 0 ;;
esac
exit 0
MOCK
chmod +x "$BIN/gh"

# Fixtures.
GREEN_CHECKS="$WORK/checks.green.json"
printf '%s' '{"check_runs":[{"name":"CI / build","status":"completed","conclusion":"SUCCESS"}]}' > "$GREEN_CHECKS"
FAIL_CHECKS="$WORK/checks.fail.json"
printf '%s' '{"check_runs":[{"name":"CI / build","status":"completed","conclusion":"FAILURE"}]}' > "$FAIL_CHECKS"

prjson() { # <author-login> -> path (state OPEN, not draft, review null, head pinned)
  local out="$WORK/pr.$RANDOM.json"
  printf '{"state":"OPEN","isDraft":false,"author":{"login":"%s"},"reviewDecision":"","headRefOid":"%s"}' \
    "$1" "$HEAD_SHA" > "$out"; echo "$out"
}

OUT=""; RC=0; TRACE=""
run() {
  : > "$WORK/trace"
  set +e
  OUT="$(env "PATH=$BIN:$PATH" "GH_TRACE=$WORK/trace" \
    REPO="Coalfire-CF/demo" PR_NUMBER=7 MERGE_METHOD=squash RETRY_MAX=1 \
    "$@" bash "$SCRIPT" 2>/dev/null)"
  RC=$?
  set -e
  TRACE="$(cat "$WORK/trace")"
}
assert_line() { echo "$OUT" | grep -qF "$1" || fail "${CASE}: expected '$1', got '$OUT'"; }
assert_rc0()  { [ "$RC" -eq 0 ] || fail "${CASE}: expected rc 0, got $RC (out: $OUT)"; }
assert_nomerge() { echo "$TRACE" | grep -qE 'api --method PUT' && fail "${CASE}: a merge PUT was issued but must not be"; return 0; }

# ---- happy dry-run → WOULD-MERGE, zero mutations ----
CASE="happy dry-run → WOULD-MERGE (no PUT)"
run TOKEN=x MOCK_PRJSON="$(prjson 'app/dependabot')" MOCK_CHECKS="$GREEN_CHECKS"
assert_rc0; assert_line "WOULD-MERGE #7"; assert_nomerge
echo "OK: ${CASE}"

# ---- live happy → MERGED, and the PUT carries sha=$HEAD_SHA (M5/#202 CAS) ----
CASE="live happy → MERGED with compare-and-swap sha"
run DRY_RUN=false MOCK_PRJSON="$(prjson 'app/dependabot')" MOCK_CHECKS="$GREEN_CHECKS"
assert_rc0; assert_line "MERGED #7"
echo "$TRACE" | grep -qE 'api --method PUT .*pulls/7/merge' || fail "${CASE}: merge must go via REST PUT .../pulls/7/merge"
echo "$TRACE" | grep -q "sha=${HEAD_SHA}" || fail "${CASE}: merge must pin the head via sha=${HEAD_SHA} (CAS, #202)"
echo "OK: ${CASE}"

# ---- CAS mismatch: head moved between gate and merge (409) → SKIP head-moved ----
CASE="409 head-moved → SKIP (never merges newer code)"
run DRY_RUN=false MOCK_MERGE_ERR="HTTP 409: Head branch was modified. Review and try the merge again." \
  MOCK_PRJSON="$(prjson 'app/dependabot')" MOCK_CHECKS="$GREEN_CHECKS"
assert_rc0; assert_line "SKIP #7 (head-moved)"
echo "OK: ${CASE}"

# ---- failing checks → SKIP, no merge ----
CASE="red checks → SKIP checks-FAIL"
run DRY_RUN=false MOCK_PRJSON="$(prjson 'app/dependabot')" MOCK_CHECKS="$FAIL_CHECKS"
assert_rc0; assert_line "SKIP #7 (checks-FAIL)"; assert_nomerge
echo "OK: ${CASE}"

# ---- untrusted author → SKIP, no merge ----
CASE="author not allowlisted → SKIP"
run DRY_RUN=false MOCK_PRJSON="$(prjson 'mallory')" MOCK_CHECKS="$GREEN_CHECKS"
assert_rc0; assert_line "SKIP #7 (author-not-allowlisted)"; assert_nomerge
echo "OK: ${CASE}"

# ---- L6/#212: `dependabot[bot]` is a valid glob ([bot] = char class). With a
# matching file in CWD, an unquoted `for a in $AUTHOR_ALLOWLIST` would expand the
# allowlist token against it and corrupt the match → a trusted author wrongly SKIPs.
CASE="#212 author allowlist is glob-safe (CWD decoy does not corrupt match)"
gdir="$WORK/globtest"; mkdir -p "$gdir"; : > "$gdir/dependabott"   # matches dependabot[bot]
prj="$(prjson 'dependabot[bot]')"
( cd "$gdir"
  env "PATH=$BIN:$PATH" "GH_TRACE=$WORK/trace212" \
    REPO="Coalfire-CF/demo" PR_NUMBER=7 MERGE_METHOD=squash RETRY_MAX=1 DRY_RUN=false \
    MOCK_PRJSON="$prj" MOCK_CHECKS="$GREEN_CHECKS" bash "$SCRIPT" > "$WORK/out212" 2>/dev/null
)
grep -qF "MERGED #7" "$WORK/out212" \
  || fail "${CASE}: dependabot[bot] author must still MERGE despite a CWD glob-decoy, got: $(cat "$WORK/out212")"
echo "OK: ${CASE}"

echo "ALL TESTS PASSED"
