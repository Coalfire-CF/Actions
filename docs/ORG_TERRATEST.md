# Terratest Integration Testing

## What This Does

> **This workflow runs Terratest integration tests against Terraform modules.**
>
> Terratest (a Go library) handles the full Terraform lifecycle — `init`, `apply`, verify,
> `destroy` — inside Go test functions. The workflow sets up the environment (Go, Terraform,
> cloud credentials via OIDC) and runs tests via `gotestsum`, which wraps `go test` and
> produces JUnit XML and JSON reports alongside human-readable output.
>
> **Real infrastructure is created and destroyed during each test run.** Ensure your OIDC
> roles are scoped to dedicated test accounts/subscriptions with appropriate spending limits.

## How It Fits Into the Pipeline

```text
Pull Request opened (touches *.tf)
  |
  ├── terraform-fmt       -- Format check (existing)
  ├── terraform-validate  -- Syntax/config validation (existing)
  ├── terraform-plan      -- Plan against real backend (existing)
  └── terratest           -- Full apply/verify/destroy (THIS WORKFLOW)

Release created
  |
  ├── terratest (release) -- Gate: tests must pass before signing
  ├── release-clean       -- Build cleaned tarball
  ├── trivy-scan          -- Security scan
  ├── gitleaks-scan       -- Secret detection
  └── cosign-sign         -- Sign artifacts (only if all gates pass)
```

## Test File Convention

All Terratest files **must** use the `terratest` build tag. This prevents accidental
execution during normal `go test ./...` runs — infrastructure tests only run when
explicitly requested with `-tags terratest`.

```go
//go:build terratest

package test

import (
    "testing"

    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestMyModule(t *testing.T) {
    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "../",
        Vars: map[string]interface{}{
            "name": "terratest-example",
        },
    })

    // Destroy infrastructure at the end of the test
    defer terraform.Destroy(t, terraformOptions)

    // Apply the Terraform module
    terraform.InitAndApply(t, terraformOptions)

    // Validate outputs
    output := terraform.Output(t, terraformOptions, "id")
    assert.NotEmpty(t, output)
}
```

### Directory Structure

Calling repositories should follow this layout:

```text
my-terraform-module/
  ├── main.tf
  ├── variables.tf
  ├── outputs.tf
  ├── .terraform-version
  └── test/
      ├── go.mod
      ├── go.sum
      └── my_module_test.go    # //go:build terratest
```

Initialize the test module:

```bash
cd test/
go mod init github.com/Coalfire-CF/terraform-<provider>-<name>/test
go get github.com/gruntwork-io/terratest/modules/terraform
go get github.com/stretchr/testify/assert
```

## Calling the Workflow

### PR Testing (AWS Example)

```yaml
name: CI

on:
  pull_request:
    paths:
      - '**.tf'
      - 'test/**'

# Caller must grant id-token: write for OIDC to work in the reusable workflow
permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  fmt:
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-fmt.yml@main

  validate:
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-validate.yml@main

  plan:
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-plan.yml@main
    with:
      aws_role_arn: arn:aws:iam::123456789012:role/terratest-ci
      aws_region: us-east-1
      backend_config: bucket=my-state-bucket,key=my-module/terraform.tfstate

  terratest:
    needs: [fmt, validate, plan]
    uses: Coalfire-CF/Actions/.github/workflows/org-terratest.yml@main
    with:
      test_mode: pr
      aws_role_arn: arn:aws:iam::123456789012:role/terratest-ci
      aws_region: us-east-1
    secrets:
      TERRATEST_APP_CLIENT_ID: ${{ secrets.TERRATEST_APP_CLIENT_ID }}
      TERRATEST_APP_PRIVATE_KEY: ${{ secrets.TERRATEST_APP_PRIVATE_KEY }}
```

### PR Testing (Azure Example)

```yaml
  terratest:
    needs: [fmt, validate, plan]
    uses: Coalfire-CF/Actions/.github/workflows/org-terratest.yml@main
    with:
      test_mode: pr
      azure_client_id: 00000000-0000-0000-0000-000000000000
      azure_tenant_id: 00000000-0000-0000-0000-000000000000
      azure_subscription_id: 00000000-0000-0000-0000-000000000000
    secrets:
      TERRATEST_APP_CLIENT_ID: ${{ secrets.TERRATEST_APP_CLIENT_ID }}
      TERRATEST_APP_PRIVATE_KEY: ${{ secrets.TERRATEST_APP_PRIVATE_KEY }}
```

### PR Testing (GCP Example)

