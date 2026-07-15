# Dependabot auto-merge: ruleset-bypass direct merge

**Date:** 2026-07-15 · **Shipped:** `v0.12.1` ([#240](https://github.com/Coalfire-CF/Actions/pull/240))

## Problem

After the 2026-07-14 migration to org repository rulesets (with the auto-merge
GitHub App added as a `bypass_mode: always` bypass actor), **100+ Dependabot PRs
across the fleet sat `merge/approved` but unmerged** — each `BLOCKED` /
`reviewDecision: REVIEW_REQUIRED`, waiting on a code-owner review a bot can neither
give nor be a CODEOWNER for. The ruleset bypass was configured correctly; nothing
in the code ever exercised it.

## Root cause

A ruleset bypass applies **only to a direct merge performed by the bypass actor**.
The pipeline never did that. Three mechanics, each verified live:

1. **Native auto-merge ignores bypass.** `gh pr merge --auto` waits for every
   ruleset requirement to be *literally* met and never consults the enabler's
   bypass. On a code-owner ruleset it waits forever. (Proof: PRs showed
   `autoMergeRequest.enabledBy = app/ci-automerge-app` yet stayed `BLOCKED`.)
1. **Plain `gh pr merge` (GraphQL) also doesn't bypass** — it refuses a `BLOCKED`
   PR ("base branch policy prohibits the merge"), even for an admin + bypass user.
   Only the **REST endpoint** `PUT /repos/{o}/{r}/pulls/{n}/merge` honors the
   authenticated actor's bypass entitlement.
1. **Reading `statusCheckRollup` needs `statuses:read` too.** That GraphQL field
   aggregates check runs *and* commit statuses, so it demands both `checks:read`
   and `statuses:read`. The App holds `checks:read` only.

## Fix

**`scripts/pr-green-merge.sh`** (propagates to all consumers immediately via
`actions_ref=main`):

- Merge via `gh api --method PUT .../merge` (REST), never `gh pr merge`.
- `BYPASS_REVIEW=true` merges past `reviewDecision=REVIEW_REQUIRED` (caller is a
  bypass actor); `CHANGES_REQUESTED` is still never overridden.
- Read CI state via REST `GET /commits/{sha}/check-runs` (`checks:read` only);
  `reviewDecision`/`headRefOid` via `gh pr view` (no `statusCheckRollup`).

**`org-dependabot-auto-merge.yml`** (workflow, adopted via pin bump):

- After approval, direct bypass-merge on green; `--auto` removed.
- New `remerge` job on `check_suite: completed` re-drives the merge the instant CI
  finishes (for PRs still building at decide-time). Resolves + filters the PR via
  `github-script` (open, dependabot-authored, `merge/approved`); never runs the
  evaluation pipeline or checks out PR-branch code.

**`org-dependabot-reconcile.yml`** — passes `BYPASS_REVIEW=true`; gained a `repo`
input for scoped canary / targeted sweeps. **Scheduled runs (every 6h) are LIVE**
(flipped 2026-07-15, after `check_suite` proved a dead end — see gotchas): the sweep
is the tail-catcher for PRs whose CI outlasts the PR-time merge. Manual dispatch
stays dry-run by default.

**Prerequisite:** `ci-automerge-app` granted `Checks: Read-only`
(perms now: contents:write, pull_requests:write, metadata:read, checks:read).

## Rollout

- Backlog drained live via reconcile: **119 PRs merged** by `app/ci-automerge-app`.
- Fleet adoption: 192 consumer callers direct-committed to `main` (cs-coalforge
  bypass) with the `v0.12.1` pin + `check_suite` trigger + widened `if`; Actions
  self-caller in #240; `MTCS` via PR ([#87](https://github.com/Coalfire-CF/MTCS/pull/87))
  because its own repo ruleset requires status checks that cs-coalforge does not
  bypass.

## Gotchas / notes

- `gh pr merge` (even `--admin` for non-admins) ≠ REST bypass merge. Use the REST
  endpoint for any bypass-actor merge.
- **Repo-level rulesets are NOT covered by the org-ruleset bypass list.** A fleet
  scan (2026-07-15) found 16 repos with active repo rulesets carrying a
  `pull_request` rule that 405'd the App's merge ("Waiting on code owner review")
  despite the org bypass — e.g. `terraform-aws-cloudfront`,
  `terraform-aws-security-hub`, the 4 `proliance-*` repos. Fixed by adding
  `ci-automerge-app` (3436395, `bypass_mode: always`) to each repo ruleset's
  bypass actors, preserving their custom rules (linear-history, copilot-review,
  creation/update). Any NEW repo-level ruleset with a `pull_request` rule must
  include the App as a bypass actor or its Dependabot PRs will wedge. (`MTCS` is
  the other variant: its repo ruleset requires status checks — adopt changes
  there via PR.)
- The 0.12.1 caller is a guarded *canonical replace*; any consumer caller with
  custom `with:` inputs is skipped (none existed at rollout).
- Reconcile returns non-zero if any single PR errors (e.g. a merge conflict → 405,
  or a mergeability-recompute race → 409); that is expected, not a fix failure.
- **Green-gate self-skip (fixed):** the `decide` job merges inline, so its own
  check run (`auto-merge / decide`) is IN_PROGRESS and `notify_failure`/`remerge`
  are QUEUED while `pr-green-merge.sh` reads check runs — making the PR-time merge
  self-classify PENDING forever. Fixed via `IGNORE_CHECK_PREFIX` (default
  `"auto-merge / "`), which excludes the auto-merge workflow's own jobs from the
  gate. Repo CI checks still gate.
- **`check_suite` re-merge is external-CI-only:** GitHub does not emit `check_suite`
  events for suites created by GitHub Actions (recursion guard), so the `remerge`
  job never fires for Actions-gated repos. Those rely on the (fixed) PR-time merge
  or the reconcile sweep. Slow-CI repos whose checks outlast the decide job still
  need the sweep to converge — which is why the scheduled sweep runs live: it is
  the only reliable automated catcher for that tail.
