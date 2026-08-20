# Actions fleet audit — 2026-08-20 evidence snapshot

Live read-only sweep of non-archived, non-fork `Coalfire-CF` repos against Actions `v0.18.1` (`23c6c8bc526102ed041f2e08a363e5ea2c2f0ec4`).

**Canary:** `Coalfire-CF/Actions` classified `role=producer`, `status=PASS`, no consumer pin-lag. `Coalfire-CF/terraform-aws-gitlab` classified `FAIL` with `pin-lag` (pins at `v0.16.1`).

**Method notes**

- Classifier: `scripts/fleet-audit.sh`. Report: `scripts/fleet-audit-report.sh`.
- Terraform `source` pins sampled from **root-level** `*.tf` only.
- First pass treated `package-ecosystem: "github-actions"` (quoted) as missing. That was a classifier bug (238 false `dependabot-missing-gha`). Script now accepts optional quotes. This snapshot was corrected by re-reading those `dependabot.yml` files; `dependabot-missing-gha` dropped to 0.
- `bootstrap-exempt` repos were still classified. None in this run.
- Full tables below. Standing issue title: `Actions fleet audit`.

# Actions fleet audit

Pin: `v0.18.1` @ `23c6c8bc526102ed041f2e08a363e5ea2c2f0ec4`

| metric | count |
| --- | --- |
| total | 241 |
| PASS | 1 |
| FAIL | 240 |
| SKIP | 0 |
| bootstrap-exempt | 0 |

## Counts by check

| id | repos |
| --- | --- |
| `automerge-approved-unmerged` | 16 |
| `automerge-blocked` | 40 |
| `automerge-missing-caller` | 25 |
| `dependabot-unlabeled` | 67 |
| `no-caller` | 1 |
| `pin-lag` | 239 |
| `pin-mixed` | 78 |
| `pin-sha-no-comment` | 1 |
| `release-no-tags` | 43 |
| `release-please-stale` | 215 |
| `release-tag-no-github-release` | 6 |
| `source-pin-warn` | 2 |
| `terraform-missing-gates` | 16 |

## automerge-approved-unmerged

