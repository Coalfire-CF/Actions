#!/usr/bin/env bash
#
# Meta-test for scripts/repo-bootstrap.sh — the per-repo worker behind the
# org-repo-bootstrap sweeper (.github/workflows/org-repo-bootstrap.yml).
#
# Same philosophy as tests/reconcile-sweeper.test.sh: the sweep workflow is a
# thin enumerate-loop; the helper IS the testable safety surface. We drive it
# through MOCK `gh` and `git` shims first on PATH that (a) record every
# invocation and (b) can REJECT any write — proving the dry-run path issues
# ZERO mutating calls and that every opt-out gate fires before any delivery.
#
# Mock knobs (env):
#   MOCK_REPO_JSON       file — response for `gh api repos/<owner/name>` metadata
#   MOCK_LANGS_JSON      file — response for `gh api repos/…/languages`
#   MOCK_PRS_JSON        file — response for `gh pr list … --json …`
#   MOCK_EXISTING_FILES  file — newline list of paths that "exist" in the target
#                        repo (contents probes 404 anything else)
#   MOCK_META_FAIL       1 — metadata read fails on every attempt (persistent)
#   MOCK_REJECT_WRITES   1 — any write (git push / gh pr create / gh label
#                        create / gh api PUT|POST) exits 1

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HELPER="${REPO_ROOT}/scripts/repo-bootstrap.sh"

fail() { echo "NOT OK: $1"; exit 1; }
[ -f "$HELPER" ] || fail "helper not found at $HELPER"
[ -x "$HELPER" ] || chmod +x "$HELPER"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"

# ---- Mock gh ----
cat > "$BIN/gh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_TRACE"
argv="$*"
is_write=0
case "$argv" in
  *"--method PUT"*|*"--method POST"*) is_write=1 ;;
esac
[ "$1" = "pr" ] && [ "$2" = "create" ] && is_write=1
[ "$1" = "label" ] && [ "$2" = "create" ] && is_write=1
if [ "$is_write" = "1" ]; then
  if [ "${MOCK_REJECT_WRITES:-0}" = "1" ]; then
    echo "MOCK: write '$argv' rejected (dry-run must not mutate)" >&2; exit 1
  fi
  if [ "$1" = "pr" ] && [ "$2" = "create" ]; then
    echo "https://github.com/${MOCK_REPO_NAME:-Coalfire-CF/new-repo}/pull/7"
  fi
  exit 0
fi
# metadata: gh api repos/<owner/name>   (no trailing path segment)
if [ "$1" = "api" ] && printf '%s' "$2" | grep -qE '^repos/[^/]+/[^/]+$'; then
  if [ "${MOCK_META_FAIL:-0}" = "1" ]; then
    echo "gh: API rate limit exceeded (mock persistent)" >&2; exit 1
  fi
  cat "$MOCK_REPO_JSON"; exit 0
fi
if [ "$1" = "api" ] && printf '%s' "$2" | grep -q '/languages'; then
  cat "$MOCK_LANGS_JSON"; exit 0
fi
if [ "$1" = "api" ] && printf '%s' "$2" | grep -q '/contents/'; then
  path="${2#*/contents/}"
  if [ -f "${MOCK_EXISTING_FILES:-/dev/null}" ] && grep -qxF "$path" "$MOCK_EXISTING_FILES"; then
    echo '{"type":"file"}'; exit 0
  fi
  echo '{"message":"Not Found","status":"404"}' >&2; exit 1
fi
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then
  cat "$MOCK_PRS_JSON"; exit 0
fi
exit 0
MOCK
chmod +x "$BIN/gh"

# ---- Mock git: records argv; `clone` fabricates a working tree; `push` is the
#      only write verb and is rejected under MOCK_REJECT_WRITES. ----
cat > "$BIN/git" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_TRACE"
if [ "$1" = "clone" ]; then
  # last arg is the destination dir
  for last in "$@"; do :; done
  mkdir -p "$last/.github"
  exit 0
fi
if [ "$1" = "push" ] || { [ "$1" = "-C" ] && [ "$3" = "push" ]; }; then
  if [ "${MOCK_REJECT_WRITES:-0}" = "1" ]; then
    echo "MOCK: git push rejected (dry-run must not mutate)" >&2; exit 1
  fi
fi
exit 0
MOCK
chmod +x "$BIN/git"

WRITE_RE='pr create|label create|--method (PUT|POST)|^push |push$|-C [^ ]+ push'

SHA_OK="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# Repo-metadata fixtures
meta() { # archived fork visibility topics_json
  printf '{"archived":%s,"fork":%s,"visibility":"%s","default_branch":"main","topics":%s}' "$1" "$2" "$3" "$4"
}
META_PUB="$(meta false false public '[]')"
META_PRIV="$(meta false false private '[]')"
META_ARCHIVED="$(meta true false public '[]')"
META_FORK="$(meta false true public '[]')"
META_EXEMPT="$(meta false false public '["bootstrap-exempt"]')"

