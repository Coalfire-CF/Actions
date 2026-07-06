# Gate promotion runbook — advisory → `strict: true` (RFC-0010)

This is the execution procedure for grade-A plan item #16 (MTCS
`governance/reviews/2026-07-06-actions-platform-grade-a-plan.md`). Promotion is
**enforcement, not new tech** — but a flip here is **fleet-wide-instant**: every
gate caller checks out this repo at `inputs.actions_ref || 'main'` and reads
`gate-config.yml` from it, so SHA-pinning the *workflow* does NOT pin the
gate-config *content*. There is no canary. The only safety mechanisms are the
telemetry window before the flip and the equally-instant flip-back after it.

## Hard prerequisites (both landed before any flip)

1. **Parser fail-closed** — `scripts/gate-config-resolve.sh` parses block-style
   and exits non-zero on a present-but-unparseable `strict` (plan item #5,
   shipped). Without it, a well-intentioned reformat of `gate-config.yml` during
   promotion silently fails **open**.
2. **Fail-open telemetry** — the MTCS `fleet_posture.py` `fail_open` signal +
   N4 detector (plan item #15) is live and aggregating, so "zero fail-open
   findings" is a measurable claim, not a hope.

## Per-gate promotion procedure (one gate at a time — mandatory, not stylistic)

1. **Qualify the window:** the gate shows **zero fail-open findings for ≥ 14
   days (≥ 1 full release cycle)** in the MTCS fleet-posture telemetry
   (`fleet/FLEET-POSTURE.md` fail-open section). A single standing finding
   disqualifies — fix the repo or record a scoped exception first.
2. **Open the promotion PR:** flips exactly one value in `gate-config.yml` to
   `{ strict: true }`, **keeping inline-flow shape**. The PR body must contain:
   - the recorded promotion decision citation (RFC-0010 / ADR-0011),
   - the telemetry-window evidence (dates + zero-count source),
   - a named **rollback owner** who can merge the flip-back PR same-day.
3. **Merge on green** (protected main; the `test-scripts.yml` meta-tests cover
   the resolver; a block-style reformat is rejected by the parser tests).
4. **Watch the fleet:** monitor the fleet-posture signal for a breakage spike
   over the next scheduled sweeps. Rollback = the same one-line PR flipping back
   to `false` — also fleet-wide-instant.
5. **Cool-down:** do not promote the next gate until the previous flip has a
   clean sweep behind it.

## Promotion order (recommended)

| Order | Gate | Rationale |
| --- | --- | --- |
| 1 | `source-pin` | Longest-baked signal; pin-hygiene scoreboard already tracked in MTCS fleet posture |
| 2 | `uses-pin` | Same mechanics as source-pin; small blast radius after 1 proves the path |
| 3 | `version-band` | Version drift is visible/fixable per-repo with the version-check PR flow |
| — | `opa` | **Tier-1 stays advisory by design (ADR-0003)** — the central default here is the Tier-2 opt-in only; do not blanket-promote |

## Current status

- All four gates ship `strict: false` (advisory). No flips have been executed.
- Item #5 (parser) — ✅ shipped. Item #15 (telemetry) — see MTCS repo.
- The 14-day qualifying window starts when the fail-open signal goes live; the
  first flip PR may be opened once gate 1 qualifies.
