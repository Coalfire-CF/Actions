#!/usr/bin/env bash
#
# Meta-test for scripts/release-patch-merge.sh (Coalfire-CF/Actions#148). A mock
# `gh` shim (per reconcile-sweeper.test.sh) records every invocation and serves
# per-SHA snapshot/manifest/changelog fixtures, so the full fail-closed gate
# chain runs offline. Every case asserts the EXACT decision line, that SKIP /
# dry-run traces contain ZERO merge/approve verbs, and rc 0.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/release-patch-merge.sh"
FIX="${SCRIPT_DIR}/fixtures/release-patch"

fail() { echo "NOT OK: $1"; exit 1; }
[ -x "$SCRIPT" ] || chmod +x "$SCRIPT"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"

# ---- mock gh: dispatch + per-jq scalar emulation + argv trace ----
cat > "$BIN/gh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_TRACE"
sub="$1 ${2:-}"
# find --json field list (if any)
jf=""; i=1; for a in "$@"; do [ "$prev" = "--json" ] && jf="$a"; prev="$a"; done
case "$sub" in
  "pr view")
    if [ "${MOCK_PRVIEW_FAIL:-0}" = "1" ]; then echo "gh: could not resolve to a PullRequest" >&2; exit 1; fi
    if [ "$jf" = "headRefOid,state,labels,reviewDecision" ] && [ -n "${MOCK_RESNAP:-}" ]; then cat "$MOCK_RESNAP"; exit 0; fi
    if [ "$jf" = "statusCheckRollup" ] && [ -n "${MOCK_ROLLUP2:-}" ]; then cat "$MOCK_ROLLUP2"; exit 0; fi
    cat "$MOCK_SNAP"; exit 0 ;;
  "pr checks") [ -n "${MOCK_WATCH_SLEEP:-}" ] && sleep "$MOCK_WATCH_SLEEP"; exit "${MOCK_WATCH_RC:-0}" ;;
  "pr merge")
    if [ "${MOCK_REJECT_WRITES:-0}" = "1" ]; then echo "MOCK: merge rejected (dry-run must not merge)" >&2; exit 90; fi
    if [ -n "${MOCK_MERGE_ERR:-}" ]; then echo "$MOCK_MERGE_ERR" >&2; exit "${MOCK_MERGE_RC:-1}"; fi
    exit "${MOCK_MERGE_RC:-0}" ;;
  "pr review")
    if [ "${MOCK_REJECT_WRITES:-0}" = "1" ]; then echo "MOCK: review rejected" >&2; exit 90; fi
    exit 0 ;;
  "api "*|"api")
    # Any `-X` (PATCH/POST) is an allowed mutation (comment upsert).
    for a in "$@"; do [ "$a" = "-X" ] && exit 0; done
    # Endpoint = first non-flag arg after `api` (robust to --paginate, --jq, …).
    shift; ep=""
    while [ $# -gt 0 ]; do case "$1" in -*) shift ;; *) ep="$1"; break ;; esac; done
    case "$ep" in
      */contents/*)
        ref="${ep##*ref=}"; path="${ep#*/contents/}"; path="${path%%\?*}"
        f=""
        case "$path" in
          *manifest*)  [ "$ref" = "${MOCK_BASE_SHA:-basesha000}" ] && f="$MOCK_MANIFEST_BASE" || f="$MOCK_MANIFEST_HEAD" ;;
          *CHANGELOG*) [ "$ref" = "${MOCK_BASE_SHA:-basesha000}" ] && f="$MOCK_CL_BASE" || f="$MOCK_CL_HEAD" ;;
        esac
        if [ -n "$f" ] && [ -f "$f" ]; then base64 < "$f"; exit 0; fi
        exit 1 ;;                                    # missing file
      */commits/*) printf '%s' "${MOCK_BASE_SHA:-basesha000}"; exit 0 ;;
      */issues/*/comments) printf '%s' "${MOCK_COMMENT_ID:-}"; exit 0 ;;
      repos/*/*) printf '%s' "${MOCK_DEFAULT_BRANCH:-main}"; exit 0 ;;   # default_branch
    esac
    exit 0 ;;
