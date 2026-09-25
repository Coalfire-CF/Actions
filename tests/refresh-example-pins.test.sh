#!/usr/bin/env bash
#
# Meta-test for scripts/refresh-example-pins.sh. Runs it against a copy of the
# real example files, then proves the result with tests/example-pin-check.test.sh
# (the guard CI runs), plus idempotency, a pin it must not touch, and input guards.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REFRESH="${REPO_ROOT}/scripts/refresh-example-pins.sh"

fail() { echo "NOT OK: $1"; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# A fake repo root: the real example files, the check, and a manifest at v9.9.9.
mkdir -p "$WORK/docs" "$WORK/tests"
cp "${REPO_ROOT}/README.md" "$WORK/README.md"
cp "${REPO_ROOT}/docs/ORG_DEPENDABOT_AUTO_MERGE.md" "${REPO_ROOT}/docs/ORG_TERRATEST.md" "$WORK/docs/"
cp "${REPO_ROOT}/tests/example-pin-check.test.sh" "$WORK/tests/"
printf '{".": "9.9.9"}\n' > "$WORK/.release-please-manifest.json"
# A third-party pin with a version comment must not be touched.
printf '\n    uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1\n' >> "$WORK/README.md"

SHA=abcdefabcdefabcdefabcdefabcdefabcdefabcd

# Control: the check fails before the refresh (manifest says 9.9.9).
bash "$WORK/tests/example-pin-check.test.sh" >/dev/null 2>&1 && fail "control: check passed before refresh"
echo "OK: control, check fails before refresh"

out="$(REPO_ROOT="$WORK" bash "$REFRESH" v9.9.9 "$SHA" 2>&1)" || fail "refresh failed: $out"
n="$(sed -nE 's/^example pins at v9\.9\.9: ([0-9]+)$/\1/p' <<< "$out")"
[ "${n:-0}" -gt 0 ] || fail "refresh reported no pins: $out"
echo "OK: refreshed ${n} pin(s)"

bash "$WORK/tests/example-pin-check.test.sh" >/dev/null 2>&1 || fail "check still fails after refresh"
grep -qF "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1" "$WORK/README.md" || fail "third-party pin was rewritten"
old_left="$(grep -hcE '/Actions/\.github/workflows/[^@]*@[0-9a-f]{40} # v' "$WORK/README.md" "$WORK"/docs/*.md | paste -sd+ - | bc)"
new_now="$(grep -hcE "/Actions/\.github/workflows/[^@]*@${SHA} # v9\.9\.9" "$WORK/README.md" "$WORK"/docs/*.md | paste -sd+ - | bc)"
[ "$old_left" = "$new_now" ] || fail "some workflow pins were not refreshed (${new_now} of ${old_left})"
echo "OK: example-pin-check passes; third-party pin untouched"

cp -R "$WORK" "$WORK.snap" 2>/dev/null
REPO_ROOT="$WORK" bash "$REFRESH" v9.9.9 "$SHA" >/dev/null 2>&1 || fail "second run failed"
diff -rq "$WORK.snap" "$WORK" >/dev/null || fail "second run changed files (not idempotent)"
rm -rf "$WORK.snap"
echo "OK: idempotent"

REPO_ROOT="$WORK" bash "$REFRESH" 9.9.9 "$SHA" >/dev/null 2>&1 && fail "tag without v accepted"
REPO_ROOT="$WORK" bash "$REFRESH" v9.9.9 main >/dev/null 2>&1 && fail "non-SHA accepted"
echo "OK: bad tag and bad sha refused"

# No pins at all is a failure, not a silent success.
EMPTY="$(mktemp -d)"; printf 'nothing here\n' > "$EMPTY/README.md"
REPO_ROOT="$EMPTY" bash "$REFRESH" v9.9.9 "$SHA" >/dev/null 2>&1 && { rm -rf "$EMPTY"; fail "no pins reported success"; }
rm -rf "$EMPTY"
echo "OK: no pins found exits non-zero"
echo "ALL TESTS PASSED"