```yaml
  terratest:
    needs: [fmt, validate, plan]
    uses: Coalfire-CF/Actions/.github/workflows/org-terratest.yml@main
    with:
      test_mode: pr
      gcp_workload_identity_provider: projects/123456/locations/global/workloadIdentityPools/ci-pool/providers/github
      gcp_service_account: terratest@my-project.iam.gserviceaccount.com
    secrets:
      TERRATEST_APP_CLIENT_ID: ${{ secrets.TERRATEST_APP_CLIENT_ID }}
      TERRATEST_APP_PRIVATE_KEY: ${{ secrets.TERRATEST_APP_PRIVATE_KEY }}
```

### Release Gate

```yaml
name: Release

on:
  release:
    types: [created]

jobs:
  terratest:
    uses: Coalfire-CF/Actions/.github/workflows/org-terratest.yml@main
    with:
      test_mode: release
      aws_role_arn: arn:aws:iam::123456789012:role/terratest-ci
      aws_region: us-east-1

  release-clean:
    needs: terratest
    uses: Coalfire-CF/Actions/.github/workflows/org-release-clean.yml@main
    with:
      tag_name: ${{ github.event.release.tag_name }}
```

## OIDC Setup by Provider

All three providers use the same concept: GitHub mints a short-lived OIDC token for the
workflow run, and the cloud provider exchanges it for temporary credentials. No long-lived
secrets are stored in GitHub.

### AWS

1. Create an IAM OIDC Identity Provider for `token.actions.githubusercontent.com`
2. Create an IAM role with a trust policy scoping to your org/repo:
   ```json
   {
     "Effect": "Allow",
     "Principal": {
       "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
     },
     "Action": "sts:AssumeRoleWithWebIdentity",
     "Condition": {
       "StringEquals": {
         "token.actions.githubusercontent.com:sub": "repo:Coalfire-CF/terraform-aws-my-module:ref:refs/heads/main"
       }
     }
   }
   ```
   > **Scope the trust policy to specific repos and ref types.** Using a wildcard like
   > `repo:Coalfire-CF/*:*` trusts every repo in the org on any branch or PR — any contributor
   > who can open a PR could assume the role. Prefer `StringEquals` with an explicit repo and
   > ref pattern. If you need org-wide trust, at minimum restrict to `ref:refs/heads/*` to
   > exclude pull request refs.
3. Attach only the permissions the module under test needs (least privilege)
4. Pass the role ARN via the `aws_role_arn` input

### Azure

1. Register an App (or use an existing Service Principal) in Azure AD
2. Add a Federated Credential:
   - Issuer: `https://token.actions.githubusercontent.com`
   - Subject: `repo:Coalfire-CF/<repo>:ref:refs/heads/*` (or scope to specific branches)
   - Audience: `api://AzureADTokenExchange`
3. Grant the Service Principal RBAC roles on the target subscription (least privilege)
4. Pass `azure_client_id`, `azure_tenant_id`, and `azure_subscription_id` as inputs

### GCP

1. Create a Workload Identity Pool:
   ```bash
   gcloud iam workload-identity-pools create "ci-pool" \
     --location="global" \
     --display-name="CI Pool"
   ```
2. Create a Provider in the pool:
   ```bash
   gcloud iam workload-identity-pools providers create-oidc "github" \
     --location="global" \
     --workload-identity-pool="ci-pool" \
     --issuer-uri="https://token.actions.githubusercontent.com" \
     --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
     --attribute-condition="assertion.repository_owner == 'Coalfire-CF'"
   ```
3. Bind a service account:
   ```bash
   gcloud iam service-accounts add-iam-policy-binding "terratest@PROJECT.iam.gserviceaccount.com" \
     --role="roles/iam.workloadIdentityUser" \
     --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/ci-pool/attribute.repository/Coalfire-CF/REPO"
   ```
4. Pass `gcp_workload_identity_provider` and `gcp_service_account` as inputs

## Inputs Reference

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `test_mode` | No | `pr` | `pr` posts results to PR comment; `release` gates the pipeline |
| `go_version` | No | `1.23` | Go version for Terratest |
| `terraform_version` | No | *(auto)* | Terraform version (falls back to `.terraform-version`) |
| `test_directory` | No | `test` | Directory containing Go test files |
| `test_timeout` | No | `30m` | Go test timeout |
| `working_directory` | No | `.` | Working directory |
| `aws_role_arn` | No | | AWS IAM role ARN for OIDC |
| `aws_region` | No | `us-east-1` | AWS region |
| `azure_client_id` | No | | Azure App Registration client ID |
| `azure_tenant_id` | No | | Azure AD tenant ID |
| `azure_subscription_id` | No | | Azure subscription ID |
| `gcp_workload_identity_provider` | No | | GCP Workload Identity Provider |
| `gcp_service_account` | No | | GCP service account email |
| `slack_channel_id` | No | | Slack channel for failure notifications |