| repo | severity | detail |
| --- | --- | --- |
| `Coalfire-CF/upwind-gov` | fail | PR #120 labeled merge/approved |
| `Coalfire-CF/proliance-cli` | fail | PR #14 labeled merge/approved |
| `Coalfire-CF/proliance-cli` | fail | PR #15 labeled merge/approved |
| `Coalfire-CF/proliance-cli` | fail | PR #16 labeled merge/approved |
| `Coalfire-CF/proliance-cli` | fail | PR #21 labeled merge/approved |
| `Coalfire-CF/proliance-cli` | fail | PR #22 labeled merge/approved |
| `Coalfire-CF/proliance-cli` | fail | PR #23 labeled merge/approved |
| `Coalfire-CF/proliance-workspace` | fail | PR #356 labeled merge/approved |
| `Coalfire-CF/proliance-workspace` | fail | PR #357 labeled merge/approved |
| `Coalfire-CF/terraform-aws-lb` | fail | PR #172 labeled merge/approved |
| `Coalfire-CF/terraform-aws-s3` | fail | PR #189 labeled merge/approved |
| `Coalfire-CF/terraform-aws-s3` | fail | PR #191 labeled merge/approved |
| `Coalfire-CF/terraform-aws-private-certificate-authority` | fail | PR #198 labeled merge/approved |
| `Coalfire-CF/terraform-aws-private-certificate-authority` | fail | PR #199 labeled merge/approved |
| `Coalfire-CF/terraform-aws-private-certificate-authority` | fail | PR #201 labeled merge/approved |
| `Coalfire-CF/terraform-aws-private-certificate-authority` | fail | PR #203 labeled merge/approved |
| `Coalfire-CF/terraform-aws-inventorylambda` | fail | PR #194 labeled merge/approved |
| `Coalfire-CF/terraform-aws-inventorylambda` | fail | PR #195 labeled merge/approved |
| `Coalfire-CF/terraform-aws-inventorylambda` | fail | PR #196 labeled merge/approved |
| `Coalfire-CF/terraform-aws-inventorylambda` | fail | PR #197 labeled merge/approved |
| `Coalfire-CF/terraform-aws-account-setup` | fail | PR #273 labeled merge/approved |
| `Coalfire-CF/terraform-aws-account-setup` | fail | PR #274 labeled merge/approved |
| `Coalfire-CF/terraform-aws-account-setup` | fail | PR #275 labeled merge/approved |
| `Coalfire-CF/terraform-aws-account-setup` | fail | PR #276 labeled merge/approved |
| `Coalfire-CF/terraform-aws-account-setup` | fail | PR #277 labeled merge/approved |
| `Coalfire-CF/terraform-aws-security-hub` | fail | PR #229 labeled merge/approved |
| `Coalfire-CF/terraform-aws-eks-compliance-scanner` | fail | PR #223 labeled merge/approved |
| `Coalfire-CF/terraform-aws-iam-identity-center` | fail | PR #266 labeled merge/approved |
| `Coalfire-CF/terraform-aws-iam-identity-center` | fail | PR #269 labeled merge/approved |
| `Coalfire-CF/terraform-aws-iam-identity-center` | fail | PR #270 labeled merge/approved |
| `Coalfire-CF/terraform-aws-iam-identity-center` | fail | PR #271 labeled merge/approved |
| `Coalfire-CF/terraform-aws-organization` | fail | PR #200 labeled merge/approved |
| `Coalfire-CF/terraform-aws-organization` | fail | PR #201 labeled merge/approved |
| `Coalfire-CF/terraform-aws-organization` | fail | PR #202 labeled merge/approved |
| `Coalfire-CF/terraform-aws-organization` | fail | PR #203 labeled merge/approved |
| `Coalfire-CF/terraform-aws-organization` | fail | PR #204 labeled merge/approved |
| `Coalfire-CF/Remediation-Of-Threats-Through-Issue-Entry` | fail | PR #18 labeled merge/approved |
| `Coalfire-CF/Remediation-Of-Threats-Through-Issue-Entry` | fail | PR #19 labeled merge/approved |
| `Coalfire-CF/Remediation-Of-Threats-Through-Issue-Entry` | fail | PR #20 labeled merge/approved |
| `Coalfire-CF/Remediation-Of-Threats-Through-Issue-Entry` | fail | PR #21 labeled merge/approved |
| `Coalfire-CF/Remediation-Of-Threats-Through-Issue-Entry` | fail | PR #22 labeled merge/approved |
| `Coalfire-CF/cs-scm` | fail | PR #32 labeled merge/approved |
| `Coalfire-CF/cs-go-bundler` | fail | PR #21 labeled merge/approved |
| `Coalfire-CF/cs-go-bundler` | fail | PR #22 labeled merge/approved |
| `Coalfire-CF/cs-go-bundler` | fail | PR #23 labeled merge/approved |
| `Coalfire-CF/cs-go-bundler` | fail | PR #24 labeled merge/approved |
| `Coalfire-CF/cs-go-bundler` | fail | PR #25 labeled merge/approved |
| `Coalfire-CF/npm` | fail | PR #25 labeled merge/approved |
| `Coalfire-CF/npm` | fail | PR #32 labeled merge/approved |
| `Coalfire-CF/npm` | fail | PR #34 labeled merge/approved |

## automerge-blocked

