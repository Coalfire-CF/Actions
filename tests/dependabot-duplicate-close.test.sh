#!/usr/bin/env bash
#
# Meta-test for scripts/dependabot-duplicate-close.sh.
#
# Drives the script through a MOCK `gh` that serves a fixture PR list and
# records every call, to prove:
#   1. An older PR is closed only when a newer PR bumps the same dependency and
#      changes every file the older one does (README.md ignored), including the
#      grouped (label::github::Coalfire-CF/repo::ref) vs ungrouped (label::repo)
#      terraform title forms.
#   2. Same dependency in a different directory, a different dependency in the
#      same file, group titles, and the newest PR are never closed.
#   3. DRY_RUN=true (the default) issues zero `gh pr close` calls.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/dependabot-duplicate-close.sh"

fail() { echo "NOT OK: $1"; exit 1; }
[ -f "$SCRIPT" ] || fail "script not found at $SCRIPT"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"
export GH_TRACE="$WORK/trace"
export MOCK_PRS="$WORK/prs.json"

cat > "$BIN/gh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_TRACE"
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then cat "$MOCK_PRS"; exit 0; fi
# Group PR commits (REST, already shaped as the script's --jq would shape it).
if [ "$1" = "api" ] && printf '%s' "$2" | grep -qE '/pulls/25/commits'; then
  printf '[{"messageBody":"---\\nupdated-dependencies:\\n- dependency-name: github.com/foo/z\\n  dependency-version: 1.2.0\\n"}]\n'
  exit 0
fi
if [ "$1" = "api" ] && printf '%s' "$2" | grep -qE '/pulls/[0-9]+/commits'; then echo '[]'; exit 0; fi
if [ "$1" = "pr" ] && [ "$2" = "close" ]; then exit 0; fi
echo "mock gh: unexpected call: $*" >&2; exit 1
MOCK
chmod +x "$BIN/gh"
export PATH="$BIN:$PATH"

f() { printf '{"path":"%s"}' "$1"; }
cat > "$MOCK_PRS" <<EOF
[
 {"number":10,"createdAt":"2026-07-06T00:00:00Z","title":"chore(deps): bump kms::terraform-google-kms from 1.0.6 to 1.1.0","files":[$(f README.md),$(f kms.tf)]},
 {"number":20,"createdAt":"2026-09-25T00:00:00Z","title":"chore(deps): bump kms::github::Coalfire-CF/terraform-google-kms::v1.0.6 in /","files":[$(f kms.tf)]},
 {"number":11,"createdAt":"2026-08-17T00:00:00Z","title":"chore(deps): bump acct::terraform-aws-account-setup from 0.2.9 to 0.3.1 in /prod","files":[$(f prod/main.tf)]},
 {"number":21,"createdAt":"2026-09-25T00:00:00Z","title":"chore(deps): bump acct::github::Coalfire-CF/terraform-aws-account-setup::v0.2.4 in /mgmt","files":[$(f mgmt/main.tf)]},
 {"number":12,"createdAt":"2026-07-01T00:00:00Z","title":"chore(deps): bump github.com/foo/x from 1.0.0 to 1.1.0 in /test","files":[$(f test/go.mod),$(f test/go.sum)]},
 {"number":22,"createdAt":"2026-09-01T00:00:00Z","title":"chore(deps): bump github.com/foo/y from 2.0.0 to 2.1.0 in /test","files":[$(f test/go.mod),$(f test/go.sum)]},
 {"number":13,"createdAt":"2026-07-01T00:00:00Z","title":"chore(deps): bump the org-actions group with 3 updates","files":[$(f .github/workflows/a.yml)]},
 {"number":23,"createdAt":"2026-09-01T00:00:00Z","title":"chore(deps): bump the org-actions group with 8 updates","files":[$(f .github/workflows/a.yml)]},
 {"number":14,"createdAt":"2026-07-01T00:00:00Z","title":"chore(deps): bump multer from 1.0.0 to 2.0.0","files":[$(f package.json),$(f package-lock.json)]},
 {"number":24,"createdAt":"2026-09-01T00:00:00Z","title":"chore(deps): bump multer from 1.0.0 to 2.4.0","files":[$(f package.json),$(f package-lock.json)]},
 {"number":15,"createdAt":"2026-07-01T00:00:00Z","title":"chore(deps): bump github.com/foo/z from 1.0.0 to 1.1.0 in /test","files":[$(f test/go.mod),$(f test/go.sum)]},
 {"number":25,"createdAt":"2026-09-26T00:00:00Z","title":"chore(deps): bump the gomod-test group across 1 directory with 1 update","body":"Bumps the gomod-test group. (body truncated)","files":[$(f test/go.mod),$(f test/go.sum)]}
]
EOF

# ---- dry run (default): reports exactly #10, #14 and #15 (group body), closes nothing ----
: > "$GH_TRACE"
OUT="$(REPO=Coalfire-CF/r bash "$SCRIPT")" || fail "dry run exited non-zero"
[ "$(printf '%s\n' "$OUT" | grep -c '^CLOSE ')" = "3" ] || fail "expected 3 CLOSE lines, got: $OUT"
printf '%s\n' "$OUT" | grep -q '^CLOSE Coalfire-CF/r#10 (covered by #20)' || fail "#10 should be covered by #20"
printf '%s\n' "$OUT" | grep -q '^CLOSE Coalfire-CF/r#14 (covered by #24)' || fail "#14 should be covered by #24"
printf '%s\n' "$OUT" | grep -q '^CLOSE Coalfire-CF/r#15 (covered by #25)' || fail "#15 should be covered by group #25 (commit updated-dependencies lists it)"
printf '%s\n' "$OUT" | grep -q '^CLOSE Coalfire-CF/r#12 ' && fail "#12 is not listed in group #25 and must stay open"
printf '%s\n' "$OUT" | grep -q 'SUMMARY Coalfire-CF/r open=12 duplicates=3 dry_run=true' || fail "summary wrong: $OUT"
[ "$(grep -c '^pr close' "$GH_TRACE")" = "0" ] || fail "dry run issued pr close"
echo "OK: dry run reports the 3 duplicates (one via a group PR commit) and closes nothing"

# ---- live: closes exactly #10 and #14 ----
: > "$GH_TRACE"
REPO=Coalfire-CF/r DRY_RUN=false bash "$SCRIPT" >/dev/null || fail "live run exited non-zero"
[ "$(grep -c '^pr close' "$GH_TRACE")" = "3" ] || fail "expected 3 pr close calls"
grep -q '^pr close 10 -R Coalfire-CF/r' "$GH_TRACE" || fail "#10 not closed"
grep -q '^pr close 14 -R Coalfire-CF/r' "$GH_TRACE" || fail "#14 not closed"
grep -q '^pr close 15 -R Coalfire-CF/r' "$GH_TRACE" || fail "#15 not closed"
echo "OK: live run closes exactly the 3 duplicates"

# ---- missing REPO fails loudly ----
if REPO='' bash "$SCRIPT" >/dev/null 2>&1; then fail "missing REPO should fail"; fi
echo "OK: missing REPO fails"

echo "ALL OK: dependabot-duplicate-close closes only covered duplicates"
