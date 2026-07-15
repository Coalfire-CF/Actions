# Codebase Analysis — Coalfire-CF/Actions

**Date:** 2026-07-08
**Scope:** 27 reusable workflows (`.github/workflows/`), 13 shell scripts (`scripts/`), the composite gitleaks action (`actions/gitleaks/`), configs (`dependabot.yml`, `readmetreerc.yml`, `gate-config.yml`, `renovate/`, `release-please-config.json`), the test harness (`tests/`), and docs.
**Method:** Full read of every file in scope, followed by direct source verification of every High/Medium finding (cache-write paths, injection site, validate/fmt gate behavior).

---

## 1. Executive Summary

The security posture of this repository is genuinely strong and, in several areas, exemplary. The README's headline claims hold up under scrutiny: every third-party action is SHA-pinned (enforced in CI by a dedicated `no-main-refs` guard job), `${{ }}` expressions are almost always routed through `env:` blocks rather than interpolated into `run:` scripts, external tool downloads (OPA, yq, actionlint) are checksum-verified, and the shell test suite is unusually rigorous — full of fail-closed characterization tests.

The real risk is concentrated in two places:

1. **The Dependabot auto-merge pipeline's shared S3 cache.** The two scripts that gate auto-merge (`supply-chain-check.sh`, `breaking-change-check.sh`) are also the *only* two scripts in the repo with zero test coverage — and both can write an optimistically-clean verdict into the fleet-wide cache on a transient outage. A subsequent run for the same dependency, in any repo, can then auto-approve on that poisoned entry. This is the single highest-impact class of defect found.

1. **Two Terraform PR gates that silently do nothing.** `org-terraform-validate.yml` reports green even when `terraform validate` fails, and `org-terraform-fmt.yml` neither fails on nor fixes misformatted code. Both look like enforcement but enforce nothing.

The remaining findings are hardening and hygiene items. No committed secret, no deprecated `set-output`, and no untrusted-code-with-secrets checkout was found.

**Counts:** 4 High · 8 Medium · 19 Low · 2 zero-coverage scripts.

---

## 2. Methodology & Severity Definitions

- **High** — silently ships wrong/unvetted results to production (auto-merge, release, or a security gate) or enables code execution.
- **Medium** — breaks under realistic-but-non-default conditions (transient API failure, grouped PR, malformed input, non-PR trigger), or a gate that fails to enforce its stated purpose.
- **Low** — hygiene, portability, cosmetic, doc drift, or a latent hazard that requires an unlikely precondition.

Every High and Medium finding below was confirmed by reading the cited lines directly.

---

## 3. Findings

### High

#### H1 — Shared-cache self-poisoning on transient errors

**Files:** `scripts/supply-chain-check.sh:133-141,197-218` · `scripts/breaking-change-check.sh:278-287,342-367`

On an OSV or Bedrock API failure, both scripts correctly fail *closed for the current run* — they increment `CHECK_ERRORS`, which routes the PR to manual review. But the error-path fallback sets an optimistic verdict, and the cache write that follows is **unconditional**:

```bash
# supply-chain-check.sh — OSV failure path
echo "::warning::OSV query FAILED for ${DEP_NAME}@${TO_VERSION} — failing closed"
CHECK_ERRORS=$((CHECK_ERRORS + 1))
OSV_RESPONSE='{"vulns":[]}'          # -> OSV_CLEAR stays "true"
...
# later, always runs:
jq -n ... 'osv: { clear: $osv_clear, vulns: $osv_vulns } ...' > /tmp/supply_chain_result.json
aws s3 cp /tmp/supply_chain_result.json "s3://${S3_BUCKET}/${CACHE_KEY}" ...
```

The written object carries a valid `schema_version` and `producer`, so the read-side validation (`cache_schema_ok`) accepts it. The next run for that same `dep@version` — in **any** repo in the fleet, for the full `cache_ttl_days` window (default 30) — gets a cache hit with `clear=true` / `breaking=false` and `check_errors=0`, and can auto-approve.

**Failure scenario:** A brief OSV.dev outage during the first analysis of `some-dep@1.2.3` writes `osv.clear=true` to the cache. An hour later, another repo bumps the same dependency, hits the cache, and auto-merges an unscanned dependency.

**Resolution:** Skip the cache write when `CHECK_ERRORS > 0` for that dependency, or persist an explicit `errored: true` marker and reject errored entries on read. The documented S3 bucket-policy control addresses only *external* writers and does not cover this self-inflicted write.

#### H2 — Stale temp file contaminates the next dependency's cache object in grouped PRs

