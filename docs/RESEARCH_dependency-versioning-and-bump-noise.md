# RESEARCH TASK — Decouple version lines + kill fleet bump-noise

> **Status:** Deferred research/design task, saved 2026-07-24. NOT yet implemented.
> Captured from a planning session so it can be picked up later. Layer 1 is
> implementation-ready; Layer 2 is a fully-specified follow-on roadmap.
> Verified against `dependabot-core`, release-please, Knope, and Renovate docs +
> this repo's actual files (line refs below were accurate as of 2026-07-24 —
> re-verify before acting).

## Context

`Coalfire-CF/Actions` is a single-version monorepo — release-please `simple` type,
one version (`0.13.0` per `.release-please-manifest.json`) for ~31 reusable workflows

+ 1 composite action. Two pains follow from the single version line:

- **Toil / volume** — *any* merged change bumps the one version, and because every
  downstream repo SHA-pins `org-*.yml@<sha> # vX.Y.Z`, a bump PR fans out to *every*
  consumer regardless of relevance.
- **Cross-technology coupling** — a change to ansible test tooling bumps the same
  version line terraform consumers track. As ansible testing lands, terraform consumers
  get bumped — and their expensive terratest CI runs — for ansible-only releases.

Two composable fixes on different layers:

- **Layer 1 (consumer-side, noise) — implement first.** Add a cooldown to the existing
  self-dogfooded Dependabot machinery and confirm all `Coalfire-CF/Actions` bumps
  collapse into one auto-merged PR per consumer. No versioning change.
- **Layer 2 (producer-side, coupling) — later PR.** Give each technology domain its own
  version line + tag (`terraform/v*`, `ansible/v*`, …) via Knope, so a domain's release
  only reaches that domain's consumers.

Off-table (researched, rejected): moving major tags (`@v1`) — blocked by RFC-0008's
no-moving-tags CI guard; repo-splitting — reverses recent consolidation; release-please
multi-component — needs codegen/dual-copy since reusable workflows are pinned flat in
`.github/workflows/` (re-evaluated & confirmed 2026-07-29, see below).

---

## release-please multi-component — re-evaluated & rejected (2026-07-29)

Prompted by `Coalfire-CF/ansible-aws` running release-please multi-component successfully
(22 independently-versioned components, `separate-pull-requests`, `<component>/vX.Y.Z` tags,
umbrella `.` keeps plain `vX.Y.Z`). Question: does that precedent let Actions drop the Knope
plan and get per-domain tags with the tool already in the repo? **Answer: no — the pattern is
not portable to Actions.** Verified against release-please's actual source (main = v17.10.4;
the routing logic predates and is unchanged in the CLI wrapped by `release-please-action@v5.0.0`):

