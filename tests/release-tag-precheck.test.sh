#!/usr/bin/env bash
#
# Meta-test for scripts/release-tag-precheck.sh. A mock `gh` shim records every
# invocation and serves fixtures, so collision / clear / unstick paths run
# offline. Every case asserts the exact verdict line, GITHUB_OUTPUT keys, and
# that label mutations happen only when APPLY_LABELS=true.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/release-tag-precheck.sh"

fail() { echo "NOT OK: $1"; exit 1; }
[ -x "$SCRIPT" ] || chmod +x "$SCRIPT"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"

HEAD_SHA="def5678aaa111bbbb222cccc333dddd444eeee55"
TAG_SHA="abc1234aaa111bbbb222cccc333dddd444eeee55"
ANNOTATED_TAG_OBJ="eeeeffff00001111222233334444555566667777"

cat > "$BIN/gh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_TRACE"
sub="$1 ${2:-}"
# Endpoint = first non-flag arg after `api`
if [ "$1" = "api" ]; then
  shift
  method="GET"
  ep=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -X) method="$2"; shift 2 ;;
      --jq) shift 2 ;;
      --input) shift 2 ;;
      -f) shift 2 ;;
      -*) shift ;;
      *) ep="$1"; break ;;
    esac
  done
  case "$method:$ep" in
    GET:*/contents/.release-please-manifest.json*)
      if [ "${MOCK_NO_MANIFEST:-0}" = "1" ]; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
      # gh --jq '.content' expects the raw JSON with .content; the script pipes
      # through --jq inside gh, so print the decoded payload as if --jq already
      # ran... but the real gh applies --jq. Our mock dropped --jq above and
      # must print the jq result: base64 content.
      printf '%s' "${MOCK_MANIFEST_B64}"
      exit 0 ;;
    GET:*/contents/release-please-config.json*)
      if [ -z "${MOCK_CONFIG_B64:-}" ]; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
      printf '%s' "${MOCK_CONFIG_B64}"
      exit 0 ;;
    GET:*/git/ref/tags/*)
      if [ "${MOCK_TAG_EXISTS:-0}" != "1" ]; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
      if [ "${MOCK_ANNOTATED:-0}" = "1" ]; then
        printf '{"object":{"type":"tag","sha":"%s"}}' "${MOCK_ANNOTATED_OBJ:-eeeeffff00001111222233334444555566667777}"
      else
        printf '{"object":{"type":"commit","sha":"%s"}}' "${MOCK_TAG_SHA}"
      fi
      exit 0 ;;
    GET:*/git/tags/*)
      # Script always uses --jq '.object.sha'
      printf '%s' "${MOCK_TAG_SHA}"
      exit 0 ;;
    GET:*/releases/tags/*)
      if [ "${MOCK_RELEASE_EXISTS:-0}" != "1" ]; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
      echo '12345'
      exit 0 ;;
    GET:*/commits/*/pulls)
      printf '%s' "${MOCK_PULLS:-[]}"
      exit 0 ;;
    GET:*/commits/*)
      printf '{"message":"%s"}' "${MOCK_COMMIT_MSG:-feat: something}"
      exit 0 ;;
    POST:*/issues/*/labels|DELETE:*/issues/*/labels/*)
      if [ "${MOCK_REJECT_LABELS:-0}" = "1" ]; then echo "MOCK: label mutation rejected" >&2; exit 90; fi
      exit 0 ;;
  esac
  echo "gh: unexpected api ${method} ${ep}" >&2
  exit 1
fi
if [ "$sub" = "pr list" ]; then
  printf '%s' "${MOCK_PENDING_PRS:-[]}"
  exit 0
fi
echo "gh: unexpected $*" >&2
exit 1
MOCK
chmod +x "$BIN/gh"

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

MANIFEST_B64="$(b64 '{".": "4.4.0"}')"
CONFIG_DEFAULT_B64=""  # 404 → include-v-in-tag defaults true
CONFIG_NO_V_B64="$(b64 '{"packages":{".":{"release-type":"simple","include-v-in-tag":false}}}')"

RELEASE_PR='[{"number":338,"title":"chore(main): release 4.4.0","labels":[{"name":"autorelease: pending"}]}]'
FEAT_PR='[{"number":12,"title":"feat: add widgets","labels":[]}]'

OUT=""; RC=0; TRACE=""; GOUT=""
run() {
  local label="$1"
  : > "$WORK/trace"
  : > "$WORK/ghout"
  set +e
  OUT="$(env "PATH=$BIN:$PATH" "GH_TRACE=$WORK/trace" \
    REPO="Coalfire-CF/demo" HEAD_SHA="$HEAD_SHA" \
    RETRY_MAX=1 APPLY_LABELS="${APPLY_LABELS:-false}" \
    GITHUB_OUTPUT="$WORK/ghout" \
    MOCK_MANIFEST_B64="${MOCK_MANIFEST_B64:-$MANIFEST_B64}" \
    MOCK_CONFIG_B64="${MOCK_CONFIG_B64:-}" \
    MOCK_TAG_EXISTS="${MOCK_TAG_EXISTS:-0}" \
    MOCK_RELEASE_EXISTS="${MOCK_RELEASE_EXISTS:-0}" \
    MOCK_TAG_SHA="${MOCK_TAG_SHA:-$TAG_SHA}" \
    MOCK_ANNOTATED="${MOCK_ANNOTATED:-0}" \
    MOCK_NO_MANIFEST="${MOCK_NO_MANIFEST:-0}" \
    MOCK_PULLS="${MOCK_PULLS:-[]}" \
    MOCK_COMMIT_MSG="${MOCK_COMMIT_MSG:-feat: something}" \
    MOCK_PENDING_PRS="${MOCK_PENDING_PRS:-[]}" \
    MOCK_REJECT_LABELS="${MOCK_REJECT_LABELS:-0}" \
    bash "$SCRIPT" 2>"$WORK/err")"
  RC=$?
  set -e
  TRACE="$(cat "$WORK/trace")"
  GOUT="$(cat "$WORK/ghout")"
  echo "CASE ${label}: rc=${RC} out=${OUT}"
}

out_key() { printf '%s' "$GOUT" | awk -F= -v k="$1" '$1==k {print substr($0, index($0,"=")+1)}' | tail -n1; }

# ---- CLEAR: publish attempt, no tag ----
MOCK_COMMIT_MSG="chore(main): release 4.4.0"
MOCK_PULLS="$RELEASE_PR"
MOCK_TAG_EXISTS=0
MOCK_RELEASE_EXISTS=0
run "clear-publish"
[ "$RC" -eq 0 ] || fail "CLEAR should exit 0, got $RC"
printf '%s' "$OUT" | grep -qE '^CLEAR tag=v4.4.0$' || fail "expected CLEAR tag=v4.4.0, got: $OUT"
[ "$(out_key skip_release_please)" = "false" ] || fail "CLEAR must not skip release-please"
[ "$(out_key collision)" = "false" ] || fail "CLEAR collision should be false"
[ "$(out_key supply_chain)" = "false" ] || fail "CLEAR supply_chain should be false"
echo "OK: CLEAR when publishing a version with no existing tag"

# mutation: a tag appearing must flip CLEAR → COLLISION
MOCK_TAG_EXISTS=1
MOCK_RELEASE_EXISTS=1
run "clear-mutates-to-collision"
printf '%s' "$OUT" | grep -qE '^COLLISION ' || fail "adding a release must collide, got: $OUT"
[ "$(out_key collision)" = "true" ] || fail "collision output not true"
echo "OK: mutation — existing GitHub Release flips CLEAR to COLLISION"

# ---- COLLISION: release exists, same or different SHA; skip RP; supply-chain ----
MOCK_COMMIT_MSG="chore(main): release 4.4.0"
MOCK_PULLS="$RELEASE_PR"
MOCK_TAG_EXISTS=1
MOCK_RELEASE_EXISTS=1
run "collision-release-exists"
[ "$RC" -eq 0 ] || fail "script must exit 0 (workflow owns the fail)"
printf '%s' "$OUT" | grep -q "tag=v4.4.0" || fail "collision missing tag: $OUT"
printf '%s' "$OUT" | grep -q "tag_sha=${TAG_SHA}" || fail "collision missing tag_sha: $OUT"
printf '%s' "$OUT" | grep -q "head_sha=${HEAD_SHA}" || fail "collision missing head_sha: $OUT"
printf '%s' "$OUT" | grep -q "release_exists=true" || fail "collision missing release_exists: $OUT"
[ "$(out_key skip_release_please)" = "true" ] || fail "collision must skip release-please"
[ "$(out_key supply_chain)" = "true" ] || fail "existing GitHub Release must enable supply-chain"
[ "$(out_key tag_name)" = "v4.4.0" ] || fail "tag_name should be v4.4.0"
[ "$(out_key pr_number)" = "338" ] || fail "pr_number should be 338"
echo "OK: COLLISION names tag, existing commit, and would-tag commit"

# ---- labels: APPLY_LABELS=false must not mutate ----
printf '%s' "$TRACE" | grep -qE 'issues/.*/labels' && fail "APPLY_LABELS=false must not hit labels API: $TRACE"
echo "OK: mutation — APPLY_LABELS=false performs zero label writes"

