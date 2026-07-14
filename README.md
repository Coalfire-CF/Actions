# Coalfire Advisory GitHub Actions

Centralized reusable GitHub Actions workflows for Coalfire Advisory repositories.

## Security Posture

All workflows follow security-hardened patterns:

- **SHA-pinned actions** — All third-party actions pinned to immutable commit SHAs, not mutable tags
- **Script injection prevention** — All `${{ }}` expressions passed via `env:` blocks, never interpolated directly in `run:` scripts
- **Least-privilege permissions** — Each workflow declares minimum required `permissions:`
- **Explicit secrets** — Secrets forwarded explicitly where possible instead of blanket `secrets: inherit`
- **Dependency pinning** — Tools like markdownlint-cli2 and yq pinned to specific versions with integrity checks

## Workflows

### PR Workflows

Called by downstream repos on pull requests.

| Workflow | File | Description |
|----------|------|-------------|
| Trivy PR | `org-trivy-pr.yml` | Security scanning of changed Terraform files |
| Gitleaks | `org-gitleaks-pr.yml` | Secret detection on PR commits |
| Terraform Validate | `org-terraform-validate.yml` | `terraform init` + `terraform validate` with PR comment |
| Terraform fmt | `org-terraform-fmt.yml` | Format check and auto-fix for Terraform files |
| Terraform Docs | `org-terraform-docs.yml` | Auto-generate and commit terraform-docs output (check-only on Dependabot PRs — read-only token can't push; drift surfaced as a warning, [#149](https://github.com/Coalfire-CF/Actions/issues/149)) |
| Terraform Plan | `org-terraform-plan.yml` | Terraform plan with PR comment |
| Terraform Apply | `org-terraform-apply.yml` | Terraform apply (manual trigger or post-merge) |
| Markdown Lint | `org-markdown-lint.yml` | Lint changed markdown files with markdownlint-cli2 |
| Tree README | `org-tree-readme.yml` | Auto-generate and commit directory tree in README (check-only on Dependabot PRs — read-only token can't push; drift surfaced as a warning, [#149](https://github.com/Coalfire-CF/Actions/issues/149)) |
| Dependabot Refresh | `org-dependabot.yml` | Auto-detect ecosystems and regenerate dependabot.yml |
| Dependabot Auto-Merge | `org-dependabot-auto-merge.yml` | Evaluate and auto-merge non-terraform Dependabot PRs ([docs](docs/ORG_DEPENDABOT_AUTO_MERGE.md)) |
| Label Sync | `org-label-sync.yml` | Sync Dependabot auto-merge label taxonomy to downstream repos ([taxonomy](docs/ORG_LABEL_TAXONOMY.md)) |
| Trivy Exception Review | `org-trivy-exception-review.yml` | Weekly review of Trivy `.trivyignore` exceptions |
| Terraform Source Pin | `org-terraform-source-pin.yml` | SHA-preferred pin gate for Coalfire-CF module sources **and** workflow `uses:` refs — advisory (`strict: false`) ([docs](docs/ORG_SOURCE_PIN.md)) |
| Terraform Version Band | `org-terraform-version-band.yml` | Enforces the org Terraform version band `>= 1.15.7, < 2.0.0` — advisory ([docs](docs/ORG_VERSION_BAND.md)) |
| OPA Policy Check | `org-opa.yml` | Tier-1 advisory OPA/Rego policy-as-code runner ([docs](docs/ORG_OPA.md)) |
| Terratest | `org-terratest.yml` | Reusable Terratest / behavioral-test harness with multi-cloud OIDC ([docs](docs/ORG_TERRATEST.md)) |

### Release Workflows

Called on merge to main.

| Workflow | File | Description |
|----------|------|-------------|
| Release | `org-release.yml` | Release-please + security scans + clean tarball + Slack notification |
| Release Clean | `org-release-clean.yml` | Produces stripped release tarball (no .github/, docs/, etc.) |
| Trivy Release | `org-trivy-release.yml` | Full-repo Trivy scan on release |
| Gitleaks Release | `org-gitleaks-release.yml` | Full-history secret scan on release |

### Utility Workflows

| Workflow | File | Description |
|----------|------|-------------|
| Slack Notify | `org-slack-notify.yml` | Sends release, failure, or health-check notifications to Slack |
| Jira Sync | `org-jira-sync.yml` | Syncs GitHub issues to Jira (Cloud or Data Center) |
| Terraform Version Check | `org-terraform-version-check.yml` | Scheduled check for new Terraform versions, auto-creates PRs |

### Legacy / Internal

| Workflow | File | Description |
|----------|------|-------------|
| Local Release | `release.yml` | Release workflow for the Actions repo itself |
| Sync Auto-Merge Labels | `label-sync.yml` | Self-caller: syncs the auto-merge label taxonomy on this repo (weekly + manual) |
| README Tree | `tree-readme.yml` | Self-caller: regenerates the README `## Tree` section on this repo's PRs |
| Dependabot Auto-Merge (self) | `dependabot-auto-merge.yml` | Self-caller: runs auto-merge evaluation on this repo's own Dependabot PRs |

## Usage

> **Pin by release SHA (RFC-0008).** Always reference these workflows as
> `@<40-hex-release-sha> # vX.Y.Z` — never `@main` or a bare tag (a moving ref is a
> supply-chain hole; the SHA makes the reference immutable and auditable). Resolve the
> SHA from the latest release tag at adoption time
> (`gh api repos/Coalfire-CF/Actions/git/refs/tags/<tag>`), and bump it deliberately when
> adopting a new release. All examples below follow this form.

### Basic Setup

Downstream repos call these workflows via `workflow_call`. Example `.github/workflows/` setup:

```yaml
# .github/workflows/org-release.yml
name: Org Release
on:
  push:
    branches: [main]

permissions:
  contents: write
  pull-requests: write
  issues: write

jobs:
  create-release:
    uses: Coalfire-CF/Actions/.github/workflows/org-release.yml@72d0360b99f80252dda40f6dfefc252f5a66edb3 # v0.10.0
    secrets: inherit
    with:
      slack_channel_id: 'C0123456789'
```

### Terraform Validate — Private Repository Access

Access to private Terraform module repositories is controlled using a GitHub App. The App ID and private key are stored as org-level secrets with visibility set to private repositories only.

```yaml
# Private repo — pass app credentials for module access
jobs:
  validate:
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-validate.yml@72d0360b99f80252dda40f6dfefc252f5a66edb3 # v0.10.0
    with:
      terraform_version: '1.15.7' # or omit to use .terraform-version
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}

# Public repo — no app credentials needed
jobs:
  validate:
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-validate.yml@72d0360b99f80252dda40f6dfefc252f5a66edb3 # v0.10.0
    with:
      terraform_version: '1.15.7' # or omit to use .terraform-version
```

### Terraform Docs

Wrapper around [terraform-docs GitHub Actions](https://github.com/terraform-docs/gh-actions).

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `find-dir` | Root directory to extract list of directories | `disabled` | no |
| `recursive` | Update submodules recursively | `false` | no |
| `recursive-path` | Submodules path to recursively update | `modules` | no |
| `working-dir` | Comma-separated directories to generate docs for | `.` | no |

```yaml
# Root module and submodules
jobs:
  terraform-docs:
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-docs.yml@72d0360b99f80252dda40f6dfefc252f5a66edb3 # v0.10.0
    with:
      recursive: true
```

### Slack Notifications

All workflows accept an optional `slack_channel_id` input. When provided, failure notifications are sent automatically. The release workflow also sends release notifications.

See [docs/ORG_SLACK_NOTIFY.md](docs/ORG_SLACK_NOTIFY.md) for full setup instructions.

### Jira Integration

Syncs GitHub issues to Jira on issue creation. Supports both Jira Cloud (API token) and Jira Data Center (PAT).

See [docs/ORG_JIRA_SYNC_SETUP.md](docs/ORG_JIRA_SYNC_SETUP.md) for setup instructions.

### Release Artifact Cleaning

Releases automatically include a cleaned tarball that strips non-essential files (.github/, docs/, etc.). Enabled by default.

See [docs/ORG_RELEASE_CLEAN.md](docs/ORG_RELEASE_CLEAN.md) for details and customization.

## Issues

Bug fixes and enhancements are managed through GitHub issues on this repository.

Issue labels:

- Bug
- Enhancement
- Documentation
- Code

## Tree

```text
.
|-- CHANGELOG.md
|-- README.md
|-- actions
|   |-- gitleaks
|       |-- action.yml
|-- docs
|   |-- GATE_CONFIG.md
|   |-- GATE_PROMOTION.md
|   |-- ORG_DEPENDABOT_AUTO_MERGE.md
|   |-- ORG_JIRA_SYNC_SETUP.md
|   |-- ORG_LABEL_TAXONOMY.md
|   |-- ORG_OPA.md
|   |-- ORG_RELEASE_AUTO_PATCH.md
|   |-- ORG_RELEASE_CLEAN.md
|   |-- ORG_SLACK_NOTIFY.md
|   |-- ORG_SOURCE_PIN.md
|   |-- ORG_TERRATEST.md
|   |-- ORG_TERRATEST_PROVISIONING.md
|   |-- ORG_VERSION_BAND.md
|   |-- superpowers
|       |-- specs
|           |-- 2026-07-14-self-dogfood-reusable-workflows-design.md
|-- gate-config.yml
|-- package-lock.json
|-- package.json
|-- release-please-config.json
|-- renovate
|   |-- terraform-ref-pins.json5
|-- scripts
|   |-- auto-merge-decide.sh
|   |-- breaking-change-check.sh
|   |-- cache-lib.sh
|   |-- gate-config-resolve.sh
|   |-- pr-green-merge.sh
|   |-- prompt-lib.sh
|   |-- release-patch-merge.sh
|   |-- retry-lib.sh
|   |-- source-pin-check.sh
|   |-- stagger-slot.sh
|   |-- supply-chain-check.sh
|   |-- uses-pin-check.sh
|   |-- version-band-check.sh
|-- tests
    |-- auto-merge-decide.test.sh
    |-- cache-read.test.sh
    |-- fixtures
    |   |-- auto-merge-decide
    |   |   |-- first_party_waiver.env
    |   |   |-- major_blocked.env
    |   |   |-- osv_blocked.env
    |   |   |-- parse_error_manual.env
    |   |-- cache-read
    |   |   |-- complete_clean.json
    |   |   |-- legacy_no_schema.json
    |   |   |-- missing_fields.json
    |   |   |-- string_booleans.json
    |   |   |-- unknown_schema.json
    |   |   |-- vuln.json
    |   |   |-- wrong_producer.json
    |   |-- release-patch
    |   |   |-- changelog.base.md
    |   |   |-- changelog.patch.md
    |   |   |-- manifest.base.json
    |   |   |-- manifest.patch.json
    |   |   |-- snapshot.happy.json
    |   |-- source-pin
    |   |   |-- fail_branch.tf
    |   |   |-- fail_floating.tf
    |   |   |-- fail_sha.tf
    |   |   |-- pass.tf
    |   |   |-- pass_renovate.tf
    |   |   |-- warn_tag.tf
    |   |-- uses-pin
    |       |-- fail_main.yml
    |       |-- fail_sha_nocomment.yml
    |       |-- pass_local.yml
    |       |-- pass_sha.yml
    |       |-- warn_tag.yml
    |-- gate-config-resolve.test.sh
    |-- prompt-build.test.sh
    |-- reconcile-sweeper.test.sh
    |-- release-patch-merge.test.sh
    |-- retry-lib.test.sh
    |-- source-pin-check.test.sh
    |-- stagger-slot.test.sh
    |-- tree-readme-section.test.sh
    |-- uses-pin-check.test.sh
    |-- version-band-check.test.sh
```
