#!/usr/bin/env bash
#
# Meta-test for scripts/retry-lib.sh (grade-A plan #13): the single shared
# bounded-retry + jitter helper. Uses a MOCK CLOCK (_retry_sleep override) so no
# test actually sleeps, and mock curl/aws shims to exercise the evidence-based
# transient classification.
#
# Also re-pins the two hard-won gh_read properties (from #172/#173) at the
# with_retry level so the convergence can't regress them:
#   - a permanent failure's exit code is captured and returned (not masked to 0);
#   - retry logging goes to STDERR only (never contaminates a $(...) capture).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB="${REPO_ROOT}/scripts/retry-lib.sh"

fail() { echo "NOT OK: $1"; exit 1; }
[ -f "$LIB" ] || fail "retry-lib.sh not found at $LIB"
# shellcheck source=scripts/retry-lib.sh
. "$LIB"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
DELAYS="$WORK/delays"; : > "$DELAYS"

# Mock clock: record requested delays, never sleep.
_retry_sleep() { echo "$1" >> "$DELAYS"; }

# ---- with_retry: transient twice then success → 2 recorded backoffs, strictly
#      increasing, each within cap. ----
: > "$DELAYS"; N=0
flaky() { N=$((N + 1)); [ "$N" -ge 3 ] && { echo "OK-BODY"; return 0; }; return "$RETRY_TRANSIENT_RC"; }
out="$(with_retry 5 1 8 -- flaky)"; rc=$?
[ "$rc" -eq 0 ] || fail "flaky-then-success should return 0 (got $rc)"
[ "$out" = "OK-BODY" ] || fail "success body should flow through (got '$out')"
nd="$(wc -l < "$DELAYS" | tr -d ' ')"
[ "$nd" -eq 2 ] || fail "expected exactly 2 backoffs before success, got $nd"
d1="$(sed -n 1p "$DELAYS")"; d2="$(sed -n 2p "$DELAYS")"
[ "$d2" -gt "$d1" ] || fail "backoff not strictly increasing ($d1 then $d2)"
[ "$d2" -le $((8 + 1)) ] || fail "backoff exceeded cap+jitter ($d2)"
echo "OK: with_retry retries transient then succeeds — 2 increasing backoffs, body passthrough"

# ---- with_retry: persistent transient → exhausts, returns RETRY_TRANSIENT_RC. ----
: > "$DELAYS"
always_transient() { return "$RETRY_TRANSIENT_RC"; }
with_retry 3 1 8 -- always_transient; rc=$?
[ "$rc" -eq "$RETRY_TRANSIENT_RC" ] || fail "persistent transient should return RETRY_TRANSIENT_RC (got $rc)"
[ "$(wc -l < "$DELAYS" | tr -d ' ')" -eq 2 ] || fail "3 attempts should back off exactly twice"
echo "OK: with_retry exhausts persistent transient and returns transient rc (caller fails closed)"

# ---- with_retry: permanent failure → returned immediately, rc PRESERVED, no retry. ----
: > "$DELAYS"
permanent42() { return 42; }
with_retry 5 1 8 -- permanent42; rc=$?
[ "$rc" -eq 42 ] || fail "permanent rc must be captured & returned unchanged (got $rc, want 42)"
[ "$(wc -l < "$DELAYS" | tr -d ' ')" -eq 0 ] || fail "permanent failure must not back off/retry"
echo "OK: permanent failure returns its exact rc with zero retries (rc-capture property re-pinned)"

# ---- stderr-only: retry logs must NOT appear on stdout (capture-safe). ----
: > "$DELAYS"; N=0
logout="$(with_retry 5 1 8 -- flaky 2>/dev/null)"
[ "$logout" = "OK-BODY" ] || fail "captured stdout must be ONLY the body, no retry log lines (got '$logout')"
echo "OK: retry logging is stderr-only (stdout capture uncontaminated)"

