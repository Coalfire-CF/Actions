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

File, workflow and job names follow the cs-delta naming contract. See
[docs/PIPELINE_NAMING.md](docs/PIPELINE_NAMING.md), which also has the
v1.0.0 old-to-new rename table for callers.

### PR Workflows

Called by downstream repos on pull requests.

| Workflow | File | Description |
|----------|------|-------------|
| Trivy PR | `ci-security-trivy.yml` | Security scanning of changed Terraform files |
| Gitleaks | `ci-security-gitleaks.yml` | Secret detection on PR commits |
| Terraform Validate | `ci-terraform-validate.yml` | `terraform init` + `terraform validate` with PR comment. Takes `working_directory` (default `.`) — **repos with no root module must set or matrix it**, or the gate validates an empty directory |
| Terraform fmt | `ci-terraform-format.yml` | Format check and auto-fix for Terraform files |
| Terraform Docs | `ci-terraform-docs.yml` | Verifies `README.md` matches the module; never pushes. Authors regenerate locally with the pinned pre-commit hook. Drift fails human PRs with the diff and warns on Dependabot PRs ([docs](docs/ORG_TERRAFORM_DOCS.md)) |
| Terraform Plan | `deploy-terraform-plan.yml` | Terraform plan with PR comment |
| Terraform Apply | `deploy-terraform-apply.yml` | Terraform apply (manual trigger or post-merge) |
| Markdown Lint | `ci-markdown.yml` | Lint changed markdown files with markdownlint-cli2 |
| Dependabot Refresh | `automation-dependabot-refresh.yml` | Auto-detect ecosystems and regenerate dependabot.yml |
| Dependabot Auto-Merge | `automation-dependabot-auto-merge.yml` | Evaluate and auto-merge non-terraform Dependabot PRs ([docs](docs/ORG_DEPENDABOT_AUTO_MERGE.md)) |
| Label Sync | `automation-label-sync.yml` | Sync Dependabot auto-merge label taxonomy to downstream repos ([taxonomy](docs/ORG_LABEL_TAXONOMY.md)) |
| Trivy Exception Review | `automation-trivy-exception-review.yml` | Weekly review of Trivy `.trivyignore` exceptions |
| Terraform Source Pin | `ci-terraform-source-pin.yml` | SHA-preferred pin gate for Coalfire-CF module sources **and** workflow `uses:` refs — advisory (`strict: false`) ([docs](docs/ORG_SOURCE_PIN.md)) |
| Terraform Version Band | `ci-terraform-version-band.yml` | Enforces the org Terraform version band `>= 1.15.7, < 2.0.0` — advisory ([docs](docs/ORG_VERSION_BAND.md)) |
| OPA Policy Check | `ci-policy-opa.yml` | Tier-1 advisory OPA/Rego policy-as-code runner ([docs](docs/ORG_OPA.md)) |
| Terratest | `ci-terratest.yml` | Reusable Terratest / behavioral-test harness with multi-cloud OIDC ([docs](docs/ORG_TERRATEST.md)) |

### Release Workflows

Called on merge to main.

| Workflow | File | Description |
|----------|------|-------------|
| Release | `release-please.yml` | Release-please + security scans + clean tarball + Slack notification |
| Release Clean | `release-clean-archive.yml` | Produces stripped release tarball (no .github/, docs/, etc.) |
| Trivy Release | `release-security-trivy.yml` | Full-repo Trivy scan on release |
| Gitleaks Release | `release-security-gitleaks.yml` | Full-history secret scan on release |

### Utility Workflows

| Workflow | File | Description |
|----------|------|-------------|
| Slack Notify | `automation-slack-notify.yml` | Sends release, failure, or health-check notifications to Slack |
| Jira Sync | `automation-jira-sync.yml` | Syncs GitHub issues to Jira (Cloud or Data Center) |
| Terraform Version Check | `automation-terraform-version-check.yml` | Scheduled check for new Terraform versions, auto-creates PRs |
| Repo Bootstrap | `automation-repo-bootstrap.yml` | Daily sweeper that opens baseline-adoption PRs (pinned caller bundle from `templates/bootstrap/`) on org repos that never adopted the standard workflows ([docs](docs/ORG_REPO_BOOTSTRAP.md)) |

### Legacy / Internal

| Workflow | File | Description |
|----------|------|-------------|
| Local Release | `internal-release.yml` | Release workflow for the Actions repo itself |
| Sync Auto-Merge Labels | `internal-label-sync.yml` | Self-caller: syncs the auto-merge label taxonomy on this repo (weekly + manual) |
| Dependabot Auto-Merge (self) | `internal-dependabot-auto-merge.yml` | Self-caller: runs auto-merge evaluation on this repo's own Dependabot PRs |

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
# .github/workflows/release-please.yml
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
    uses: Coalfire-CF/Actions/.github/workflows/release-please.yml@6976ca6fc363706ebbe5a5454a3719436303f027 # v1.1.0
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
    uses: Coalfire-CF/Actions/.github/workflows/ci-terraform-validate.yml@6976ca6fc363706ebbe5a5454a3719436303f027 # v1.1.0
    with:
      terraform_version: '1.15.7' # or omit to use .terraform-version
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}

# Public repo — no app credentials needed
jobs:
  validate:
    uses: Coalfire-CF/Actions/.github/workflows/ci-terraform-validate.yml@6976ca6fc363706ebbe5a5454a3719436303f027 # v1.1.0
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
    uses: Coalfire-CF/Actions/.github/workflows/ci-terraform-docs.yml@6976ca6fc363706ebbe5a5454a3719436303f027 # v1.1.0
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

