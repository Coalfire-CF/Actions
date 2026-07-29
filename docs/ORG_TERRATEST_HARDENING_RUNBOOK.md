# org-terratest hardening — operator runbook

Privileged / live steps that complete the org-terratest hardening effort — the dedicated App
(#231), the environment gate (#237), the EIP sweep (#273), and the janitor (#234). The
**workflow, tooling, and doc changes have already shipped** on the feature
branch; the steps below are the ones that mutate real GitHub-org / cloud / cross-repo state and
must be executed by an operator with the right credentials, then verified. Each step is idempotent
and re-runnable, and states its own verification.

Order: do the App (1a) and the AWS release-permission check (2a) first — they unblock everything
else. The Environment (1b) is only meaningful once a caller opts in. GCP and Azure live work are
**out of scope for this effort** (backburnered).

---

## 1a. Dedicated Terratest GitHub App (#231)

GitHub App creation has **no REST endpoint** — it is a browser manifest flow, so this is an
operator step, not scriptable.

1. As an org owner, create a GitHub App **`coalfire-terratest`**:
   `https://github.com/organizations/Coalfire-CF/settings/apps/new`
   - **Repository permissions → Contents: Read-only** (nothing else).
   - Uncheck "Webhook → Active".
   - "Where can this be installed": Only on this account.
1. Generate a **private key** (downloads a `.pem`) and note the **Client ID**.
1. Install the App on the org — **All repositories** (or select the `terraform-*` module repos).
1. Set the two org secrets from it (org owner; scope to the module repos that call terratest):

   ```bash
   gh secret set TERRATEST_APP_CLIENT_ID  --org Coalfire-CF --visibility selected --body "<client-id>"
   gh secret set TERRATEST_APP_PRIVATE_KEY --org Coalfire-CF --visibility selected --body "$(cat coalfire-terratest.*.pem)"
   # then grant the repos that need it:
   gh api -X PUT orgs/Coalfire-CF/actions/secrets/TERRATEST_APP_CLIENT_ID/repositories/<repo_id>
   ```

1. **Drop the Option A alias** from each caller's `secrets:` block (the
   `CF_TF_PULL_PRIVATE_APP_*` pass-through) — the org secrets now back the dedicated App directly.

**Verify:** trigger a caller PR that pulls a private sibling module; the "Get GitHub App Token"
and "Configure Git for private modules" steps succeed and `go mod download` pulls the private
module. In the App's **Advanced → Recent Deliveries / installation token log**, confirm the
token was minted by `coalfire-terratest`, not the fleet pull App.

**Rollback:** re-add the Option A alias to callers; the workflow needs no change.

---

## 1b. Protected Environment `terratest-gov` (#237)

The `environment` input has shipped. The Environment itself is **repo-scoped**, so create it on
each repo that will opt in (start with the first adopter). Only meaningful after the workflow
release is pinned by that caller and the caller passes `environment: terratest-gov`.

```bash
REPO=Coalfire-CF/terraform-aws-vpc-nfw
# Create the environment with a required reviewer (a team or user id).
gh api -X PUT "repos/$REPO/environments/terratest-gov" \
  -f 'reviewers[][type]=Team' -F "reviewers[][id]=<cs-aws-codeowners-team-id>" \
  -F 'deployment_branch_policy=null'
# Org setting: require approval for first-time / outside contributors (org → Actions settings).
```

Then in that repo's caller add `with: { environment: terratest-gov }`.

**Verify:** open a PR from a non-maintainer identity; the Terratest job shows **"Waiting for
review"** and no cloud OIDC step runs until a reviewer approves. A maintainer PR still runs (if
the maintainer is an allowed reviewer). Document who may approve in the repo's `test/README.md`.

**Rollback:** delete the environment (`gh api -X DELETE repos/$REPO/environments/terratest-gov`)
and drop the input; the job reverts to ungated.

---

## 2a. Verify `ec2:ReleaseAddress` on the terratest role (#273)

