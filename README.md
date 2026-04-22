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
| Terraform Docs | `org-terraform-docs.yml` | Auto-generate and commit terraform-docs output |
| Terraform Plan | `org-terraform-plan.yml` | Terraform plan with PR comment |
| Terraform Apply | `org-terraform-apply.yml` | Terraform apply (manual trigger or post-merge) |
| Markdown Lint | `org-markdown-lint.yml` | Lint changed markdown files with markdownlint-cli2 |
| Tree README | `org-tree-readme.yml` | Auto-generate and commit directory tree in README |
| Dependabot Refresh | `org-dependabot.yml` | Auto-detect ecosystems and regenerate dependabot.yml |
| Dependabot Auto-Merge | `org-dependabot-auto-merge.yml` | Evaluate and auto-merge non-terraform Dependabot PRs ([docs](docs/ORG_DEPENDABOT_AUTO_MERGE.md)) |
| Label Sync | `org-label-sync.yml` | Sync Dependabot auto-merge label taxonomy to downstream repos ([taxonomy](docs/ORG_LABEL_TAXONOMY.md)) |
| Trivy Exception Review | `org-trivy-exception-review.yml` | Weekly review of Trivy `.trivyignore` exceptions |

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
| Azure Deploy | `org-azure-deploy.yml` | **Deprecated** — Legacy Azure deployment example. Do not use as a template. |
| Local Release | `release.yml` | Release workflow for the Actions repo itself |

## Usage

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
  actions: read

jobs:
  create-release:
    uses: Coalfire-CF/Actions/.github/workflows/org-release.yml@main
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
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-validate.yml@main
    with:
      terraform_version: '1.13.3'
    secrets:
      APP_CLIENT_ID: ${{ secrets.APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}

# Public repo — no app credentials needed
jobs:
  validate:
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-validate.yml@main
    with:
      terraform_version: '1.13.3'
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
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-docs.yml@main
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
