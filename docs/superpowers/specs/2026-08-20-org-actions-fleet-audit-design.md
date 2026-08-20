# Org Actions fleet audit — design spec (2026-08-20)

**Status:** implemented 2026-08-20 · first live snapshot [docs/RESEARCH_actions-fleet-audit-2026-08-20.md](../../RESEARCH_actions-fleet-audit-2026-08-20.md) · **Runbook:** [docs/ORG_ACTIONS_FLEET_AUDIT.md](../../ORG_ACTIONS_FLEET_AUDIT.md)

## Problem

Consumer repos in `Coalfire-CF` lag the Actions release, miss Dependabot auto-merge wiring, or never cut `v*` tags. The 2026-08-11 workflow audit scored producer YAML. This sweep scores fleet health.

## Shape

Read-only sweeper: `scripts/fleet-audit.sh` (enumerate + classify) + `scripts/fleet-audit-report.sh` (NDJSON to markdown) + `.github/workflows/org-actions-fleet-audit.yml` (weekly + dispatch).

**Decision:** report only. No consumer pushes, PRs, merges, or label changes. The only write is a standing issue on `Coalfire-CF/Actions` plus the workflow artifact.

**Decision:** `bootstrap-exempt` repos are still classified. They get `exempt: true`. Lag stays visible.

**Decision:** `Coalfire-CF/Actions` is `role=producer`. Local `./` workflow refs are not consumer pins. Pin-lag / no-caller do not apply. Other checks still run.

## Check catalog

| id | severity | When |
|---|---|---|
| `pin-lag` | fail | A `Coalfire-CF/Actions/.github/workflows/*.yml@<sha> # vX.Y.Z` pin is older than the run's `ACTIONS_SHA` / `ACTIONS_VERSION` |
| `pin-bad-ref` | fail | Pin ref is `@main`, a branch, or a moving major (`@v1`) |
| `pin-bare-tag` | warn | Pin is `@vX.Y.Z` with no 40-hex SHA (RFC-0008 transitional) |
| `pin-sha-no-comment` | fail | 40-hex SHA with no `# vX[.Y[.Z]]` comment |
| `pin-mixed` | fail | Two or more distinct Actions SHAs or version comments in one repo |
| `no-caller` | fail | No `Coalfire-CF/Actions` workflow `uses:` and no `.github/workflows/org-release.yml` (bootstrap gap) |
| `automerge-missing-caller` | fail | Missing `org-dependabot.yml` or `org-dependabot-auto-merge.yml` under `.github/workflows/` (after adoption: has `org-release.yml`) |
| `dependabot-missing-gha` | fail | Adopted, but `.github/dependabot.yml` missing `package-ecosystem: github-actions` |
| `dependabot-unlabeled` | fail | Open `dependabot[bot]` PR that touches workflows / github-actions and has none of `merge/approved`, `merge/blocked`, `merge/skipped` |
| `automerge-approved-unmerged` | fail | Open Dependabot PR labeled `merge/approved` (reconcile/ruleset path) |
| `automerge-blocked` | warn | Open Dependabot PR labeled `merge/blocked` (reason labels in `detail`) |
| `automerge-tf-block-on-actions` | fail | Open github-actions Dependabot PR labeled `blocked/terraform-no-tests` |
| `ruleset-no-bypass` | fail | Repo-level ruleset with a `pull_request` rule and no Integration bypass for `AUTOMERGE_APP_ID` (default `3436395`) |
| `source-pin-fail` | fail | Coalfire-CF Terraform `source` FAIL-class on root-level `*.tf` (same rules as `source-pin-check.sh`) |
| `source-pin-warn` | warn | Coalfire-CF Terraform `source` WARN-class (tag `?ref=`) |
| `release-no-tags` | fail | Has `org-release.yml` caller and zero `v*` git tags |
| `release-tag-no-github-release` | warn | `v*` tags exist but no GitHub Release objects |
| `release-please-stale` | fail | Open PR whose head branch matches `release-please--branches--*` |
| `terraform-missing-gates` | fail | Languages include HCL, adopted, missing caller files `org-terraform-validate.yml` / `org-terraform-fmt.yml` / `org-terraform-docs.yml` |
| `bootstrap-pr-open` | warn | Open PR on `bootstrap/*` or labeled `bootstrap/proposed` |
| `orphan-caller` | warn | `uses:` of `org-terraform-apply.yml`, `org-terraform-plan.yml`, `org-terraform-source-pin.yml`, or `org-terraform-version-band.yml` |

Unreadable metadata or contents: repo `status=SKIP`, `skip_reason=unreadable`. Never emit PASS from a failed read.

Infra skip (enumerate filter, same as bootstrap): `Actions` is not skipped (producer). Skip `.github`, `.allstar`, archived, forks.

## Per-repo JSON (NDJSON, one object per line)

```json
{
  "repo": "Coalfire-CF/example",
  "role": "consumer",
  "exempt": false,
  "status": "FAIL",
  "skip_reason": "",
  "is_terraform": true,
  "has_org_release": true,
  "pins": [
    {
      "file": ".github/workflows/org-release.yml",
      "workflow": "org-release.yml",
      "ref": "abc...",
      "version": "v0.12.1",
      "shape": "sha-comment"
    }
  ],
  "findings": [
    { "id": "pin-lag", "severity": "fail", "detail": "v0.12.1 vs v0.18.1" }
  ]
}
```

`status`: `SKIP` (unreadable/infra) · `FAIL` (any fail finding) · `PASS` (no fail findings; warn findings allowed).

Pin `shape`: `sha-comment` · `sha-no-comment` · `bare-tag` · `bad-ref` · `local`.

## Report + standing issue

`fleet-audit-report.sh` reads NDJSON on stdin. Writes markdown: current pin, counts, then one table per check id that fired.

Standing issue title (exact): `Actions fleet audit`

Upsert: search open issues with that title on `Coalfire-CF/Actions`; edit body if found, else create. Body is the report markdown, truncated to 60_000 characters with a pointer to the artifact if truncated.

## Snapshot mode (tests)

`FLEET_AUDIT_SNAPSHOT=<dir>` skips `gh`. Directory layout:

```
<meta.json>           # nameWithOwner, default_branch, repositoryTopics, isFork, isArchived
<languages.json>      # GitHub languages API object
<workflows/*.yml>
<dependabot.yml>      # optional, maps to .github/dependabot.yml
<prs.json>            # gh pr list --json number,title,author,labels,headRefName,files
<tags.json>           # array of {name}
<releases.json>       # array of {tagName}
<rulesets.json>       # repo rulesets array
<tf/*.tf>             # optional Terraform sources
```

## Env

| Var | Default | Meaning |
|---|---|---|
| `ORG` | `Coalfire-CF` | GitHub org |
| `REPO` | empty | Single `owner/name` canary |
| `ACTIONS_SHA` | required (live) | Current Actions release commit |
| `ACTIONS_VERSION` | required (live) | Current tag, e.g. `v0.18.1` |
| `AUTOMERGE_APP_ID` | `3436395` | ci-automerge-app |
| `FLEET_AUDIT_SNAPSHOT` | empty | Fixture dir (no network) |
| `GH_TOKEN` | from environment | App token in CI |

## Rejected

- Mutation / auto-bump PRs: Dependabot + bootstrap already exist.
- Skipping `bootstrap-exempt`: hides lag.
- Slack on every run: extra secret surface; issue + artifact is enough.
