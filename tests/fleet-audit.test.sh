#!/usr/bin/env bash
#
# Meta-test for scripts/fleet-audit.sh and scripts/fleet-audit-report.sh.
# Snapshot mode (FLEET_AUDIT_SNAPSHOT) classifies fixture trees with no gh.
# A mock gh that rejects writes proves live enumerate issues zero mutations.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
AUDIT="${REPO_ROOT}/scripts/fleet-audit.sh"
REPORT="${REPO_ROOT}/scripts/fleet-audit-report.sh"

fail() { echo "NOT OK: $1"; exit 1; }
ok() { echo "OK: $1"; }

[ -f "$AUDIT" ] || fail "helper not found at $AUDIT"
[ -f "$REPORT" ] || fail "helper not found at $REPORT"
chmod +x "$AUDIT" "$REPORT"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

CURRENT_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
OLD_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
export ACTIONS_SHA="$CURRENT_SHA"
export ACTIONS_VERSION="v0.18.1"
export AUTOMERGE_APP_ID="3436395"

empty_json_files() {
  local d="$1"
  printf '%s\n' '{}' > "$d/languages.json"
  printf '%s\n' '[]' > "$d/prs.json"
  printf '%s\n' '[]' > "$d/tags.json"
  printf '%s\n' '[]' > "$d/releases.json"
  printf '%s\n' '[]' > "$d/rulesets.json"
}

write_meta() {
  local d="$1" name="$2"
  cat > "$d/meta.json" <<EOF
{"nameWithOwner":"${name}","default_branch":"main","isFork":false,"isArchived":false,"repositoryTopics":[]}
EOF
}

run_snap() {
  local d="$1"
  FLEET_AUDIT_SNAPSHOT="$d" bash "$AUDIT"
}

assert_finding() {
  local json="$1" id="$2"
  printf '%s' "$json" | jq -e --arg id "$id" '.findings[] | select(.id == $id)' >/dev/null \
    || fail "expected finding $id in: $json"
}

assert_no_finding() {
  local json="$1" id="$2"
  if printf '%s' "$json" | jq -e --arg id "$id" '.findings[] | select(.id == $id)' >/dev/null 2>&1; then
    fail "did not expect finding $id in: $json"
  fi
}

# ---- pin-lag + sha-comment ----
SNAP="$WORK/lag"; mkdir -p "$SNAP/workflows"
write_meta "$SNAP" "Coalfire-CF/lag-repo"
empty_json_files "$SNAP"
cat > "$SNAP/workflows/org-release.yml" <<EOF
jobs:
  release:
    uses: Coalfire-CF/Actions/.github/workflows/org-release.yml@${OLD_SHA} # v0.12.1
EOF
OUT="$(run_snap "$SNAP")" || fail "lag snapshot rc"
assert_finding "$OUT" "pin-lag"
printf '%s' "$OUT" | jq -e '.status == "FAIL"' >/dev/null || fail "lag status FAIL"
ok "pin-lag"

# ---- @main ----
SNAP="$WORK/main"; mkdir -p "$SNAP/workflows"
write_meta "$SNAP" "Coalfire-CF/main-repo"
empty_json_files "$SNAP"
cat > "$SNAP/workflows/ci.yml" <<'EOF'
jobs:
  t:
    uses: Coalfire-CF/Actions/.github/workflows/org-gitleaks-pr.yml@main
EOF
OUT="$(run_snap "$SNAP")" || fail "main snapshot rc"
assert_finding "$OUT" "pin-bad-ref"
ok "pin-bad-ref"

# ---- bare tag ----
SNAP="$WORK/bare"; mkdir -p "$SNAP/workflows"
write_meta "$SNAP" "Coalfire-CF/bare-repo"
empty_json_files "$SNAP"
cat > "$SNAP/workflows/ci.yml" <<'EOF'
jobs:
  t:
    uses: Coalfire-CF/Actions/.github/workflows/org-gitleaks-pr.yml@v0.18.1
EOF
OUT="$(run_snap "$SNAP")" || fail "bare snapshot rc"
assert_finding "$OUT" "pin-bare-tag"
ok "pin-bare-tag"

