#!/usr/bin/env bash
#
# Integration meta-test for the cache-integrity fixes in the Dependabot
# auto-merge check scripts (2026-07-08 deep-dive: #193/#194 H1, #195 H2, #201 M4).
#
# Drives scripts/supply-chain-check.sh and scripts/breaking-change-check.sh
# end-to-end with fake `aws` (S3 cp + bedrock-runtime) and `curl`
# (OSV / Scorecard / GitHub release-notes) binaries on PATH, so the whole gate
# runs fully offline. The fakes are driven by environment variables and record
# every S3 upload, letting us assert on cache-WRITE behavior — the crux of all
# three bugs. Real jq / bc / date / base64 / sed are used throughout.
#
# Asserted (fixed) behavior:
#   #193/#194 — a per-dependency check ERROR (OSV / Bedrock) SKIPS the shared-cache
#               write, so a transient outage never persists an optimistic
#               (clear / non-breaking) verdict to the fleet-wide cache.
#   #195      — in a grouped PR, a dependency that MISSES the shared cache does not
#               inherit the previous dependency's cached object (no stale /tmp
#               contamination of the next dep's written object).
#   #201      — a corrupt / non-JSON cached object is treated as a cache miss and
#               re-analyzed; the pre-validation jq reads no longer abort the job
#               under `set -e`.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SUPPLY="${REPO_ROOT}/scripts/supply-chain-check.sh"
BREAKING="${REPO_ROOT}/scripts/breaking-change-check.sh"

fail() { echo "NOT OK: $1"; exit 1; }

[ -f "$SUPPLY" ]   || fail "supply-chain-check.sh not found at $SUPPLY"
[ -f "$BREAKING" ] || fail "breaking-change-check.sh not found at $BREAKING"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"

# ---- fake `aws`: S3 cp (up/down against $FAKE_S3_DIR) + bedrock-runtime --------
cat > "$BIN/aws" <<'AWS'
#!/usr/bin/env bash
set -u
key_to_path() { printf '%s' "$1" | sed 's#[/:]#_#g'; }
svc="$1"; shift
case "$svc" in
  s3)
    sub="$1"; src="$2"; dst="$3"
    [ "$sub" = "cp" ] || exit 0
    if [[ "$src" == s3://* ]]; then                 # download
      key="${src#s3://*/}"
      f="$FAKE_S3_DIR/$(key_to_path "$key")"
      [ -f "$f" ] && { cp "$f" "$dst"; exit 0; }
      exit 1                                         # miss
    elif [[ "$dst" == s3://* ]]; then               # upload
      key="${dst#s3://*/}"
      mkdir -p "$FAKE_S3_DIR"
      cp "$src" "$FAKE_S3_DIR/$(key_to_path "$key")"
      [ -n "${UPLOAD_LOG:-}" ] && printf '%s\n' "$key" >> "$UPLOAD_LOG"
      exit 0
    fi
    exit 0 ;;
  bedrock-runtime)
    if [ -n "${BEDROCK_FAIL:-}" ]; then
      echo "ThrottlingException: rate exceeded" >&2   # transient signature
      exit 255
    fi
    cat "${BEDROCK_RESP_FILE:?BEDROCK_RESP_FILE unset}"
    exit 0 ;;
  *) exit 0 ;;
esac
AWS
chmod +x "$BIN/aws"

# ---- fake `curl`: emit `body\ncode` (http_retryable ignores real -w) -----------
cat > "$BIN/curl" <<'CURL'
#!/usr/bin/env bash
set -u
url=""
for a in "$@"; do case "$a" in http://*|https://*) url="$a" ;; esac; done
case "$url" in
  *api.osv.dev*)             [ -n "${OSV_FAIL:-}" ] && exit 1
                             printf '%s\n%s' "${OSV_BODY:-}" "${OSV_CODE:-200}" ;;
  *securityscorecards.dev*)  [ -n "${SC_FAIL:-}" ] && exit 1
                             printf '%s\n%s' "${SC_BODY:-}" "${SC_CODE:-200}" ;;
  *api.github.com*)          printf '%s\n%s' "${GH_BODY:-}" "${GH_CODE:-404}" ;;
  *)                         printf '\n000' ;;
esac
CURL
chmod +x "$BIN/curl"