- **`include-paths` is not a real release-please option.** It does not exist in `src/` or
  `schemas/config.json`; it is silently ignored (issue #2339 calls it a "made up key"). A
  component is scoped **only** by its package *directory key*, optionally narrowed by
  `exclude-paths`. ansible-aws's `include-paths` entries are effectively no-ops — its components
  work purely because each package key *is* a real directory (`roles/audit`).
- **Routing is directory-prefix only, never by commit scope.** `manifest.ts` splits commits by
  path (`CommitSplit`) then filters (`CommitExclude`); both match with
  `file.indexOf(`${path}/`) === 0` — the key is treated as a directory (suffixed with `/`, file
  must be nested under it). Scope (`feat(foo):`) only drives changelog sections + bump level
  (sole exception: a hardcoded filter for `googleapis/google-cloud-go`). release-please does
  **not** route by scope — that is Knope's mechanism.
- **Consequence:** a package key that is an individual *file*
  (`.github/workflows/org-terraform-validate.yml`) resolves to a search under `…validate.yml/`,
  which can never match (a file has no children; top-level files with no `/` are skipped). So
  **per-workflow components on Actions' flat workflow layout cannot work.** GitHub forbids
  nesting reusable workflows, so there are no per-domain directories to key on.
- Corrections to worries raised mid-investigation: the `org-release.yml` vs `org-release-clean.yml`
  prefix "collision" is **not** real (the enforced `/` boundary prevents it, fix `29ba3b5`); and
  root `.` **double-counts** every commit unless given explicit `exclude-paths` per component
  (exactly why ansible-aws lists all 21 `roles/*/` under `.`'s excludes).

**Verdict:** the original rejection above was correct, and the original **Knope** choice for
Layer 2 is vindicated — scope-based routing is the only directory-free mechanism for per-domain
tags. **Layer 1 (Dependabot cooldown) remains the immediate, independent win** and is unaffected
by any of this; ship it first regardless of whether Layer 2 ever proceeds.

---

## What already exists (verified — do not rebuild)

The auto-merge pipeline is live and already does most of Layer 1's "auto-merge" goal:

- **Grouping.** The generator emits two homogeneous github-actions groups —
  `org-actions` (`patterns: ["Coalfire-CF/*"]`, minor/patch) and `third-party` — at
  `.github/workflows/org-dependabot.yml:297-309`, mirrored in this repo's own
  `.github/dependabot.yml:13-22` and in
  `templates/bootstrap/common/.github/dependabot.yml.tmpl:11-20`.
  Majors arrive as individually-reviewable singletons by design.
- **Auto-merge of grouped first-party minor/patch.** `org-dependabot-auto-merge.yml`
  classifies github-actions as eligible, and `scripts/auto-merge-decide.sh` waives the
  Scorecard gate for `Coalfire-CF/` first-party deps (`:76-86`), blocks majors
  (`blocked/major-bump`, `:56-61`/`:88-93`), and on green approves + merges via the
  App's ruleset bypass through `scripts/pr-green-merge.sh` (green-gates on head-commit
  **check-runs**, not `statusCheckRollup`; `BYPASS_REVIEW=true`).

So Layer 1 is **not** a rebuild of auto-merge. It is: add cooldown, and *verify* the
grouped first-party path actually reaches `decision=approve` (incl. the SHA-pin
"digest/version" update-type — the one thing to confirm rather than assume; the verdict
keys on `SEMVER_TYPE`/`UPDATE_TYPE_META` at `auto-merge-decide.sh:56,88,110`).

---

## Layer 1 — Dependabot noise-kill (implement first)

### 1a. Add cooldown to all three copies of the emitted `updates:` block

Dependabot cooldown is GA (default 3-day). Add a modest window so a batch of releases
collapses into one PR instead of a PR the instant each release lands. **All three copies
must stay byte-identical** (the generator note at `org-dependabot.yml:296` calls this out).
Place `cooldown:` as a sibling of `schedule:`/`commit-message:`/`labels:`, before the
github-actions `groups:` block:

- **Generator heredoc** — `.github/workflows/org-dependabot.yml`, per-entry block emitted
  at `:277-288` (insert after the `labels:` list, before the closing `YAML` at `:288` and
  the github-actions `groups:` heredoc at `:298`). Match the existing emitted indentation
  (entry keys at 4 spaces in the rendered file).
- **Bootstrap template** — `templates/bootstrap/common/.github/dependabot.yml.tmpl`
  (after `commit-message:` block, `:10`).
- **This repo's dogfood** — `.github/dependabot.yml` (after `commit-message:` block, `:12`).

Value:

```yaml
cooldown:
  default-days: 3
```

Note the open github-actions cooldown bugs (#14645 / #13691 — frequently-released actions
can be dropped from a cooldown window). Keep the window modest and validate on the pilot
before fleet-wide reliance.

### 1b. Confirm grouping genuinely collapses per-consumer

Verify (on a scratch/pilot consumer) that every
`Coalfire-CF/Actions/.github/workflows/*.yml` path — each is a distinct Dependabot
dependency — matches the `Coalfire-CF/*` group pattern and collapses into a single
grouped PR. Keep majors-as-singletons.

### 1c. Confirm auto-merge closes the loop (verify, patch only if a gap shows)

Trigger a synthetic `Coalfire-CF/Actions` minor/patch release and confirm the grouped PR
reaches `decision=approve` and merges. The only real unknown is the **SHA-pin update-type**:
Dependabot follows the release tag on a SHA pin and refreshes the `# vX.Y.Z` comment —
confirm this surfaces to `auto-merge-decide.sh` as patch/minor (`SEMVER_TYPE`), not an
unhandled type, so it flows through. If it doesn't, extend the `SEMVER_TYPE`/`UPDATE_TYPE_META`
handling in `scripts/auto-merge-decide.sh` and add a fixture to
`tests/auto-merge-decide.test.sh`. Do **not** speculatively change the decision logic before
the pilot shows a gap.

### Files touched (Layer 1)
`.github/workflows/org-dependabot.yml`,
`templates/bootstrap/common/.github/dependabot.yml.tmpl`, `.github/dependabot.yml`
(cooldown, three-way byte-identical); `scripts/auto-merge-decide.sh` +
`tests/auto-merge-decide.test.sh` **only if** the pilot exposes a SHA-pin update-type gap.

### Layer 1 flow

```
release cut in Coalfire-CF/Actions
        │
        ▼
Dependabot (each consumer)  ──cooldown 3d──▶ ONE grouped PR
   org-actions group  (Coalfire-CF/*, minor/patch)   third-party (rest)
        │                                                  │
        ▼                                                  ▼
org-dependabot-auto-merge.yml → auto-merge-decide.sh   (unchanged behavior)
   first-party minor/patch, green ⇒ approve            majors ⇒ singleton, human-gated
        │
        ▼
pr-green-merge.sh  (check-runs green, App bypass) ⇒ squash-merge
```

---

## Layer 2 — Per-domain version lines via Knope (design; later PR)

### Domain components (scopes)

| Package | Scope(s) | Members |
|---|---|---|
| `terraform` | `terraform`, `all` | org-terraform-{validate,fmt,docs,plan,apply,source-pin,version-band,version-check}, org-terratest |
| `ansible` | `ansible`, `all` | org-ansible-* (new, forward-looking) |
| `security` | `security`, `all` | org-gitleaks-{pr,release}, org-trivy-{pr,release,exception-review}, org-opa, actions/gitleaks |
| `release` | `release`, `all` | org-release, org-release-clean |
| `util` | `util`, `all` | org-slack-notify, org-jira-sync, org-label-sync, org-markdown-lint, org-tree-readme, org-repo-bootstrap, org-dependabot{,-auto-merge,-reconcile} |

Every package carries a shared **`all`** scope so repo-wide / shared-`scripts/` changes bump
all domains. Self-caller workflows (`release.yml`, `test-scripts.yml`, `tree-readme.yml`,
`label-sync.yml`, `dependabot-auto-merge.yml`) run on this repo only and are **not** versioned.

### `knope.toml` (new)

- One `[packages."<name>"]` per domain; **omit `versioned_files`** (Knope derives the version
  from the latest matching `<package>/v<semver>` git tag); `changelog = "docs/changelogs/<name>.md"`;
  `scopes = [...]` as above.
- `[[workflows]]` `prepare-release` (opens the release PR) and `release` (cuts one GitHub
  Release + `<name>/v<semver>` tag per changed package). `[github] owner/repo`.

### CRITICAL constraint — one domain tag per commit (top pilot risk)
Dependabot resolves a SHA pin's *current* version by taking the **highest** tag on that commit
(prefix-agnostic), then prefix-scopes candidates via `same_prefix?`. If one merge commit carries
several domains' tags (`terraform/v…` **and** `ansible/v…`), resolution is ambiguous and can
mis-scope. Therefore **each domain's tag must land on a commit bearing only that tag** — the
`release` job cuts each package's tag on its own dedicated (empty) release commit
(`chore(release): <name>/vX.Y.Z`), not all on the merge commit. **This is the single
load-bearing assumption; prove it on the pilot before fleet rollout.** If Knope's built-in
`Release` step tags everything on the merge commit and can't be steered to per-commit tags,
replace it with a scripted tag-and-release loop (one empty commit + tag + `gh release` per
changed package). Same rule applies to the initial seed.

### Rewire this repo's release (`.github/workflows/release.yml`)
Keep the three self-scan gates (`self-scan-gitleaks/trivy/actionlint`) as `needs:`, the
App-token wiring (`RELEASE_APP_ID` → `create-github-app-token`, fallback `github.token`,
`:132-150`), and the merged-gate + `dependabot[bot]` actor-skip (`:119-121`). **Replace** the
`release-please-action` step (`:152-155`) with `knope-dev/action@v2.1.2` (pinned by SHA +
`# v2.1.2`) running `knope prepare-release` / `knope release`. App token stays so release PRs
get CI and tag pushes trigger downstream; App needs `contents: write` + `pull-requests: write`
and an auto-merge-App bypass entry if review is required. Retire `release-please-config.json`

+ `.release-please-manifest.json`; migrate `CHANGELOG.md` → per-domain `docs/changelogs/*.md`.

### Silent-no-op guard (Knope's sharp edge)
An unknown/typo scope releases **nothing**, silently. Add `scripts/scope-check.sh` +
`tests/scope-check.test.sh` enforcing commit scopes ∈ {terraform, ansible, security, release,
util, all}. Two distinct wirings:

- The **meta-test** (`tests/scope-check.test.sh`) auto-runs — `test-scripts.yml` already globs
  `tests/*.test.sh` (`:31`) — and `scripts/scope-check.sh` is auto-shellchecked (`:67`). No
  wiring needed for these.
- **Enforcement on real PR commits** is a *new job* in `test-scripts.yml` that runs
  `scope-check.sh` against the PR's commit messages (mirror the `no-main-refs` job shape). This
  is the piece that actually fails CI on a bad scope; it does not exist yet.

### Pin-comment shape (Layer 2, consumer side)
Extend **only** `scripts/uses-pin-check.sh` to accept `# <domain>/vX.Y.Z` as PASS. Today its
`has_comment` regex (`:79`, `#[[:space:]]*v[0-9]+(\.[0-9]+)*`) requires the comment to start
with `v`, so `# terraform/v0.13.0` would FAIL. Change the regex to allow an optional
`[a-z]+/` prefix; update `tests/uses-pin-check.test.sh` fixtures. **Do not touch**
`source-pin-check.sh` (it gates Terraform *module* sources in other repos — never
domain-tagged) or `no-main-refs` (guards `@main` only — unaffected by comment shape).

### Migration (one-time, via the org-repo-bootstrap sweeper)

1. **Seed** each domain's first tag at the current baseline (`terraform/v0.13.0`,
   `ansible/v0.13.0`, …) — **each on its own commit** (one-tag-per-commit rule).
