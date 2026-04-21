# Dependabot Auto-Merge

> **Note**: This is a highly custom workflow that requires a dedicated AWS account
> with OIDC federation, an S3 cache bucket, Bedrock model access, and a GitHub App
> for PR approvals. External consumers would need to replicate this infrastructure
> to use it.

Automated triage and merge for Dependabot PRs across the organization. Non-terraform
dependency updates are evaluated for supply chain risks and breaking changes, then
auto-merged when safe. Terraform module and provider bumps are labeled for manual
review until unit testing infrastructure is in place.

## How It Works

```text
Dependabot PR opened
  -> classify (ecosystem, dep name, versions)
  -> terraform? -> label merge/skipped + blocked/terraform-no-tests -> STOP
  -> non-terraform:
       -> supply_chain_check (OSV.dev + OpenSSF Scorecard)       \  parallel
       -> breaking_change_check (semver + Bedrock changelog       /
            + repo usage analysis for applicability)
       -> decide:
            all green  -> merge/approved -> approve + auto-merge
            concerns   -> merge/blocked  -> label reasons + comment
```

### Breaking Change Analysis

The breaking change check does more than semver detection. It:

1. **Fetches upstream release notes** from GitHub releases, with expanded tag format
   matching (e.g. Dependabot reports version `9` but the release tag is `v9.0.0`)
2. **Gathers usage context** by checking out the consuming repo's default branch and
   searching for how the dependency is actually used (inline scripts, imports, etc.)
3. **Sends both to Bedrock** so the model can assess whether breaking changes in the
   release notes actually affect this specific repo's usage patterns
4. **Returns an `applies_to_repo` flag** alongside the generic breaking change analysis

## Prerequisites

### 1. GitHub App (required)

Create a dedicated GitHub App for PR approval and auto-merge:

- **Permissions**: Pull Requests (read/write), Contents (read)
- **Installation**: Install on your GitHub organization
- **Secrets**: Store as org-level secrets:
  - `AUTOMERGE_CLIENT_ID` - The App client ID
  - `AUTOMERGE_APP_PRIVATE_KEY` - The PEM private key

The App is required because `GITHUB_TOKEN` cannot approve PRs authored by
`dependabot[bot]` when branch protection requires non-bot approvals.

### 2. AWS OIDC Role (required)

Create an IAM role for GitHub Actions OIDC with these permissions:

