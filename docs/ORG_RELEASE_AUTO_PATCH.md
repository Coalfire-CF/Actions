# Auto-merge patch-only releases (`auto_release_patch`)

Opt-in policy for `org-release.yml` that auto-merges a release-please **release
PR** only when it is an **unambiguous patch-only release**. Minor and major
releases always keep the human gate. Tracking: Coalfire-CF/Actions#148.

The decision engine is `scripts/release-patch-merge.sh` (unit-tested by
`tests/release-patch-merge.test.sh`). It is **fail-closed**: every gate below has
a distinct SKIP reason, and any doubt → SKIP, never merge.

## Why a GitHub App token is mandatory

A merge performed with the default `GITHUB_TOKEN` **does not fire a `push`
event**. release-please's publish run is triggered by the push to the default
branch, so a `GITHUB_TOKEN` merge produces a **merged-but-unpublished** release —
the tag/release never gets cut. The policy therefore **refuses to run** without a
GitHub App token (`RELEASE_APP_ID` / `RELEASE_APP_PRIVATE_KEY`); gate 1 emits
`SKIP (no-app-token)`.

## Why never `gh pr merge --auto`

Armed auto-merge survives a release-please **re-roll**: if a `fix:` PR is open and
auto-merge is armed, a later `feat:` commit re-rolls the SAME PR into a *minor*,
and the armed auto-merge would merge the minor (a TOCTOU escape). Instead the
merge is a **compare-and-swap**: `gh pr merge --match-head-commit "$HEAD_SHA"`,
after re-verifying the head SHA is unchanged (gate 13). If the head moved, the
merge call is rejected by GitHub and we SKIP.

## Gate chain (in order; first failure wins)

| # | Gate | SKIP reason on failure |
|---|------|------------------------|
| 1 | App token present (`TOKEN_IS_APP=true`) | `no-app-token` |
| 2 | PR snapshot readable; pin `HEAD_SHA` (all later content read by SHA) | `snapshot-unavailable` |
| 3 | State OPEN + not draft | `already-merged` / `not-open` / `draft` |
| 4 | Not a fork PR (`isCrossRepository=false`) | `cross-repository` |
| 5 | Head is `release-please--branches--<base>` and base is the default branch | `wrong-branch` / `wrong-base` |
| 6 | Carries the `autorelease: pending` label | `missing-pending-label` |
| 7 | Author ∈ `AUTHOR_ALLOWLIST` (the release App) | `author-not-allowlisted` |
| 8 | Every changed file ∈ `RELEASE_FILE_ALLOWLIST` | `unexpected-file` |
| 9 | Manifest delta (base SHA vs head SHA) is strictly patch-only: `X.Y.Z`, same major+minor, patch == base+1, all changed entries patch | `not-patch-only` / `first-release` / `no-version-change` / `missing-manifest` |
| 10 | Changelog additions do not advertise `### Features` / `BREAKING` (belt over the manifest) | `inconsistent-changelog` |
| 11 | `reviewDecision` ∉ {REVIEW_REQUIRED, CHANGES_REQUESTED} — never auto-approves | `review-REVIEW_REQUIRED` / `review-CHANGES_REQUESTED` |
| 12 | Checks green. Empty rollup → re-poll for a registration grace window, then `zero-checks` unless `ALLOW_ZERO_CHECKS`. FAIL → skip; PENDING → `gh pr checks --watch --fail-fast` | `zero-checks` / `checks-fail` / `checks-not-green` |
| 13 | Re-snapshot: `headRefOid` unchanged and gates 3/6/11 still hold | `head-moved` |
| 14 | Dry-run → `WOULD-MERGE`; live → CAS merge via `--match-head-commit` | `merge-raced` / `merge-failed` |
| 15 | Upsert ONE marker comment (`<!-- org-release-auto-patch -->`, edited not re-posted) + step summary | — |

**Manifest is authoritative** (gate 9), not the PR title. The changelog belt
(gate 10) is a secondary consistency check, not the source of truth.

## Decision output

One line on stdout: `MERGED #n` / `WOULD-MERGE #n` / `SKIP #n (<reason>)`. Exit 0
for any well-formed decision. On every decision the policy upserts a marker
comment on the PR explaining the outcome (so an opted-in repo owner can always
see *why* a release was or wasn't auto-merged) — in both dry-run and live. The
`dry_run` "zero mutations" guarantee scopes to **merge/approve**: dry-run never
merges or approves, but it does post the legibility comment.

## Rollout

1. Land this PR (before the v0.11 cut).
2. Opt a repo in with `auto_release_patch: true` **in dry-run** (the default) and
   watch the marker comments on a few real release PRs.
3. Configure org secrets `RELEASE_APP_ID` / `RELEASE_APP_PRIVATE_KEY` (the release
   App). Without them the policy stays `SKIP (no-app-token)`.
4. Flip `auto_release_patch_dry_run: false` for live auto-merge once the dry-run
   window looks correct.

## Consumer snippet

```yaml
jobs:
  release:
    uses: Coalfire-CF/Actions/.github/workflows/org-release.yml@<sha> # vX.Y.Z
    with:
      auto_release_patch: true            # opt in (patch-only)
      auto_release_patch_dry_run: true    # log-only until validated; flip to false for live
      # auto_release_allow_zero_checks: false   # keep fail-closed unless a repo truly has no checks
      # actions_ref: <sha> # vX.Y.Z        # pin the decision logic to a release
    secrets: inherit                       # must include RELEASE_APP_ID / RELEASE_APP_PRIVATE_KEY
```

Minor and major releases are unaffected — they always require a human merge.
