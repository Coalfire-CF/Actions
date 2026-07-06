#!/usr/bin/env bash
#
# retry-lib.sh — the single shared bounded-retry + jitter helper for the
# Dependabot auto-merge platform (grade-A plan #13). Converges the three ad-hoc
# retry stubs that previously existed (the inline external-call error handling in
# supply-chain-check.sh / breaking-change-check.sh, pr-green-merge.sh's gh_read,
# and the reconcile sweeper's gh-search loop) onto ONE implementation.
#
# Model: transient-only retry. with_retry retries a command ONLY when it exits
# with $RETRY_TRANSIENT_RC; exit 0 = success (stop), any other exit = permanent
# failure (stop immediately). This forces every call site to classify its own
# failures on EVIDENCE (HTTP status / CLI stderr) rather than blindly retrying —
# and to default UNKNOWN failures to permanent (fail toward the caller's existing
# fail-closed routing, never spin). Thin classifier wrappers (http_retryable,
# bedrock_retryable) supply that evidence per call site.
#
# Sleeping goes through _retry_sleep so tests can substitute a mock clock (record
# delays, never actually sleep). Pure bash + coreutils; unit-tested by
# tests/retry-lib.test.sh.

# Exit code a command uses to request a retry. 75 = EX_TEMPFAIL (sysexits.h).
: "${RETRY_TRANSIENT_RC:=75}"

# _retry_sleep <seconds> : real sleep. Tests override this to record instead.
_retry_sleep() { sleep "$1"; }

# _retry_log <msg> : logs go to STDERR only, so a $(with_retry ...) capture is
# never contaminated (a lesson from #172/#173).
_retry_log() { echo "[retry] $*" >&2; }

# _backoff_delay <attempt> <base> <cap> : exponential backoff base*2^(attempt-1),
# capped at <cap>, plus random jitter in [0, base). attempt is 1-based.
_backoff_delay() {
  local attempt="$1" base="$2" cap="$3" exp jitter span
  exp=$(( base * (1 << (attempt - 1)) ))
  [ "$exp" -gt "$cap" ] && exp="$cap"
  span=$(( base > 0 ? base : 1 ))
  jitter=$(( RANDOM % span ))
  echo $(( exp + jitter ))
}

# jitter_delay <max_j> : sleep a random pre-delay in [0, max_j] to de-synchronise
# a fleet-wide burst before the first external call of a run.
jitter_delay() {
  local max="$1" d
  [ "${max:-0}" -gt 0 ] || return 0
  d=$(( RANDOM % (max + 1) ))
  _retry_log "pre-call jitter ${d}s"
  _retry_sleep "$d"
}

# with_retry <max_attempts> <base_delay_s> <cap_delay_s> -- <cmd...>
#   exit 0                    -> success; with_retry returns 0 (cmd's stdout flows through)
#   exit $RETRY_TRANSIENT_RC  -> transient; retry with backoff+jitter up to max_attempts
#   any other exit            -> permanent; return that code immediately (no retry)
# After exhausting attempts on transient failures, returns $RETRY_TRANSIENT_RC.
with_retry() {
  local max="$1" base="$2" cap="$3"; shift 3
  [ "${1:-}" = "--" ] && shift
  local attempt=1 rc delay
  while :; do
    "$@"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      return 0
    elif [ "$rc" -ne "$RETRY_TRANSIENT_RC" ]; then
      return "$rc"                       # permanent — do not retry
    elif [ "$attempt" -ge "$max" ]; then
      _retry_log "transient failure persisted after ${attempt} attempt(s)"
      return "$RETRY_TRANSIENT_RC"
    fi
    delay="$(_backoff_delay "$attempt" "$base" "$cap")"
    _retry_log "transient (attempt ${attempt}/${max}); backing off ${delay}s"
    _retry_sleep "$delay"
    attempt=$(( attempt + 1 ))
  done
}

# http_retryable <curl-args...> : run curl capturing the HTTP status code; print
# the response body to stdout. Classification (EVIDENCE = captured http_code):
#   2xx                         -> 0 (success)
#   429 / 5xx / 000 (timeout/conn) / empty -> $RETRY_TRANSIENT_RC (retry)
#   any other definitive code (4xx) -> 1 (permanent; do not spin on a 400/404)
# Run under with_retry. Uses -sS (surface transport errors to stderr) not -f, so
# the body is available for classification even on an error status.
http_retryable() {
  local resp code body
  resp="$(curl -sS -w '\n%{http_code}' "$@" 2>/dev/null)" || resp="${resp:-}"$'\n'000
  code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  case "$code" in
    2[0-9][0-9])                 printf '%s' "$body"; return 0 ;;
    429|5[0-9][0-9]|000|"")      return "$RETRY_TRANSIENT_RC" ;;
    *)                           return 1 ;;
  esac
}

# bedrock_retryable <aws-bedrock-runtime-args...> : run the AWS CLI Bedrock call
# (which yields no HTTP code) capturing stderr; print stdout on success.
# Classification (EVIDENCE = exit code + stderr patterns):
#   exit 0                                          -> 0 (success)
#   stderr matches throttle/5xx/timeout signatures  -> $RETRY_TRANSIENT_RC (retry)
#   any other failure (Validation/AccessDenied/UNKNOWN) -> 1 (permanent)
# UNKNOWN defaults to permanent: fail toward the caller's manual-review routing,
# never spin on an unclassifiable error.
bedrock_retryable() {
  local out errf rc
  errf="$(mktemp)"
  out="$(aws bedrock-runtime "$@" 2>"$errf")"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    rm -f "$errf"
    printf '%s' "$out"
    return 0
  fi
  if grep -qiE 'Throttl|TooManyRequests|ServiceUnavailable|InternalServerError|RequestTimeout|Timeout|ServiceQuota|(^|[^0-9])(429|500|502|503|504)([^0-9]|$)' "$errf"; then
    _retry_log "bedrock transient: $(tail -n1 "$errf" 2>/dev/null)"
    rm -f "$errf"
    return "$RETRY_TRANSIENT_RC"
  fi
  _retry_log "bedrock permanent (not retrying): $(tail -n1 "$errf" 2>/dev/null)"
  rm -f "$errf"
  return 1
}