# ---- SHA no comment ----
SNAP="$WORK/nocomment"; mkdir -p "$SNAP/workflows"
write_meta "$SNAP" "Coalfire-CF/nocomment-repo"
empty_json_files "$SNAP"
cat > "$SNAP/workflows/ci.yml" <<EOF
jobs:
  t:
    uses: Coalfire-CF/Actions/.github/workflows/org-gitleaks-pr.yml@${CURRENT_SHA}
EOF
OUT="$(run_snap "$SNAP")" || fail "nocomment snapshot rc"
assert_finding "$OUT" "pin-sha-no-comment"
ok "pin-sha-no-comment"

# ---- mixed pins ----
SNAP="$WORK/mixed"; mkdir -p "$SNAP/workflows"
write_meta "$SNAP" "Coalfire-CF/mixed-repo"
empty_json_files "$SNAP"
cat > "$SNAP/workflows/a.yml" <<EOF
jobs:
  t:
    uses: Coalfire-CF/Actions/.github/workflows/org-release.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/workflows/b.yml" <<EOF
jobs:
  t:
    uses: Coalfire-CF/Actions/.github/workflows/org-gitleaks-pr.yml@${OLD_SHA} # v0.12.1
EOF
OUT="$(run_snap "$SNAP")" || fail "mixed snapshot rc"
assert_finding "$OUT" "pin-mixed"
ok "pin-mixed"

# ---- no-caller ----
SNAP="$WORK/nocall"; mkdir -p "$SNAP/workflows"
write_meta "$SNAP" "Coalfire-CF/empty-repo"
empty_json_files "$SNAP"
echo "name: local" > "$SNAP/workflows/ci.yml"
OUT="$(run_snap "$SNAP")" || fail "nocall snapshot rc"
assert_finding "$OUT" "no-caller"
ok "no-caller"

# ---- producer: local refs, not no-caller / pin-lag ----
SNAP="$WORK/producer"; mkdir -p "$SNAP/workflows"
write_meta "$SNAP" "Coalfire-CF/Actions"
empty_json_files "$SNAP"
cat > "$SNAP/workflows/dependabot-auto-merge.yml" <<'EOF'
jobs:
  t:
    uses: ./.github/workflows/org-dependabot-auto-merge.yml
EOF
OUT="$(run_snap "$SNAP")" || fail "producer snapshot rc"
printf '%s' "$OUT" | jq -e '.role == "producer"' >/dev/null || fail "producer role"
assert_no_finding "$OUT" "no-caller"
assert_no_finding "$OUT" "pin-lag"
ok "producer local refs"

# ---- current pin PASS (adopted, automerge + dependabot present) ----
SNAP="$WORK/pass"; mkdir -p "$SNAP/workflows"
write_meta "$SNAP" "Coalfire-CF/pass-repo"
empty_json_files "$SNAP"
printf '%s\n' '{"HCL": 100}' > "$SNAP/languages.json"
cat > "$SNAP/workflows/org-release.yml" <<EOF
jobs:
  release:
    uses: Coalfire-CF/Actions/.github/workflows/org-release.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/workflows/org-dependabot.yml" <<EOF
jobs:
  d:
    uses: Coalfire-CF/Actions/.github/workflows/org-dependabot.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/workflows/org-dependabot-auto-merge.yml" <<EOF
jobs:
  d:
    uses: Coalfire-CF/Actions/.github/workflows/org-dependabot-auto-merge.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/workflows/org-terraform-validate.yml" <<EOF
jobs:
  d:
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-validate.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/workflows/org-terraform-fmt.yml" <<EOF
jobs:
  d:
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-fmt.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/workflows/org-terraform-docs.yml" <<EOF
jobs:
  d:
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-docs.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/dependabot.yml" <<'EOF'
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: /
    groups:
      org-actions:
        patterns: ["Coalfire-CF/*"]
EOF
printf '%s\n' '[{"name":"v1.0.0"}]' > "$SNAP/tags.json"
printf '%s\n' '[{"tagName":"v1.0.0"}]' > "$SNAP/releases.json"
OUT="$(run_snap "$SNAP")" || fail "pass snapshot rc"
printf '%s' "$OUT" | jq -e '.status == "PASS"' >/dev/null || fail "expected PASS: $OUT"
ok "current pin PASS"

