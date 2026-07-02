# org-terraform-version-band — Terraform version band gate

Reusable workflow enforcing the org-wide Terraform version band
**`>= 1.15.7, < 2.0.0`** (RFC-0004 / ADR-0013). The band is authoritative in
this repo's [`.terraform-version-band`](../.terraform-version-band) mirror and is
read alongside `scripts/version-band-check.sh` from a checkout of this repo, so
the band and the check are co-versioned.

## What it checks (in the caller repo)

| Declaration | Rule |
|---|---|
| `.terraform-version` | must be a concrete `X.Y.Z` inside the band |
| CI `terraform_version:` pins | concrete `X.Y.Z` inside the band |
| Terraform `required_version = "…"` | must be **upper-bounded** (`<` or `~>`) and anchored in band; open-ended constraints (e.g. `>= 1.15.7`) fail |

`vendor/`, `.terraform/`, and `example(s)/` trees are excluded.

## Advisory-first rollout

`strict` input (**default `false`**): findings emit `::warning` and the job exits
0. Flip `strict: true` on the recorded promotion (ADR-0013) to enforce. The
companion `org-terraform-version-check.yml` auto-bump bot respects the ceiling:
it skips the bump PR and annotates when the latest Terraform is at/above the
band ceiling (a band raise is a manual RFC-0004/ADR-0013 decision).

## Caller example

```yaml
jobs:
  version-band:
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-version-band.yml@<sha> # v0.7.0
    with:
      strict: false   # advisory (default)
    secrets:
      SLACK_BOT_TOKEN: ${{ secrets.SLACK_BOT_TOKEN }}
```
