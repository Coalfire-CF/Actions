# org-terraform-source-pin — SHA-preferred pin gate

Reusable workflow enforcing **SHA-preferred pinning** (RFC-0008 / ADR-0018) for
both Terraform module `source` `?ref=` values and workflow `uses:` references.

## Classification

**Terraform sources (`scripts/source-pin-check.sh`):**

| Class | Example | Result |
|---|---|---|
| PASS | `source = "github.com/Coalfire-CF/terraform-aws-ec2?ref=<40-hex>" # v2.2.6` | ✅ |
| WARN | `?ref=v2.2.6` (release tag) | ⚠️ transitional (tags are mutable) |
| FAIL | no `?ref=`, `?ref=<branch>`, or bare SHA **without** `# vX.Y.Z` comment | ❌ |

**Workflow `uses:` refs (`scripts/uses-pin-check.sh`):**

| Class | Example | Result |
|---|---|---|
| PASS | `uses: actions/checkout@<40-hex> # v6`, or a local `uses: ./...` ref | ✅ |
| WARN | `uses: actions/setup-python@v5.0.0` (version tag) | ⚠️ transitional |
| FAIL | `@main`/branch, or a bare SHA without a `# vX.Y.Z` comment | ❌ |

## Advisory-first rollout

Both checks share a `strict` input (**default `false`**): FAIL-class findings are
emitted as `::warning` and the job exits 0. Flip `strict: true` on the recorded
promotion (RFC-0008) to enforce (`::error`, exit 1). WARN-class is always a
warning and never fails.

## Caller example

```yaml
jobs:
  source-pin:
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-source-pin.yml@<sha> # v0.7.0
    with:
      scan_root: '.'
      strict: false   # advisory (default)
    secrets:
      SLACK_BOT_TOKEN: ${{ secrets.SLACK_BOT_TOKEN }}
```

Dependabot's `github-actions` ecosystem natively maintains SHA pins and updates
the adjacent version comment; Terraform module `?ref=` SHAs are updated by the
release re-pin procedure.