esac
exit 0
MOCK
chmod +x "$BIN/gh"

MERGE_VERBS='pr (merge|review)'
BASE_SHA="basesha000"; HEAD_SHA="headsha111"

# run <label> ; caller pre-sets MOCK_* env. Sets OUT/RC/TRACE globals.
OUT=""; RC=0; TRACE=""
run() {
  : > "$WORK/trace"
  set +e
  # Route ALL env through `env` — words from "$@" expansion are NOT recognized as
  # assignment-prefixes by the shell, but `env VAR=val … cmd` accepts them.
  OUT="$(env "PATH=$BIN:$PATH" "GH_TRACE=$WORK/trace" \
    REPO="Coalfire-CF/demo" PR_NUMBER=42 \
    MERGE_METHOD=squash RETRY_MAX=2 CHECKS_GRACE_TRIES=2 CHECKS_GRACE_SLEEP=0 \
    AUTHOR_ALLOWLIST="app/coalfire-release coalfire-release[bot]" \
    "MOCK_BASE_SHA=$BASE_SHA" \
    "$@" bash "$SCRIPT" 2>/dev/null)"
  RC=$?
  set -e
  TRACE="$(cat "$WORK/trace")"
}
assert_line()  { echo "$OUT" | grep -qF "$1" || fail "${CASE}: expected decision '$1', got '$OUT'"; }
assert_rc0()   { [ "$RC" -eq 0 ] || fail "${CASE}: expected rc 0, got $RC (out: $OUT)"; }
assert_nomerge(){ echo "$TRACE" | grep -qE "$MERGE_VERBS" && fail "${CASE}: a merge/review verb was issued but must not be"; return 0; }

# Build a snapshot with jq overrides from the happy fixture.
snap() { # <jq-filter> -> path
  local out="$WORK/snap.$RANDOM.json"
  jq "$1" "$FIX/snapshot.happy.json" > "$out"; echo "$out"
}

# ---- default env pointers reused across cases ----
export_defaults() {
  MOCK_SNAP="$FIX/snapshot.happy.json"
  MOCK_MANIFEST_BASE="$FIX/manifest.base.json"
  MOCK_MANIFEST_HEAD="$FIX/manifest.patch.json"
  MOCK_CL_BASE="$FIX/changelog.base.md"
  MOCK_CL_HEAD="$FIX/changelog.patch.md"
  MOCK_COMMENT_ID=""; MOCK_RESNAP=""; MOCK_ROLLUP2=""
  MOCK_WATCH_RC=0; MOCK_MERGE_RC=0; MOCK_MERGE_ERR=""; MOCK_REJECT_WRITES=0
}
E() { export_defaults; }   # convenience

# ===================== CASES =====================

CASE="no-app-token (default TOKEN_IS_APP=false)"
E; run MOCK_SNAP="$MOCK_SNAP"   # TOKEN_IS_APP unset → false
assert_rc0; assert_line "SKIP #42 (no-app-token)"; assert_nomerge
echo "OK: ${CASE}"

# From here TOKEN_IS_APP=true. Happy path, dry-run (default).
CASE="happy dry-run → WOULD-MERGE"
E; run TOKEN_IS_APP=true MOCK_SNAP="$MOCK_SNAP" MOCK_MANIFEST_BASE="$MOCK_MANIFEST_BASE" MOCK_MANIFEST_HEAD="$MOCK_MANIFEST_HEAD" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "WOULD-MERGE #42"; assert_nomerge
echo "OK: ${CASE} (zero merge verbs)"