# Canned Bedrock Converse success (no breaking changes; applies_to_repo true).
BEDROCK_GOOD="$WORK/bedrock_good.json"
cat > "$BEDROCK_GOOD" <<'EOF'
{"output":{"message":{"content":[{"text":"{\"breaking\":false,\"confidence\":80,\"risks\":[],\"summary\":\"no breaking changes\",\"applies_to_repo\":true}"}]}}}
EOF

# Valid-JSON verdict with a NON-numeric confidence — a prompt-injection could make
# the model emit this; the fix must default confidence to 0, not crash --argjson.
BEDROCK_BADCONF="$WORK/bedrock_badconf.json"
cat > "$BEDROCK_BADCONF" <<'EOF'
{"output":{"message":{"content":[{"text":"{\"breaking\":false,\"confidence\":\"high\",\"risks\":[],\"summary\":\"x\",\"applies_to_repo\":true}"}]}}}
EOF

b64() { printf '%b' "$1" | base64 | tr -d '\n'; }
s3put() { cp "$2" "$FAKE_S3_DIR/$(printf '%s' "$1" | sed 's#[/:]#_#g')"; }
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ============================================================================
# #193/#194 — supply-chain: OSV error SKIPS the shared-cache write
# ============================================================================
S3="$WORK/s3_t1"; mkdir -p "$S3"; UL="$WORK/ul_t1"; : > "$UL"; GHO="$WORK/gho_t1"; : > "$GHO"
(
  export PATH="$BIN:$PATH" FAKE_S3_DIR="$S3" UPLOAD_LOG="$UL" GITHUB_OUTPUT="$GHO"
  export S3_BUCKET=test-bucket CACHE_TTL_DAYS=30 SCORECARD_THRESHOLD=7
  export ECOSYSTEM=github-actions RETRY_MAX=1 JITTER_MAX_SECONDS=0
  export DEPS_B64="$(b64 'actions/checkout\t4.0.0\t5.0.0\n')"
  export OSV_FAIL=1 SC_BODY='{"score":9.5}' SC_CODE=200
  bash "$SUPPLY" >>"$WORK/log_t1" 2>&1
)
rc=$?
[ "$rc" -eq 0 ] || fail "#194 supply: script aborted (exit $rc): $(cat "$WORK/log_t1")"
grep -q '^check_errors=1$' "$GHO" || fail "#194 supply: expected check_errors=1, got: $(grep check_errors "$GHO")"
grep -q 'actions--checkout/5.0.0.json' "$UL" \
  && fail "#194 supply: cache write happened despite OSV error (would poison the fleet cache): $(cat "$UL")"
echo "OK: #193/#194 supply-chain skips cache write on OSV error (check_errors=1, no upload)"

# ---- control: a clean supply-chain run DOES write the cache ----
S3="$WORK/s3_t2"; mkdir -p "$S3"; UL="$WORK/ul_t2"; : > "$UL"; GHO="$WORK/gho_t2"; : > "$GHO"
(
  export PATH="$BIN:$PATH" FAKE_S3_DIR="$S3" UPLOAD_LOG="$UL" GITHUB_OUTPUT="$GHO"
  export S3_BUCKET=test-bucket CACHE_TTL_DAYS=30 SCORECARD_THRESHOLD=7
  export ECOSYSTEM=github-actions RETRY_MAX=1 JITTER_MAX_SECONDS=0
  export DEPS_B64="$(b64 'actions/checkout\t4.0.0\t5.0.0\n')"
  export OSV_BODY='{"vulns":[]}' OSV_CODE=200 SC_BODY='{"score":9.5}' SC_CODE=200
  bash "$SUPPLY" >>"$WORK/log_t2" 2>&1
)
rc=$?
[ "$rc" -eq 0 ] || fail "supply control: script aborted (exit $rc): $(cat "$WORK/log_t2")"
grep -q '^check_errors=0$' "$GHO" || fail "supply control: expected check_errors=0"
grep -q 'actions--checkout/5.0.0.json' "$UL" || fail "supply control: clean run should write cache, but no upload: $(cat "$UL")"
echo "OK: control — clean supply-chain run writes the cache (check_errors=0, upload present)"

