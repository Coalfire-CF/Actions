# gate-config.yml — central advisory→blocking switch (RFC-0010)

`gate-config.yml` at this repo's root is the single place that sets the
**blocking default** for the org CI gates. It removes the per-caller edit that
fleet-scaling would otherwise require to promote a gate from warn-only to
blocking.

```yaml
gates:
  source-pin:   { strict: false }
  uses-pin:     { strict: false }
  version-band: { strict: false }
  opa:          { strict: false }  # Tier-2 blocking default only; opa Tier-1 stays advisory (ADR-0003)
```

## How a gate resolves `strict`

Each gate resolves its effective blocking flag with this precedence
(`scripts/gate-config-resolve.sh`):

1. **Caller `strict` input** — if the caller passes `'true'` or `'false'`, it wins
   (a local override, e.g. during a repo's migration).
2. **Central default** — otherwise `gates.<key>.strict` from this file.
3. **`false`** — if the key/file is absent.

A caller leaves `strict: ''` (the default) to defer to the central value.
For `org-opa`, the caller input is named `blocking` and maps to `gates.opa.strict`.

## How the file is read (why not `job_workflow_sha`)

Each gate reads `gate-config.yml` from its own `actions/checkout` of
`Coalfire-CF/Actions` at `inputs.actions_ref` (**default `main`**) — the same
mechanism as `.terraform-version-band`. `github.job_workflow_sha` is **not** used:
a 2026-07-02 spike proved it is empty when a reusable workflow is called
cross-repo (actions/runner#2417).

**Consequence:** because the default ref is `main`, flipping a value here takes
effect **fleet-wide immediately** — no consumer needs to re-pin. A consumer that
wants reproducibility can pin `actions_ref` to a release SHA.

## Promoting a gate (advisory → blocking)

1. Open a PR that flips the gate's value to `strict: true` here.
2. The PR body **must cite the recorded promotion decision** (the ADR-0011
   warn→required cycle; RFC-0008/RFC-0010).
3. Merge on protected `main`. The gate is blocking for every caller on the next
   run. To roll back, flip it to `false` the same way.

Day-one ships **all `false`** (advisory) — no behavior change on adoption.