CASE="dry-run zero-mutation (MOCK_REJECT_WRITES=1) still WOULD-MERGE"
E; run TOKEN_IS_APP=true MOCK_REJECT_WRITES=1 MOCK_SNAP="$MOCK_SNAP" MOCK_MANIFEST_BASE="$MOCK_MANIFEST_BASE" MOCK_MANIFEST_HEAD="$MOCK_MANIFEST_HEAD" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "WOULD-MERGE #42"; assert_nomerge
echo "OK: ${CASE}"

CASE="live happy → MERGED, trace has --match-head-commit and NOT --auto"
E; run TOKEN_IS_APP=true DRY_RUN=false MOCK_SNAP="$MOCK_SNAP" MOCK_MANIFEST_BASE="$MOCK_MANIFEST_BASE" MOCK_MANIFEST_HEAD="$MOCK_MANIFEST_HEAD" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "MERGED #42"
echo "$TRACE" | grep -q -- "--match-head-commit $HEAD_SHA" || fail "${CASE}: merge must use --match-head-commit \$HEAD_SHA"
echo "$TRACE" | grep -q -- "--auto" && fail "${CASE}: merge must NEVER use --auto"
echo "OK: ${CASE}"

CASE="title-lies-manifest-decides (files ok, manifest is a MINOR bump)"
E; mb="$WORK/mm.base"; mh="$WORK/mm.head"; printf '{".":"1.2.3"}' >"$mb"; printf '{".":"1.3.0"}' >"$mh"
run TOKEN_IS_APP=true DRY_RUN=false MOCK_SNAP="$MOCK_SNAP" MOCK_MANIFEST_BASE="$mb" MOCK_MANIFEST_HEAD="$mh" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "SKIP #42 (not-patch-only)"; assert_nomerge
echo "OK: ${CASE}"

CASE="smuggled-file (extra changed path outside allowlist)"
E; s="$(snap '.files += [{"path":"scripts/evil.sh"}]')"
run TOKEN_IS_APP=true DRY_RUN=false MOCK_SNAP="$s" MOCK_MANIFEST_BASE="$MOCK_MANIFEST_BASE" MOCK_MANIFEST_HEAD="$MOCK_MANIFEST_HEAD" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "SKIP #42 (unexpected-file)"; assert_nomerge
echo "OK: ${CASE}"

CASE="fork-lookalike (isCrossRepository=true)"
E; s="$(snap '.isCrossRepository=true')"
run TOKEN_IS_APP=true DRY_RUN=false MOCK_SNAP="$s"
assert_rc0; assert_line "SKIP #42 (cross-repository)"; assert_nomerge
echo "OK: ${CASE}"

CASE="wrong-branch with forged label (head not release-please branch)"
E; s="$(snap '.headRefName="feature/sneaky"')"
run TOKEN_IS_APP=true DRY_RUN=false MOCK_SNAP="$s"
assert_rc0; assert_line "SKIP #42 (wrong-branch)"; assert_nomerge
echo "OK: ${CASE}"

CASE="missing pending label"
E; s="$(snap '.labels=[]')"
run TOKEN_IS_APP=true DRY_RUN=false MOCK_SNAP="$s"
assert_rc0; assert_line "SKIP #42 (missing-pending-label)"; assert_nomerge
echo "OK: ${CASE}"

CASE="author not allowlisted"
E; s="$(snap '.author.login="mallory"')"
run TOKEN_IS_APP=true DRY_RUN=false MOCK_SNAP="$s"
assert_rc0; assert_line "SKIP #42 (author-not-allowlisted)"; assert_nomerge
echo "OK: ${CASE}"

CASE="first-release (new package key in manifest)"
E; mb="$WORK/f.base"; mh="$WORK/f.head"; printf '{".":"1.2.3"}' >"$mb"; printf '{".":"1.2.4","pkg/new":"0.1.0"}' >"$mh"
run TOKEN_IS_APP=true DRY_RUN=false MOCK_SNAP="$MOCK_SNAP" MOCK_MANIFEST_BASE="$mb" MOCK_MANIFEST_HEAD="$mh" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "SKIP #42 (first-release)"; assert_nomerge
echo "OK: ${CASE}"