| repo | severity | detail |
| --- | --- | --- |
| `Coalfire-CF/upwind-gov` | warn | PR #203 merge/blocked (dep/pip,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump,ai/breaking-suspected) |
| `Coalfire-CF/upwind-gov` | warn | PR #206 merge/blocked (dep/pip,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump,ai/breaking-suspected) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #103 merge/blocked (check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,dep/other,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #108 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #114 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #120 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #138 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #140 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #141 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #144 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #150 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #151 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #152 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #153 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/changelog-safe,check/semver-patch,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #155 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/changelog-safe,check/semver-patch,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #162 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #166 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #169 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #177 merge/blocked (check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,dep/other,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #184 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/changelog-safe,check/semver-patch,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #187 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #204 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #208 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #213 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #215 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/changelog-safe,check/semver-patch,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #239 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #242 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #243 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #245 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #246 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #247 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #251 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #255 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #258 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #259 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #260 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #307 merge/blocked (check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,dep/other,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #313 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #315 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #316 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #317 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #319 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #321 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #322 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #324 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #346 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #353 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #355 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #386 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #387 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #388 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #389 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #402 merge/blocked (check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,dep/other,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #408 merge/blocked (check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,dep/other,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #423 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #56 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #61 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #62 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #77 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #92 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #94 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-dev-conmon` | warn | PR #99 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/terraform-google-secret-manager` | warn | PR #36 merge/blocked (dependencies,github_actions,dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump,ai/breaking-suspected) |
| `Coalfire-CF/terraform-google-kms` | warn | PR #34 merge/blocked (dependencies,github_actions,dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump,ai/breaking-suspected) |
| `Coalfire-CF/terraform-google-project` | warn | PR #35 merge/blocked (dependencies,github_actions,dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump,ai/breaking-suspected) |
| `Coalfire-CF/terraform-google-service-account` | warn | PR #40 merge/blocked (dependencies,github_actions,dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump,ai/breaking-suspected) |
| `Coalfire-CF/terraform-google-cloud-storage` | warn | PR #33 merge/blocked (dependencies,github_actions,dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump) |
| `Coalfire-CF/terraform-google-cloud-router` | warn | PR #33 merge/blocked (dependencies,github_actions,dep/github-actions,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump,ai/breaking-suspected) |
| `Coalfire-CF/cf-sre-claude-skills` | warn | PR #18 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/CF-AWS-Bottlerocket-CIS` | warn | PR #10 merge/blocked (dep/github-actions,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/CF-AWS-Bottlerocket-CIS` | warn | PR #11 merge/blocked (dep/github-actions,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/CF-AWS-Bottlerocket-CIS` | warn | PR #14 merge/blocked (dep/github-actions,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/CF-AWS-Bottlerocket-CIS` | warn | PR #9 merge/blocked (dep/github-actions,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/mt-ops-toolkit` | warn | PR #109 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/mt-ops-toolkit` | warn | PR #117 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/mt-ops-toolkit` | warn | PR #152 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/mt-ops-toolkit` | warn | PR #52 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/mt-ops-toolkit` | warn | PR #53 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/proliance-platform` | warn | PR #40 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/consolidated-inventory` | warn | PR #29 merge/blocked (check/osv-clear,check/scorecard-pass,dep/pip,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/consolidated-inventory` | warn | PR #6 merge/blocked (dep/github-actions,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/consolidated-inventory` | warn | PR #8 merge/blocked (check/osv-clear,check/scorecard-pass,dep/pip,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/packer-aws` | warn | PR #139 merge/blocked (dep/pip,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump,ai/breaking-suspected) |
| `Coalfire-CF/cs-staffing` | warn | PR #137 merge/blocked (dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump) |
| `Coalfire-CF/onyx-licenser` | warn | PR #10 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/onyx-licenser` | warn | PR #5 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/onyx-licenser` | warn | PR #6 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/proliance-cli` | warn | PR #17 merge/blocked (check/osv-clear,check/scorecard-pass,dep/github-actions,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/proliance-cli` | warn | PR #18 merge/blocked (check/osv-clear,dep/github-actions,check/semver-major,check/changelog-breaking,ai/breaking-suspected,check/scorecard-low,risk/high,merge/blocked,blocked/major-bump,blocked/low-scorecard) |
| `Coalfire-CF/proliance-cli` | warn | PR #19 merge/blocked (check/osv-clear,check/scorecard-pass,dep/github-actions,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/proliance-cli` | warn | PR #20 merge/blocked (check/osv-clear,check/scorecard-pass,dep/github-actions,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cf-minfanger-claude-testing` | warn | PR #19 merge/blocked (dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump) |
| `Coalfire-CF/cf-minfanger-claude-testing` | warn | PR #35 merge/blocked (dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump,ai/breaking-suspected) |
| `Coalfire-CF/cf-minfanger-claude-testing` | warn | PR #37 merge/blocked (dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump,ai/breaking-suspected) |
| `Coalfire-CF/ansible-azure` | warn | PR #15 merge/blocked (dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump) |
| `Coalfire-CF/go-github-stats` | warn | PR #66 merge/blocked (dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump) |
| `Coalfire-CF/proliance-workspace` | warn | PR #76 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/smarshgov-aws` | warn | PR #102 merge/blocked (check/osv-clear,check/scorecard-pass,dep/pip,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/smarshgov-aws` | warn | PR #105 merge/blocked (check/osv-clear,check/scorecard-pass,dep/pip,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/smarshgov-aws` | warn | PR #108 merge/blocked (check/osv-clear,check/scorecard-pass,dep/pip,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/smarshgov-aws` | warn | PR #109 merge/blocked (check/osv-clear,check/scorecard-pass,dep/pip,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/smarshgov-aws` | warn | PR #49 merge/blocked (check/osv-clear,check/scorecard-pass,dep/pip,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cf-minfanger-skills` | warn | PR #8 merge/blocked (dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump) |
| `Coalfire-CF/onyx2` | warn | PR #1001 merge/blocked (check/osv-clear,check/scorecard-pass,dep/other,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/onyx2` | warn | PR #995 merge/blocked (check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump,dep/docker) |
| `Coalfire-CF/onyx2` | warn | PR #997 merge/blocked (check/osv-clear,check/scorecard-pass,dep/other,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/onyx2` | warn | PR #998 merge/blocked (check/osv-clear,check/scorecard-pass,dep/other,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/images` | warn | PR #278 merge/blocked (dep/docker,check/osv-clear,check/scorecard-pass,risk/high,check/semver-major,check/changelog-breaking,ai/breaking-suspected,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/images` | warn | PR #284 merge/blocked (dep/docker,check/osv-clear,check/scorecard-pass,risk/high,check/semver-major,check/changelog-breaking,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/images` | warn | PR #287 merge/blocked (dep/docker,check/osv-clear,check/scorecard-pass,risk/high,check/semver-major,check/changelog-breaking,ai/breaking-suspected,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/optum-conmon` | warn | PR #4 merge/blocked (dep/github-actions,check/semver-major,check/changelog-breaking,check/osv-clear,check/scorecard-pass,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/optum-conmon` | warn | PR #5 merge/blocked (dep/github-actions,check/semver-major,check/changelog-breaking,check/osv-clear,check/scorecard-pass,risk/high,merge/blocked,blocked/major-bump,ai/breaking-suspected) |
| `Coalfire-CF/optum-conmon` | warn | PR #8 merge/blocked (dep/pip,check/semver-major,check/changelog-breaking,check/osv-clear,check/scorecard-pass,risk/high,merge/blocked,blocked/major-bump,ai/breaking-suspected) |
| `Coalfire-CF/cs-os-images` | warn | PR #32 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-os-images` | warn | PR #34 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-os-images` | warn | PR #6 merge/blocked (dep/github-actions,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/Coalfire-Azure-RAMPpak` | warn | PR #19 merge/blocked (dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump) |
| `Coalfire-CF/Coalfire-Azure-RAMPpak` | warn | PR #20 merge/blocked (dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump) |
| `Coalfire-CF/ansible-aws` | warn | PR #365 merge/blocked (dependencies,python,dep/pip,check/osv-clear,check/scorecard-pass,merge/blocked,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump,ai/breaking-suspected) |
| `Coalfire-CF/cs-scm` | warn | PR #33 merge/blocked (check/osv-clear,risk/high,dep/pip,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/coalforge-dashboard` | warn | PR #11 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/coalforge-dashboard` | warn | PR #12 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/coalforge-dashboard` | warn | PR #13 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/coalforge-dashboard` | warn | PR #14 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/coalforge-dashboard` | warn | PR #15 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/coalforge-dashboard` | warn | PR #17 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/coalforge-dashboard` | warn | PR #19 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/coalforge-dashboard` | warn | PR #21 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/coalforge-dashboard` | warn | PR #22 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/coalforge-dashboard` | warn | PR #24 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/coalforge-dashboard` | warn | PR #25 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/coalforge-dashboard` | warn | PR #26 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/coalforge-dashboard` | warn | PR #40 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/coalforge-dashboard` | warn | PR #8 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/coalforge-dashboard` | warn | PR #9 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-pipeline-runner` | warn | PR #16 merge/blocked (dep/github-actions,check/semver-major,check/changelog-breaking,check/osv-clear,check/scorecard-pass,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-pipeline-runner` | warn | PR #17 merge/blocked (dep/github-actions,check/semver-major,check/changelog-breaking,ai/breaking-suspected,check/osv-clear,check/scorecard-pass,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-pipeline-runner` | warn | PR #18 merge/blocked (dep/github-actions,check/semver-major,check/changelog-breaking,ai/breaking-suspected,check/osv-clear,check/scorecard-pass,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-pipeline-runner` | warn | PR #19 merge/blocked (dep/github-actions,check/semver-major,check/changelog-breaking,check/osv-clear,check/scorecard-pass,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/evidence-capture` | warn | PR #11 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/evidence-capture` | warn | PR #4 merge/blocked (dep/github-actions,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/evidence-capture` | warn | PR #5 merge/blocked (dep/github-actions,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/image-bakery` | warn | PR #15 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/azure-policy-management` | warn | PR #11 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump,ai/breaking-suspected) |
| `Coalfire-CF/azure-policy-management` | warn | PR #13 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump,ai/breaking-suspected) |
| `Coalfire-CF/azure-policy-management` | warn | PR #17 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump,ai/breaking-suspected) |
| `Coalfire-CF/azure-policy-management` | warn | PR #18 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump,ai/breaking-suspected) |
| `Coalfire-CF/azure-policy-management` | warn | PR #8 merge/blocked (dep/pip,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-jim-industries` | warn | PR #6 merge/blocked (dep/github-actions,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-jim-industries` | warn | PR #7 merge/blocked (dep/github-actions,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-jim-industries` | warn | PR #8 merge/blocked (dep/github-actions,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/npm` | warn | PR #20 merge/blocked (dep/github-actions,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/npm` | warn | PR #21 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/npm` | warn | PR #22 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/npm` | warn | PR #23 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/npm` | warn | PR #24 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/npm` | warn | PR #26 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/npm` | warn | PR #27 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/npm` | warn | PR #29 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/npm` | warn | PR #31 merge/blocked (dep/other,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-stoker-poam` | warn | PR #10 merge/blocked (dep/github-actions,check/osv-clear,check/scorecard-low,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump,blocked/low-scorecard) |
| `Coalfire-CF/cs-stoker-poam` | warn | PR #11 merge/blocked (dep/github-actions,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-stoker-poam` | warn | PR #12 merge/blocked (dep/github-actions,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-stoker-poam` | warn | PR #13 merge/blocked (dep/github-actions,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-stoker-poam` | warn | PR #14 merge/blocked (dep/github-actions,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,ai/breaking-suspected,risk/high,merge/blocked,blocked/major-bump) |
| `Coalfire-CF/cs-onyx-parsers` | warn | PR #114 merge/blocked (dependencies,dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump) |
| `Coalfire-CF/cs-onyx-parsers` | warn | PR #115 merge/blocked (dependencies,dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump) |
| `Coalfire-CF/cs-onyx-parsers` | warn | PR #117 merge/blocked (dependencies,dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump) |
| `Coalfire-CF/driftctlGov` | warn | PR #43 merge/blocked (dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump) |
| `Coalfire-CF/driftctlGov` | warn | PR #44 merge/blocked (dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump) |
| `Coalfire-CF/driftctlGov` | warn | PR #45 merge/blocked (dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump) |
| `Coalfire-CF/driftctlGov` | warn | PR #46 merge/blocked (dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump) |
| `Coalfire-CF/driftctlGov` | warn | PR #51 merge/blocked (dep/github-actions,merge/blocked,check/osv-clear,check/scorecard-pass,check/semver-major,check/changelog-breaking,risk/high,blocked/major-bump) |

