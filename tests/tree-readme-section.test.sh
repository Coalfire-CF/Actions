#!/usr/bin/env bash
#
# Regression pin for the README-tree section emitted by org-tree-readme.yml.
#
# Bug (pre-fix): the embedded updater emitted
#     ## Tree
#     ```text
#     ...
#     ```
# with NO blank line after the heading and NONE around the fence — i.e. a section
# that FAILS the org-markdown-lint rules MD022 (blanks-around-headings) and MD031
# (blanks-around-fences). Because the tree workflow re-runs on every push and
# rewrites this section, any README it migrates ping-pongs red on `check-markdown`
# and no consumer-side blank-line fix can survive the next regeneration.
#
# This test extracts the REAL embedded updater straight out of the workflow (so it
# cannot drift from what Actions runs), regenerates the section against a fixture,
# and asserts the result is MD022/MD031-clean — both structurally (always) and via
# real markdownlint-cli2 with the actual org config (when node/npx is available).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WF="${REPO_ROOT}/.github/workflows/org-tree-readme.yml"
MDLINT_WF="${REPO_ROOT}/.github/workflows/org-markdown-lint.yml"

fail() { echo "NOT OK: $1"; exit 1; }

[ -f "$WF" ] || fail "workflow not found: $WF"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

# ---- 1. Extract the embedded updater exactly as GitHub Actions runs it --------
# The script lives in a `cat >/tmp/update-readme-tree.sh <<'BASH' ... BASH` heredoc
# inside a `run: |` block. YAML dedents the block scalar at runtime; textwrap.dedent
# reproduces that faithfully (stdlib only — no pyyaml on the runner).
UPDATER="${TMPD}/update-readme-tree.sh"
python3 - "$WF" > "$UPDATER" <<'PY'
import re, sys, textwrap
src = open(sys.argv[1]).read()
m = re.search(r"<<'BASH'\n(.*?)\n[ \t]*BASH\b", src, re.S)
if not m:
    sys.stderr.write("could not locate the <<'BASH' updater heredoc\n"); sys.exit(1)
sys.stdout.write(textwrap.dedent(m.group(1)))
PY
[ -s "$UPDATER" ] || fail "extracted updater is empty"
grep -q 'final_tree=' "$UPDATER" || fail "extracted updater does not contain the tree template"
echo "OK: extracted the embedded updater from org-tree-readme.yml ($(wc -l < "$UPDATER" | tr -d ' ') lines)"

# ---- 2. Hermetic `tree` shim (runner has no tree; content is irrelevant here) --
mkdir -p "${TMPD}/bin"
cat > "${TMPD}/bin/tree" <<'SH'
#!/bin/sh
# canned listing — the bug is in the section framing, not the tree body
printf '.\n|-- main.tf\n|-- variables.tf\n|-- outputs.tf\n'
SH
chmod +x "${TMPD}/bin/tree"

# ---- helper: run updater in a fixture dir, echo the resulting README ----------
run_updater() {
  local dir="$1"
  ( cd "$dir" && PATH="${TMPD}/bin:$PATH" EXCLUDE_PATTERN=".git" "${BASH:-bash}" "$UPDATER" >/dev/null 2>&1
    echo "$?" )  # exit 10 == updated, 0 == no change
}

# structural MD022/MD031 assertion on a produced README
assert_section_clean() {
  local readme="$1" label="$2"
  python3 - "$readme" "$label" <<'PY'
import sys
readme, label = sys.argv[1], sys.argv[2]
lines = open(readme).read().split("\n")
def blank(i): return 0 <= i < len(lines) and lines[i].strip() == ""
try:
    ti = next(i for i, l in enumerate(lines) if l.strip() == "## Tree")
except StopIteration:
    print(f"NOT OK: [{label}] no '## Tree' heading in output"); sys.exit(1)
if not blank(ti + 1):
    print(f"NOT OK: [{label}] MD022 — no blank line AFTER '## Tree' (got {lines[ti+1]!r})"); sys.exit(1)
fo = next((i for i in range(ti, len(lines)) if lines[i].startswith("```")), None)
if fo is None:
    print(f"NOT OK: [{label}] no opening fence after '## Tree'"); sys.exit(1)
if not blank(fo - 1):
    print(f"NOT OK: [{label}] MD031 — no blank line BEFORE the fence (got {lines[fo-1]!r})"); sys.exit(1)
fc = next((i for i in range(fo + 1, len(lines)) if lines[i].startswith("```")), None)
if fc is None:
    print(f"NOT OK: [{label}] no closing fence"); sys.exit(1)
# after the closing fence: blank line, or end-of-document (single trailing newline)
tail = [l for l in lines[fc + 1:]]
if any(l.strip() for l in tail) and not blank(fc + 1):
    print(f"NOT OK: [{label}] MD031 — no blank line AFTER the closing fence (got {lines[fc+1]!r})"); sys.exit(1)
print(f"structural-clean [{label}]")
PY
}