CASE="patch-jump>1 (1.2.3 -> 1.2.5)"
E; mb="$WORK/j.base"; mh="$WORK/j.head"; printf '{".":"1.2.3"}' >"$mb"; printf '{".":"1.2.5"}' >"$mh"
run TOKEN_IS_APP=true DRY_RUN=false MOCK_SNAP="$MOCK_SNAP" MOCK_MANIFEST_BASE="$mb" MOCK_MANIFEST_HEAD="$mh" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "SKIP #42 (not-patch-only)"; assert_nomerge
echo "OK: ${CASE}"

CASE="downgrade (1.2.4 -> 1.2.3)"
E; mb="$WORK/d.base"; mh="$WORK/d.head"; printf '{".":"1.2.4"}' >"$mb"; printf '{".":"1.2.3"}' >"$mh"
run TOKEN_IS_APP=true DRY_RUN=false MOCK_SNAP="$MOCK_SNAP" MOCK_MANIFEST_BASE="$mb" MOCK_MANIFEST_HEAD="$mh" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "SKIP #42 (not-patch-only)"; assert_nomerge
echo "OK: ${CASE}"

CASE="prerelease (1.2.3 -> 1.2.4-rc1)"
E; mb="$WORK/p.base"; mh="$WORK/p.head"; printf '{".":"1.2.3"}' >"$mb"; printf '{".":"1.2.4-rc1"}' >"$mh"
run TOKEN_IS_APP=true DRY_RUN=false MOCK_SNAP="$MOCK_SNAP" MOCK_MANIFEST_BASE="$mb" MOCK_MANIFEST_HEAD="$mh" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "SKIP #42 (not-patch-only)"; assert_nomerge
echo "OK: ${CASE}"

CASE="major bump (1.2.3 -> 2.0.0)"
E; mb="$WORK/M.base"; mh="$WORK/M.head"; printf '{".":"1.2.3"}' >"$mb"; printf '{".":"2.0.0"}' >"$mh"
run TOKEN_IS_APP=true DRY_RUN=false MOCK_SNAP="$MOCK_SNAP" MOCK_MANIFEST_BASE="$mb" MOCK_MANIFEST_HEAD="$mh" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "SKIP #42 (not-patch-only)"; assert_nomerge
echo "OK: ${CASE}"

CASE="no version change"
E; mb="$WORK/n.base"; mh="$WORK/n.head"; printf '{".":"1.2.3"}' >"$mb"; printf '{".":"1.2.3"}' >"$mh"
run TOKEN_IS_APP=true DRY_RUN=false MOCK_SNAP="$MOCK_SNAP" MOCK_MANIFEST_BASE="$mb" MOCK_MANIFEST_HEAD="$mh" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "SKIP #42 (no-version-change)"; assert_nomerge
echo "OK: ${CASE}"

CASE="inconsistent-changelog (patch manifest, but changelog adds ### Features)"
E; clh="$WORK/cl.head"; printf '# Changelog\n\n## 1.2.4\n### Features\n* sneaky feature\n' > "$clh"
run TOKEN_IS_APP=true DRY_RUN=false MOCK_SNAP="$MOCK_SNAP" MOCK_MANIFEST_BASE="$MOCK_MANIFEST_BASE" MOCK_MANIFEST_HEAD="$MOCK_MANIFEST_HEAD" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$clh"
assert_rc0; assert_line "SKIP #42 (inconsistent-changelog)"; assert_nomerge
echo "OK: ${CASE}"

