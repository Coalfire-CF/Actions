# Terratest Per-Repo OIDC Provisioning Runbook

This runbook onboards a module repo to the org Terratest platform
([`org-terratest.yml`](../.github/workflows/org-terratest.yml), documented in
[`ORG_TERRATEST.md`](./ORG_TERRATEST.md)). It covers the identity plumbing that must exist
*before* a caller's first run can authenticate to the cloud test account:

1. AWS — extend the shared OIDC role's trust policy and attach a least-privilege permission
   policy
1. Azure — add a federated credential to the App Registration
1. Post-first-green tightening — replace the starter permission policy with an
   Access-Analyzer-generated one

> **Principle: one shared test identity, many scoped trust claims.** The org uses a single
> IAM role (`github-action-test-role`) and a single Azure App Registration for all module
> self-tests, both pointed at dedicated test accounts. Onboarding a repo = **adding its claim**
> to the existing trust policy / App, not creating a new identity. This keeps the blast radius
> auditable in one place.

---

## 1. AWS — trust policy

The GovCloud test role is `arn:aws-us-gov:iam::358745275192:role/github-action-test-role`
(admin-managed via the `occ-dev` profile). Its trust policy lists, per onboarded repo, **two**
`sub` claims: the `pull_request` claim (PR-mode runs) and the `ref:refs/tags/*` claim
(release-mode runs).

### Trust policy shape

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws-us-gov:iam::358745275192:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:Coalfire-CF/<repo>:pull_request",
            "repo:Coalfire-CF/<repo>:ref:refs/tags/*"
          ]
        },
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

### Claim scoping — why each piece matters

- **`:pull_request`** — in PR mode GitHub sets the OIDC `sub` to
  `repo:<owner>/<repo>:pull_request`, **not** a branch ref. Omitting this claim (e.g. listing
  only `ref:refs/heads/*`) makes every PR-mode run fail with `AccessDenied` / `Not authorized
  to perform sts:AssumeRoleWithWebIdentity`.
- **`:ref:refs/tags/*`** — release-mode (`test_mode: release`) runs on a tag; the `sub` becomes
  `repo:<owner>/<repo>:ref:refs/tags/v1.2.3`. `StringLike` with the `*` suffix matches any tag.
- **`aud` pinned to `sts.amazonaws.com`** — the exact audience `configure-aws-credentials`
  requests. Pinning it prevents a token minted for a different audience from being replayed
  against this role.
- **No wildcards.** Never write `repo:Coalfire-CF/*:*` — that trusts **every repo in the org on
  any event**, so anyone who can open a PR anywhere in the org could assume the test role. List
  the two exact claims per repo instead.

### Extend the trust policy (REPLACE, not merge)

`aws iam update-assume-role-policy` **replaces** the entire document — there is no partial
update. Fetch the current policy, append the new repo's two claims, and put it back whole:

```bash
# 1. Fetch the current trust policy
aws iam get-role --role-name github-action-test-role --profile occ-dev \
  --query 'Role.AssumeRolePolicyDocument' > trust-policy.json

# 2. Edit trust-policy.json — add the two new claims to the existing
#    token.actions.githubusercontent.com:sub array (keep all existing repos' claims):
#      "repo:Coalfire-CF/<new-repo>:pull_request",
#      "repo:Coalfire-CF/<new-repo>:ref:refs/tags/*"

# 3. Put the whole document back
aws iam update-assume-role-policy --role-name github-action-test-role \
  --policy-document file://trust-policy.json --profile occ-dev

# 4. Verify
aws iam get-role --role-name github-action-test-role --profile occ-dev \
  --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition.StringLike'
```

