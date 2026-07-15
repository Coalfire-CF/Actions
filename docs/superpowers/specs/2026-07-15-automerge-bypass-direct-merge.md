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
input for scoped canary / targeted sweeps. Stays `dry_run` on schedule (a manual
safety net, not the primary path).

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
- A repo with its **own** ruleset requiring status checks (e.g. `MTCS`) is not
  covered by the org-ruleset bypass list — adopt via PR there.
- The 0.12.1 caller is a guarded *canonical replace*; any consumer caller with
  custom `with:` inputs is skipped (none existed at rollout).
- Reconcile returns non-zero if any single PR errors (e.g. a merge conflict → 405,
  or a mergeability-recompute race → 409); that is expected, not a fix failure.