CASE="review-required"
E; s="$(snap '.reviewDecision="REVIEW_REQUIRED"')"
run TOKEN_IS_APP=true DRY_RUN=false MOCK_SNAP="$s" MOCK_MANIFEST_BASE="$MOCK_MANIFEST_BASE" MOCK_MANIFEST_HEAD="$MOCK_MANIFEST_HEAD" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "SKIP #42 (review-REVIEW_REQUIRED)"; assert_nomerge
echo "OK: ${CASE}"

CASE="zero-checks fail-closed"
E; s="$(snap '.statusCheckRollup=[]')"
run TOKEN_IS_APP=true DRY_RUN=false MOCK_SNAP="$s" MOCK_MANIFEST_BASE="$MOCK_MANIFEST_BASE" MOCK_MANIFEST_HEAD="$MOCK_MANIFEST_HEAD" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "SKIP #42 (zero-checks)"; assert_nomerge
echo "OK: ${CASE}"

CASE="zero-checks ALLOW flag → MERGED"
E; s="$(snap '.statusCheckRollup=[]')"
run TOKEN_IS_APP=true DRY_RUN=false ALLOW_ZERO_CHECKS=true MOCK_SNAP="$s" MOCK_MANIFEST_BASE="$MOCK_MANIFEST_BASE" MOCK_MANIFEST_HEAD="$MOCK_MANIFEST_HEAD" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "MERGED #42"
echo "OK: ${CASE}"

CASE="red checks → SKIP checks-fail"
E; s="$(snap '.statusCheckRollup=[{"status":"COMPLETED","conclusion":"FAILURE"}]')"
run TOKEN_IS_APP=true DRY_RUN=false MOCK_SNAP="$s" MOCK_MANIFEST_BASE="$MOCK_MANIFEST_BASE" MOCK_MANIFEST_HEAD="$MOCK_MANIFEST_HEAD" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "SKIP #42 (checks-fail)"; assert_nomerge
echo "OK: ${CASE}"

CASE="pending checks, watch fails → checks-not-green"
E; s="$(snap '.statusCheckRollup=[{"status":"IN_PROGRESS","conclusion":null}]')"
run TOKEN_IS_APP=true DRY_RUN=false MOCK_WATCH_RC=8 MOCK_SNAP="$s" MOCK_MANIFEST_BASE="$MOCK_MANIFEST_BASE" MOCK_MANIFEST_HEAD="$MOCK_MANIFEST_HEAD" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "SKIP #42 (checks-not-green)"; assert_nomerge
echo "OK: ${CASE}"

CASE="head-moved TOCTOU (re-snapshot oid differs)"
E; rs="$WORK/resnap.json"; jq '{headRefOid:"DIFFERENT999",state:"OPEN",labels:.labels,reviewDecision:.reviewDecision}' "$FIX/snapshot.happy.json" > "$rs"
run TOKEN_IS_APP=true DRY_RUN=false MOCK_RESNAP="$rs" MOCK_SNAP="$MOCK_SNAP" MOCK_MANIFEST_BASE="$MOCK_MANIFEST_BASE" MOCK_MANIFEST_HEAD="$MOCK_MANIFEST_HEAD" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "SKIP #42 (head-moved)"; assert_nomerge
echo "OK: ${CASE}"

CASE="merge-race benign (405) → SKIP merge-raced rc0"
E; run TOKEN_IS_APP=true DRY_RUN=false MOCK_MERGE_RC=1 MOCK_MERGE_ERR="HTTP 405: Base branch was modified. Review and try the merge again." MOCK_SNAP="$MOCK_SNAP" MOCK_MANIFEST_BASE="$MOCK_MANIFEST_BASE" MOCK_MANIFEST_HEAD="$MOCK_MANIFEST_HEAD" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "SKIP #42 (merge-raced)"
echo "OK: ${CASE}"