# ============================================================================
# #201 — supply-chain: corrupt cached object is treated as a miss (no abort)
# ============================================================================
S3="$WORK/s3_t3"; mkdir -p "$S3"; UL="$WORK/ul_t3"; : > "$UL"; GHO="$WORK/gho_t3"; : > "$GHO"
printf 'this is not json {{{' > "$WORK/corrupt.json"
s3put_dir() { cp "$2" "$1/$(printf '%s' "$3" | sed 's#[/:]#_#g')"; }
s3put_dir "$S3" "$WORK/corrupt.json" 'analyses/shared/actions--checkout/5.0.0.json'
(
  export PATH="$BIN:$PATH" FAKE_S3_DIR="$S3" UPLOAD_LOG="$UL" GITHUB_OUTPUT="$GHO"
  export S3_BUCKET=test-bucket CACHE_TTL_DAYS=30 SCORECARD_THRESHOLD=7
  export ECOSYSTEM=github-actions RETRY_MAX=1 JITTER_MAX_SECONDS=0
  export DEPS_B64="$(b64 'actions/checkout\t4.0.0\t5.0.0\n')"
  export OSV_BODY='{"vulns":[]}' OSV_CODE=200 SC_BODY='{"score":9.5}' SC_CODE=200
  bash "$SUPPLY" >>"$WORK/log_t3" 2>&1
)
rc=$?
[ "$rc" -eq 0 ] || fail "#201 supply: corrupt cache object aborted the job (exit $rc): $(cat "$WORK/log_t3")"
grep -q '^check_errors=' "$GHO" || fail "#201 supply: no outputs emitted — job aborted before completion"
echo "OK: #201 supply-chain treats a corrupt cached object as a miss (no set -e abort)"

# ============================================================================
# #193/#194 — breaking-change: Bedrock error SKIPS the shared-cache write
# ============================================================================
S3="$WORK/s3_t4"; mkdir -p "$S3"; UL="$WORK/ul_t4"; : > "$UL"; GHO="$WORK/gho_t4"; : > "$GHO"
(
  export PATH="$BIN:$PATH" FAKE_S3_DIR="$S3" UPLOAD_LOG="$UL" GITHUB_OUTPUT="$GHO"
  export S3_BUCKET=test-bucket CACHE_TTL_DAYS=30 BEDROCK_MODEL_ID=test-model
  export ECOSYSTEM=github-actions RETRY_MAX=1 JITTER_MAX_SECONDS=0
  export GH_TOKEN=x GITHUB_REPOSITORY=test-org/test-repo BEDROCK_RESP_FILE="$BEDROCK_GOOD"
  export DEPS_B64="$(b64 'actions/checkout\t4.0.0\t5.0.0\n')"
  export BEDROCK_FAIL=1 GH_CODE=404
  bash "$BREAKING" >>"$WORK/log_t4" 2>&1
)
rc=$?
[ "$rc" -eq 0 ] || fail "#194 breaking: script aborted (exit $rc): $(cat "$WORK/log_t4")"
grep -qE '^check_errors=[1-9]' "$GHO" || fail "#194 breaking: expected check_errors>=1, got: $(grep check_errors "$GHO")"
grep -q 'analyses/shared/actions--checkout/5.0.0.json' "$UL" \
  && fail "#194 breaking: SHARED cache write happened despite Bedrock error: $(cat "$UL")"
echo "OK: #193/#194 breaking-change skips SHARED cache write on Bedrock error"

# ============================================================================
# #195 — breaking-change grouped PR: dep2 (miss) must NOT inherit dep1 (hit)
# ============================================================================
S3="$WORK/s3_t5"; mkdir -p "$S3"; UL="$WORK/ul_t5"; : > "$UL"; GHO="$WORK/gho_t5"; : > "$GHO"
cat > "$WORK/dep1.json" <<EOF
{
  "schema_version":"1",
  "producer":"coalfire-org-dependabot-auto-merge",
  "dependency":"actions/checkout",
  "version":"5.0.0",
  "analyzed_at":"$NOW",
  "semver":{"type":"minor","from":"4.0.0","to":"5.0.0"},
  "changelog":{"breaking":false,"ai_breaking":false,"confidence":80,"summary":"ok","risks":[]},
  "osv":{"clear":true,"vulns":[]},
  "scorecard":{"score":"9.5","pass":true}
}
EOF
s3put_dir "$S3" "$WORK/dep1.json" 'analyses/shared/actions--checkout/5.0.0.json'
(
  export PATH="$BIN:$PATH" FAKE_S3_DIR="$S3" UPLOAD_LOG="$UL" GITHUB_OUTPUT="$GHO"
  export S3_BUCKET=test-bucket CACHE_TTL_DAYS=30 BEDROCK_MODEL_ID=test-model
  export ECOSYSTEM=github-actions RETRY_MAX=1 JITTER_MAX_SECONDS=0
  export GH_TOKEN=x GITHUB_REPOSITORY=test-org/test-repo BEDROCK_RESP_FILE="$BEDROCK_GOOD"
  export DEPS_B64="$(b64 'actions/checkout\t4.0.0\t5.0.0\nactions/setup-go\t4.0.0\t5.0.0\n')"
  export GH_CODE=404
  bash "$BREAKING" >>"$WORK/log_t5" 2>&1
)
rc=$?
[ "$rc" -eq 0 ] || fail "#195 breaking: script aborted (exit $rc): $(cat "$WORK/log_t5")"
DEP2_OBJ="$S3/analyses_shared_actions--setup-go_5.0.0.json"
[ -f "$DEP2_OBJ" ] || fail "#195 breaking: dep2 shared object was never written: $(cat "$UL")"
osv_field="$(jq -c '.osv // "ABSENT"' "$DEP2_OBJ")"
[ "$osv_field" = '"ABSENT"' ] || fail "#195 breaking: dep2 object inherited dep1's supply-chain fields (.osv=${osv_field}) — stale /tmp contamination"
echo "OK: #195 breaking-change dep2 (cache miss) does not inherit dep1's cached fields"