# ---- automerge-missing-caller + dependabot-missing-gha ----
SNAP="$WORK/amiss"; mkdir -p "$SNAP/workflows"
write_meta "$SNAP" "Coalfire-CF/amiss-repo"
empty_json_files "$SNAP"
printf '%s\n' '[{"name":"v1.0.0"}]' > "$SNAP/tags.json"
printf '%s\n' '[{"tagName":"v1.0.0"}]' > "$SNAP/releases.json"
cat > "$SNAP/workflows/org-release.yml" <<EOF
jobs:
  release:
    uses: Coalfire-CF/Actions/.github/workflows/org-release.yml@${CURRENT_SHA} # v0.18.1
EOF
OUT="$(run_snap "$SNAP")" || fail "amiss snapshot rc"
assert_finding "$OUT" "automerge-missing-caller"
assert_finding "$OUT" "dependabot-missing-gha"
ok "automerge-missing-caller + dependabot-missing-gha"

# ---- Dependabot PR classifications ----
SNAP="$WORK/prs"; mkdir -p "$SNAP/workflows"
write_meta "$SNAP" "Coalfire-CF/prs-repo"
empty_json_files "$SNAP"
printf '%s\n' '[{"name":"v1.0.0"}]' > "$SNAP/tags.json"
printf '%s\n' '[{"tagName":"v1.0.0"}]' > "$SNAP/releases.json"
cat > "$SNAP/workflows/org-release.yml" <<EOF
jobs:
  release:
    uses: Coalfire-CF/Actions/.github/workflows/org-release.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/workflows/org-dependabot.yml" <<EOF
jobs:
  d:
    uses: Coalfire-CF/Actions/.github/workflows/org-dependabot.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/workflows/org-dependabot-auto-merge.yml" <<EOF
jobs:
  d:
    uses: Coalfire-CF/Actions/.github/workflows/org-dependabot-auto-merge.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/dependabot.yml" <<'EOF'
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: /
EOF
cat > "$SNAP/prs.json" <<'EOF'
[
  {
    "number": 1,
    "title": "chore(deps): bump Coalfire-CF/Actions",
    "author": {"login": "dependabot[bot]"},
    "labels": [],
    "headRefName": "dependabot/github_actions/x",
    "files": [{"path": ".github/workflows/org-release.yml"}]
  },
  {
    "number": 2,
    "title": "chore(deps): bump actions/checkout",
    "author": {"login": "dependabot[bot]"},
    "labels": [{"name": "merge/approved"}],
    "headRefName": "dependabot/github_actions/y",
    "files": [{"path": ".github/workflows/ci.yml"}]
  },
  {
    "number": 3,
    "title": "chore(deps): bump hashicorp/aws",
    "author": {"login": "dependabot[bot]"},
    "labels": [{"name": "merge/blocked"}, {"name": "blocked/known-vuln"}],
    "headRefName": "dependabot/terraform/z",
    "files": [{"path": "main.tf"}]
  },
  {
    "number": 4,
    "title": "chore(deps): bump Coalfire-CF/Actions",
    "author": {"login": "dependabot[bot]"},
    "labels": [{"name": "blocked/terraform-no-tests"}, {"name": "merge/skipped"}],
    "headRefName": "dependabot/github_actions/z",
    "files": [{"path": ".github/workflows/org-release.yml"}]
  }
]
EOF
OUT="$(run_snap "$SNAP")" || fail "prs snapshot rc"
assert_finding "$OUT" "dependabot-unlabeled"
assert_finding "$OUT" "automerge-approved-unmerged"
assert_finding "$OUT" "automerge-blocked"
assert_finding "$OUT" "automerge-tf-block-on-actions"
ok "dependabot PR classifications"

# ---- ruleset-no-bypass ----
SNAP="$WORK/rules"; mkdir -p "$SNAP/workflows"
write_meta "$SNAP" "Coalfire-CF/rules-repo"
empty_json_files "$SNAP"
printf '%s\n' '[{"name":"v1.0.0"}]' > "$SNAP/tags.json"
printf '%s\n' '[{"tagName":"v1.0.0"}]' > "$SNAP/releases.json"
cat > "$SNAP/workflows/org-release.yml" <<EOF
jobs:
  release:
    uses: Coalfire-CF/Actions/.github/workflows/org-release.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/workflows/org-dependabot.yml" <<EOF