When a repo is **retired**, run the same fetch-edit-put loop to *remove* its two claims (keep
everyone else's, keep the `aud` pin).

---

## 2. AWS — least-privilege permission policy

The role also needs an identity (permission) policy granting exactly what the module under
test creates and destroys. Below is the **starter policy iterated for `terraform-aws-vpc-nfw`**
— use it as the template and prune/extend to your module's resource set. It was built
empirically: run the test, read the `AccessDenied` in the apply log, add the one action, repeat
until green (then tighten — see §4).

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerratestVpcNfw",
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "network-firewall:*",
        "logs:*",
        "s3:*",
        "kms:CreateKey",
        "kms:DescribeKey",
        "kms:ListAliases",
        "kms:CreateAlias",
        "kms:DeleteAlias",
        "kms:ScheduleKeyDeletion",
        "kms:TagResource",
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:GenerateDataKey*",
        "kms:PutKeyPolicy",
        "kms:GetKeyPolicy",
        "kms:GetKeyRotationStatus",
        "kms:EnableKeyRotation",
        "kms:ListResourceTags",
        "kms:CreateGrant",
        "kms:ListGrants",
        "kms:RevokeGrant",
        "kms:RetireGrant"
      ],
      "Resource": "*"
    },
    {
      "Sid": "NfwServiceLinkedRole",
      "Effect": "Allow",
      "Action": "iam:CreateServiceLinkedRole",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "iam:AWSServiceName": [
            "network-firewall.amazonaws.com",
            "networkfirewall.amazonaws.com"
          ]
        }
      }
    },
    {
      "Sid": "FlowLogRoleLifecycle",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:PutRolePolicy",
        "iam:GetRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:ListInstanceProfilesForRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy"
      ],
      "Resource": "arn:aws-us-gov:iam::358745275192:role/*-flowlogs-cloudwatch-role"
    },
    {
      "Sid": "FlowLogPassRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws-us-gov:iam::358745275192:role/*-flowlogs-cloudwatch-role",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "vpc-flow-logs.amazonaws.com"
        }
      }
    },
    {
      "Sid": "FlowLogPolicyLifecycle",
      "Effect": "Allow",
      "Action": [
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicyVersions",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:TagPolicy",
        "iam:UntagPolicy",
        "iam:ListEntitiesForPolicy"
      ],
      "Resource": "arn:aws-us-gov:iam::358745275192:policy/*-flowlogs-cloudwatch-policy"
    },
    {
      "Sid": "SubnetGroupsAndResolver",
      "Effect": "Allow",
      "Action": [
        "rds:CreateDBSubnetGroup",
        "rds:DeleteDBSubnetGroup",
        "rds:DescribeDBSubnetGroups",
        "rds:AddTagsToResource",
        "rds:RemoveTagsFromResource",
        "rds:ListTagsForResource",
        "redshift:CreateClusterSubnetGroup",
        "redshift:DeleteClusterSubnetGroup",
        "redshift:DescribeClusterSubnetGroups",
        "redshift:CreateTags",
        "redshift:DeleteTags",
        "redshift:DescribeTags",
        "elasticache:CreateCacheSubnetGroup",
        "elasticache:DeleteCacheSubnetGroup",
        "elasticache:DescribeCacheSubnetGroups",
        "elasticache:AddTagsToResource",
        "elasticache:RemoveTagsFromResource",
        "elasticache:ListTagsForResource",
        "route53resolver:UpdateResolverDnssecConfig",
        "route53resolver:GetResolverDnssecConfig",
        "route53resolver:ListResolverDnssecConfigs"
      ],
      "Resource": "*"
    }
  ]
}
```

### How this policy was iterated (commentary)

- **`ec2:*`, `network-firewall:*`, `logs:*`, `s3:*`** are left as service wildcards because the
  VPC-NFW module touches a very broad EC2/NFW surface (VPCs, subnets, route tables, NAT/IGW,
  endpoints, flow-log delivery, firewall policies/rule-groups, the S3 backend). Wildcarding
  *these four services* on the dedicated test account was the pragmatic floor to reach first
  green; §4 tightens them.
- **KMS is enumerated, not wildcarded** — the module creates CMKs for CloudWatch and NFW
  logging. `CreateGrant`/`ListGrants`/`RevokeGrant`/`RetireGrant` are needed because services
  (logs, NFW) receive grants on those keys; `ScheduleKeyDeletion` + `DeleteAlias` are the
  destroy path.
- **IAM is tightly scoped by ARN pattern.** The module's only IAM footprint is the VPC
  flow-log delivery role/policy, so the lifecycle actions are constrained to
  `*-flowlogs-cloudwatch-role` and `*-flowlogs-cloudwatch-policy`. `PassRole` is additionally
  conditioned to `iam:PassedToService = vpc-flow-logs.amazonaws.com` so the role can only be
  handed to the flow-logs service, nothing else.
- **`iam:CreateServiceLinkedRole`** is limited by `iam:AWSServiceName` to the two Network
  Firewall service principals (both spellings exist across partitions).
- **Subnet groups + resolver DNSSEC** cover the database/cache subnet groups and the DNSSEC
  config the module optionally manages; enumerated because they are low-volume and easy to pin.

Attach it:

```bash
aws iam put-role-policy --role-name github-action-test-role \
  --policy-name terratest-<module>-permissions \
  --policy-document file://terratest-permissions.json --profile occ-dev
