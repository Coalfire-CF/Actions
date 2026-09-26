#!/usr/bin/env bash
#
# Meta-test for scripts/release-publish-draft.sh.
#
# Drives the script through a MOCK `gh` that serves a fixture release list and
# records every call, to prove it publishes a draft only when release-clean
# succeeded and the required asset is attached, leaves an already published
# release alone, and exits non-zero (without publishing) otherwise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/release-publish-draft.sh"

fail() { echo "NOT OK: $1"; exit 1; }
[ -f "$SCRIPT" ] || fail "script not found at $SCRIPT"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"
export GH_TRACE="$WORK/trace" MOCK_RELEASES="$WORK/releases.json" MOCK_STATE="$WORK/state"

# Mock gh. `release edit` flips MOCK_STATE to published unless MOCK_EDIT_NOOP=1;
# the post-publish read (`api .../releases/<id> --jq .draft`) reports that state.
cat > "$BIN/gh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_TRACE"
if [ "$1" = "api" ] && [ "$2" = "--paginate" ]; then cat "$MOCK_RELEASES"; exit 0; fi
if [ "$1" = "release" ] && [ "$2" = "edit" ]; then
  [ "${MOCK_EDIT_NOOP:-0}" = "1" ] || echo published > "$MOCK_STATE"
  exit 0
fi
if [ "$1" = "api" ] && printf '%s' "$2" | grep -qE '/releases/[0-9]+$'; then
  if [ "$(cat "$MOCK_STATE" 2>/dev/null)" = "published" ]; then echo false; else echo true; fi
  exit 0
fi
echo "mock gh: unexpected call: $*" >&2; exit 1
MOCK
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

# releases <json-array-of-releases>: write one slurped page.
releases() { printf '[%s]\n' "$1" > "$MOCK_RELEASES"; }
DRAFT_OK='{"id":7,"tag_name":"v1.2.0","draft":true,"immutable":false,"assets":[{"name":"r-v1.2.0-clean.tar.gz"},{"name":"cosign.pub"}]}'
DRAFT_NOASSET='{"id":7,"tag_name":"v1.2.0","draft":true,"immutable":false,"assets":[{"name":"trivy_release_results.json"}]}'
PUBLISHED='{"id":7,"tag_name":"v1.2.0","draft":false,"immutable":true,"assets":[]}'
OTHER='{"id":6,"tag_name":"v1.1.0","draft":false,"immutable":true,"assets":[]}'

run() {
  # run <expected-exit> <env assignments...>; sets OUT
  local want="$1"; shift
  : > "$GH_TRACE"; rm -f "$MOCK_STATE"
  OUT="$(env REPO=Coalfire-CF/r TAG_NAME=v1.2.0 "$@" bash "$SCRIPT" 2>&1)"
  local got=$?
  [ "$got" = "$want" ] || fail "expected exit $want, got $got: $OUT"
}
edits() { grep -c '^release edit' "$GH_TRACE" | tr -d ' '; }

releases "[${OTHER},${DRAFT_OK}]"
run 0 CLEAN_RESULT=success REQUIRE_ASSET=-clean.tar.gz
[ "$(edits)" = "1" ] || fail "draft with clean asset should be published once"
grep -q '^release edit v1.2.0 --repo Coalfire-CF/r --draft=false --latest' "$GH_TRACE" || fail "wrong edit call"
echo "OK: draft with the clean tarball is published"

releases "[${DRAFT_OK}]"
run 0 CLEAN_RESULT=skipped
[ "$(edits)" = "1" ] || fail "clean_release off (skipped, no required asset) should still publish"
echo "OK: publishes when release-clean is skipped and no asset is required"

releases "[${PUBLISHED}]"
run 0 CLEAN_RESULT=success REQUIRE_ASSET=-clean.tar.gz
[ "$(edits)" = "0" ] || fail "already published release must not be edited"
printf '%s' "$OUT" | grep -q 'already published (immutable=true, assets=0)' || fail "missing warning: $OUT"
echo "OK: already published release is left alone with a warning"

releases "[${DRAFT_OK}]"
run 1 CLEAN_RESULT=failure REQUIRE_ASSET=-clean.tar.gz
[ "$(edits)" = "0" ] || fail "release-clean failure must not publish"
echo "OK: release-clean failure leaves the draft"

releases "[${DRAFT_NOASSET}]"
run 1 CLEAN_RESULT=success REQUIRE_ASSET=-clean.tar.gz
[ "$(edits)" = "0" ] || fail "missing clean asset must not publish"
echo "OK: missing required asset leaves the draft"

releases "[${OTHER}]"
run 1 CLEAN_RESULT=success
echo "OK: missing release exits non-zero"

releases "[${DRAFT_OK},${DRAFT_OK}]"
run 1 CLEAN_RESULT=success
[ "$(edits)" = "0" ] || fail "duplicate tag must not publish"
echo "OK: two releases on one tag exits non-zero"

releases "[${DRAFT_OK}]"
run 1 CLEAN_RESULT=success MOCK_EDIT_NOOP=1
echo "OK: still-draft after edit exits non-zero"

echo "ALL OK: release-publish-draft publishes only a complete draft"