jobs:
  d:
    uses: Coalfire-CF/Actions/.github/workflows/org-dependabot.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/workflows/org-dependabot-auto-merge.yml" <<EOF
jobs:
  d:
    uses: Coalfire-CF/Actions/.github/workflows/org-dependabot-auto-merge.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/dependabot.yml" <<'EOF'
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: /
EOF
cat > "$SNAP/rulesets.json" <<'EOF'
[
  {
    "id": 9,
    "name": "pr",
    "bypass_actors": [],
    "rules": [{"type": "pull_request"}]
  }
]
EOF
OUT="$(run_snap "$SNAP")" || fail "rules snapshot rc"
assert_finding "$OUT" "ruleset-no-bypass"
ok "ruleset-no-bypass"

# ---- release / source-pin / terraform gates / bootstrap / orphan ----
SNAP="$WORK/rest"; mkdir -p "$SNAP/workflows" "$SNAP/tf"
write_meta "$SNAP" "Coalfire-CF/rest-repo"
empty_json_files "$SNAP"
printf '%s\n' '{"HCL": 1}' > "$SNAP/languages.json"
cat > "$SNAP/workflows/org-release.yml" <<EOF
jobs:
  release:
    uses: Coalfire-CF/Actions/.github/workflows/org-release.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/workflows/org-dependabot.yml" <<EOF
jobs:
  d:
    uses: Coalfire-CF/Actions/.github/workflows/org-dependabot.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/workflows/org-dependabot-auto-merge.yml" <<EOF
jobs:
  d:
    uses: Coalfire-CF/Actions/.github/workflows/org-dependabot-auto-merge.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/workflows/orphan.yml" <<EOF
jobs:
  d:
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-apply.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/dependabot.yml" <<'EOF'
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: /
EOF
cat > "$SNAP/tf/main.tf" <<'EOF'
module "x" {
  source = "github.com/Coalfire-CF/terraform-aws-vpc?ref=main"
}
EOF
cat > "$SNAP/prs.json" <<'EOF'
[
  {
    "number": 10,
    "title": "chore(bootstrap): baseline",
    "author": {"login": "ci-automerge-app[bot]"},
    "labels": [{"name": "bootstrap/proposed"}],
    "headRefName": "bootstrap/baseline-v0.18.1",
    "files": []
  },
  {
    "number": 11,
    "title": "chore(main): release 1.2.3",
    "author": {"login": "release-please[bot]"},
    "labels": [{"name": "autorelease: pending"}],
    "headRefName": "release-please--branches--main",
    "files": []
  }
]
EOF
OUT="$(run_snap "$SNAP")" || fail "rest snapshot rc"
assert_finding "$OUT" "release-no-tags"
assert_finding "$OUT" "source-pin-fail"
assert_finding "$OUT" "terraform-missing-gates"
assert_finding "$OUT" "bootstrap-pr-open"
assert_finding "$OUT" "release-please-stale"
assert_finding "$OUT" "orphan-caller"
ok "release/source-pin/terraform/bootstrap/orphan"

# ---- source-pin-warn + release-tag-no-github-release + exempt ----
SNAP="$WORK/warns"; mkdir -p "$SNAP/workflows" "$SNAP/tf"
cat > "$SNAP/meta.json" <<'EOF'
{"nameWithOwner":"Coalfire-CF/warn-repo","default_branch":"main","isFork":false,"isArchived":false,"repositoryTopics":[{"name":"bootstrap-exempt"}]}
EOF
empty_json_files "$SNAP"
printf '%s\n' '[{"name":"v1.0.0"}]' > "$SNAP/tags.json"
printf '%s\n' '[]' > "$SNAP/releases.json"
cat > "$SNAP/workflows/org-release.yml" <<EOF
jobs:
  release:
    uses: Coalfire-CF/Actions/.github/workflows/org-release.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/workflows/org-dependabot.yml" <<EOF
jobs:
  d:
    uses: Coalfire-CF/Actions/.github/workflows/org-dependabot.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/workflows/org-dependabot-auto-merge.yml" <<EOF
jobs:
  d:
    uses: Coalfire-CF/Actions/.github/workflows/org-dependabot-auto-merge.yml@${CURRENT_SHA} # v0.18.1