## automerge-missing-caller

| repo | severity | detail |
| --- | --- | --- |
| `Coalfire-CF/terraform-google-secops` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/terraform-aws-elasticache` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/terraform-aws-prismacloud` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/terraform-aws-managed-ad` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/terraform-aws-nexpose` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/terraform-google-burpsuite` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/terraform-okta-stig` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/terraform-azurerm-VM-Linux-SS` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/terraform-azurerm-vm-windows-scale-set` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/terraform-azurerm-NAT-GW` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/terraform-azurerm-GitHub` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/terraform-azurerm-galleryimage-definition` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/terraform-azurerm-automation-account` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/Coalfire-AWS-RAMPpak` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/terraform-aws-clientvpn` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/terraform-aws-active-directory` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/Coalfire-Azure-RAMPpak` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/Remediation-Of-Threats-Through-Issue-Entry` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/terraform-google-iap-ingress` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/CS-Azure-RA` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/terraform-aws-backup` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/cs-support-scripts` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/Coalfire-GCP-RAMPpak` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/cs-onyx-parsers` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |
| `Coalfire-CF/driftctlGov` | fail | need org-dependabot.yml and org-dependabot-auto-merge.yml callers |

## dependabot-unlabeled

| repo | severity | detail |
| --- | --- | --- |
| `Coalfire-CF/cs-delta` | fail | PR #269 has no merge/* label |
| `Coalfire-CF/cf-sre-claude-skills` | fail | PR #51 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-MySQL-Flexible` | fail | PR #135 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-firewall` | fail | PR #138 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-splunk` | fail | PR #115 has no merge/* label |
| `Coalfire-CF/ansible-azure` | fail | PR #34 has no merge/* label |
| `Coalfire-CF/terraform-aws-elasticache` | fail | PR #75 has no merge/* label |
| `Coalfire-CF/terraform-aws-elasticache` | fail | PR #76 has no merge/* label |
| `Coalfire-CF/terraform-aws-elasticache` | fail | PR #77 has no merge/* label |
| `Coalfire-CF/terraform-aws-lambda` | fail | PR #149 has no merge/* label |
| `Coalfire-CF/onyx2` | fail | PR #999 has no merge/* label |
| `Coalfire-CF/terraform-aws-security-hub` | fail | PR #231 has no merge/* label |
| `Coalfire-CF/cs-delta-client-onboarding` | fail | PR #57 has no merge/* label |
| `Coalfire-CF/images` | fail | PR #286 has no merge/* label |
| `Coalfire-CF/images` | fail | PR #288 has no merge/* label |
| `Coalfire-CF/images` | fail | PR #289 has no merge/* label |
| `Coalfire-CF/cs-anthracite` | fail | PR #507 has no merge/* label |
| `Coalfire-CF/cs-anthracite` | fail | PR #508 has no merge/* label |
| `Coalfire-CF/optum-conmon` | fail | PR #16 has no merge/* label |
| `Coalfire-CF/terraform-google-burpsuite` | fail | PR #129 has no merge/* label |
| `Coalfire-CF/terraform-google-burpsuite` | fail | PR #130 has no merge/* label |
| `Coalfire-CF/terraform-google-burpsuite` | fail | PR #132 has no merge/* label |
| `Coalfire-CF/terraform-google-burpsuite` | fail | PR #133 has no merge/* label |
| `Coalfire-CF/terraform-google-burpsuite` | fail | PR #136 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-tenable.sc` | fail | PR #155 has no merge/* label |
| `Coalfire-CF/cs-os-images` | fail | PR #40 has no merge/* label |
| `Coalfire-CF/terraform-okta-stig` | fail | PR #121 has no merge/* label |
| `Coalfire-CF/terraform-okta-stig` | fail | PR #122 has no merge/* label |
| `Coalfire-CF/terraform-okta-stig` | fail | PR #123 has no merge/* label |
| `Coalfire-CF/terraform-okta-stig` | fail | PR #124 has no merge/* label |
| `Coalfire-CF/terraform-okta-stig` | fail | PR #131 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-VM-Linux-SS` | fail | PR #111 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-VM-Linux-SS` | fail | PR #112 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-VM-Linux-SS` | fail | PR #113 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-VM-Linux-SS` | fail | PR #114 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-vm-windows-scale-set` | fail | PR #115 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-vm-windows-scale-set` | fail | PR #116 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-vm-windows-scale-set` | fail | PR #117 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-vm-windows-scale-set` | fail | PR #118 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-NAT-GW` | fail | PR #64 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-NAT-GW` | fail | PR #65 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-NAT-GW` | fail | PR #66 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-NAT-GW` | fail | PR #67 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-GitHub` | fail | PR #65 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-GitHub` | fail | PR #66 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-GitHub` | fail | PR #67 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-GitHub` | fail | PR #68 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-galleryimage-definition` | fail | PR #84 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-galleryimage-definition` | fail | PR #85 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-galleryimage-definition` | fail | PR #86 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-galleryimage-definition` | fail | PR #88 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-galleryimage-definition` | fail | PR #90 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-automation-account` | fail | PR #92 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-automation-account` | fail | PR #93 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-automation-account` | fail | PR #94 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-automation-account` | fail | PR #96 has no merge/* label |
| `Coalfire-CF/terraform-azurerm-automation-account` | fail | PR #98 has no merge/* label |
| `Coalfire-CF/Coalfire-AWS-RAMPpak` | fail | PR #71 has no merge/* label |
| `Coalfire-CF/Coalfire-AWS-RAMPpak` | fail | PR #72 has no merge/* label |
| `Coalfire-CF/Coalfire-AWS-RAMPpak` | fail | PR #73 has no merge/* label |
| `Coalfire-CF/Coalfire-AWS-RAMPpak` | fail | PR #75 has no merge/* label |
| `Coalfire-CF/Coalfire-AWS-RAMPpak` | fail | PR #77 has no merge/* label |
| `Coalfire-CF/terraform-aws-clientvpn` | fail | PR #67 has no merge/* label |
| `Coalfire-CF/terraform-aws-clientvpn` | fail | PR #68 has no merge/* label |
| `Coalfire-CF/terraform-aws-active-directory` | fail | PR #303 has no merge/* label |
| `Coalfire-CF/terraform-aws-active-directory` | fail | PR #304 has no merge/* label |
| `Coalfire-CF/terraform-aws-active-directory` | fail | PR #305 has no merge/* label |
| `Coalfire-CF/terraform-aws-active-directory` | fail | PR #306 has no merge/* label |
| `Coalfire-CF/terraform-aws-active-directory` | fail | PR #307 has no merge/* label |
| `Coalfire-CF/terraform-aws-aquasec` | fail | PR #119 has no merge/* label |
| `Coalfire-CF/cs-bstest02` | fail | PR #74 has no merge/* label |
| `Coalfire-CF/Coalfire-Azure-RAMPpak` | fail | PR #19 has no merge/* label |
| `Coalfire-CF/Coalfire-Azure-RAMPpak` | fail | PR #48 has no merge/* label |
| `Coalfire-CF/Coalfire-Azure-RAMPpak` | fail | PR #49 has no merge/* label |
| `Coalfire-CF/Coalfire-Azure-RAMPpak` | fail | PR #52 has no merge/* label |
| `Coalfire-CF/terraform-aws-iam-identity-center` | fail | PR #272 has no merge/* label |
| `Coalfire-CF/terraform-aws-organization` | fail | PR #210 has no merge/* label |
| `Coalfire-CF/ansible-aws` | fail | PR #373 has no merge/* label |
| `Coalfire-CF/ansible-aws` | fail | PR #374 has no merge/* label |
| `Coalfire-CF/ansible-aws` | fail | PR #375 has no merge/* label |
| `Coalfire-CF/ansible-aws` | fail | PR #376 has no merge/* label |
| `Coalfire-CF/ansible-aws` | fail | PR #378 has no merge/* label |
| `Coalfire-CF/cs-did-deep-purple` | fail | PR #1 has no merge/* label |
| `Coalfire-CF/cs-scm` | fail | PR #34 has no merge/* label |
| `Coalfire-CF/terraform-google-iap-ingress` | fail | PR #95 has no merge/* label |
| `Coalfire-CF/terraform-google-iap-ingress` | fail | PR #96 has no merge/* label |
| `Coalfire-CF/terraform-google-iap-ingress` | fail | PR #97 has no merge/* label |
| `Coalfire-CF/terraform-google-iap-ingress` | fail | PR #98 has no merge/* label |
| `Coalfire-CF/terraform-google-iap-ingress` | fail | PR #99 has no merge/* label |
| `Coalfire-CF/CS-Azure-RA` | fail | PR #195 has no merge/* label |
| `Coalfire-CF/CS-Azure-RA` | fail | PR #196 has no merge/* label |
| `Coalfire-CF/CS-Azure-RA` | fail | PR #197 has no merge/* label |
| `Coalfire-CF/CS-Azure-RA` | fail | PR #198 has no merge/* label |
| `Coalfire-CF/CS-Azure-RA` | fail | PR #199 has no merge/* label |
| `Coalfire-CF/proliance-live-template` | fail | PR #8 has no merge/* label |
| `Coalfire-CF/ansible-google` | fail | PR #11 has no merge/* label |
| `Coalfire-CF/cs-go-bundler` | fail | PR #28 has no merge/* label |
| `Coalfire-CF/coalforge-dashboard` | fail | PR #39 has no merge/* label |
| `Coalfire-CF/org-opa-policies` | fail | PR #28 has no merge/* label |
| `Coalfire-CF/terraform-aws-backup` | fail | PR #95 has no merge/* label |
| `Coalfire-CF/terraform-aws-backup` | fail | PR #96 has no merge/* label |
| `Coalfire-CF/terraform-aws-backup` | fail | PR #97 has no merge/* label |
| `Coalfire-CF/terraform-aws-backup` | fail | PR #98 has no merge/* label |
| `Coalfire-CF/terraform-aws-backup` | fail | PR #99 has no merge/* label |
| `Coalfire-CF/proliance-dev` | fail | PR #29 has no merge/* label |
| `Coalfire-CF/packer-azure` | fail | PR #14 has no merge/* label |
| `Coalfire-CF/cs-pipeline-runner` | fail | PR #22 has no merge/* label |
| `Coalfire-CF/MTCS` | fail | PR #143 has no merge/* label |
| `Coalfire-CF/evidence-capture` | fail | PR #12 has no merge/* label |
| `Coalfire-CF/terraform-aws-eck-aws-ingestion` | fail | PR #14 has no merge/* label |
| `Coalfire-CF/proliance-policies` | fail | PR #9 has no merge/* label |
| `Coalfire-CF/cs-test` | fail | PR #3 has no merge/* label |
| `Coalfire-CF/cs-test` | fail | PR #7 has no merge/* label |
| `Coalfire-CF/terraform-aws-vault-enterprise-mvp` | fail | PR #42 has no merge/* label |
| `Coalfire-CF/image-bakery` | fail | PR #24 has no merge/* label |
| `Coalfire-CF/terraform-azure-vpn-gateway` | fail | PR #14 has no merge/* label |
| `Coalfire-CF/proliance-docs` | fail | PR #7 has no merge/* label |
| `Coalfire-CF/proliance-modules` | fail | PR #92 has no merge/* label |
| `Coalfire-CF/cs-support-scripts` | fail | PR #43 has no merge/* label |
| `Coalfire-CF/cs-support-scripts` | fail | PR #44 has no merge/* label |
| `Coalfire-CF/cs-support-scripts` | fail | PR #45 has no merge/* label |
| `Coalfire-CF/cs-support-scripts` | fail | PR #46 has no merge/* label |
| `Coalfire-CF/ansible-collection-elasticsearch` | fail | PR #6 has no merge/* label |
| `Coalfire-CF/prowler-claude-did-projects` | fail | PR #6 has no merge/* label |
| `Coalfire-CF/cs-pak-sbom` | fail | PR #13 has no merge/* label |
| `Coalfire-CF/azure-policy-management` | fail | PR #21 has no merge/* label |
| `Coalfire-CF/ansible-collection-aws` | fail | PR #6 has no merge/* label |
| `Coalfire-CF/sre-icm-sre-sprint-planning` | fail | PR #10 has no merge/* label |
| `Coalfire-CF/Coalfire-GCP-RAMPpak` | fail | PR #53 has no merge/* label |
| `Coalfire-CF/Coalfire-GCP-RAMPpak` | fail | PR #54 has no merge/* label |
| `Coalfire-CF/Coalfire-GCP-RAMPpak` | fail | PR #55 has no merge/* label |
| `Coalfire-CF/Coalfire-GCP-RAMPpak` | fail | PR #56 has no merge/* label |
| `Coalfire-CF/packer-google` | fail | PR #18 has no merge/* label |
| `Coalfire-CF/cs-jim-industries` | fail | PR #11 has no merge/* label |
| `Coalfire-CF/cs-onyx-parsers` | fail | PR #116 has no merge/* label |
| `Coalfire-CF/cs-onyx-parsers` | fail | PR #118 has no merge/* label |

