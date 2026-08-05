#!/usr/bin/env bash
# supply-chain-osv-range.test.sh — issue #153
#
# The OSV known-vuln gate queried POST /v1/query with {package, version}. For
# the GitHub Actions ecosystem, advisories that encode affected versions as a
# RANGE with an empty versions[] array (e.g. GHSA-mrrh-fwg8-r2c3, the
# tj-actions/changed-files compromise) never match a version-included query —
# OSV can't order git-tag versions server-side. So blocked/known-vuln could
# never fire on that advisory class.
#
# Fix (direction #3): keep the fast versioned query; when it returns empty AND
# the ecosystem is GitHub Actions, re-query WITHOUT the version and evaluate
# affected[].ranges locally against the target version.
#
# The mock curl below distinguishes the two OSV calls by whether the POST body
# carries a "version" field, so these cases genuinely exercise the fallback:
# delete the fallback and case 1/3 flip to osv_clear=true (mutation-proof).
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPPLY="${REPO_ROOT}/scripts/supply-chain-check.sh"
fail() { echo "NOT OK: $1"; exit 1; }
[ -f "$SUPPLY" ] || fail "supply-chain-check.sh not found at $SUPPLY"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"

# fake aws: S3 cp only (up/down against $FAKE_S3_DIR); everything else is a no-op.
cat > "$BIN/aws" <<'AWS'
#!/usr/bin/env bash
set -u
key_to_path() { printf '%s' "$1" | sed 's#[/:]#_#g'; }
svc="$1"; shift
if [ "$svc" = "s3" ] && [ "${1:-}" = "cp" ]; then
  src="$2"; dst="$3"
  if [[ "$src" == s3://* ]]; then
    key="${src#s3://*/}"; f="$FAKE_S3_DIR/$(key_to_path "$key")"
    [ -f "$f" ] && { cp "$f" "$dst"; exit 0; }; exit 1
  elif [[ "$dst" == s3://* ]]; then
    key="${dst#s3://*/}"; mkdir -p "$FAKE_S3_DIR"
    cp "$src" "$FAKE_S3_DIR/$(key_to_path "$key")"
    [ -n "${UPLOAD_LOG:-}" ] && printf '%s\n' "$key" >> "$UPLOAD_LOG"
  fi
fi
exit 0
AWS
chmod +x "$BIN/aws"

# fake curl: emit `body\ncode`. The OSV branch splits on the POST -d payload:
# a body carrying "version" is the fast versioned query (returns empty here);
# a body without it is the package-only range query (returns the advisories).
cat > "$BIN/curl" <<'CURL'
#!/usr/bin/env bash
set -u
url=""; data=""; prev=""
for a in "$@"; do
  [ "$prev" = "-d" ] && data="$a"
  case "$a" in http://*|https://*) url="$a" ;; esac
  prev="$a"
done
case "$url" in
  *api.osv.dev*)
    case "$data" in
      *'"version"'*) printf '%s\n%s' "${OSV_VER_BODY:-{\"vulns\":[]\}}" "200" ;;
      *)             printf '%s\n%s' "${OSV_PKG_BODY:-{\"vulns\":[]\}}" "200" ;;
    esac ;;
  *securityscorecards.dev*) printf '%s\n%s' "${SC_BODY:-{\"score\":9.5\}}" "200" ;;
  *) printf '\n000' ;;
esac
CURL
chmod +x "$BIN/curl"

# Real tj-actions/changed-files advisories (trimmed): both ECOSYSTEM ranges with
# an empty versions[] — GHSA-mcph fixed at 41, GHSA-mrrh fixed at 46.0.1.
PKG_BODY='{"vulns":[
  {"id":"GHSA-mcph-m25j-8j63","affected":[{"package":{"name":"tj-actions/changed-files","ecosystem":"GitHub Actions"},"ranges":[{"type":"ECOSYSTEM","events":[{"introduced":"0"},{"fixed":"41"}]}]}]},
  {"id":"GHSA-mrrh-fwg8-r2c3","affected":[{"package":{"name":"tj-actions/changed-files","ecosystem":"GitHub Actions"},"ranges":[{"type":"ECOSYSTEM","events":[{"introduced":"0"},{"fixed":"46.0.1"}]}]}]}
]}'

b64() { printf '%b' "$1" | base64 | tr -d '\n'; }

# run_case <name> <to_version> : drive one dep bump, echo "<osv_clear> <check_errors>"
run_case() {
  local to="$2" gho="$WORK/gho_$1" s3="$WORK/s3_$1"
  mkdir -p "$s3"; : > "$gho"
  (
    export PATH="$BIN:$PATH" FAKE_S3_DIR="$s3" GITHUB_OUTPUT="$gho"
    export S3_BUCKET=test-bucket CACHE_TTL_DAYS=30 SCORECARD_THRESHOLD=7
    export ECOSYSTEM=github-actions RETRY_MAX=1 JITTER_MAX_SECONDS=0
    local deps; deps="$(b64 "tj-actions/changed-files\t0\t${to}\n")"
    export DEPS_B64="$deps"
    export OSV_VER_BODY='{"vulns":[]}' OSV_PKG_BODY="$PKG_BODY" SC_BODY='{"score":9.5}'
    bash "$SUPPLY" >>"$WORK/log_$1" 2>&1
  ) || fail "$1: script aborted: $(cat "$WORK/log_$1")"
  echo "$(grep '^osv_clear=' "$gho" | tail -1 | cut -d= -f2) $(grep '^check_errors=' "$gho" | tail -1 | cut -d= -f2)"
}

# Case 1: bump to v40 — in range of BOTH advisories (< 41). Versioned query is
# blind; the range fallback must block.
r=$(run_case affected 40)
[ "$r" = "false 0" ] || fail "#153 case1: v40 is range-affected, expected 'false 0', got '$r'"
echo "OK: #153 range-affected version (v40) blocks via package-only fallback"

# Case 2: bump to v46.0.1 — the fix version for mrrh and past mcph's fix. No
# range contains it: must stay clear, no manual-review noise.
r=$(run_case fixed 46.0.1)
[ "$r" = "true 0" ] || fail "#153 case2: v46.0.1 is fixed, expected 'true 0', got '$r'"
echo "OK: #153 fixed version (v46.0.1) stays clear (no false positive)"

# Case 3: bump to v46.0.0 — still inside mrrh's range (< 46.0.1). Must block.
r=$(run_case boundary 46.0.0)
[ "$r" = "false 0" ] || fail "#153 case3: v46.0.0 is range-affected, expected 'false 0', got '$r'"
echo "OK: #153 boundary version (v46.0.0) blocks (< fixed 46.0.1)"

# Case 4: an unparseable target version with a live range advisory can't be
# range-evaluated — fail closed to manual review (check_errors), not auto-clear.
r=$(run_case indeterminate "deadbeef")
[ "$r" = "true 1" ] || fail "#153 case4: unparseable version, expected 'true 1' (manual review), got '$r'"
echo "OK: #153 unevaluable version fails closed to manual review (check_errors=1)"

echo "ALL OK: supply-chain-osv-range"