# ---- jitter_delay: bounded pre-delay ∈ [0, J] over many samples; 0 → no sleep. ----
: > "$DELAYS"
for _ in $(seq 1 200); do jitter_delay 5 >/dev/null 2>&1; done
awk 'NR{ if ($1<0 || $1>5) { print "OUT_OF_RANGE:"$1; exit 1 } } END{ if(NR<200) exit 1 }' "$DELAYS" \
  || fail "jitter_delay produced an out-of-range or missing sample"
[ "$(sort -u "$DELAYS" | wc -l | tr -d ' ')" -gt 1 ] || fail "jitter_delay is constant — not random"
: > "$DELAYS"; jitter_delay 0; [ "$(wc -l < "$DELAYS" | tr -d ' ')" -eq 0 ] || fail "jitter_delay 0 must not sleep"
echo "OK: jitter_delay bounded in [0,J], varies, and no-ops at 0"

# ---- http_retryable: evidence-based classification via a mock curl shim. ----
BIN="$WORK/bin"; mkdir -p "$BIN"
cat > "$BIN/curl" <<'MOCK'
#!/usr/bin/env bash
[ "${MOCK_CURL_RC:-0}" != "0" ] && exit "$MOCK_CURL_RC"     # simulate transport failure (http_code 000)
printf '%s\n%s' "${MOCK_BODY:-}" "${MOCK_CODE:-200}"
MOCK
chmod +x "$BIN/curl"
export PATH="$BIN:$PATH"
hget() { http_retryable https://example.test; }

out="$(MOCK_CODE=200 MOCK_BODY='{"ok":true}' hget)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = '{"ok":true}' ] || fail "200 should succeed with body (rc=$rc out=$out)"
( MOCK_CODE=503 hget ) >/dev/null 2>&1; [ $? -eq "$RETRY_TRANSIENT_RC" ] || fail "503 must be transient"
( MOCK_CODE=429 hget ) >/dev/null 2>&1; [ $? -eq "$RETRY_TRANSIENT_RC" ] || fail "429 must be transient"
( MOCK_CODE=404 hget ) >/dev/null 2>&1; [ $? -eq 1 ] || fail "404 must be permanent (no spin)"
( MOCK_CURL_RC=28 hget ) >/dev/null 2>&1; [ $? -eq "$RETRY_TRANSIENT_RC" ] || fail "curl timeout (rc!=0 → code 000) must be transient"
echo "OK: http_retryable — 2xx ok, 429/5xx/000 transient, 4xx permanent"

# ---- bedrock_retryable: classification via a mock aws shim. ----
cat > "$BIN/aws" <<'MOCK'
#!/usr/bin/env bash
if [ -n "${MOCK_AWS_ERR:-}" ]; then echo "$MOCK_AWS_ERR" >&2; exit 255; fi
printf '%s' "${MOCK_AWS_OUT:-}"
MOCK
chmod +x "$BIN/aws"
bget() { bedrock_retryable converse --model-id m; }

out="$(MOCK_AWS_OUT='{"output":1}' bget)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = '{"output":1}' ] || fail "bedrock success should pass through (rc=$rc)"
( MOCK_AWS_ERR='An error occurred (ThrottlingException) when calling Converse' bget ) >/dev/null 2>&1
[ $? -eq "$RETRY_TRANSIENT_RC" ] || fail "ThrottlingException must be transient"
( MOCK_AWS_ERR='An error occurred (ValidationException): bad input' bget ) >/dev/null 2>&1
[ $? -eq 1 ] || fail "ValidationException must be permanent"
( MOCK_AWS_ERR='some unclassifiable weirdness' bget ) >/dev/null 2>&1
[ $? -eq 1 ] || fail "UNKNOWN error must default to permanent (never spin)"
echo "OK: bedrock_retryable — success ok, throttle transient, validation/unknown permanent"

echo "ALL TESTS PASSED"