**Trust policy** (scoped to all org repos):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:<YOUR_ORG>/*:*"
      },
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      }
    }
  }]
}
```

**Permissions policy** (least privilege):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3CacheReadWrite",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::<YOUR_CACHE_BUCKET>/analyses/*"
    },
    {
      "Sid": "S3CacheList",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::<YOUR_CACHE_BUCKET>",
      "Condition": {
        "StringLike": { "s3:prefix": "analyses/*" }
      }
    },
    {
      "Sid": "BedrockInvoke",
      "Effect": "Allow",
      "Action": "bedrock-runtime:Converse",
      "Resource": [
        "arn:aws:bedrock:<REGION>:<ACCOUNT_ID>:inference-profile/<MODEL_ID>",
        "arn:aws:bedrock:*::foundation-model/<MODEL_ID>"
      ]
    }
  ]
}
```

Store the role ARN as an org-level secret: `AUTOMERGE_DEPENDABOT_ROLE_ARN`

### 3. S3 Cache Bucket (required)

Create an S3 bucket for cross-repo analysis caching:

- **Name**: Customize via `s3_cache_bucket` input
- **Encryption**: SSE-S3
- **Access**: Private (no public access)
- **Lifecycle**: Expire objects after 90 days

The cache uses a two-tier layout to share universal data across repos while keeping
repo-specific analysis scoped:

```text
s3://<your-cache-bucket>/
├── analyses/shared/{dep-name}/{version}.json       # OSV, scorecard, semver, changelog
└── analyses/repos/{owner--repo}/{dep-name}/{version}.json  # applies_to_repo, repo-specific summary
```

**Shared tier**: Supply chain checks (OSV vulns, Scorecard) and generic changelog
analysis are the same regardless of which repo bumps the dependency. These are written
once and reused across all repos.

**Repo tier**: Whether a breaking change actually affects a given repo depends on how
that repo uses the dependency. This is stored per-repo. On a shared cache hit with a
repo cache miss, a lightweight Bedrock call assesses applicability using the repo's
usage context without re-analyzing the full changelog.

### 4. Bedrock Model Access (required)

Ensure the AWS account has Bedrock model access enabled for the configured model.
The OIDC role must have `bedrock-runtime:Converse` permissions.

### 5. Labels (required)

Run the label sync workflow on each repo before enabling auto-merge:

```yaml
jobs:
  sync-labels:
    uses: <YOUR_ORG>/Actions/.github/workflows/org-label-sync.yml@main
    secrets: inherit
```

See [ORG_LABEL_TAXONOMY.md](ORG_LABEL_TAXONOMY.md) for the full label reference.

## Usage

Add this workflow to each downstream repo as `.github/workflows/dependabot-auto-merge.yml`:

```yaml
name: Dependabot Auto-Merge
on:
  pull_request_target:
    types: [opened, synchronize, reopened]

jobs:
  auto-merge:
    if: github.actor == 'dependabot[bot]'
    uses: <YOUR_ORG>/Actions/.github/workflows/org-dependabot-auto-merge.yml@main
    secrets: inherit
```

> **Important**: Use `pull_request_target` (not `pull_request`) so the workflow has
> write permissions on Dependabot PRs. The workflow only checks out the default branch
> for usage analysis — it never executes code from the PR branch.

Requires the org-level setting **"Send secrets to workflows from pull requests
created by Dependabot"** to be enabled under Org Settings > Actions > General.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `aws_region` | No | `us-east-1` | AWS region for OIDC, S3, and Bedrock |
| `s3_cache_bucket` | No | `my-dependabot-cache` | S3 bucket for analysis cache |
| `scorecard_threshold` | No | `5` | Minimum OpenSSF Scorecard score (0-10) |
| `auto_merge_method` | No | `squash` | Merge method: merge, squash, or rebase |
| `bedrock_model_id` | No | `us.anthropic.claude-haiku-4-5-20251001-v1:0` | Bedrock model ID for changelog analysis |
| `cache_ttl_days` | No | `30` | Days before cached analysis expires |
| `slack_channel_id` | No | - | Slack channel for failure alerts |

## Secrets

| Secret | Required | Description |
|--------|----------|-------------|
| `AUTOMERGE_DEPENDABOT_ROLE_ARN` | **Yes** | IAM role ARN for OIDC (S3 + Bedrock) |
| `AUTOMERGE_CLIENT_ID` | **Yes** | GitHub App client ID |
| `AUTOMERGE_APP_PRIVATE_KEY` | **Yes** | GitHub App PEM private key |
| `SLACK_BOT_TOKEN` | No | Slack bot token for failure notifications |

## Decision Matrix

| Condition | Decision | Labels Applied |
|-----------|----------|---------------|
| Terraform module/provider | Skip | `merge/skipped`, `blocked/terraform-no-tests` |
| All checks green (patch/minor, no vulns, good scorecard, no breaking changes) | Approve + auto-merge | `merge/approved`, `risk/low` |
| Known vulnerability | Block | `merge/blocked`, `risk/high`, `blocked/known-vuln` |
| Low scorecard | Block | `merge/blocked`, `risk/high`, `blocked/low-scorecard` |
| Major version bump | Block | `merge/blocked`, `risk/high`, `blocked/major-bump` |
| Breaking change in changelog | Block | `merge/blocked`, `risk/high`, `blocked/breaking-change` |

## Example: Blocked PR Comment

When a PR is blocked, the workflow posts a comment with the blocking reasons and
the Bedrock analysis. This example is from a `actions/github-script` 8 -> 9 major
bump:

> ### Auto-Merge Blocked
>
> **actions/github-script@9** did not pass automated checks.
>
> #### Blocking Reasons
>
> - `blocked/major-bump`
>
> #### Analysis
>
> While the current scripts only use the standard injected `github` object
> (which should continue to work), the upgrade to ESM-only @actions/github v9
> could introduce compatibility issues and requires verification that the
> `github` object remains properly injected.
>
> Please review and merge manually if appropriate.

The analysis references the repo's actual usage because the workflow checks out the
default branch and searches for how the dependency is used before calling Bedrock.

## Cost Estimate

With ~2,700 Dependabot PRs/month and ~80% cache hit rate at steady state:

- **Bedrock (Haiku 4.5)**: ~$0.50-2.00/month
- **S3**: Negligible (tiny JSON files)
- **GitHub Actions**: Minimal (API calls only, no builds)

## Security Controls

| NIST 800-53 | Implementation |
|-------------|---------------|
| AC-6 (Least Privilege) | Per-job permissions, scoped OIDC role, dedicated Bedrock-only policy |
| AU-3 (Audit) | All decisions recorded as PR labels and step summaries |
| IA-2 (Identification) | OIDC for AWS, GitHub App for approvals |
| SC-28 (Data at Rest) | S3 SSE encryption for cache bucket |
| SI-7 (Software Integrity) | All actions SHA-pinned, OSV + Scorecard checks |
| SI-10 (Input Validation) | All expressions via env blocks, jq for JSON construction |
| CM-3 (Change Control) | Major bumps blocked, breaking changes detected, terraform gated |
| SA-11 (Supply Chain) | Multi-layer: OSV vulns, Scorecard posture, Bedrock changelog analysis |

## Rollout

1. Run `org-label-sync.yml` on target repos
2. Enable on a few repos in dry-run (observe labels, no auto-merge)
3. Enable auto-merge on those repos, monitor for 1 week
4. Expand to remaining repos