# ============================================================================
# #200 (M3) — supply-chain: a non-JSON / non-numeric Scorecard body fails closed
# (SCORECARD_PASS=false) instead of crashing bc / jq under set -e.
# ============================================================================
S3="$WORK/s3_t6"; mkdir -p "$S3"; UL="$WORK/ul_t6"; : > "$UL"; GHO="$WORK/gho_t6"; : > "$GHO"
(
  export PATH="$BIN:$PATH" FAKE_S3_DIR="$S3" UPLOAD_LOG="$UL" GITHUB_OUTPUT="$GHO"
  export S3_BUCKET=test-bucket CACHE_TTL_DAYS=30 SCORECARD_THRESHOLD=7
  export ECOSYSTEM=github-actions RETRY_MAX=1 JITTER_MAX_SECONDS=0
  export DEPS_B64="$(b64 'actions/checkout\t4.0.0\t5.0.0\n')"
  export OSV_BODY='{"vulns":[]}' OSV_CODE=200 SC_BODY='<html>502 Bad Gateway</html>' SC_CODE=200
  bash "$SUPPLY" >>"$WORK/log_t6" 2>&1
)
rc=$?
[ "$rc" -eq 0 ] || fail "#200 supply: non-JSON Scorecard body crashed the job (exit $rc): $(cat "$WORK/log_t6")"
grep -q '^scorecard_pass=false$' "$GHO" || fail "#200 supply: garbage score must fail closed (scorecard_pass=false), got: $(grep scorecard_pass "$GHO")"
echo "OK: #200 supply-chain non-numeric/garbage Scorecard body fails closed (no crash)"

# ============================================================================
# #199 (M2) — breaking-change: a non-numeric model confidence defaults to 0
# instead of crashing `jq --argjson conf` under set -e.
# ============================================================================
S3="$WORK/s3_t7"; mkdir -p "$S3"; UL="$WORK/ul_t7"; : > "$UL"; GHO="$WORK/gho_t7"; : > "$GHO"
(
  export PATH="$BIN:$PATH" FAKE_S3_DIR="$S3" UPLOAD_LOG="$UL" GITHUB_OUTPUT="$GHO"
  export S3_BUCKET=test-bucket CACHE_TTL_DAYS=30 BEDROCK_MODEL_ID=test-model
  export ECOSYSTEM=github-actions RETRY_MAX=1 JITTER_MAX_SECONDS=0
  export GH_TOKEN=x GITHUB_REPOSITORY=test-org/test-repo BEDROCK_RESP_FILE="$BEDROCK_BADCONF"
  export DEPS_B64="$(b64 'actions/checkout\t4.0.0\t5.0.0\n')"
  export GH_CODE=404
  bash "$BREAKING" >>"$WORK/log_t7" 2>&1
)
rc=$?
[ "$rc" -eq 0 ] || fail "#199 breaking: non-numeric confidence crashed the job (exit $rc): $(cat "$WORK/log_t7")"
grep -q '^confidence=0$' "$GHO" || fail "#199 breaking: non-numeric confidence should default to 0, got: $(grep '^confidence=' "$GHO")"
echo "OK: #199 breaking-change non-numeric confidence defaults to 0 (no --argjson crash)"

echo "ALL TESTS PASSED"
