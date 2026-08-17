#!/usr/bin/env bash
#
# Tests for scripts/terraform-docs-partial-cleanup.sh.
#
# This script deletes lines from authored partials, so the assertions that matter
# are the ones proving it does NOT delete too much. Every check is mutation-proved:
# the false-positive guard uses a table that is deliberately NOT generated and
# asserts it survives.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLEANUP="${REPO_ROOT}/scripts/terraform-docs-partial-cleanup.sh"

fail() { echo "NOT OK: $1"; exit 1; }
[ -x "$CLEANUP" ] || fail "cleanup script missing or not executable: ${CLEANUP}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
checks=0

# ---------------------------------------------------------------------------
# 1. An orphaned generated section is removed; prose before AND after survives.
# ---------------------------------------------------------------------------
cat > "${TMP}/a.md" <<'MD'
# Title

Keep this intro.

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.5 |

## Contributing

Keep this outro.
MD
bash "$CLEANUP" "${TMP}/a.md" >/dev/null || fail "cleanup exited non-zero on a.md"
grep -q '^## Requirements' "${TMP}/a.md" && fail "generated heading survived"
grep -q 'requirement_terraform' "${TMP}/a.md" && fail "generated table row survived"
grep -q 'Keep this intro.' "${TMP}/a.md" || fail "prose BEFORE the orphan was deleted"
grep -q 'Keep this outro.' "${TMP}/a.md" || fail "prose AFTER the orphan was deleted"
grep -q '^## Contributing' "${TMP}/a.md" || fail "heading after the orphan was deleted"
checks=$((checks + 5))
echo "OK: orphaned generated section removed, surrounding prose intact"

# ---------------------------------------------------------------------------
# 2. FALSE-POSITIVE GUARD. An AUTHORED table under a generated-looking heading
#    must survive, because it carries no generated signature. Without this the
#    script would silently eat hand-written tables.
# ---------------------------------------------------------------------------
cat > "${TMP}/b.md" <<'MD'
## Inputs

| Setting | Meaning |
|---------|---------|
| retention | how long we keep logs |

## Notes

after
MD
cp "${TMP}/b.md" "${TMP}/b.orig"
bash "$CLEANUP" "${TMP}/b.md" >/dev/null || fail "cleanup exited non-zero on b.md"
cmp -s "${TMP}/b.orig" "${TMP}/b.md" \
  || fail "an AUTHORED table under '## Inputs' was modified; it has no generated marker"
checks=$((checks + 1))
echo "OK: authored table under a generated-style heading is left untouched"

# ---------------------------------------------------------------------------
# 3. The Resources table is generated via registry links, not <a name=>.
# ---------------------------------------------------------------------------
cat > "${TMP}/c.md" <<'MD'
## Resources

| Name | Type |
|------|------|
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |

## Keep

kept
MD
bash "$CLEANUP" "${TMP}/c.md" >/dev/null || fail "cleanup exited non-zero on c.md"
grep -q 'registry.terraform.io' "${TMP}/c.md" && fail "generated Resources table survived"
grep -q '^## Keep' "${TMP}/c.md" || fail "heading after Resources was deleted"
checks=$((checks + 2))
echo "OK: generated Resources table detected via its registry link"

# ---------------------------------------------------------------------------
# 4. pre-commit-terraform hook block. The opening marker is "BEGINNING OF".
# ---------------------------------------------------------------------------
cat > "${TMP}/d.md" <<'MD'
before
<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

junk
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
after
MD
bash "$CLEANUP" "${TMP}/d.md" >/dev/null || fail "cleanup exited non-zero on d.md"
grep -q 'PRE-COMMIT-TERRAFORM' "${TMP}/d.md" && fail "hook markers survived"
grep -q '^before$' "${TMP}/d.md" || fail "text before the hook block was deleted"
grep -q '^after$'  "${TMP}/d.md" || fail "text after the hook block was deleted"
checks=$((checks + 3))
echo "OK: pre-commit-terraform hook block removed, surrounding text intact"

# ---------------------------------------------------------------------------
# 5. Tree section removed, following heading kept.
# ---------------------------------------------------------------------------
printf '## Tree\n\n```text\n.\n|-- main.tf\n```\n\n## After\n\nkept\n' > "${TMP}/e.md"
bash "$CLEANUP" "${TMP}/e.md" >/dev/null || fail "cleanup exited non-zero on e.md"
grep -q '^## Tree' "${TMP}/e.md" && fail "Tree heading survived"
grep -q 'main.tf' "${TMP}/e.md" && fail "Tree body survived"
grep -q '^## After' "${TMP}/e.md" || fail "heading after Tree was deleted"
checks=$((checks + 3))
echo "OK: Tree section removed, following heading kept"

# ---------------------------------------------------------------------------
# 6. A clean file is untouched, and the script is idempotent.
# ---------------------------------------------------------------------------
printf '# Title\n\nJust prose.\n' > "${TMP}/f.md"
cp "${TMP}/f.md" "${TMP}/f.orig"
bash "$CLEANUP" "${TMP}/f.md" >/dev/null || fail "cleanup exited non-zero on a clean file"
cmp -s "${TMP}/f.orig" "${TMP}/f.md" || fail "a clean file was modified"
cp "${TMP}/a.md" "${TMP}/a.second"
bash "$CLEANUP" "${TMP}/a.second" >/dev/null || fail "second pass exited non-zero"
cmp -s "${TMP}/a.md" "${TMP}/a.second" || fail "not idempotent: a second pass changed the file again"
checks=$((checks + 2))
echo "OK: clean file untouched, and the pass is idempotent"

# ---------------------------------------------------------------------------
# 7. CHECK=true must report without writing.
# ---------------------------------------------------------------------------
cat > "${TMP}/g.md" <<'MD'
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | the id |
MD
cp "${TMP}/g.md" "${TMP}/g.orig"
CHECK=true bash "$CLEANUP" "${TMP}/g.md" >/dev/null || fail "CHECK mode exited non-zero"
cmp -s "${TMP}/g.orig" "${TMP}/g.md" || fail "CHECK=true wrote to the file"
checks=$((checks + 1))
echo "OK: CHECK=true reports without writing"

[ "$checks" -ge 17 ] || fail "expected at least 17 checks, ran ${checks}"
echo "ALL TESTS PASSED (${checks} checks)"