APPLY_LABELS=true
run "collision-applies-tagged"
printf '%s' "$TRACE" | grep -qE 'POST .*/issues/338/labels' || fail "expected POST add tagged: $TRACE"
printf '%s' "$TRACE" | grep -qE 'DELETE .*/issues/338/labels/autorelease%3A%20pending' || fail "expected DELETE pending: $TRACE"
echo "OK: COLLISION with GitHub Release applies autorelease: tagged (unstick next versions)"
APPLY_LABELS=false

# ---- tag exists at a different commit, no GitHub Release: still collision, no supply-chain ----
MOCK_RELEASE_EXISTS=0
MOCK_TAG_EXISTS=1
run "collision-wrong-commit-tag-only"
printf '%s' "$OUT" | grep -qE '^COLLISION ' || fail "mismatched tag SHA must collide, got: $OUT"
[ "$(out_key supply_chain)" = "false" ] || fail "tag-only mismatch must not enable supply-chain"
[ "$(out_key skip_release_please)" = "true" ] || fail "mismatched tag must skip release-please"
echo "OK: tag at a different commit with no GitHub Release is a closed collision"

# restore pending (self-heal) when APPLY_LABELS and no release
APPLY_LABELS=true
run "collision-restores-pending"
printf '%s' "$TRACE" | grep -qE 'POST .*/issues/338/labels' || fail "expected POST pending: $TRACE"
printf '%s' "$TRACE" | grep -qE 'DELETE .*/issues/338/labels/autorelease%3A%20tagged' || fail "expected DELETE tagged: $TRACE"
echo "OK: tag-only collision restores autorelease: pending so a later run can self-heal"
APPLY_LABELS=false

