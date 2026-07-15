# Org repo bootstrap — design spec (2026-07-15)

**Status:** shipped in v0.13.0, live · **Runbook:** [docs/ORG_REPO_BOOTSTRAP.md](../../ORG_REPO_BOOTSTRAP.md)

## Problem

New org repos get no CI baseline until a human hand-adopts the caller bundle.
GitHub offers no native apply-template-at-creation: template repos and starter
workflows are opt-in pickers, the org `.github` repo only propagates
community-health files, rulesets enforce but never add files, and org-ruleset
"required workflows" cover PR events only and lock out pre-adoption repos.

## Shape

A daily sweeper (`org-repo-bootstrap.yml`, clone of the reconcile sweeper's
safety model) + a per-repo worker (`scripts/repo-bootstrap.sh`) + a template
bundle (`templates/bootstrap/{common,terraform,private}` as `.tmpl` files with
`__ACTIONS_SHA__`/`__ACTIONS_VERSION__`/`__STAGGER_SLOT__` placeholders).

Per repo: opt-out gates (`bootstrap-exempt` topic → `.github/.no-bootstrap`
marker → adoption probe on `.github/workflows/org-release.yml` → open/declined
`bootstrap/*` PR history) → classify (languages API `HCL` ⇒ terraform set;
private ⇒ `setup-bot-access.yml`) → render with the latest release pin
(RFC-0008) → drop any file that already exists remotely (never overwrite) →
one PR labeled `bootstrap/proposed` + `merge/approved`.

Landing is delegated to the existing machinery: the reconcile sweeper merges
green bootstrap PRs; `pr-green-merge.sh`'s `AUTHOR_ALLOWLIST` now admits
`app/ci-automerge-app` / `ci-automerge-app[bot]` (the sweeper's own PR author).

## Key decisions

| Decision | Choice | Why |
|---|---|---|
| Delivery | PRs, never direct pushes | reviewable, ruleset-safe; a declined PR doubles as a durable opt-out |
| Auto-merge | yes (`merge/approved` at open) | user decision; the reconcile green gate + allowlist still gate every merge |
| Detection | `org-release.yml` presence | every adopted repo has it; one contents probe |
| Schedule | daily 07:43 UTC, LIVE, cap 5 non-SKIP/run | reconcile precedent; fleet converges over ~12 days, not one blast |
| Dispatch | dry-run default, `repo=` canary, `max_repos=` | reconcile precedent |
| CODEOWNERS | omitted from bundle | sweeper can't know the owning team; Allstar already nags |
| Failure posture | fail closed on any read; inconclusive contents probe = "exists" | when in doubt, never deliver/overwrite |
| Starter workflows | org `.github` `workflow-templates/` (five common callers) | creation-time discoverability; sweeper converges pin drift |

## Known behavior

- Workflows **added by** a bootstrap PR do not run on that PR (GitHub
  limitation) — the PR merges via the green gate's no-checks path; callers
  activate on the first PR after merge.
- `.tmpl` suffixes keep templates out of workflow lint / uses-pin gates; the
  renderer strips them.
- Languages-API lag on brand-new repos can misclassify terraform for a few
  minutes after first push; re-run or override `IS_TERRAFORM`.

## Verification (all passed 2026-07-15)

`tests/repo-bootstrap.test.sh` (8 cases: dry-run zero-mutation, every gate,
class file sets, non-overwrite, placeholder rendering, fail-closed) +
2 new allowlist cases in `tests/reconcile-sweeper.test.sh`. Live lifecycle on
`image-bakery`: BOOTSTRAPPED PR#13 (14 files, terraform+private) → reconcile
MERGED → re-run `SKIP (compliant)`. Org census: 240 candidates / 181 compliant
/ 1 opt-out / 58 to bootstrap.

## Prerequisite discovered

The `ci-automerge-app` installation needed **`workflows: write`** (bootstrap
PRs push workflow files) — granted 2026-07-15. Any future App-token writer of
workflow files needs the same.
