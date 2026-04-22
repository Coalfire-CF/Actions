# Label Taxonomy

35 labels across 6 categories for the Dependabot auto-merge system. Labels are
managed by the `org-label-sync.yml` workflow, which creates missing labels and
corrects drifted colors/descriptions.

## Categories

### `dep/` - Dependency Ecosystem

Classifies the type of dependency being updated. Applied by Dependabot (via
generated `dependabot.yml` labels config) and refined by the `classify` job.

**Color**: `#0075ca` (blue)

| Label | Description |
|-------|-------------|
| `dep/github-actions` | GitHub Actions version bump |
| `dep/terraform-provider` | Terraform provider update |
| `dep/terraform-module` | Terraform module reference update |
| `dep/docker` | Docker base image update |
| `dep/pip` | Python dependency |
| `dep/npm` | Node.js dependency |
| `dep/gomod` | Go module dependency |
| `dep/nuget` | .NET NuGet dependency |
| `dep/cargo` | Rust Cargo dependency |
| `dep/bundler` | Ruby Bundler dependency |
| `dep/composer` | PHP Composer dependency |
| `dep/other` | Other ecosystem dependency |

### `merge/` - Auto-Merge Lifecycle

Drives the merge lifecycle. Only one `merge/*` label is active per PR at a time.
The `decide` job removes conflicting labels before applying the new one.

| Label | Color | Description |
|-------|-------|-------------|
| `merge/eligible` | `#2ea44f` (green) | Checks in progress |
| `merge/approved` | `#0e8a16` (dark green) | All checks passed, auto-merge enabled |
| `merge/blocked` | `#d73a49` (red) | Auto-merge blocked, see `blocked/*` labels |
| `merge/manual-review` | `#e4e669` (yellow) | Requires human review |
| `merge/skipped` | `#cccccc` (gray) | Not eligible (terraform deps) |

### `check/` - Individual Check Results

Applied additively as each check completes. Provides an audit trail of what
was evaluated and the result.

| Label | Color | Description |
|-------|-------|-------------|
| `check/osv-clear` | `#0e8a16` (green) | No known vulnerabilities in OSV.dev |
| `check/osv-vuln` | `#d73a49` (red) | Known vulnerability found in OSV.dev |
| `check/scorecard-pass` | `#0e8a16` (green) | OpenSSF Scorecard meets threshold |
| `check/scorecard-low` | `#d73a49` (red) | OpenSSF Scorecard below threshold |
| `check/semver-patch` | `#0e8a16` (green) | Patch version bump |
| `check/semver-minor` | `#0e8a16` (green) | Minor version bump |
| `check/semver-major` | `#d73a49` (red) | Major version bump detected |
| `check/changelog-safe` | `#0e8a16` (green) | AI analysis: no breaking changes detected |
| `check/changelog-risk` | `#fbca04` (yellow) | AI analysis: potential breaking changes |
| `check/changelog-breaking` | `#d73a49` (red) | AI analysis: confirmed breaking changes |
| `check/cached` | `#c5def5` (light blue) | Analysis result loaded from cross-repo cache |

### `risk/` - Overall Risk Level

Single summary label per PR. Computed from the combined check results.

| Label | Color | Description |
|-------|-------|-------------|
| `risk/low` | `#0e8a16` (green) | Patch bump, clean checks |
| `risk/medium` | `#fbca04` (yellow) | Minor bump or scorecard concerns |
| `risk/high` | `#d73a49` (red) | Major bump, vulns, or breaking changes |

### `blocked/` - Blocking Reasons

Explains why auto-merge was blocked. Multiple `blocked/*` labels can be present
simultaneously on a single PR.

**Color**: `#b60205` (dark red)

| Label | Description |
|-------|-------------|
| `blocked/known-vuln` | Target version has known vulnerability |
| `blocked/low-scorecard` | OpenSSF Scorecard below threshold |
| `blocked/major-bump` | Major semver bump requires manual review |
| `blocked/breaking-change` | Breaking change detected in changelog |
| `blocked/analysis-error` | Automated analysis failed, needs manual check |
| `blocked/terraform-no-tests` | Terraform dep, unit tests not yet available |

## Color Reference

| Hex | Usage |
|-----|-------|
| `#0075ca` | Blue - ecosystem classification |
| `#0e8a16` | Dark green - passed / safe / approved |
| `#2ea44f` | Green - eligible / in progress |
| `#fbca04` | Yellow - warning / medium risk |
| `#e4e669` | Light yellow - manual review |
| `#d73a49` | Red - failed / blocked / high risk |
| `#b60205` | Dark red - blocking reasons |
| `#c5def5` | Light blue - informational (cached) |
| `#cccccc` | Gray - skipped / not applicable |

## Filtering Examples

**GitHub search queries for common views:**

```
# All blocked Dependabot PRs across the org
org:Coalfire-CF is:pr is:open label:merge/blocked author:app/dependabot

# High-risk PRs needing attention
org:Coalfire-CF is:pr is:open label:risk/high author:app/dependabot

# Terraform deps waiting for unit tests
org:Coalfire-CF is:pr is:open label:blocked/terraform-no-tests

# PRs with known vulnerabilities
org:Coalfire-CF is:pr is:open label:blocked/known-vuln

# Successfully auto-merged PRs (last 30 days)
org:Coalfire-CF is:pr is:merged label:merge/approved author:app/dependabot

# All GitHub Actions bumps
org:Coalfire-CF is:pr is:open label:dep/github-actions author:app/dependabot
```

## Managing Labels

### Sync labels to a repo

```yaml
jobs:
  sync-labels:
    uses: Coalfire-CF/Actions/.github/workflows/org-label-sync.yml@main
    secrets: inherit
```

### Schedule weekly sync

```yaml
on:
  schedule:
    - cron: '0 6 * * 1'
  workflow_dispatch:

jobs:
  sync-labels:
    uses: Coalfire-CF/Actions/.github/workflows/org-label-sync.yml@main
    secrets: inherit
```

The sync workflow is idempotent: it creates missing labels, updates drifted
colors/descriptions, and leaves correct labels untouched.
