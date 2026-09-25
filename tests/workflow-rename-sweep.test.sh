#!/usr/bin/env bash
#
# Meta-test for scripts/workflow-rename-sweep.sh MODE=rewrite (offline). Builds
# a fake fleet checkout with bootstrap-named callers, a custom-named caller, a
# commented example and an unrelated workflow, then asserts the exact result.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SWEEP="${REPO_ROOT}/scripts/workflow-rename-sweep.sh"

fail() { echo "NOT OK: $1"; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

OLD=d06776a5840b53ff374f80f3c45e84181425b6d6
PIN=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
REPO="$WORK/repo"; WF="$REPO/.github/workflows"; mkdir -p "$WF"
git -C "$REPO" init -q

cat > "$WF/org-release.yml" <<EOF
name: Org Release
on:
  push:
jobs:
  create-release:
    uses: Coalfire-CF/Actions/.github/workflows/org-release.yml@${OLD} # v0.18.2
    secrets: inherit
EOF
cat > "$WF/org-dependabot-auto-merge.yml" <<EOF
name: Dependabot Auto-Merge
on:
  pull_request_target:
jobs:
  auto-merge:
    uses: Coalfire-CF/Actions/.github/workflows/org-dependabot-auto-merge.yml@${OLD} # v0.18.2
    with:
      actions_ref: ${OLD} # v0.18.2
    secrets: inherit
EOF
cat > "$WF/security.yml" <<EOF
name: Security
on:
  pull_request:
jobs:
  trivy:
    uses: Coalfire-CF/Actions/.github/workflows/org-trivy-pr.yml@${OLD}
  gitleaks:
    uses: Coalfire-CF/Actions/.github/workflows/org-gitleaks-pr.yml@v0.18.2 # tag pin
  # uses: Coalfire-CF/Actions/.github/workflows/org-opa.yml@${OLD}
EOF
# Historical names that map onto one new file: the second must not clobber the first.
cat > "$WF/org-gitleaks.yml" <<EOF
name: Gitleaks
on:
  pull_request:
jobs:
  gitleaks:
    uses: Coalfire-CF/Actions/.github/workflows/org-gitleaks-pr.yml@${OLD} # v0.18.2
EOF
cp "$WF/org-gitleaks.yml" "$WF/org-gitleaks-pr.yml"
cat > "$WF/unrelated.yml" <<'EOF'
name: Unrelated
on: push
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
EOF
cp "$WF/unrelated.yml" "$WORK/unrelated.orig"
git -C "$REPO" add -A && git -C "$REPO" -c user.name=t -c user.email=t@t commit -qm init

run() { MODE=rewrite TARGET_DIR="$REPO" ACTIONS_PIN="$PIN" ACTIONS_TAG=v1.0.0 bash "$SWEEP"; }
out="$(run 2>&1)" || fail "rewrite exited non-zero: $out"

# Bootstrap-named callers are renamed and retitled.
[ -f "$WF/release-please.yml" ] && [ ! -e "$WF/org-release.yml" ] || fail "org-release.yml not renamed: $(ls "$WF")"
[ -f "$WF/automation-dependabot-auto-merge.yml" ] || fail "auto-merge caller not renamed"
grep -qx 'name: "Release: Release Please"' "$WF/release-please.yml" || fail "release caller name not set"
grep -qF "workflows/release-please.yml@${PIN} # v1.0.0" "$WF/release-please.yml" || fail "release uses: not rewritten"
grep -qF "workflows/automation-dependabot-auto-merge.yml@${PIN} # v1.0.0" "$WF/automation-dependabot-auto-merge.yml" || fail "auto-merge uses: not rewritten"
grep -qF "actions_ref: ${PIN} # v1.0.0" "$WF/automation-dependabot-auto-merge.yml" || fail "actions_ref not repinned"
grep -q '^  auto-merge:$' "$WF/automation-dependabot-auto-merge.yml" || fail "caller job id changed"
echo "OK: bootstrap callers renamed, retitled, repinned; job id kept"

# Custom-named caller keeps its filename and name; every org-* ref rewritten.
[ -f "$WF/security.yml" ] || fail "custom caller was renamed"
grep -qx 'name: Security' "$WF/security.yml" || fail "custom caller name changed"
grep -qF "workflows/ci-security-trivy.yml@${PIN} # v1.0.0" "$WF/security.yml" || fail "unpinned-comment ref not rewritten"
grep -qF "workflows/ci-security-gitleaks.yml@${PIN} # v1.0.0" "$WF/security.yml" || fail "tag-pinned ref not rewritten"
grep -q 'tag pin' "$WF/security.yml" && fail "old trailing comment kept"
grep -qF "# uses: Coalfire-CF/Actions/.github/workflows/org-opa.yml@${OLD}" "$WF/security.yml" || fail "commented example was touched"
echo "OK: custom caller rewritten in place; commented example untouched"

cmp -s "$WF/unrelated.yml" "$WORK/unrelated.orig" || fail "unrelated workflow modified"
changed="$(grep -cE '^(renamed|rewrote) ' <<< "$out")"
[ "$changed" = "5" ] || fail "expected 5 changed files, got ${changed}: ${out}"
echo "OK: exactly 5 caller files changed, unrelated untouched"

# Two historical names for one new file: one renamed, the other kept and repinned.
[ -f "$WF/ci-security-gitleaks.yml" ] || fail "gitleaks caller not renamed"
n_gl=0; for g in org-gitleaks org-gitleaks-pr ci-security-gitleaks; do [ -f "$WF/$g.yml" ] && n_gl=$((n_gl + 1)); done
[ "$n_gl" = "2" ] || fail "expected 2 gitleaks callers after rename, got ${n_gl}: $(ls "$WF")"
grep -l "org-gitleaks-pr.yml@" "$WF"/*.yml >/dev/null 2>&1 && fail "a gitleaks caller still calls org-gitleaks-pr.yml"
grep -q "already exists" <<< "$out" || fail "collision was not reported"
echo "OK: colliding historical names keep one old filename, both repinned"

# Second run: nothing left to rewrite -> rc 3.
MODE=rewrite TARGET_DIR="$REPO" ACTIONS_PIN="$PIN" ACTIONS_TAG=v1.0.0 bash "$SWEEP" >/dev/null 2>&1
[ $? -eq 3 ] || fail "second run should report nothing to rewrite (rc 3)"
echo "OK: idempotent (second run rc=3)"

# Pre-0.18.2 auto-merge callers have no actions_ref: add it, with and without an
# existing with: block. The result must be one with: key holding both inputs.
for variant in bare with; do
  R2="$WORK/r2-$variant"; mkdir -p "$R2/.github/workflows"
  {
    echo "name: Dependabot Auto-Merge"
    echo "jobs:"
    echo "  auto-merge:"
    echo "    uses: Coalfire-CF/Actions/.github/workflows/org-dependabot-auto-merge.yml@${OLD} # v0.18.0"
    [ "$variant" = with ] && { echo "    with:"; echo "      auto_merge_method: squash"; }
    echo "    secrets: inherit"
  } > "$R2/.github/workflows/org-dependabot-auto-merge.yml"
  out2="$(MODE=rewrite TARGET_DIR="$R2" ACTIONS_PIN="$PIN" ACTIONS_TAG=v1.0.0 bash "$SWEEP" 2>&1)" || fail "${variant}: rewrite failed: $out2"
  f2="$R2/.github/workflows/automation-dependabot-auto-merge.yml"
  grep -qx "      actions_ref: ${PIN} # v1.0.0" "$f2" || fail "${variant}: actions_ref not added: $(cat "$f2")"
  [ "$(grep -c '^    with:$' "$f2")" = "1" ] || fail "${variant}: expected one with: key: $(cat "$f2")"
  if [ "$variant" = with ]; then
    grep -qx "      auto_merge_method: squash" "$f2" || fail "with: existing input lost"
  fi
  uv run --quiet --with pyyaml python3 -c "import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); w=d['jobs']['auto-merge']['with']; assert w['actions_ref']=='${PIN}', w" "$f2" \
    || fail "${variant}: result is not valid YAML with actions_ref: $(cat "$f2")"
  echo "OK: actions_ref added (${variant})"
done

# Guard: a bad pin is refused.
MODE=rewrite TARGET_DIR="$REPO" ACTIONS_PIN=main ACTIONS_TAG=v1.0.0 bash "$SWEEP" >/dev/null 2>&1 && fail "non-SHA pin accepted"
echo "OK: non-SHA pin refused"
echo "ALL TESTS PASSED"