```

---

## 3. Azure — federated credential

The org uses one App Registration for Azure Government module self-tests. Each onboarded repo
gets its **own federated credential** on that app, subject-scoped to the repo's `pull_request`
claim (add a second for release/tag runs).

### Check whether you can manage the app

The app's client ID is in the caller's `terratest-azure.yml` (`azure_client_id`). List its
existing credentials:

```bash
az ad app federated-credential list --id <azure_client_id>
```

If this fails (`Insufficient privileges` / not logged into the Gov tenant), **stop** — record
the exact `az` command below as a blocker for the identity owner (Doug) and open the PR anyway;
CI cannot run until the credential exists.

### Add the credential

```bash
az ad app federated-credential create --id <azure_client_id> --parameters '{
  "name": "coalfire-<repo>-pr",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:Coalfire-CF/<repo>:pull_request",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

For release-mode runs add a second credential with
`"subject": "repo:Coalfire-CF/<repo>:ref:refs/tags/*"` and name `coalfire-<repo>-tags`.

- **Issuer** `https://token.actions.githubusercontent.com` — GitHub's OIDC issuer.
- **Audience** `api://AzureADTokenExchange` — the audience the azurerm provider's OIDC login
  requests (distinct from the AWS `sts.amazonaws.com` audience).
- **Subject** is the same `repo:<owner>/<repo>:<claim>` string as the AWS `sub`. Azure matches
  the subject **exactly** (no wildcards in the subject), which is why release runs need their
  own credential rather than a pattern.

When a repo is retired, delete its credential(s):

```bash
az ad app federated-credential delete --id <azure_client_id> \
  --federated-credential-id coalfire-<repo>-pr
```

### Org secret visibility

The private-module pull secrets (`CF_TF_PULL_PRIVATE_APP_CLIENTID` /
`CF_TF_PULL_PRIVATE_APP_PRIVATE_KEY`) are **selected-repos scoped**. A new repo must be added to
each secret's repository list, or the `go mod download` of private sibling modules fails:

```bash
# List repos currently granted the secret (needs org admin)
gh api orgs/Coalfire-CF/actions/secrets/CF_TF_PULL_PRIVATE_APP_CLIENTID/repositories \
  --jq '.repositories[].full_name'
```

If you lack org-admin, record adding the repo as a blocker for the identity owner.

---

## 4. Post-first-green tightening (IAM Access Analyzer)

The starter permission policy (§2) deliberately over-grants a few services (`ec2:*`, `s3:*`,
etc.) to reach the first green run without a dozen `AccessDenied` round-trips. Once the lane is
green, **generate a least-privilege policy from what the run actually used** and replace the
starter:

1. Ensure CloudTrail is capturing management events for the test account (the GovCloud test
   account already does).
1. Let one full green PR run complete (apply → assert → destroy) so CloudTrail records the
   complete action set.
1. Generate a policy from that activity with IAM Access Analyzer:

   ```bash
   aws accessanalyzer start-policy-generation --profile occ-dev \
     --policy-generation-details '{"principalArn":"arn:aws-us-gov:iam::358745275192:role/github-action-test-role"}' \
     --cloud-trail-details '{
       "trails":[{"cloudTrailArn":"<trail-arn>","allRegions":true}],
       "accessRole":"<access-analyzer-service-role-arn>",
       "startTime":"<run-start>","endTime":"<run-end>"
     }'

   # Poll, then fetch the generated policy:
   aws accessanalyzer get-generated-policy --job-id <job-id> --profile occ-dev
   ```

1. Diff the generated policy against the starter, replace the service wildcards
   (`ec2:*`, `s3:*`, `logs:*`) with the enumerated action set Access Analyzer observed, keep the
   already-tight IAM/KMS statements, and `put-role-policy` the result.
1. Re-run the lane to confirm it is still green under the tightened policy.

This converts the "wildcard to get green, then tighten" starter into a real least-privilege
policy grounded in observed behavior — the same iteration that produced the vpc-nfw KMS/IAM
statements above, taken to completion for the wildcarded services.