## Secrets Reference

| Secret | Required | Description |
| --- | --- | --- |
| `TERRATEST_APP_CLIENT_ID` | No | GitHub App client ID for private module access |
| `TERRATEST_APP_PRIVATE_KEY` | No | GitHub App private key for private module access |

## Important Notes

### Destroy Is Your Responsibility

Terratest handles infrastructure cleanup via `defer terraform.Destroy(t, opts)` in Go test
code. **Every test function must call `defer terraform.Destroy()` before `InitAndApply()`.**
If you forget, resources will leak when tests fail.

```go
// Correct — destroy runs even if apply or assertions fail
defer terraform.Destroy(t, terraformOptions)
terraform.InitAndApply(t, terraformOptions)
```

### terraform_wrapper Must Be Disabled

The workflow sets `terraform_wrapper: false` when installing Terraform. This is required
because Terratest calls the `terraform` binary directly and parses its stdout. The
HashiCorp wrapper injects extra formatting that breaks Terratest's output parsing.

### Test Accounts Should Be Isolated

OIDC roles should point to dedicated test accounts/subscriptions/projects that are:
- Isolated from production workloads
- Scoped with least-privilege IAM (only what the module needs)
- Monitored for cost anomalies (runaway tests can be expensive)
- Subject to resource quotas where possible

### Timeout Tuning

The default 30-minute timeout works for most modules. If your module creates resources
that take longer to provision (e.g., RDS clusters, GKE clusters), increase the timeout:

```yaml
with:
  test_timeout: '1h'
```

## Test Output and Artifacts

The workflow uses `gotestsum` as the test runner. `gotestsum` wraps `go test` — your test
code doesn't change — but produces structured output that's portable across CI systems.

### What Gets Generated

| Artifact | Format | Purpose |
| --- | --- | --- |
| `terratest_output.txt` | Plain text | Human-readable verbose output (same as `go test -v`) |
| `terratest-results.xml` | JUnit XML | Machine-readable test report — GitHub Actions and GitLab CI both render this natively |
| `terratest-results.json` | JSON (one event per line) | Structured log for custom parsing, dashboards, or trend analysis |

All three are uploaded as workflow artifacts and retained for 30 days.

### PR Comments

In `pr` mode, the workflow posts a comment with:
- A summary table (tests/passed/failed/skipped/duration) parsed from the JUnit XML
- The full verbose output in a collapsible details block (truncated at 55k chars)

### GitLab Portability

The JUnit XML output (`terratest-results.xml`) is the same format GitLab CI expects in
its `artifacts:reports:junit` configuration. When porting this workflow to `.gitlab-ci.yml`,
point the report path at the same file and GitLab will render test results in merge requests.

## Onboarding Checklist

When adding Terratest to a Terraform module repo:

1. **Create the test directory** with `go.mod`, `go.sum`, and test files (see Directory Structure above)
2. **Add `gomod` to the repo's `dependabot.yml`** so Go dependencies are kept up to date:
   ```yaml
   - package-ecosystem: "gomod"
     directory: "/test"
     schedule:
       interval: "weekly"
     commit-message:
       prefix: "chore"
       include: "scope"
     labels:
       - "dep/gomod"
   ```
   If you use the `org-dependabot.yml` refresh workflow, this will be auto-detected from `test/go.mod`.
3. **Set up OIDC trust** in the target cloud provider (see OIDC Setup by Provider above)
4. **Add the caller workflow** to `.github/workflows/ci.yml` (see Calling the Workflow above)
5. **Ensure the caller workflow includes `permissions`** with `id-token: write` — OIDC will fail without it

## GitHub App for Private Module Access

If your Terraform modules reference other private modules in the org, the workflow needs
a GitHub App token to authenticate `go mod download` against private repos.

**Recommended setup: create a dedicated GitHub App for Terratest** rather than reusing the
plan or apply app. This gives you:

- **Minimal permissions** — the app only needs `Contents: read` to pull module source
- **Separate audit trail** — Terratest token usage is logged independently from plan/apply
- **Independent revocation** — rotating or revoking the Terratest app doesn't break other workflows

**Setup steps:**

1. Create a GitHub App in the org with **Repository permissions: Contents → Read**
2. Install the app on the org (all repos, or select repos that contain Terraform modules)
3. Set the app's client ID and private key as **org-level secrets**:
   - `TERRATEST_APP_CLIENT_ID`
   - `TERRATEST_APP_PRIVATE_KEY`
4. Calling repos pass these secrets through to the workflow (see examples above)