## no-caller

| repo | severity | detail |
| --- | --- | --- |
| `Coalfire-CF/PUBSEC-GovRAMP-Agent-Workspace` | fail | no Coalfire-CF/Actions uses: and no org-release.yml |

## pin-lag

| repo | severity | detail |
| --- | --- | --- |
| `Coalfire-CF/cs-delta` | fail | v0.16.1@9e201c39 vs v0.18.1@23c6c8bc |
| `Coalfire-CF/cs-delta` | fail | v0.17.0@43274fdf vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-aws-gitlab` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-aws-vpc-nfw` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/upwind-gov` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/cs-dev-conmon` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/CF-SecOps-Detection-Repo` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-trend-micro-dsm` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-azurerm-vm-linux` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-security-core` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-azurerm-vm-backup` | fail | v0.16.1@9e201c39 vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-azurerm-vnet` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-secret-manager` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-azurerm-VM-SQL` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-rhel-image-builder` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-azurerm-vm-site-recovery` | fail | v0.16.1@9e201c39 vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-cloud-gke` | fail | v0.16.1@9e201c39 vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-azurerm-Trend-Micro-DSM` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-kms` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-log-export` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-sumologic` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-private-ca` | fail | v0.16.1@9e201c39 vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-private-ca` | fail | v0.17.0@43274fdf vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-project` | fail | v0.16.1@9e201c39 vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-project` | fail | v0.17.0@43274fdf vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-lb` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-service-account` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-folder` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-active-directory` | fail | v0.16.1@9e201c39 vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-active-directory` | fail | v0.17.0@43274fdf vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-private-service-access` | fail | v0.18.0@162d71ff vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-palo-alto` | fail | v0.16.1@9e201c39 vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-palo-alto` | fail | v0.17.0@43274fdf vs v0.18.1@23c6c8bc |
| `Coalfire-CF/terraform-google-cloud-sql` | fail | v0.16.1@9e201c39 vs v0.18.1@23c6c8bc |

... truncated (120792 bytes). Full report is the workflow artifact.