LANGS_NONE='{"Python": 1234}'
LANGS_HCL='{"HCL": 9999, "Shell": 12}'

PRS_NONE='[]'
PRS_OPEN_BOOT='[{"headRefName":"bootstrap/baseline-v0.12.1","state":"OPEN","mergedAt":null}]'
PRS_DECLINED='[{"headRefName":"bootstrap/baseline-v0.11.0","state":"CLOSED","mergedAt":null}]'
PRS_MERGED_OLD='[{"headRefName":"bootstrap/baseline-v0.11.0","state":"MERGED","mergedAt":"2026-01-01T00:00:00Z"}]'

# run_helper <meta> <langs> <prs> <existing_files_newline> <dry_run> <reject>
OUT=""; LAST_RC=0; TRACE=""; CLONE_DIR=""
run_helper() {
  local m="$1" l="$2" p="$3" ex="$4" dry="$5" reject="$6"
  printf '%s' "$m" > "$WORK/meta.json"
  printf '%s' "$l" > "$WORK/langs.json"
  printf '%s' "$p" > "$WORK/prs.json"
  printf '%s' "$ex" > "$WORK/existing.txt"
  : > "$WORK/trace"
  CLONE_DIR="$WORK/clones"
  rm -rf "$CLONE_DIR"; mkdir -p "$CLONE_DIR"
  PATH="$BIN:$PATH" GH_TRACE="$WORK/trace" \
      MOCK_REPO_JSON="$WORK/meta.json" MOCK_LANGS_JSON="$WORK/langs.json" \
      MOCK_PRS_JSON="$WORK/prs.json" MOCK_EXISTING_FILES="$WORK/existing.txt" \
      MOCK_REJECT_WRITES="$reject" MOCK_META_FAIL="${MF:-0}" MOCK_REPO_NAME="Coalfire-CF/new-repo" \
    TARGET_REPO="Coalfire-CF/new-repo" ACTIONS_SHA="$SHA_OK" ACTIONS_VERSION="v0.12.1" \
    DRY_RUN="$dry" TEMPLATE_DIR="${REPO_ROOT}/templates/bootstrap" WORK_DIR="$CLONE_DIR" RETRY_MAX=2 \
    bash "$HELPER" > "$WORK/out" 2>/dev/null
  LAST_RC=$?
  OUT="$(cat "$WORK/out")"
  TRACE="$(cat "$WORK/trace")"
}

# ---- Case 1: dry-run, generic public, nothing exists → WOULD-BOOTSTRAP with the
#      common file set (8 files), ZERO write calls (mock also rejects). ----
run_helper "$META_PUB" "$LANGS_NONE" "$PRS_NONE" "" true 1
[ "$LAST_RC" -eq 0 ] || fail "dry-run should exit 0 (got $LAST_RC)"
echo "$OUT" | grep -q "WOULD-BOOTSTRAP Coalfire-CF/new-repo (8 files)" || fail "generic dry-run should propose 8 files (got: $OUT)"
echo "$TRACE" | grep -qE "$WRITE_RE" && fail "dry-run issued a WRITE: $(echo "$TRACE" | grep -E "$WRITE_RE")"
echo "OK: dry-run generic public → WOULD-BOOTSTRAP (8 files), zero mutating calls"

# ---- Case 2: dry-run, terraform private → common(8) + terraform(5) + private(1) = 14. ----
run_helper "$META_PRIV" "$LANGS_HCL" "$PRS_NONE" "" true 1
echo "$OUT" | grep -q "WOULD-BOOTSTRAP Coalfire-CF/new-repo (14 files)" || fail "terraform+private dry-run should propose 14 files (got: $OUT)"
echo "OK: dry-run terraform private → WOULD-BOOTSTRAP (14 files)"

# ---- Case 3: adopted repo (org-release.yml present) → SKIP (compliant). ----
run_helper "$META_PUB" "$LANGS_NONE" "$PRS_NONE" ".github/workflows/org-release.yml" true 1
echo "$OUT" | grep -q "SKIP Coalfire-CF/new-repo (compliant)" || fail "adopted repo should SKIP compliant (got: $OUT)"
echo "OK: adopted repo → SKIP (compliant)"

# ---- Case 4: opt-out gates — archived / fork / topic / marker file. ----
run_helper "$META_ARCHIVED" "$LANGS_NONE" "$PRS_NONE" "" true 1
echo "$OUT" | grep -q "SKIP Coalfire-CF/new-repo (archived)" || fail "archived should SKIP (got: $OUT)"
run_helper "$META_FORK" "$LANGS_NONE" "$PRS_NONE" "" true 1
echo "$OUT" | grep -q "SKIP Coalfire-CF/new-repo (fork)" || fail "fork should SKIP (got: $OUT)"
run_helper "$META_EXEMPT" "$LANGS_NONE" "$PRS_NONE" "" true 1
echo "$OUT" | grep -q "SKIP Coalfire-CF/new-repo (topic-exempt)" || fail "topic should SKIP (got: $OUT)"
run_helper "$META_PUB" "$LANGS_NONE" "$PRS_NONE" ".github/.no-bootstrap" true 1
echo "$OUT" | grep -q "SKIP Coalfire-CF/new-repo (opt-out-file)" || fail ".no-bootstrap should SKIP (got: $OUT)"
echo "OK: archived / fork / topic-exempt / opt-out-file → SKIP"

