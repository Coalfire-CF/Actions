# ci-security-govulncheck: Go vulnerability scan

Reusable workflow that runs [govulncheck](https://go.dev/doc/security/vuln/)
against a Go module. The Trivy reusable only scans Terraform files, so this is
the dependency vulnerability scan for Go repos.

govulncheck reports only vulnerabilities in code your module can reach. A
vulnerable package that nothing calls does not fail the job. Any reachable
finding does, and the log names the vulnerable function and the fixed version.

## Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `working_directory` | `.` | Directory that holds `go.mod`. The job fails if `go.mod` is not there, so a wrong path cannot pass by scanning nothing. |
| `go_version_file` | empty | Go version file, relative to the repo root. Empty means `go.mod` in `working_directory`. |
| `slack_channel_id` | empty | Slack channel for failure notifications. Needs the `SLACK_BOT_TOKEN` secret. |

## Pins

- govulncheck `v1.8.0`, set in `GOVULNCHECK_VERSION` in the workflow. The
  vulnerability database is fetched on every run, so new advisories apply
  without a bump. Bump the tool by editing that value.
- `actions/checkout` and `actions/setup-go` are pinned by SHA like every other
  `uses:` in this repo.

## Caller example

Add `.github/workflows/ci-security-govulncheck.yml` to the Go repo:

```yaml
name: "CI: Security Govulncheck"

on:
  pull_request:
    branches: [main]
  schedule:
    - cron: '17 6 * * 1'   # weekly: new advisories can land with no code change

permissions:
  contents: read

jobs:
  govulncheck:
    name: Run govulncheck
    uses: Coalfire-CF/Actions/.github/workflows/ci-security-govulncheck.yml@<sha> # v0.7.0
    with:
      working_directory: '.'
```

Pin `<sha>` to the release that contains this workflow, with the `# vX.Y.Z`
comment (RFC-0008).

Repos that use private Go modules need `GOPRIVATE` and git credentials, which
this workflow does not set up.