**File:** `scripts/breaking-change-check.sh:100,336-341`

The shared-cache download and the later merge-write are decoupled:

```bash
CACHED=$(aws s3 cp "s3://.../${SHARED_CACHE_KEY}" /tmp/cached_analysis.json 2>/dev/null && echo "ok" || echo "miss")
...
if [ -f /tmp/cached_analysis.json ]; then      # file-existence, not CACHED=ok
  EXISTING=$(cat /tmp/cached_analysis.json)
else
  EXISTING='{}'
fi
echo "$EXISTING" | jq '. + { ... }' > /tmp/merged_analysis.json   # -> this dep's key
```

On a cache **miss**, `aws s3 cp` fails and leaves the file from the *previous loop iteration* in place. The write path keys off `[ -f ... ]` only, so dependency N's freshly-written object inherits dependency N-1's fields (`osv`, `scorecard`, `vulns`) that this script's `. + {…}` merge does not overwrite.

**Failure scenario:** A grouped Dependabot PR where dep #1 hits the shared cache and dep #2 misses → dep #2's new S3 object carries dep #1's supply-chain/vuln verdict, poisoning the entry that gates future merges of dep #2.

**Resolution:** `rm -f /tmp/cached_analysis.json` at the top of `check_one`, or gate the `EXISTING` read on `[ "$CACHED" = "ok" ]`. (`supply-chain-check.sh` avoids this by gating reads on `CACHED=ok` and writing with `jq -n`.)

#### H3 — Script injection into `github-script` from repository file content

**File:** `.github/workflows/org-trivy-exception-review.yml:116-118`

```js
const expiredList = `${{ steps.check_expired.outputs.expired_list }}`;
const expiringSoonList = `${{ steps.check_expired.outputs.expiring_soon_list }}`;
const hasExpiringSoon = '${{ steps.check_expired.outputs.has_expiring_soon }}' === 'true';
```

`expired_list` / `expiring_soon_list` are built from the `statement` field of `.trivyignore.yaml` — repo-file content — and interpolated directly into a JS template literal via `${{ }}`. The job token holds `issues: write`. A `statement` containing a backtick or `${…}` breaks out of the literal and executes arbitrary JS in the runner; even a benign backtick corrupts the script and breaks the step.

