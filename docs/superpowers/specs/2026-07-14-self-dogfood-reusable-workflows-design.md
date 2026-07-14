# Design: Dogfood the org reusable workflows on the Actions repo itself

**Date:** 2026-07-14
**Status:** Approved (design), pending implementation plan
**Author:** Douglas Francis (with Claude Code)

## Problem

`Coalfire-CF/Actions` publishes ~24 reusable (`workflow_call`) workflows that the
rest of the fleet consumes, but it does not run all of the applicable ones on
**itself**. This surfaced when Dependabot PR
[#192](https://github.com/Coalfire-CF/Actions/pull/192) received no auto-merge
evaluation and no Bedrock changelog comment: the `org-dependabot-auto-merge.yml`
reusable workflow has no self-caller in this repo, so the per-PR half of the
Dependabot pipeline never runs here — even though the scheduled
`org-dependabot-reconcile.yml` sweeper (which assumes that per-PR workflow ran)
runs on cron.

The goal: the Actions repo should exercise the same tooling it ships, wherever
that tooling genuinely applies to a composite-actions + reusable-workflows +
scripts repo (i.e. one with **no production Terraform**).

## Scope decision

"Everything applicable" — wire up every reusable workflow that has real work to
do on this repo, and explicitly exclude the ones that would be no-ops, noise, or
a regression. The full accounting is in the Gap Analysis below.

## Gap analysis (all published reusable workflows)

### Already dogfooding — no work

| Workflow | How it self-triggers |
|---|---|
| `test-scripts.yml` | `pull_request` |
| `org-markdown-lint.yml` | baked-in `pull_request` (paths `**.md`) |
| `org-terraform-fmt.yml` | baked-in `pull_request` |
| `org-terraform-source-pin.yml` | baked-in `pull_request` (incl. the `uses:` pin job, highly relevant here) |
| `org-terraform-version-check.yml` | `schedule` |
| `org-dependabot-reconcile.yml` | `schedule` (every 6h) + `workflow_dispatch` |
| `release.yml` (Local Release) | `pull_request` closed→main; gates on gitleaks(full-history) + trivy(fs) + actionlint + release-please |

### ADD a self-caller (applicable, currently dormant)

| # | New caller file | Trigger | Calls | Rationale |
|---|---|---|---|---|
| 1 | `dependabot-auto-merge.yml` | `pull_request_target` [opened, synchronize, reopened], `if dependabot[bot]` | `./.github/workflows/org-dependabot-auto-merge.yml` | The #192 gap. Completes the per-PR producer the reconcile sweeper already assumes. |
| 2 | `label-sync.yml` | `schedule` weekly + `workflow_dispatch` | `./.github/workflows/org-label-sync.yml` | Prerequisite for #1 — creates the `merge/*`, `dep/*`, `check/*`, `ai/*`, `risk/*`, `blocked/*` label taxonomy auto-merge writes. |
| 3 | `tree-readme.yml` | `pull_request` branches [main] | `./.github/workflows/org-tree-readme.yml` | `.github/readmetreerc.yml` already present; workflow under active development yet never exercised on the repo's own PRs. |

### Deferred (applicable but low-value / higher-friction)

- **`dependabot-config-refresh.yml`** (`org-dependabot.yml`) — regenerates
  `.github/dependabot.yml`. Deferred: this repo's ecosystem set changes rarely,
  and a `pull_request`-triggered commit would race `tree-readme`'s commits on the
  same human PRs. Revisit later, path-scoped, if desired.

### Skip — not applicable / would be a regression

| Workflow | Reason to skip |
|---|---|
| `org-trivy-pr.yml` | Scans changed `*.tf` only; repo has none but source-pin test fixtures → no-op. `self-scan-trivy` in `release.yml` already covers fs+vuln+secret as a **blocking** gate. |
| `org-trivy-exception-review.yml` | No `.trivyignore.yaml` exists → pure no-op. |
| `org-terraform-docs.yml` | No real modules with a README to inject → no-op / churn. |
| `org-terraform-version-band.yml` | No real `required_version` constraints → no-op or fixture noise. |
| `org-opa.yml` | No `.rego` policies; `org-opa-policies` not landed; no production Terraform → self-skips. |
| `org-release.yml` (migration) | Keep `release.yml`. It runs scans as **blocking pre-gates**; `org-release.yml` runs them post-release/report-only and adds cosign tarballs a SHA-consumed repo does not need. Migrating would be a **security downgrade**. |

### Borderline — creds exist, deliberately not wired (opt-in later)

- **`org-gitleaks-pr.yml`** — would add earlier secret-scan feedback on *open* PRs,
  but is PR-diff-only vs the stronger full-history blocking gate already in
  `release.yml`. Complementary, mildly redundant. Not added.
- **`org-jira-sync.yml`** — `JIRA_*` secrets exist org-wide, so it *could* mirror
  this repo's issues into the org Jira project, but that pushes Actions-repo
  issues into a shared tracker. Judgment call; not added.

## The three new files

### `.github/workflows/dependabot-auto-merge.yml`
```yaml
name: Dependabot Auto-Merge
on:
  pull_request_target:
    types: [opened, synchronize, reopened]
jobs:
  auto-merge:
    if: github.event.pull_request.user.login == 'dependabot[bot]'
    uses: ./.github/workflows/org-dependabot-auto-merge.yml
    secrets: inherit
```
`pull_request_target` (per the reusable workflow's header) so it gets write access
plus the org secrets on Dependabot PRs. The reusable workflow owns its own per-PR
`concurrency` group and re-applies the `dependabot[bot]` guard internally, so the
caller stays minimal. All reusable-workflow inputs are optional; defaults are
correct for this repo.

### `.github/workflows/label-sync.yml`
```yaml
name: Sync Auto-Merge Labels
on:
  schedule:
    - cron: '0 6 * * 1'   # Mondays 06:00 UTC
  workflow_dispatch:
jobs:
  sync-labels:
    uses: ./.github/workflows/org-label-sync.yml
    secrets: inherit
```
No required inputs/secrets. Run once via `workflow_dispatch` at rollout so the
label taxonomy exists before the first auto-merge evaluation.

### `.github/workflows/tree-readme.yml`
```yaml
name: README Tree
on:
  pull_request:
    branches: [main]
jobs:
  tree-readme:
    uses: ./.github/workflows/org-tree-readme.yml
    secrets: inherit
```
Idempotent: no-op commit when the tree is unchanged. On Dependabot PRs it is
push-suppressed by design (read-only token → warn only), so it does not collide
with the auto-merge caller.

## Conventions & constraints

- **Local `./` path form, not `@main`.** `test-scripts.yml` (the N2 regression
  lint) fails any internal sibling call that uses `@main`; self-callers must use
  `uses: ./.github/workflows/<name>.yml`. Consumer-repo callers (in docs) keep the
  pinned `@<sha>` form — that rule is for external consumers, not in-repo callers.
- **`secrets: inherit`** on every caller so org-level `AUTOMERGE_*` and
  `SLACK_BOT_TOKEN` (all `ALL` visibility) forward into the reusable workflow.

## Prerequisites (status: all met)

- `AUTOMERGE_CLIENT_ID`, `AUTOMERGE_APP_PRIVATE_KEY`,
  `AUTOMERGE_DEPENDABOT_ROLE_ARN` — present as org secrets (`ALL` visibility);
  the reconcile sweeper already uses the App successfully every 6h, so the
  GitHub App + OIDC/S3/Bedrock role are proven working.
- Labels — created by the new `label-sync` job (dispatch once at rollout).
- `.github/readmetreerc.yml` — already present.

## Risks & interactions

- **auto-merge × tree-readme on Dependabot PRs:** auto-merge runs via
  `pull_request_target`; tree-readme runs via `pull_request` but is push-suppressed
  for the `dependabot[bot]` actor → no commit, no collision.
- **auto-merge does not run on human PRs** (guarded to `dependabot[bot]`), so it
  never competes with tree-readme's commits there.
- **reconcile sweeper** is unchanged and now has the per-PR producer it assumed;
  no behavioral change to it.
- **Terraform module/provider bumps** are still labeled `blocked/*` for manual
  review by the reusable auto-merge logic (no unit-test infra), so no Terraform
  change auto-merges unexpectedly.

## Success criteria

1. A new Dependabot PR receives the `Dependabot Auto-Merge` check and (for an
   eligible non-Terraform bump) the classification labels + Bedrock changelog
   evaluation, and either auto-merges or is labeled for review.
2. `label-sync` `workflow_dispatch` run creates/updates the full label taxonomy.
3. A PR that changes the repo tree gets a `## Tree` README update committed by
   `tree-readme` (or a clean no-op when unchanged).
4. All three new workflow files pass the repo's own `test-scripts.yml` lint
   (actionlint + N2 no-mutable-main-refs guard).
