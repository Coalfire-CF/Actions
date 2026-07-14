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

All caller examples in this document are drawn from the two **proven, green** callers in the
org and are pinned to the current release **v0.11.3**
(`9451b979c22b3762b3c8a7d4d9493fefaee7edc5`):

- **AWS (GovCloud):** [`terraform-aws-vpc-nfw`](https://github.com/Coalfire-CF/terraform-aws-vpc-nfw)
  `.github/workflows/org-terratest.yml` — the canonical **module-repo self-test** (PR #198).
- **Azure Government:** the `cs-terratest-poc` `terratest-azure.yml` pilot — the org's first
  green Azure Gov lane (now being ported into the module repos it validated).

## How It Fits Into the Pipeline

```text
Pull Request opened (touches *.tf under test)
  |
  ├── terraform-fmt       -- Format check (existing)
  ├── terraform-validate  -- Syntax/config validation (existing)
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
explicitly requested with `-tags terratest` (the workflow does this for you).

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
        // Source a fixture that pins the module at PR HEAD — see the
        // "Module-repo self-test pattern" section below.
        TerraformDir: "fixtures/my-module",
        Vars: map[string]interface{}{
            "resource_prefix": "myci",
        },
    })

    // Destroy infrastructure at the end of the test — deferred BEFORE apply so it
    // runs even when apply or an assertion fails.
    defer terraform.Destroy(t, terraformOptions)

    // Apply the Terraform module
    terraform.InitAndApply(t, terraformOptions)

    // Assert on posture/behavior, not merely that apply succeeded (see below).
    output := terraform.Output(t, terraformOptions, "id")
    assert.NotEmpty(t, output)
}
```

## Module-repo self-test pattern

The canonical layout — proven by
[`terraform-aws-vpc-nfw`](https://github.com/Coalfire-CF/terraform-aws-vpc-nfw) PR #198 — is
for a module repo to **test its own working tree at PR HEAD**. Every PR applies, asserts, and
destroys the code under review in a dedicated cloud test account. This is the pattern all new
module repos should adopt.

### Layout

```text
terraform-aws-vpc-nfw/            # module root == repo root
  ├── main.tf ...                 # the module under test
  └── test/
      ├── go.mod                  # module github.com/Coalfire-CF/<repo>/test
      ├── go.sum                  # complete, committed — CI NEVER mutates it
      ├── vpc_nfw_test.go         # //go:build terratest
      └── fixtures/
          └── vpc-nfw/            # a thin root-module fixture
              ├── main.tf ...     # module "under_test" { source = "../../.." }
              └── *.tf
```

### The five rules

1. **Fixture sources the module at HEAD via a relative path.** The fixture lives at
   `test/fixtures/<name>/` and calls the module with `source = "../../.."` (up three levels:
   `<name>` → `fixtures` → `test` → repo root). This means the test exercises the **working
   tree of the PR**, not a published release — a regression is caught before it ships.

   ```hcl
   module "mgmt_vpc" {
     source = "../../.." # the module at PR HEAD — tests the working tree, not a release
     # ...module inputs...
   }
   ```

1. **`test/go.mod` is re-homed to the repo.** The module path is
   `github.com/Coalfire-CF/<repo>/test` (e.g.
   `github.com/Coalfire-CF/terraform-aws-vpc-nfw/test`), not a scaffold/borrowed path. This
   keeps the test module self-describing and lets Dependabot's `gomod` ecosystem track it.

1. **`go.sum` is complete and committed; CI never mutates it.** Run `go mod tidy` locally and
   commit the full `go.sum`. The workflow does **not** run `go mod tidy` or otherwise write
   `go.sum` — a missing/partial sum fails the run rather than being silently repaired. This
   keeps the dependency set reproducible and reviewable.

1. **Unique `resource_prefix` per repo.** Each module's fixture uses a short prefix unique
   across the fleet (vpc-nfw uses `nfwci`; the storage-account port uses `stci`). Because all
   module repos share **one** cloud test account, colliding names across two repos' concurrent
   runs would clash on globally-scoped resources (KMS aliases, IAM role names, S3 buckets,
   log groups). A per-repo prefix removes the collision.

1. **Assert posture/behavior truth-tables, not apply-success.** A green `terraform apply`
   proves the config is valid, not that it is *correct*. vpc-nfw asserts the NFW routing
   truth-table — firewall subnets hold the IGW default route; public subnets egress via the
   firewall endpoint (**not** directly to an IGW); private subnets have no IGW path — by
   reading route tables back through the AWS API. Azure asserts security posture
   (`min_tls_version == TLS1_2`, HTTPS-only enforced, the Gov-cloud blob endpoint) read back
   through a Terraform data source. Write assertions that would **fail if the module regressed
   its security or routing contract**, even when apply still succeeds.

See [`terraform-aws-vpc-nfw`](https://github.com/Coalfire-CF/terraform-aws-vpc-nfw)
(`test/vpc_nfw_test.go`, `test/fixtures/vpc-nfw/`) as the worked example.

## Calling the Workflow

### AWS (GovCloud) — module self-test

Sourced verbatim from the proven `terraform-aws-vpc-nfw` caller.

```yaml
name: Terratest

# Behavioral test of THIS module at PR HEAD. The fixture under
# test/fixtures/vpc-nfw sources the module via ../../.., so every PR applies,
# asserts, and destroys the working-tree code in the GovCloud test account.

on:
  pull_request:
    branches: [main]
    # Real infra costs real money — only run when the code under test changes.
    # Without this scoping, a docs-only or unrelated PR would trigger a full
    # apply/destroy cycle (real spend) for no coverage gain.
    paths:
      - "**.tf"
      - "**.tfvars"
      - "test/**"
      - ".github/workflows/org-terratest.yml"

permissions:
  contents: read # checkout
  id-token: write # cloud OIDC (a reusable workflow cannot self-grant this)
  pull-requests: write # post the results comment in pr mode

concurrency:
  # One in-flight Terratest run per branch. cancel-in-progress MUST be false:
  # cancelling a run mid-apply/destroy orphans real infrastructure in the test
  # account (see Operational Notes). Superseded *pending* runs are still
  # auto-cancelled by GitHub — only a running apply is protected.
  group: terratest-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: false

jobs:
  terratest:
    uses: Coalfire-CF/Actions/.github/workflows/org-terratest.yml@9451b979c22b3762b3c8a7d4d9493fefaee7edc5 # v0.11.3
    with:
      test_mode: pr
      go_version: "1.26"
      terraform_version: "1.15.7" # org default; module requires ~> 1.10
      test_directory: test
      test_timeout: 45m
      aws_role_arn: arn:aws-us-gov:iam::358745275192:role/github-action-test-role
      aws_region: us-gov-west-1
    secrets:
      # Option A (dev-phase secret aliasing): pass the org private-module pull App
      # through under the TERRATEST_APP_* names org-terratest expects, so the test
      # can `go mod download` private sibling modules. A dedicated Terratest App
      # (Option B) is the go-live hardening — see "GitHub App for Private Module Access".
      TERRATEST_APP_CLIENT_ID: ${{ secrets.CF_TF_PULL_PRIVATE_APP_CLIENTID }}
      TERRATEST_APP_PRIVATE_KEY: ${{ secrets.CF_TF_PULL_PRIVATE_APP_PRIVATE_KEY }}
```

### Azure Government — module self-test

Sourced from the proven `cs-terratest-poc` `terratest-azure.yml` pilot.

```yaml
name: Terratest Azure

# Azure Government behavioral test of THIS module at PR HEAD.

on:
  pull_request:
    branches: [main]
    # Path-scoped so the Azure lane only runs when Azure test surface (or this
    # caller) changes — unrelated PRs no longer trigger a real Azure Gov apply.
    paths:
      - "test/**"
      - "**.tf"
      - ".github/workflows/org-terratest.yml"

permissions:
  contents: read # checkout
  id-token: write # cloud OIDC (a reusable workflow cannot self-grant this)
  pull-requests: write # post the results comment in pr mode

concurrency:
  group: terratest-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: false # never cancel a live apply/destroy mid-flight

jobs:
  terratest-azure:
    uses: Coalfire-CF/Actions/.github/workflows/org-terratest.yml@9451b979c22b3762b3c8a7d4d9493fefaee7edc5 # v0.11.3
    with:
      test_mode: pr
      go_version: "1.26"
      terraform_version: "1.14.9" # match the module's required_version; the org default 1.15.7 may not satisfy ~> 1.14.9
      test_directory: test
      test_timeout: 30m
      azure_environment: azureusgovernment
      # Azure identity UUIDs are identifiers, not secrets — and the `secrets`
      # context is NOT permitted in a reusable-workflow `with:` block, so they are
      # passed as inline literals here (the stored org secrets remain the record).
      azure_client_id: 00000000-0000-0000-0000-000000000000 # app registration client ID
      azure_tenant_id: 00000000-0000-0000-0000-000000000000 # Entra (Gov) tenant ID
      azure_subscription_id: 00000000-0000-0000-0000-000000000000 # target subscription
    secrets:
      # Option A secret aliasing (see AWS example above).
      TERRATEST_APP_CLIENT_ID: ${{ secrets.CF_TF_PULL_PRIVATE_APP_CLIENTID }}
      TERRATEST_APP_PRIVATE_KEY: ${{ secrets.CF_TF_PULL_PRIVATE_APP_PRIVATE_KEY }}
```

`azure_environment` defaults to `azurecloud`. For Azure Government the workflow logs in to
the Gov cloud and exports `ARM_ENVIRONMENT=usgovernment` (plus `ARM_USE_OIDC` and the three
IDs) so the azurerm provider authenticates via the same GitHub OIDC token. The federated
credential on the Azure AD app must be **subject-scoped to this repo's `pull_request` claim**
(`repo:Coalfire-CF/<repo>:pull_request`) — see
[`ORG_TERRATEST_PROVISIONING.md`](./ORG_TERRATEST_PROVISIONING.md).

### GCP Example

```yaml
concurrency:
  group: terratest-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: false

jobs:
  terratest:
    uses: Coalfire-CF/Actions/.github/workflows/org-terratest.yml@9451b979c22b3762b3c8a7d4d9493fefaee7edc5 # v0.11.3
    with:
      test_mode: pr
      go_version: "1.26"
      test_directory: test
      gcp_workload_identity_provider: projects/123456/locations/global/workloadIdentityPools/ci-pool/providers/github
      gcp_service_account: terratest@my-project.iam.gserviceaccount.com
    secrets:
      TERRATEST_APP_CLIENT_ID: ${{ secrets.CF_TF_PULL_PRIVATE_APP_CLIENTID }}
      TERRATEST_APP_PRIVATE_KEY: ${{ secrets.CF_TF_PULL_PRIVATE_APP_PRIVATE_KEY }}
```

### Release Gate

```yaml
name: Release

on:
  release:
    types: [created]

jobs:
  terratest:
    uses: Coalfire-CF/Actions/.github/workflows/org-terratest.yml@9451b979c22b3762b3c8a7d4d9493fefaee7edc5 # v0.11.3
    with:
      test_mode: release
      go_version: "1.26"
      aws_role_arn: arn:aws-us-gov:iam::358745275192:role/github-action-test-role
      aws_region: us-gov-west-1

  release-clean:
    needs: terratest
    uses: Coalfire-CF/Actions/.github/workflows/org-release-clean.yml@9451b979c22b3762b3c8a7d4d9493fefaee7edc5 # v0.11.3
    with:
      tag_name: ${{ github.event.release.tag_name }}
```

In `release` mode the OIDC `sub` claim is `repo:<owner>/<repo>:ref:refs/tags/*`, so the trust
policy / federated credential must include the tag claim in addition to `:pull_request` —
again, see [`ORG_TERRATEST_PROVISIONING.md`](./ORG_TERRATEST_PROVISIONING.md).

## Operational Notes

Hard-won operational behavior — respect these to avoid orphaned infrastructure and wasted
spend.

### Never cancel a run mid-apply — it orphans infrastructure

Terratest destroys via `defer terraform.Destroy()`, which only runs if the Go process is
allowed to finish. **Cancelling a run while `terraform apply` (or `destroy`) is in flight
kills the process before the deferred destroy**, leaking real resources into the test
account. This is why every caller sets `concurrency.cancel-in-progress: false`.

If a run *is* cancelled mid-apply (or times out mid-apply), **sweep the test account by
tag/prefix**. For the AWS GovCloud account, check for leaked:

- VPCs and their dependencies (subnets, NAT gateways, EIPs, route tables)
- KMS **aliases** (the keys go to `PendingDeletion`, but the alias name blocks re-runs)
- CloudWatch **log groups** (`*-flowlogs-*`)
- IAM **flow-log roles/policies** (`*-flowlogs-cloudwatch-*`)
- Network Firewall resources and S3 buckets

For Azure, sweep the ephemeral resource group (`rg-terratest-*`) — deleting the RG reclaims
everything in it.

### Pending-run auto-cancel is safe (and desirable)

GitHub's concurrency group auto-cancels *superseded pending* runs — a run that is queued but
has **not started applying**. That is safe and saves money: only the latest HEAD needs to go
green. Prune redundant queued applies so you don't pay for several full apply/destroy cycles;
the goal is exactly one green run on the final PR HEAD.

### `action_required` approval loops on new/bot-touched repos

On a newly-created repo, or one where a bot (`org-dependabot`, tree-readme) just pushed a
commit, workflow runs stick at `action_required` and must be manually approved:

```bash
gh api -X POST repos/{owner}/{repo}/actions/runs/{run_id}/approve
```

A bot push *after* your approval re-triggers the gate — you may need to approve again. Watch
for a fresh `action_required` run each time the PR head moves.

### `go.sum` is never mutated by CI

The workflow will not run `go mod tidy`. Commit a complete `go.sum` (see the self-test
pattern). A partial sum fails the run instead of being silently repaired — this is deliberate
so the reviewed dependency set is exactly what runs.

## OIDC Setup by Provider

Per-repo OIDC onboarding — trust-policy shapes, the starter least-privilege permission
policy, the Azure federated-credential equivalent, and post-first-green tightening — is
documented in full in the companion runbook:

**➡ [`ORG_TERRATEST_PROVISIONING.md`](./ORG_TERRATEST_PROVISIONING.md)**

The essentials:

- **AWS:** an IAM OIDC provider for `token.actions.githubusercontent.com` plus a role whose
  trust policy `StringLike`-matches `repo:Coalfire-CF/<repo>:pull_request` **and**
  `repo:Coalfire-CF/<repo>:ref:refs/tags/*`, with the `aud` claim pinned to
  `sts.amazonaws.com`. **No wildcards** (`repo:Coalfire-CF/*:*` trusts every repo on any
  event). Pass the role ARN via `aws_role_arn`.
- **Azure:** an App Registration with a **federated credential per claim** — subject
  `repo:Coalfire-CF/<repo>:pull_request` (and a second for `:ref:refs/tags/*`), issuer
  `https://token.actions.githubusercontent.com`, audience `api://AzureADTokenExchange`.
  Pass `azure_client_id` / `azure_tenant_id` / `azure_subscription_id`.
- **GCP:** a Workload Identity Pool + provider with
  `attribute-condition="assertion.repository_owner == 'Coalfire-CF'"`, bound to a
  least-privilege service account. Pass `gcp_workload_identity_provider` /
  `gcp_service_account`.

## Inputs Reference

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `test_mode` | No | `pr` | `pr` posts results to PR comment; `release` gates the pipeline |
| `go_version` | No | `1.23` | Go version for Terratest (proven callers pin `1.26`) |
| `terraform_version` | No | *(auto)* | Terraform version (falls back to `.terraform-version`) |
| `test_directory` | No | `test` | Directory containing Go test files |
| `test_timeout` | No | `30m` | Go test timeout |
| `working_directory` | No | `.` | Working directory |
| `aws_role_arn` | No | | AWS IAM role ARN for OIDC |
| `aws_region` | No | `us-east-1` | AWS region |
| `azure_client_id` | No | | Azure App Registration client ID |
| `azure_tenant_id` | No | | Azure AD tenant ID |
| `azure_subscription_id` | No | | Azure subscription ID |
| `azure_environment` | No | `azurecloud` | Azure cloud environment: `azurecloud` or `azureusgovernment` |
| `gcp_workload_identity_provider` | No | | GCP Workload Identity Provider |
| `gcp_service_account` | No | | GCP service account email |
| `slack_channel_id` | No | | Slack channel for failure notifications |

## Secrets Reference

| Secret | Required | Description |
| --- | --- | --- |
| `TERRATEST_APP_CLIENT_ID` | No | GitHub App client ID for private module access |
| `TERRATEST_APP_PRIVATE_KEY` | No | GitHub App private key for private module access |
| `SLACK_BOT_TOKEN` | No | Slack bot token for failure notifications (required if `slack_channel_id` is set) |

## Important Notes

### Caller Must Grant `id-token: write`

A reusable workflow **cannot** grant itself `id-token: write` — the calling workflow must
declare it in its own top-level `permissions:` block. If it is omitted, every cloud OIDC
step fails with `Unable to load credentials` / `Credentials could not be loaded`. This is
the single most common setup error; the caller examples above all include the required block.

### `workflow_dispatch` Mode Has No Cloud Inputs

The `workflow_dispatch` trigger exposes only `test_mode`, `go_version`, `terraform_version`,
`test_directory`, and `test_timeout` — it has **no** cloud-credential inputs. A manual
dispatch therefore runs a **no-cloud smoke test** only: any test that needs AWS/Azure/GCP
credentials will fail to authenticate. Use the `workflow_call` path (the caller examples
above) for full multi-cloud runs.

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
that take longer to provision (e.g., RDS clusters, GKE clusters, Network Firewall),
increase the timeout (vpc-nfw uses `45m`):

```yaml
with:
  test_timeout: '45m'
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

In `pr` mode, the workflow posts a **sticky** comment (updated in place on every run,
keyed per `test_directory` so multi-lane repos get one comment per lane) with:

- A header line carrying the tested commit SHA, mode, test directory, TF/Go versions,
  and a link to the run
- A summary table (passed/failed/errors/skipped/duration) parsed from the JUnit root
  `<testsuites>` aggregate — `passed = tests − failures − errors − skipped`
- A per-test result table (result icon, test name, duration)
- On failure: the extracted testify/go-test error blocks per failing test, shown
  expanded — no digging through terraform apply logs to find the assertion
- The full output in a collapsible block, ANSI/log-prefix stripped and
  **tail**-truncated at 50k chars (failures live at the end of a test log)

### GitLab Portability

The JUnit XML output (`terratest-results.xml`) is the same format GitLab CI expects in
its `artifacts:reports:junit` configuration. When porting this workflow to `.gitlab-ci.yml`,
point the report path at the same file and GitLab will render test results in merge requests.

## Onboarding Checklist

When adding Terratest to a Terraform module repo:

1. **Create the self-test layout** — `test/go.mod` (re-homed to
   `github.com/Coalfire-CF/<repo>/test`), a complete committed `go.sum`, a `//go:build
   terratest` test file, and a `test/fixtures/<name>/` fixture whose module `source` is
   `../../..` (see "Module-repo self-test pattern")
1. **Pick a unique `resource_prefix`** not used by any other repo in the fleet
1. **Add `gomod` to the repo's `dependabot.yml`** so Go dependencies are kept up to date:

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

   If you use the `org-dependabot.yml` refresh workflow, this is auto-detected from
   `test/go.mod`.
1. **Provision OIDC trust** in the target cloud (see
   [`ORG_TERRATEST_PROVISIONING.md`](./ORG_TERRATEST_PROVISIONING.md))
1. **Add the caller workflow** with `paths` scoping, a `concurrency` block
   (`cancel-in-progress: false`), and the `permissions` block including `id-token: write`
1. **Open a PR and shepherd the run to green** — approve any `action_required` gate, prune
   redundant queued applies, never cancel mid-apply

## GitHub App for Private Module Access

If your Terraform modules reference other private modules in the org, the workflow needs
a GitHub App token to authenticate `go mod download` against private repos.

**Option A (dev-phase, in use today):** alias the existing org private-module pull App into
the names org-terratest expects, right in the caller's `secrets:` block:

```yaml
    secrets:
      TERRATEST_APP_CLIENT_ID: ${{ secrets.CF_TF_PULL_PRIVATE_APP_CLIENTID }}
      TERRATEST_APP_PRIVATE_KEY: ${{ secrets.CF_TF_PULL_PRIVATE_APP_PRIVATE_KEY }}
```

This reuses an already-provisioned App, so no new registration is needed to get a lane green.
Note these org secrets are **selected-repos scoped** — a brand-new repo may need to be added
to each secret's repository list before the pull works.

**Option B (go-live hardening): a dedicated Terratest App.** Create a purpose-built App so the
Terratest token is minimal, separately audited, and independently revocable:

- **Minimal permissions** — the app only needs `Contents: read` to pull module source
- **Separate audit trail** — Terratest token usage is logged independently from plan/apply
- **Independent revocation** — rotating or revoking the Terratest app doesn't break other workflows

**Setup steps:**

1. Create a GitHub App in the org with **Repository permissions: Contents → Read**
1. Install the app on the org (all repos, or select repos that contain Terraform modules)
1. Set the app's client ID and private key as **org-level secrets**
   (`TERRATEST_APP_CLIENT_ID`, `TERRATEST_APP_PRIVATE_KEY`)
1. Calling repos pass these secrets through to the workflow (see examples above)