**Failure scenario:** A contributor adds a Trivy exception whose statement is `` malicious`;require('child_process').execSync('...');// `` → arbitrary code runs on the runner with an issue-writable token.

**Resolution:** Pass the outputs via `env:` and read `process.env.*`. The workflow's own "Generate summary" step (lines 179-183) already does exactly this — the `github-script` step is the inconsistent one.

#### H4 — `org-terraform-validate.yml` can never fail

**File:** `.github/workflows/org-terraform-validate.yml:108-117`

```bash
set +e
OUTPUT=$(terraform validate)
CLEAN_OUTPUT=$(echo "$OUTPUT" | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g")
echo "$CLEAN_OUTPUT"
echo "$CLEAN_OUTPUT" > "$GITHUB_WORKSPACE/validate_output.txt"
set -e
# continue-on-error: true
```

Three compounding problems: (1) `terraform validate` writes diagnostics to **stderr**, but `$( )` captures only stdout, so `validate_output.txt` and the PR comment are empty on a real failure; (2) the exit code is discarded into the `$( )` substitution; (3) `continue-on-error: true` is set and no later step re-checks the result. The "Validate Terraform" gate is therefore green on invalid Terraform.

**Failure scenario:** A PR introduces a Terraform syntax error. The gate passes, the empty PR comment says nothing, and the error reaches merge.

**Resolution:** `OUTPUT=$(terraform validate 2>&1); RC=$?`, write the output, then `exit $RC` (or a dedicated fail step). `org-terraform-plan.yml:260-262` already uses this explicit-fail pattern.

---

### Medium

#### M1 — `org-terraform-fmt.yml` is a no-op

**File:** `.github/workflows/org-terraform-fmt.yml:79-86`

```bash
- name: Run Terraform fmt
  run: terraform fmt -recursive              # rewrites in place, always exits 0
- name: Commit changes
  run: |
    git diff --quiet && git diff --staged --quiet || (git add -A && git commit -m "Apply terraform fmt")
```

`terraform fmt -recursive` (no `-check`) reformats and exits 0, so the job never fails on misformatted code. The commit is made locally and **never pushed**, so it is discarded when the runner is torn down. The "Post comment on failure" step can never fire for formatting issues. The job named "Check Terraform Formatting" neither checks nor fixes.

**Resolution:** Use `terraform fmt -check -recursive -diff` to fail on drift, or add a `git push` of the fix commit.

#### M2 — `--argjson conf` crashes the job on non-numeric model confidence

**File:** `scripts/breaking-change-check.sh:311-317,353`

`ai_verdict_has_boolean_breaking` validates only the `breaking` field. `CONFIDENCE=$(echo "$AI_TEXT" | jq -r '.confidence // 0')` then feeds `--argjson conf "$CONFIDENCE"`. A model response of `{"breaking":true,"confidence":"high"}` (or `"confidence":""`, where `// 0` does not fire) yields a non-numeric value → `--argjson conf high` is invalid JSON → jq exits non-zero → under `set -e` in the unguarded `check_one`, the whole job aborts.

**Failure scenario:** Release notes are attacker-influenceable and are spliced into the Bedrock prompt; a prompt-injection that makes the model emit a non-numeric confidence hard-crashes the breaking-change gate. (The aggregate compare at line 460 is guarded with `2>/dev/null || echo 0`; line 353 is not.)

**Resolution:** Numeric-validate `CONFIDENCE` (e.g. regex `^[0-9]+(\.[0-9]+)?$`) and default to `0` otherwise.

#### M3 — Non-numeric Scorecard score crashes the supply-chain gate

**File:** `scripts/supply-chain-check.sh:180-182`

```bash
SCORECARD_SCORE=$(echo "$SCORECARD_RESPONSE" | jq -r '.score // 0')
if [ "$(echo "$SCORECARD_SCORE < $SCORECARD_THRESHOLD" | bc -l)" -eq 1 ]; then
```

A 2xx response with a non-JSON body (proxy/HTML error page) or a non-numeric `.score` leaves `SCORECARD_SCORE` empty; `bc` then errors, its output is empty, and `[ "" -eq 1 ]` raises an integer-expression error → `set -e` aborts the unguarded `check_one`. Same latent risk at line 228.

**Resolution:** Validate `SCORECARD_SCORE` is numeric before the `bc` comparison; default to a failing score on garbage.

#### M4 — Unguarded `jq` on cache files before schema validation

**Files:** `scripts/breaking-change-check.sh:102-104,133` · `scripts/supply-chain-check.sh:84`

```bash
BC_EXISTS=$(jq -r '.changelog // empty' /tmp/cached_analysis.json)   # no 2>/dev/null, before cache_schema_ok
```

These parse the just-downloaded S3 object with no error guard and *before* schema validation runs. A corrupt / non-JSON cached object makes `jq` exit non-zero; under `set -e` in the unguarded `check_one`, the job aborts instead of treating it as a miss and re-analyzing — defeating the fail-safe intent `cache-lib.sh` was written for.

**Resolution:** Add `2>/dev/null || true` to the pre-validation reads, or validate the object parses before reading fields.

#### M5 — `pr-green-merge.sh` merge is not compare-and-swap (TOCTOU)

**File:** `scripts/pr-green-merge.sh:138-157`

The script classifies `statusCheckRollup` and then merges the current head with no re-verification and no `--match-head-commit`:

```bash
gh pr merge "$PR_NUMBER" "--${MERGE_METHOD}" --repo "$REPO"
```

A commit pushed (or a check turning red) between the read and the merge results in merging unreviewed/failing code.

**Resolution:** Snapshot the head SHA at classification time and pass `gh pr merge --match-head-commit "$SHA"`. `release-patch-merge.sh` already does exactly this.

#### M6 — `release-patch-merge.sh` comment lookup is unpaginated

**File:** `scripts/release-patch-merge.sh:97-103`

```bash
gh_read api "repos/${REPO}/issues/${PR_NUMBER}/comments" --jq "map(select(.body|contains(...)))|last|.id"
```

No `--paginate` / `per_page`, so only the first page (default 30) of comments is searched. On a PR with more than 30 comments the existing marker comment is never found, so `upsert_comment` POSTs a new comment on every run instead of editing — the upsert degrades to append.

**Resolution:** Add `--paginate` (and search all pages for the marker).

#### M7 — `dependabot.yml` omits the `npm` ecosystem

**File:** `.github/dependabot.yml:5-22`

The file declares only `package-ecosystem: "github-actions"`, but the repo ships `package.json` (devDependency `markdownlint-cli2`) and `package-lock.json`. The generator this file claims to dogfood explicitly maps npm (`org-dependabot.yml:120` → `[npm]="package.json"`), so the committed config is out of sync with what the workflow would emit for this very repo.

**Failure scenario:** Future advisories against the pinned markdownlint-cli2 tree open no automatic bump PRs; the documented "dependency pinning with integrity checks" posture silently rots.

**Resolution:** Add an `npm` block (or regenerate via `org-dependabot.yml` and commit the result).

#### M8 — Version-bump PRs are opened with `GITHUB_TOKEN` and get no CI

**File:** `.github/workflows/org-terraform-version-check.yml:94-115`

The auto-generated Terraform-version bump PR is created with `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}`. By GitHub's anti-recursion rule, PRs opened by `GITHUB_TOKEN` do not trigger `on: pull_request` workflows, so the bump PR gets no validate/plan/fmt runs — defeating the review checklist it embeds. This workflow has no `concurrency:` group either, so a `workflow_dispatch` can overlap the monthly cron run. The release path documents this exact rationale for preferring an App token (`org-release.yml:123-131`: "a GITHUB_TOKEN merge fires no push event and the publish run never runs").

**Resolution:** Open the PR with a GitHub App token (as `org-release.yml` does) and add a `concurrency` group.

---

### Low

| ID | File:line | Issue | Resolution |
|----|-----------|-------|------------|
| L1 | `auto-merge-decide.sh:59,91` | `blocked/major-bump` label appended twice when both `UPDATE_TYPE_META=*semver-major*` and `SEMVER_TYPE=major`; test characterizes it verbatim | Append once; dedupe `BLOCKED_LABELS` |
| L2 | `.github/readmetreerc.yml:4-5` | Quoted `include:` values (`- "."`) are never unquoted by the parser in `org-tree-readme.yml:104-114`; works today only because the `.` fallback fires. A quoted non-root include would be silently skipped | Strip surrounding quotes in the parser, or drop quotes in the config |
| L3 | `version-band-check.sh:111-121` | Ceiling-only constraint (`< 2.0.0`, no floor) anchors at the ceiling and is reported out-of-band | Detect upper-bound-only constraints and anchor differently |
| L4 | `actions/gitleaks/action.yml:114-116` | `passed` / `finding-count` outputs unset on the scanner-error branch → downstream `outputs.passed == 'false'` won't fire | Set both outputs on every exit path |
| L5 | `actions/gitleaks/action.yml:62` | Installs to `/usr/local/bin` without `sudo`; fails on hardened/self-hosted runners (inconsistent with `test-scripts.yml:90` which uses `sudo`) | Use `sudo`, or a writable per-runner path |
| L6 | `pr-green-merge.sh:116`, `release-patch-merge.sh:160,167` | `for a in $AUTHOR_ALLOWLIST` unquoted; `dependabot[bot]` is a valid glob (`[bot]` char class) and can be corrupted by a matching filename in cwd | `set -f` around the loop, or use a quoted array |
| L7 | `release-patch-merge.sh:243` | `gh pr checks --watch` has no timeout; a stuck check hangs until the workflow-level timeout | Add `--timeout` or a wrapping timeout |
| L8 | `release-patch-merge.sh:68` (`_gh_once`) | Every gh failure classified transient, so permanent 404s are retried `RETRY_MAX` times | Distinguish 4xx (non-retryable) from 5xx/timeout |
| L9 | `org-release.yml:348` | `notify-failure` `needs:` omits `auto-merge-patch` and `notify-release`, so `failure()` won't alert on those jobs | Add both to `needs:` |
| L10 | `org-markdown-lint.yml:109-111` | `if: failure()` comment step has no event guard; on a non-PR trigger `context.issue.number` is undefined and `createComment` throws | Guard with `github.event_name == 'pull_request'` |
| L11 | `org-opa.yml:107` | `inputs.policy_repo` interpolated inline into `run:` (caller-controlled, not event) while `POLICY_REF` is correctly via `env:` | Route `policy_repo` through `env:` too |
| L12 | `org-terraform-apply.yml:252-254`, `org-terraform-plan.yml:239-241` | Unquoted `$INIT_ARGS` / `$PLAN_ARGS` rely on word-splitting; a `backend_config` with spaces splits wrong | Use bash arrays |
| L13 | `org-gitleaks-pr.yml:53`, `org-trivy-pr.yml:74`, `org-terraform-plan.yml:282` | `${{ }}` interpolated into `github-script` JS (controlled true/false/int values — anti-pattern, low exploitability) | Move to `env:` + `process.env.*` for consistency |
| L14 | `docs/ORG_DEPENDABOT_AUTO_MERGE.md:275` vs `auto-merge-decide.sh:110-111` | Docs say approved patch/minor → `risk/low`, but an approved minor bump is labeled `risk/medium` | Reconcile doc with code |
| L15 | `README.md:93,107,117,137`; `docs/ORG_DEPENDABOT_AUTO_MERGE.md:192,211,…` | Copy-paste examples pin `# v0.10.0` while repo is `0.11.3`; new adopters onboard two minor releases behind | Auto-update via release-please `extra-files`, or note the drift |
| L16 | `org-dependabot.yml:47`, `org-terraform-fmt.yml:35` | `pull-requests: write` (dependabot) / `contents: write` (fmt) granted but unused | Drop the unused grants |
| L17 | `breaking-change-check.sh:289-291`; `org-jira-sync.yml:98-101`; `org-dependabot-auto-merge.yml:170,211` | Dead code: `bedrock_err.log` surfacing (nothing writes it now), an overwritten `ISSUE_BODY` heredoc with a wrong var name, and unused `PR_TITLE` env | Remove |
| L18 | `renovate/terraform-ref-pins.json5:21` | Deprecated `fileMatch` key (now `managerFilePatterns`; still honored with a warning) | Rename |
| L19 | `breaking-change-check.sh:248,493` | Byte-based `head -c` truncation can cut mid-UTF-8; jq tolerates it (cosmetic) | Truncate on char boundaries if it matters |

---

## 4. Test-Coverage Gaps

Two committed scripts have **zero** dedicated test files — and they are the two largest and highest-blast-radius scripts, both gating Dependabot auto-merge:

- `scripts/supply-chain-check.sh` (258 lines) — OSV + Scorecard gate.
- `scripts/breaking-change-check.sh` (494 lines) — semver + Bedrock changelog gate.

Every other script is covered (`auto-merge-decide`, `cache-lib`, `gate-config-resolve`, `prompt-lib`, `pr-green-merge` via `reconcile-sweeper`, `release-patch-merge`, `retry-lib`, `source-pin-check`, `stagger-slot`, `uses-pin-check`, `version-band-check`).

Findings **H1, H2, M2, M3, M4 all live in these two untested scripts.** Recommend adding tests with mocked `aws`/`curl` that assert: (a) no optimistic cache write occurs when `CHECK_ERRORS > 0`; (b) a grouped multi-dep run does not carry fields across dependencies on a mid-loop cache miss; (c) non-numeric confidence/score inputs fail closed instead of crashing.

---

## 5. Verified Clean

Checked and confirmed as *not* defects (documented so they aren't re-litigated):

- **SHA-pinning of third-party actions is 100%** — the README claim is true and is enforced in CI by the `no-main-refs` guard job (`test-scripts.yml:101-133`). The only non-SHA `uses:` are local sibling/composite calls and commented examples.
- **No deprecated `set-output` / `save-state` / `set-env`** anywhere.
- **The `pull_request_target` auto-merge flow never checks out untrusted PR head** — it classifies against the base default branch and passes all event fields via `env:`. No secret-exposure-to-untrusted-code foot-gun.
- **External tool downloads are checksum-verified** — OPA, yq, actionlint all download-then-verify against pinned SHA-256 sums.
- **Auto-commit workflows cannot self-retrigger** — they push with the default `GITHUB_TOKEN`, which by design does not trigger further workflow runs; concurrency groups are present.
- **`org-slack-notify.yml` / `org-jira-sync.yml`** build all payloads via `jq --arg` / `env:` and use `permissions: {}` — injection-safe.
- **`retry-lib.sh`, the `cache-lib.sh` read side, `prompt-lib.sh` fencing, `gate-config-resolve.sh`, the Renovate preset, and the release-please config** are all sound (individually verified).

---

## 6. Prioritized Remediation Roadmap

1. **H1 + H2** — stop the auto-merge scripts from writing optimistic/contaminated verdicts to the shared cache. Highest blast radius; fleet-wide and silent.
1. **H3** — close the `github-script` injection in `org-trivy-exception-review.yml` (mechanical `env:` fix).
1. **H4 + M1** — make the Terraform validate and fmt gates actually enforce.
1. **M2–M4** — harden the `set -e` crash paths (non-numeric confidence/score, corrupt cache object) so failures route to manual review instead of aborting the job.
1. **Add tests for the two zero-coverage scripts** (§4), locking in the H1/H2/M2–M4 fixes.
1. **M5–M8** — TOCTOU merge, comment pagination, npm ecosystem, version-check PR token.
1. **Low table (§3)** — sweep opportunistically; L1, L2, L4, L9, L10 are the highest-value hygiene items.