# ---- 3. REPLACE case: an existing, NON-compliant ## Tree section (the bug) ----
REP="${TMPD}/replace"; mkdir -p "$REP"
cat > "${REP}/README.md" <<'MD'
# terraform-aws-example

## Description

An example module.

## Tree
```text
stale
```
## License

MIT
MD
rc="$(run_updater "$REP")"
[ "$rc" = "10" ] || fail "replace: updater exit code was '$rc' (expected 10 = updated)"
assert_section_clean "${REP}/README.md" "replace" || exit 1
grep -q '^## License$' "${REP}/README.md" || fail "replace: following '## License' section was lost"
echo "OK: replace — regenerated ## Tree section is MD022/MD031-clean and preserves the next section"

# ---- 4. APPEND case: README with NO ## Tree section --------------------------
APP="${TMPD}/append"; mkdir -p "$APP"
cat > "${APP}/README.md" <<'MD'
# terraform-aws-example

## Description

An example module.
MD
rc="$(run_updater "$APP")"
[ "$rc" = "10" ] || fail "append: updater exit code was '$rc' (expected 10 = updated)"
assert_section_clean "${APP}/README.md" "append" || exit 1
echo "OK: append — freshly appended ## Tree section is MD022/MD031-clean"

# ---- 5. IDEMPOTENCE: re-running must not re-introduce debt (the clobber loop) --
before="$(cat "${REP}/README.md")"
run_updater "$REP" >/dev/null
assert_section_clean "${REP}/README.md" "rerun" || exit 1
echo "OK: idempotence — a second regeneration stays MD022/MD031-clean (clobber loop closed)"

# ---- 6. Authoritative check: real markdownlint-cli2 + the actual org config ----
CFG="${TMPD}/.markdownlint-cli2.jsonc"
if [ -f "$MDLINT_WF" ]; then
  python3 - "$MDLINT_WF" > "$CFG" <<'PY'
import re, sys, textwrap
src = open(sys.argv[1]).read()
m = re.search(r"<<'JSONC'\n(.*?)\n[ \t]*JSONC\b", src, re.S)
sys.stdout.write(textwrap.dedent(m.group(1)) if m else "")
PY
fi
ML=""
if command -v markdownlint-cli2 >/dev/null 2>&1; then ML="markdownlint-cli2"
elif command -v npx >/dev/null 2>&1; then ML="npx --yes markdownlint-cli2@0.23.0"; fi
if [ -n "$ML" ] && [ -s "$CFG" ]; then
  out="$( ( cd "$REP" && $ML --config "$CFG" README.md ) 2>&1 )" || true
  if printf '%s' "$out" | grep -qE 'MD022|MD031'; then
    printf '%s\n' "$out"
    fail "markdownlint reported MD022/MD031 on the regenerated section"
  fi
  echo "OK: markdownlint-cli2 (org config) reports no MD022/MD031 on the regenerated section"
else
  echo "SKIP: markdownlint-cli2 unavailable (no node/npx) — structural asserts above stand in"
fi

# ---- 7. Drift guard: the template + awk in the workflow must retain the fix ----
# The line immediately after the `## ${CHAPTER}` heading in the final_tree literal
# must be blank (the heading→fence separator — MD022/MD031).
awk '
  /final_tree="## \$\{CHAPTER\}/ { getline nxt; if (nxt ~ /^[[:space:]]*$/) ok=1 }
  END { exit !ok }
' "$WF" || fail "drift — final_tree no longer has a blank line between the heading and the fence"
grep -q 'p==0 {print ""; p=1}' "$WF" \
  || fail "drift — the replace-awk no longer emits a blank line before the next heading (MD022/MD031)"
echo "OK: drift guard — workflow template + awk retain the blank-line framing"

echo "ALL TESTS PASSED"