2. **Re-pin consumers** from `@<sha> # v0.13.0` onto the domain tag per `uses:` line, mapping
   each referenced workflow path → its domain via the table. Vehicle: the org-repo-bootstrap
   sweeper (blocked until App 3436395 gains `workflows:write`).
3. **Per-domain bootstrap placeholders.** `repo-bootstrap.sh` currently does one global sed for
   `__ACTIONS_SHA__`/`__ACTIONS_VERSION__` (`:174-175`, env vars `:62-63`). Split into per-domain
   placeholders (`__TERRAFORM_SHA__ # __TERRAFORM_VERSION__`, etc.) with matching env vars and sed
   expressions; each `.tmpl` line (e.g. `org-terraform-validate.yml.tmpl:18`) adopts its domain's
   placeholder.
4. **Ansible payoff.** New `org-ansible-*` workflows land under `ansible` scope only → cut
   `ansible/v*` only → never reach terraform consumers. Add `.ansible-version` (+ band/check
   analog) mirroring `.terraform-version` / `.terraform-version-band`.
5. **Pilot** one consumer end-to-end before the fleet sweep.

---

## Sequencing

1. **(first PR)** Layer 1: cooldown in all three dependabot copies; verify grouping + auto-merge
   on a pilot; patch `auto-merge-decide.sh` only if a SHA-pin update-type gap appears.
