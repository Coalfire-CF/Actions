# org-opa — Policy-as-Code Runner (Tier-1 Advisory)

Reusable workflow that runs the org OPA/Rego policy set against a caller's
Terraform. Authority: **ADR-0003** (OPA/Rego is the canonical policy engine) and
MTCS finding **F08**.

## Advisory contract (read this first)

- **Tier-1 is advisory.** By default this workflow **never fails the pipeline** —
  it emits `::warning` / `::notice` annotations only.
- **`blocking: true`** is the **recorded Tier-2 opt-in** (per-domain, never
  global, never silent). Only then does a policy violation fail the job.
- If `policy_ref` is empty or the policy repo/ref is unreachable (e.g. before
  `Coalfire-CF/org-opa-policies` exists), the workflow **skips gracefully** with
  a `::notice` — it does not error.

## What it does

1. Checks out the caller repo and the policy repo (pinned by release SHA — RFC-0008).
2. Installs OPA (pinned `opa_version`).
3. Validates the policy set: `opa fmt --diff`, `opa check`, `opa test -v`.
4. Evaluates `data.terraform.deny` (the org convention for violation messages):
   - **post-plan**: pass `plan_json_artifact` (an uploaded `terraform show -json`).
   - **pre-plan/static**: evaluates any `*.tf.json` found under `working_directory`.

## Inputs

| Input | Default | Notes |
|---|---|---|
| `policy_repo` | `Coalfire-CF/org-opa-policies` | Policy source repo |
| `policy_ref` | `''` | Release **commit SHA** of the policy repo (RFC-0008). Empty = skip |
| `policy_path` | `policies` | Path to `.rego` within the policy repo |
| `plan_json_artifact` | `''` | Artifact name of a Terraform plan JSON (post-plan mode) |
| `working_directory` | `.` | Caller dir to evaluate in pre-plan mode |
| `opa_version` | `0.69.0` | OPA version to install |
| `blocking` | `false` | Tier-2 opt-in: fail on violations |
| `slack_channel_id` | `''` | Failure notification channel (meaningful only when `blocking`) |

## Caller example (advisory)

```yaml
jobs:
  opa:
    uses: Coalfire-CF/Actions/.github/workflows/org-opa.yml@<sha> # v0.7.0
    with:
      policy_ref: <org-opa-policies release SHA> # v0.1.0
    secrets:
      SLACK_BOT_TOKEN: ${{ secrets.SLACK_BOT_TOKEN }}
```

Promotion from advisory (Tier-1) to `blocking: true` (Tier-2) is a recorded,
per-domain decision — see ADR-0003.