The `nat-eip-sweep` job has shipped (opt-in). It needs `ec2:ReleaseAddress` (+ `DescribeAddresses`,
`DescribeRegions`) on the terratest role. `ec2:*` in the current starter policy already covers it,
but this **cannot be proven on paper** — a normal green run never exercises a release, so IAM
Access-Analyzer tightening (`ORG_TERRATEST_PROVISIONING.md` §4) would silently drop it. Confirm
against the live account:

```bash
# From a session assuming the terratest role in 358745275192 (us-gov-west-1):
aws sts get-caller-identity
# Simulate the release permission without deleting anything:
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws-us-gov:iam::358745275192:role/github-action-test-role \
  --action-names ec2:ReleaseAddress ec2:DescribeAddresses ec2:DescribeRegions \
  --query 'EvaluationResults[].{action:EvalActionName,decision:EvalDecision}' --output table
```

All three must show `allowed`. Then do a **live proof**: enable the sweep on a caller
(`enable_nat_eip_sweep: true` + stamp `RunId` on its NAT EIPs), force a mid-apply cancel, and
confirm the sweep releases the orphan and the run leaves zero unassociated tagged EIPs
(`ORG_TERRATEST.md` → "Run-scoped resource tagging"). Keep the three actions in the enumerated
policy after any Access-Analyzer tightening.

**Verify:** the deliberately-cancelled run's `nat-eip-sweep` job summary shows `released ≥ 1`,
`release failures 0`, `still associated 0`; a follow-up `describe-addresses` shows zero
unassociated addresses tagged that `RunId`.

---

## 2b. Extend the janitor to the general terratest account (#234)

**This is a sub-project, not a config edit — flag before starting.** The existing
`terraform-aws-terratest-janitor` Lambda has scope-specific handlers (`security`, `pca`) covering
Config/GuardDuty/CloudTrail/IAM/KMS/S3/logs and Security-Hub/ACM-PCA respectively. The general
terratest account (`358745275192`) creates **VPC + subnets + NAT + route tables + Network
Firewall + flow-log roles/policies + KMS aliases + log groups + S3** residue — the network
classes are **not** covered by either existing handler. Extending the janitor therefore means:

1. Author a new scope (e.g. `network`/`general`) handler in `modules/janitor/lambda` that reaps
   the VPC-dependency + NFW + flow-log classes, keyed on the same prefix-cohort-abandonment
   safety model (a cohort is swept only when every timestamped sibling is older than
   `abandon_hours`; hard account allowlist twice; loud-on-action-and-failure SNS).
1. Add `358745275192` to the deploy's account allowlist and instantiate the module with the new
   scope; add the general account's suite `resourcePrefix` tokens to `test_prefixes`.
1. Deploy **operator-only** (OAAR from `occ-dev`), supervised `dry_run=true` first, read the
   report, then `dry_run=false`.

**Decision needed** (see the message accompanying this runbook): build the new handler now as a
janitor PR, or keep #234 covered by the shipped per-run NAT-EIP net + the documented manual
break-glass until the network-scope handler is prioritized.

**Verify (once built):** a `dry_run=true` apply's report enumerates only the allowlisted accounts
and lists the intended (not executed) deletions for a known orphaned cohort; the positive control
(non-empty enumeration) passes so an empty result is a hard error, never a silent "clean".

---

## What has already shipped (no operator action)

- `org-terratest.yml`: opt-in `environment` gate, opt-in `nat-eip-sweep` job, durable
  `terratest-record.json` telemetry emit + SHA stamping, opt-in `rerun_fails`.
- `docs/ORG_TERRATEST.md` / `ORG_TERRATEST_PROVISIONING.md`: Option B active, run-scoped tagging,
  protected-environment pattern, flake/quarantine/scheduled guidance, Azure RBAC narrowing note,
  `ec2:ReleaseAddress` tightening warning, reconciled version pins.
- `Coalfire-CF/MTCS`: `tools/terratest_posture.py` + `fleet/TERRATEST-POSTURE.md` + the
  `terratest-posture.yml` CI, and metric #9 wired into `metrics.py`.
- Meta-tests: `tests/nat-eip-sweep.test.sh`, `tests/terratest-telemetry.test.sh`,
  `tests/terratest-rerun.test.sh` (Actions); `tools/test_terratest_posture.py` (MTCS) — all
  mutation-proven.