EOF
cat > "$SNAP/dependabot.yml" <<'EOF'
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: /
EOF
cat > "$SNAP/tf/main.tf" <<'EOF'
module "x" {
  source = "github.com/Coalfire-CF/terraform-aws-vpc?ref=v2.2.6" # v2.2.6
}
EOF
OUT="$(run_snap "$SNAP")" || fail "warns snapshot rc"
assert_finding "$OUT" "source-pin-warn"
assert_finding "$OUT" "release-tag-no-github-release"
printf '%s' "$OUT" | jq -e '.exempt == true' >/dev/null || fail "exempt true"
printf '%s' "$OUT" | jq -e '.status == "PASS"' >/dev/null || fail "warn-only PASS: $OUT"
ok "warn-only PASS + exempt"

# ---- unreadable snapshot (missing meta) ----
SNAP="$WORK/bad"; mkdir -p "$SNAP"
OUT="$(run_snap "$SNAP")" || fail "unreadable should rc 0"
printf '%s' "$OUT" | jq -e '.status == "SKIP" and .skip_reason == "unreadable"' >/dev/null \
  || fail "unreadable SKIP: $OUT"
ok "unreadable SKIP"

# ---- report ----
MD="$(printf '%s\n' "$OUT" "$(run_snap "$WORK/lag")" | bash "$REPORT")" || fail "report rc"
printf '%s' "$MD" | grep -q "Actions fleet audit" || fail "report title"
printf '%s' "$MD" | grep -q "pin-lag" || fail "report pin-lag section"
printf '%s' "$MD" | grep -q "Coalfire-CF/lag-repo" || fail "report names repo"
ok "report markdown"

# ---- truncation cuts on a line boundary (MD055: no half-written table row) ----
: > "$WORK/many.ndjson"
i=0
while [ "$i" -lt 60 ]; do
  SNAP="$WORK/bulk"; rm -rf "$SNAP"; mkdir -p "$SNAP/workflows"
  write_meta "$SNAP" "Coalfire-CF/bulk-repo-${i}"
  empty_json_files "$SNAP"
  cat > "$SNAP/workflows/org-release.yml" <<EOF
jobs:
  release:
    uses: Coalfire-CF/Actions/.github/workflows/org-release.yml@${OLD_SHA} # v0.12.1
EOF
  run_snap "$SNAP" >> "$WORK/many.ndjson"
  i=$((i + 1))
done
TRUNC="$(FLEET_AUDIT_MAX_BYTES=2000 bash "$REPORT" < "$WORK/many.ndjson")"
printf '%s' "$TRUNC" | grep -q "truncated" || fail "expected truncation marker"
while IFS= read -r line; do
  case "$line" in
    "|"*) printf '%s' "$line" | grep -qE '\|[[:space:]]*$' || fail "truncated table row: $line" ;;
  esac
done <<< "$TRUNC"
ok "truncation preserves whole table rows"

# ---- live enumerate: mock gh, reject writes ----
BIN="$WORK/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_TRACE:?}"
for a in "$@"; do
  case "$a" in
    --method|PUT|POST|PATCH|-X) echo "MOCK: write rejected" >&2; exit 90 ;;
  esac
done
[ "$1" = "pr" ] && [ "$2" = "create" ] && { echo "MOCK: pr create rejected" >&2; exit 90; }
[ "$1" = "pr" ] && [ "$2" = "merge" ] && { echo "MOCK: pr merge rejected" >&2; exit 90; }
if [ "$1" = "repo" ] && [ "$2" = "list" ]; then
  echo '[{"nameWithOwner":"Coalfire-CF/skip-me","isFork":true,"isArchived":false,"repositoryTopics":[]}]'
  exit 0
fi
exit 0
MOCK
chmod +x "$BIN/gh"
export GH_TRACE="$WORK/gh.trace"
: > "$GH_TRACE"
PATH="$BIN:$PATH" ORG=Coalfire-CF REPO="" bash "$AUDIT" >"$WORK/live.out" 2>"$WORK/live.err" || fail "live enumerate rc"
if grep -qE 'write rejected|pr create|pr merge' "$WORK/live.err"; then
  fail "live path attempted a write"
fi
ok "live enumerate zero writes"

echo "ALL OK"
exit 0