CASE="comment upsert edits existing (2nd run, MOCK_COMMENT_ID set)"
E; run TOKEN_IS_APP=true DRY_RUN=false MOCK_COMMENT_ID=555 MOCK_SNAP="$MOCK_SNAP" MOCK_MANIFEST_BASE="$MOCK_MANIFEST_BASE" MOCK_MANIFEST_HEAD="$MOCK_MANIFEST_HEAD" MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "MERGED #42"
echo "$TRACE" | grep -q 'api -X PATCH repos/Coalfire-CF/demo/issues/comments/555' || fail "${CASE}: expected a PATCH edit of comment 555 (not a re-post)"
echo "$TRACE" | grep -q 'api -X POST repos/Coalfire-CF/demo/issues/42/comments' && fail "${CASE}: must NOT POST a new comment when one exists"
# M6/#203: the marker lookup must paginate, or a PR with >30 comments never finds
# the existing marker and the upsert degrades to append.
echo "$TRACE" | grep -qE 'api --paginate .*issues/42/comments' || fail "${CASE}: comment lookup must use --paginate (#203)"
echo "OK: ${CASE}"

CASE="#214 permanent 404 is not retried (base-manifest read happens once)"
E; run TOKEN_IS_APP=true DRY_RUN=false RETRY_MAX=3 MOCK_SNAP="$MOCK_SNAP" \
  MOCK_MANIFEST_BASE="$WORK/nope-manifest.json" MOCK_MANIFEST_HEAD="$MOCK_MANIFEST_HEAD" \
  MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "SKIP #42 (missing-manifest)"; assert_nomerge
n=$(echo "$TRACE" | grep -cE 'contents/.*manifest.*ref=basesha000')
[ "$n" -eq 1 ] || fail "${CASE}: base-manifest 404 attempted ${n}× (expected 1 — a 404 is permanent, must not spin RETRY_MAX times)"
echo "OK: ${CASE}"

# L7/#213: bound the pending-checks watch so a stuck check can't hang the step.
# Requires coreutils `timeout` (present on CI ubuntu; skipped where absent, e.g. stock macOS).
if command -v timeout >/dev/null 2>&1; then
  CASE="#213 watch times out → checks-not-green (bounded, no hang)"
  E; s="$(snap '.statusCheckRollup=[{"status":"IN_PROGRESS","conclusion":null}]')"
  run TOKEN_IS_APP=true DRY_RUN=false CHECKS_WATCH_TIMEOUT=1 MOCK_WATCH_SLEEP=8 MOCK_SNAP="$s" \
    MOCK_MANIFEST_BASE="$MOCK_MANIFEST_BASE" MOCK_MANIFEST_HEAD="$MOCK_MANIFEST_HEAD" \
    MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
  assert_rc0; assert_line "SKIP #42 (checks-not-green)"; assert_nomerge
  echo "OK: ${CASE}"
else
  echo "SKIP (no timeout(1) on this host): #213 watch-timeout case"
fi

CASE="missing-manifest (404 at base) → SKIP, no merge"
E; run TOKEN_IS_APP=true DRY_RUN=false RETRY_MAX=1 MOCK_SNAP="$MOCK_SNAP" \
  MOCK_MANIFEST_BASE="$WORK/does-not-exist.json" MOCK_MANIFEST_HEAD="$MOCK_MANIFEST_HEAD" \
  MOCK_CL_BASE="$MOCK_CL_BASE" MOCK_CL_HEAD="$MOCK_CL_HEAD"
assert_rc0; assert_line "SKIP #42 (missing-manifest)"; assert_nomerge
echo "OK: ${CASE}"

CASE="snapshot-unavailable (persistent pr-view failure) → SKIP rc0, no merge"
E; run TOKEN_IS_APP=true DRY_RUN=false RETRY_MAX=1 MOCK_PRVIEW_FAIL=1 MOCK_SNAP="$MOCK_SNAP"
assert_rc0; assert_line "SKIP #42 (snapshot-unavailable)"; assert_nomerge
echo "OK: ${CASE}"

echo "ALL TESTS PASSED"