# ---- Case 5: existing bootstrap PRs — open → pr-open; closed-unmerged → declined
#      (durable opt-out, never re-nag); an old MERGED bootstrap PR does NOT block. ----
run_helper "$META_PUB" "$LANGS_NONE" "$PRS_OPEN_BOOT" "" true 1
echo "$OUT" | grep -q "SKIP Coalfire-CF/new-repo (pr-open)" || fail "open bootstrap PR should SKIP pr-open (got: $OUT)"
run_helper "$META_PUB" "$LANGS_NONE" "$PRS_DECLINED" "" true 1
echo "$OUT" | grep -q "SKIP Coalfire-CF/new-repo (declined)" || fail "declined bootstrap PR should SKIP declined (got: $OUT)"
run_helper "$META_PUB" "$LANGS_NONE" "$PRS_MERGED_OLD" "" true 1
echo "$OUT" | grep -q "WOULD-BOOTSTRAP" || fail "old MERGED bootstrap PR must not block a re-proposal (got: $OUT)"
echo "OK: pr-open / declined block; merged history does not"

# ---- Case 6: partial adoption — existing files are dropped, never overwritten. ----
run_helper "$META_PUB" "$LANGS_NONE" "$PRS_NONE" ".github/dependabot.yml
release-please-config.json" true 1
echo "$OUT" | grep -q "WOULD-BOOTSTRAP Coalfire-CF/new-repo (6 files)" || fail "partial adoption should drop existing files, 8-2=6 (got: $OUT)"
echo "OK: partial adoption → existing files dropped (6 files)"

# ---- Case 7: live delivery — BOOTSTRAPPED, exactly one pr create + one push,
#      rendered files fully substituted. ----
run_helper "$META_PUB" "$LANGS_NONE" "$PRS_NONE" "" false 0
[ "$LAST_RC" -eq 0 ] || fail "live delivery should exit 0 (got $LAST_RC)"
echo "$OUT" | grep -q "BOOTSTRAPPED Coalfire-CF/new-repo PR#7" || fail "live should BOOTSTRAP with PR number (got: $OUT)"
[ "$(echo "$TRACE" | grep -c 'pr create')" -eq 1 ] || fail "live must issue exactly one gh pr create"
[ "$(echo "$TRACE" | grep -cE '(^| )push( |$)')" -eq 1 ] || fail "live must issue exactly one git push"
# rendered tree: no placeholder survives; pin + stagger slot rendered
RENDERED="$(find "$CLONE_DIR" -type f \( -name '*.yml' -o -name '*.json' \) 2>/dev/null)"
[ -n "$RENDERED" ] || fail "live delivery should render files into the clone dir"
grep -rl "__ACTIONS_SHA__\|__ACTIONS_VERSION__\|__STAGGER_SLOT__" $RENDERED && fail "placeholders survived rendering"
grep -q "@${SHA_OK} # v0.12.1" "$(dirname "$(echo "$RENDERED" | head -1)")"/../workflows/org-release.yml 2>/dev/null || \
  grep -rq "@${SHA_OK} # v0.12.1" $RENDERED || fail "rendered callers must carry the SHA pin"
grep -rqE 'time: "[0-2][0-9]:[0-5][0-9]"' $RENDERED || fail "dependabot seed must carry a rendered HH:MM stagger slot"
# .tmpl suffix must be stripped in delivery
find "$CLONE_DIR" -name '*.tmpl' | grep -q . && fail ".tmpl suffix must be stripped on delivery"
echo "OK: live delivery → BOOTSTRAPPED, one pr create + one push, placeholders fully rendered, .tmpl stripped"

# ---- Case 8: persistent metadata failure → fail closed, SKIP, no writes. ----
MF=1 run_helper "$META_PUB" "$LANGS_NONE" "$PRS_NONE" "" false 0
[ "$LAST_RC" -eq 0 ] || fail "read-failure should exit 0 as a decision (got $LAST_RC)"
echo "$OUT" | grep -q "SKIP Coalfire-CF/new-repo (read-unavailable)" || fail "read failure should SKIP read-unavailable (got: $OUT)"
echo "$TRACE" | grep -qE "$WRITE_RE" && fail "read failure issued a WRITE but must fail closed"
echo "OK: persistent metadata failure → SKIP (read-unavailable), fail closed"

echo "ALL TESTS PASSED"
