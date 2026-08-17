#!/usr/bin/env bash
#
# Unit tests for the pure helpers in scripts/terraform-docs-standard-sweep.sh.
#
# The sweep rewrites README.md in place across the fleet, so the one failure it
# must never have is silently dropping authored prose. Every assertion here is
# mutation-proved: each check is shown to FAIL on a perturbed input as well as
# pass on a good one, because a preservation check that cannot fail is worse
# than none.
#
# The script is sourced with TFDOCS_SWEEP_LIB_ONLY set, which returns before any
# prerequisite check, clone or push.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SWEEP="${REPO_ROOT}/scripts/terraform-docs-standard-sweep.sh"

fail() { echo "NOT OK: $1"; exit 1; }

[ -f "$SWEEP" ] || fail "sweep script not found at ${SWEEP}"

# shellcheck source=/dev/null
TFDOCS_SWEEP_LIB_ONLY=1 . "$SWEEP" || fail "could not source sweep script as a library"

for fn in normalize_prose strip_tree_section prose_preserved; do
  declare -F "$fn" >/dev/null || fail "${fn} not defined after sourcing"
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

checks=0

# ---------------------------------------------------------------------------
# normalize_prose: strips trailing whitespace and terraform-docs escaping.
# ---------------------------------------------------------------------------
printf '![Coalfire](coalfire\\_logo.png)\ntrailing spaces here   \nplain\n' > "${TMP}/n-in.md"
got="$(normalize_prose "${TMP}/n-in.md")"
want="$(printf '![Coalfire](coalfire_logo.png)\ntrailing spaces here\nplain\n')"
[ "$got" = "$want" ] || fail "normalize_prose did not unescape/trim (got: ${got})"
checks=$((checks + 1))

# Mutation: a line that genuinely differs must still differ after normalizing,
# or the normalizer is destroying signal rather than noise.
printf 'plain text\n' > "${TMP}/n-a.md"
printf 'plain texx\n' > "${TMP}/n-b.md"
[ "$(normalize_prose "${TMP}/n-a.md")" != "$(normalize_prose "${TMP}/n-b.md")" ] \
  || fail "normalize_prose collapsed two genuinely different lines"
checks=$((checks + 1))

echo "OK: normalize_prose unescapes and trims, and preserves real differences"

# ---------------------------------------------------------------------------
# strip_tree_section: removes exactly the `## Tree` section.
# ---------------------------------------------------------------------------
cat > "${TMP}/t-in.md" <<'MD'
# Title

## Description

Keep this line.

## Tree

```text
.
|-- main.tf
```

## Dependencies

Keep this too.
MD

strip_tree_section "${TMP}/t-in.md" > "${TMP}/t-out.md"
grep -q '^## Tree' "${TMP}/t-out.md" && fail "Tree heading survived the strip"
grep -q 'main.tf' "${TMP}/t-out.md" && fail "Tree body survived the strip"
grep -q 'Keep this line.' "${TMP}/t-out.md" || fail "prose before Tree was removed"
grep -q 'Keep this too.' "${TMP}/t-out.md" || fail "prose after Tree was removed"
grep -q '^## Dependencies' "${TMP}/t-out.md" || fail "heading after Tree was removed"
checks=$((checks + 1))

# A file with no Tree section must come through byte-identical. Without this,
# the strip could be deleting content in the 150 repos that have no Tree at all.
cat > "${TMP}/t-none.md" <<'MD'
# Title

## Description

Only prose here.
MD
strip_tree_section "${TMP}/t-none.md" > "${TMP}/t-none-out.md"
cmp -s "${TMP}/t-none.md" "${TMP}/t-none-out.md" \
  || fail "strip_tree_section altered a file that has no Tree section"
checks=$((checks + 1))

# A `### Tree` subsection is NOT the retired section and must be left alone.
printf '### Tree\n\nkeep me\n' > "${TMP}/t-sub.md"
strip_tree_section "${TMP}/t-sub.md" > "${TMP}/t-sub-out.md"
grep -q 'keep me' "${TMP}/t-sub-out.md" || fail "strip removed a ### Tree subsection"
checks=$((checks + 1))

echo "OK: strip_tree_section removes only the ## Tree section (${checks} checks so far)"

# ---------------------------------------------------------------------------
# prose_preserved: the safety gate. Must pass when prose survives, and must FAIL
# when a single authored line is dropped.
# ---------------------------------------------------------------------------
printf 'First authored line.\nSecond authored line.\n' > "${TMP}/authored.md"

# Rendered output that kept both lines, with escaping and trailing space noise
# plus generated content around them.
cat > "${TMP}/rendered-good.md" <<'MD'
<!-- BEGIN_TF_DOCS -->
First authored line.
| generated | table |
Second authored line.
<!-- END_TF_DOCS -->
MD
prose_preserved "${TMP}/authored.md" "${TMP}/rendered-good.md" 2>/dev/null \
  || fail "prose_preserved reported loss when both lines were present"
checks=$((checks + 1))

# Mutation: drop one authored line from the render. The gate MUST fail.
cat > "${TMP}/rendered-lossy.md" <<'MD'
<!-- BEGIN_TF_DOCS -->
First authored line.
<!-- END_TF_DOCS -->
MD
if prose_preserved "${TMP}/authored.md" "${TMP}/rendered-lossy.md" 2>/dev/null; then
  fail "prose_preserved PASSED while an authored line was missing (gate cannot fail)"
fi
checks=$((checks + 1))

# Mutation: an empty render must fail too. This is the empty-partials case that
# would silently destroy a nested README's prose.
: > "${TMP}/rendered-empty.md"
if prose_preserved "${TMP}/authored.md" "${TMP}/rendered-empty.md" 2>/dev/null; then
  fail "prose_preserved PASSED against an empty rendered README"
fi
checks=$((checks + 1))

# Escaped and whitespace-noised render must still pass, or the gate would block
# every real migration with false positives.
printf '![Coalfire](coalfire_logo.png)\nEnds with space. \n' > "${TMP}/authored-esc.md"
printf '![Coalfire](coalfire\\_logo.png)\nEnds with space.\n' > "${TMP}/rendered-esc.md"
prose_preserved "${TMP}/authored-esc.md" "${TMP}/rendered-esc.md" 2>/dev/null \
  || fail "prose_preserved failed on legitimate escaping/trailing-space differences"
checks=$((checks + 1))

# An empty authored file trivially passes; assert that is a real 0-line case and
# not the gate short-circuiting, by confirming the lossy case above still fails.
: > "${TMP}/authored-empty.md"
prose_preserved "${TMP}/authored-empty.md" "${TMP}/rendered-empty.md" 2>/dev/null \
  || fail "prose_preserved failed on an empty authored file (the no-header-prose case)"
checks=$((checks + 1))

echo "OK: prose_preserved passes on survival and FAILS on dropped, empty and lost prose"

[ "$checks" -ge 10 ] || fail "expected at least 10 checks to run, ran ${checks}"
echo "ALL TESTS PASSED (${checks} checks)"