2. Layer 2 scaffolding: `knope.toml`, per-domain changelogs, scope-guard (+ enforcement job),
   rewired `release.yml`; retire release-please; seed tags on distinct commits.
3. Pilot re-pin on one consumer; verify Dependabot prefix-scoping.
4. Fleet re-pin via the sweeper (after App `workflows:write`).

---

## Verification (Layer 1)

- **Three-copy parity (local):** after editing, diff the emitted `cooldown:` block across
  `org-dependabot.yml`, `dependabot.yml.tmpl`, and `.github/dependabot.yml` — byte-identical.
- **Generator still renders valid YAML (local):** run the generator against a scratch tree and
  `yq`/`yaml.safe_load` the output; confirm `cooldown:` sits at entry level next to `schedule:`.
- **Guards stay green (local):** `bash tests/auto-merge-decide.test.sh` plus the
  `test-scripts.yml` equivalents — meta-tests (`tests/*.test.sh`), `shellcheck scripts/*.sh`,
  `actionlint` — all pass.
- **Cooldown/grouping (pilot, live):** synthetic `Coalfire-CF/Actions` minor/patch release →
  on a pilot consumer, exactly **one** grouped PR (not one per workflow path), cooldown honored,
  major arrives as its own singleton.
- **Auto-merge + SHA-pin update-type (pilot, live):** grouped first-party PR, once green, gets
  `merge/approved` and is squash-merged by the App; confirm the SHA-pin-follows-tag update
  surfaces as patch/minor to `auto-merge-decide.sh` (decision step summary). If not → fixture +
  handling.

## Key risks

- **Cooldown drops frequent releases** (Dependabot #14645/#13691) — keep the window modest,
  watch the pilot.
- **(Layer 2) one-tag-per-commit** is the load-bearing Dependabot-scoping assumption — prove
  before any fleet work.
- **(Layer 2) Knope is sub-1.0 / small-maintainer** — pin the action by SHA; the scope-guard
  covers its silent-no-op edge.
- **(Layer 2) Fleet re-pin** depends on App 3436395 gaining `workflows:write`.