# ---- same-commit tag, no GitHub Release: let release-please create the release ----
MOCK_TAG_SHA="$HEAD_SHA"
MOCK_TAG_EXISTS=1
MOCK_RELEASE_EXISTS=0
run "same-commit-tag-only"
printf '%s' "$OUT" | grep -qE '^CLEAR tag=v4.4.0$' || fail "same-commit tag-only should CLEAR, got: $OUT"
[ "$(out_key skip_release_please)" = "false" ] || fail "same-commit tag-only must not skip release-please"
echo "OK: existing tag pointing at HEAD with no GitHub Release lets release-please publish"

# ---- NO_PUBLISH: later feat commit, tag exists for current manifest version ----
MOCK_TAG_SHA="$TAG_SHA"
MOCK_COMMIT_MSG="feat: add widgets"
MOCK_PULLS="$FEAT_PR"
MOCK_TAG_EXISTS=1
MOCK_RELEASE_EXISTS=1
MOCK_PENDING_PRS='[]'
run "no-publish"
printf '%s' "$OUT" | grep -qE '^NO_PUBLISH tag=v4.4.0$' || fail "expected NO_PUBLISH, got: $OUT"
[ "$(out_key skip_release_please)" = "false" ] || fail "NO_PUBLISH must still run release-please (new PR / no-op)"
[ "$(out_key collision)" = "false" ] || fail "NO_PUBLISH must not be a collision"
echo "OK: existing tag on a non-release commit is NO_PUBLISH, not a collision"

