# Org Repo Bootstrap

Automated baseline adoption for new (or never-adopted) Coalfire-CF repos.

GitHub has no native "apply a template when a repo is created": template
repositories and starter workflows are opt-in pickers at creation time, the org
`.github` repository only propagates community-health files (never workflows,
CODEOWNERS, or dependabot.yml), and rulesets enforce rules but never add files.
`org-repo-bootstrap.yml` is the convergence mechanism instead: a daily sweeper
that finds org repos missing the standard Actions baseline and opens one
adoption PR per repo.

## How it works

1. **Enumerate** — all non-archived, non-fork org repos, minus the infra repos
   (`Actions`, `.github`, `.allstar`) and anything topic-exempt.
1. **Decide per repo** — `scripts/repo-bootstrap.sh` applies the opt-out gates
   (below), probes for adoption (`.github/workflows/org-release.yml` present ⇒
   compliant), classifies the repo (Terraform via the languages API → the
   `terraform/` template set; private → `setup-bot-access.yml`), renders
   `templates/bootstrap/` with the latest release pin, and **drops any file
   that already exists in the target repo** (never overwrites).
1. **Deliver** — branch `bootstrap/baseline-<version>`, one commit, one PR
   labeled `bootstrap/proposed` + `merge/approved`.
1. **Land** — the reconcile sweeper (`org-dependabot-reconcile.yml`) merges the
   PR once its own checks are green; the App author is admitted by
   `pr-green-merge.sh`'s allowlist. The bootstrap PR's own callers run on the
   PR itself, so the repo's first CI run gates its own adoption.

All `uses:` references render to `@<40-hex-release-sha> # vX.Y.Z` (RFC-0008),
resolved from the latest Actions release at sweep time.

## Safety model

Identical to the reconcile sweeper:

- **Scheduled runs are live** but capped (`MAX_REPOS`, default 5 deliveries per
  run) — the fleet converges over days, not in one blast.
- **Manual dispatch is dry-run by default** (`dry_run=false` to deliver;
  `repo=owner/name` scopes a canary).
- The worker **fails closed**: any unreadable metadata/contents probe is a
  SKIP, never a delivery.
- PR-only mutations — nothing is ever pushed to a default branch directly.

## Opt-outs (each independently sufficient)

| Mechanism | Effect |
|-----------|--------|
| Repo topic `bootstrap-exempt` | Skipped at enumeration and re-checked per repo |
| Marker file `.github/.no-bootstrap` | Skipped before any classification |
| Close the bootstrap PR unmerged | Durable: the sweeper never re-proposes (`SKIP (declined)`) |

To re-invite a repo that declined: delete the closed PR's `bootstrap/*` branch
and its closed PR (or re-open it).

## Worker env contract (`scripts/repo-bootstrap.sh`)

| Var | Default | Meaning |
|-----|---------|---------|
| `TARGET_REPO` | required | owner/name |
| `ACTIONS_SHA` / `ACTIONS_VERSION` | required | release pin rendered into callers |
| `DRY_RUN` | `true` | decision only; zero mutating calls |
| `TEMPLATE_DIR` | `templates/bootstrap` | template root |
| `PR_LABELS` | `bootstrap/proposed,merge/approved` | applied to the PR (create-if-missing guarded) |
| `BRANCH_PREFIX` | `bootstrap/` | branch + PR-history matching prefix |
| `VISIBILITY` / `IS_TERRAFORM` | detected | classification overrides |
| `RETRY_MAX` | 3 | transient-read retries (retry-lib) |

Decisions: `SKIP <repo> (<reason>)`, `WOULD-BOOTSTRAP <repo> (<n> files)`,
`BOOTSTRAPPED <repo> PR#<n>`.

## One-time org setup

1. **App permission (blocking):** the `ci-automerge-app` installation (App ID
   3436395) must hold **`workflows: write`** — the bootstrap PR pushes files
   under `.github/workflows/`. Without it the push is rejected; this is the
   most likely first-run failure.
1. **Labels:** `bootstrap/proposed` ships in the label-sync taxonomy; the
   worker also creates labels on demand as defense-in-depth.
1. **Starter workflows (complementary, opt-in):** add `workflow-templates/`
   entries to the org `.github` repo so every repo's Actions tab offers the
   callers at creation time. These carry the release pin current at the time
   they were added; the sweeper converges any drift afterward, so refreshing
   them on each release is optional polish, not a requirement.

## Deliberately not adopted: org-ruleset "required workflows"

Rulesets can require a centrally-defined workflow to pass without any file in
the target repo, but: they cover PR events only (no schedules, no release
flow), apply one workflow uniformly (no terraform/generic split), and block
PRs in repos that have not adopted yet — enforcement-before-adoption creates
lockouts. Revisit once fleet adoption exceeds ~90%, possibly for one universal
check (e.g. gitleaks).

## Canary / verification procedure

```bash
# 1. Dry-run one repo (dispatch defaults to dry-run):
gh workflow run org-repo-bootstrap.yml -f repo=Coalfire-CF/<canary>
#    → expect WOULD-BOOTSTRAP with the class-appropriate file list

# 2. Live canary:
gh workflow run org-repo-bootstrap.yml -f repo=Coalfire-CF/<canary> -f dry_run=false
#    → review the PR: pins resolve, dependabot seed valid, callers run on the PR

# 3. Let reconcile land it (or dispatch org-dependabot-reconcile.yml), then:
gh workflow run org-repo-bootstrap.yml -f repo=Coalfire-CF/<canary>
#    → expect SKIP (compliant)

# 4. Org-wide census before trusting the schedule:
gh workflow run org-repo-bootstrap.yml
#    → review every WOULD-BOOTSTRAP line for misclassifications
```

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `SKIP (read-unavailable)` everywhere | App token missing/expired scopes, or API outage — the worker fails closed by design |
| Push rejected `refusing to allow a GitHub App to create or update workflow` | App lacks `workflows: write` (see One-time org setup) |
| PR opened but never merges | Its own checks aren't green, or `pr-green-merge.sh` allowlist doesn't include the App author — check reconcile run logs |
| Repo proposed the wrong file set | Languages API lag on brand-new repos; re-run after the first push, or set `IS_TERRAFORM` via a targeted dispatch |
| Template change not reflected | Templates render from the checked-out ref of Actions at sweep time — merge template changes to `main` first |
