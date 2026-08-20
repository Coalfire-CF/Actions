# Org Actions fleet audit

Read-only health sweep of `Coalfire-CF` consumer repos: Actions pin lag, Dependabot auto-merge gaps, and release/tag shape. Producer YAML smells are out of scope; see [RESEARCH_workflow-audit-2026-08-11.md](RESEARCH_workflow-audit-2026-08-11.md).

**Decision:** report only. The sweeper never pushes, opens PRs, merges, or labels consumer repos. The only write is the standing issue `Actions fleet audit` on `Coalfire-CF/Actions` (full-org runs) plus the workflow artifact.

Design: [docs/superpowers/specs/2026-08-20-org-actions-fleet-audit-design.md](superpowers/specs/2026-08-20-org-actions-fleet-audit-design.md).

## How it works

1. Resolve the latest `Coalfire-CF/Actions` release tag and commit SHA (RFC-0008 pin).
1. Enumerate non-archived, non-fork org repos. Skip `.github` and `.allstar`. Do **not** skip `Actions` (producer) or `bootstrap-exempt` (still classified, `exempt: true`).
1. Per repo, fetch workflows, `dependabot.yml`, open PRs, tags, releases, repo rulesets, and a capped set of `.tf` files.
1. Classify into NDJSON, then markdown.

Unreadable metadata or contents: `status=SKIP`, `skip_reason=unreadable`. Never a PASS from a failed read.

## Status

| status | Meaning |
| --- | --- |
| `FAIL` | At least one fail-severity finding |
| `PASS` | No fail findings. Warn findings are allowed |
| `SKIP` | Infra filter or unreadable |

## Check catalog

Fail:

- `pin-lag` — SHA or `# vX.Y.Z` older than this run's Actions release
- `pin-bad-ref` — `@main`, branch, or moving major (`@v1`)
- `pin-sha-no-comment` — 40-hex SHA without `# vX.Y.Z`
- `pin-mixed` — more than one Actions SHA or version comment in the repo
- `no-caller` — no `Coalfire-CF/Actions` `uses:` and no `org-release.yml`
- `automerge-missing-caller` — adopted (`org-release.yml` present) but missing `org-dependabot.yml` or `org-dependabot-auto-merge.yml`
- `dependabot-missing-gha` — adopted, `dependabot.yml` has no `github-actions` ecosystem
- `dependabot-unlabeled` — open github-actions Dependabot PR with no `merge/approved|blocked|skipped`
- `automerge-approved-unmerged` — open Dependabot PR labeled `merge/approved` (reconcile / ruleset bypass path)
- `automerge-tf-block-on-actions` — github-actions Dependabot PR labeled `blocked/terraform-no-tests`
- `ruleset-no-bypass` — repo-level `pull_request` ruleset without Integration bypass for App `3436395`
- `source-pin-fail` / `source-pin-warn` — Coalfire-CF Terraform `source` classes, sampled from **root-level** `*.tf` files (not nested modules)
- `release-no-tags` — `org-release.yml` present, zero `v*` git tags
- `release-please-stale` — open `release-please--branches--*` PR
- `terraform-missing-gates` — HCL repo, adopted, missing validate/fmt/docs callers

Warn:

- `pin-bare-tag` — `@vX.Y.Z` with no SHA
- `automerge-blocked` — open Dependabot PR labeled `merge/blocked`
- `source-pin-warn` — Terraform `?ref=vX.Y.Z` tag
- `release-tag-no-github-release` — `v*` tags, no GitHub Release objects
- `bootstrap-pr-open` — open `bootstrap/*` PR
- `orphan-caller` — uses apply/plan/source-pin/version-band reusables (zero-fleet in the 2026-08-11 audit)

`Coalfire-CF/Actions` is `role=producer`. Local `./` refs are not consumer pins. `pin-lag` / `no-caller` do not apply.

## Run locally

Prerequisites: `gh` authenticated with org read, `jq`.

```bash
ACTIONS_VERSION="$(gh release view --repo Coalfire-CF/Actions --json tagName --jq .tagName)"
# Resolve the tag object to a 40-hex commit (annotated tags need a deref).
ACTIONS_SHA="$(git ls-remote --tags https://github.com/Coalfire-CF/Actions.git "refs/tags/${ACTIONS_VERSION}^{}" | awk '{print $1}')"
# Fallback if the peeled ref is missing:
[ -n "$ACTIONS_SHA" ] || ACTIONS_SHA="$(gh api "repos/Coalfire-CF/Actions/git/ref/tags/${ACTIONS_VERSION}" --jq .object.sha)"

export ACTIONS_VERSION ACTIONS_SHA ORG=Coalfire-CF

# Canary
REPO=Coalfire-CF/Actions ./scripts/fleet-audit.sh | ./scripts/fleet-audit-report.sh

# Full org (slow; thousands of API reads)
./scripts/fleet-audit.sh | tee /tmp/fleet-audit.ndjson | ./scripts/fleet-audit-report.sh
```

Snapshot fixtures (no network): `FLEET_AUDIT_SNAPSHOT=dir ./scripts/fleet-audit.sh`. Layout is in the design spec.

Tests: `bash tests/fleet-audit.test.sh`

## CI

[`.github/workflows/org-actions-fleet-audit.yml`](../.github/workflows/org-actions-fleet-audit.yml): weekly Monday 08:47 UTC, plus `workflow_dispatch`. App token (`AUTOMERGE_CLIENT_ID` / `AUTOMERGE_APP_PRIVATE_KEY`) for org reads. `GITHUB_TOKEN` upserts the standing issue on full-org runs only. A `repo=` canary does not overwrite that issue.

## After the report

Triage order:

1. Auto-merge wiring gaps vs stuck `merge/approved` (repo ruleset bypass).
1. Pin lag with an open Dependabot PR (land via existing auto-merge / reconcile).
1. Pin lag with no Dependabot PR (`dependabot.yml` / grouping).
1. Stale release-please PRs (tags never cut).
1. `@main` / bare-tag callers.