# mutation: pending merged PR on that later push → UNSTICK, skip RP
MOCK_PENDING_PRS='[{"number":338,"title":"chore(main): release 4.4.0"}]'
run "unstick-later-push"
printf '%s' "$OUT" | grep -qE '^UNSTICK tag=v4.4.0 pr=338$' || fail "expected UNSTICK, got: $OUT"
[ "$(out_key skip_release_please)" = "true" ] || fail "UNSTICK must skip release-please"
[ "$(out_key collision)" = "false" ] || fail "UNSTICK must not fail the job"
echo "OK: later push with a stuck pending merged PR unsticks without failing"

APPLY_LABELS=true
run "unstick-labels"
printf '%s' "$TRACE" | grep -qE 'POST .*/issues/338/labels' || fail "UNSTICK should apply tagged: $TRACE"
echo "OK: UNSTICK applies autorelease: tagged"
APPLY_LABELS=false

# ---- annotated tag peels to the commit SHA ----
MOCK_COMMIT_MSG="chore(main): release 4.4.0"
MOCK_PULLS="$RELEASE_PR"
MOCK_PENDING_PRS='[]'
MOCK_ANNOTATED=1
MOCK_TAG_EXISTS=1
MOCK_RELEASE_EXISTS=1
run "annotated-tag"
printf '%s' "$OUT" | grep -q "tag_sha=${TAG_SHA}" || fail "annotated tag must peel to commit, got: $OUT"
printf '%s' "$TRACE" | grep -qE 'git/tags/' || fail "annotated tag must fetch git/tags: $TRACE"
echo "OK: annotated tag is peeled to the commit SHA"
MOCK_ANNOTATED=0

# ---- include-v-in-tag: false ----
MOCK_CONFIG_B64="$CONFIG_NO_V_B64"
MOCK_RELEASE_EXISTS=1
MOCK_TAG_EXISTS=1
run "no-v-prefix"
printf '%s' "$OUT" | grep -q "tag=4.4.0" || fail "include-v-in-tag false should use 4.4.0, got: $OUT"
printf '%s' "$TRACE" | grep -qE 'git/ref/tags/4.4.0' || fail "should query tags/4.4.0: $TRACE"
echo "OK: include-v-in-tag false omits the v prefix"
MOCK_CONFIG_B64=""

# ---- missing manifest: CLEAR, do not skip ----
MOCK_NO_MANIFEST=1
MOCK_COMMIT_MSG="chore(main): release 4.4.0"
run "no-manifest"
printf '%s' "$OUT" | grep -qE '^CLEAR$' || fail "missing manifest should CLEAR, got: $OUT"
[ "$(out_key skip_release_please)" = "false" ] || fail "missing manifest must not skip release-please"
echo "OK: missing manifest is CLEAR (release-please reports its own error)"
MOCK_NO_MANIFEST=0

# ---- publish detected from associated PR labels even with a merge-commit subject ----
MOCK_COMMIT_MSG="Merge pull request #338 from Coalfire-CF/release-please--branches--main"
MOCK_PULLS="$RELEASE_PR"
MOCK_TAG_EXISTS=1
MOCK_RELEASE_EXISTS=1
run "merge-commit-subject"
printf '%s' "$OUT" | grep -qE '^COLLISION ' || fail "merge-commit + autorelease PR must collide, got: $OUT"
echo "OK: publish attempt is detected from associated PR labels, not only the subject"

# ---- drift guard: org-release.yml must invoke this script ----
WF="${REPO_ROOT}/.github/workflows/org-release.yml"
[ -f "$WF" ] || fail "org-release.yml not found"
grep -q 'scripts/release-tag-precheck.sh' "$WF" || fail "org-release.yml must invoke scripts/release-tag-precheck.sh"
grep -q 'steps.precheck.outputs.skip_release_please' "$WF" || fail "org-release.yml must skip release-please on precheck.skip_release_please"
grep -q 'steps.precheck.outputs.collision' "$WF" || fail "org-release.yml must fail the job on precheck.collision"
grep -q 'needs.release.outputs.supply_chain' "$WF" || fail "org-release.yml must gate clean/scan jobs on supply_chain"
echo "OK: org-release.yml is wired to the precheck (drift-guarded)"

echo "ALL TESTS PASSED"
