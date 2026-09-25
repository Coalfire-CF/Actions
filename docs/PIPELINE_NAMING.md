# Pipeline naming

Workflows in this repo follow the cs-delta naming contract in
[`Coalfire-CF/cs-delta` `docs/pipeline-naming.md`](https://github.com/Coalfire-CF/cs-delta/blob/main/docs/pipeline-naming.md).
`scripts/workflow-naming-check.sh` enforces it in CI (job
`Guard — workflow naming`).

| Part | Rule | Example |
| --- | --- | --- |
| Filename | `<category>-<purpose>.yml`, lower kebab-case | `ci-terraform-validate.yml` |
| `name:` | `<Category>: <purpose>`, unique | `CI: Terraform validate` |
| Job id | lower kebab-case | `notify-failure` |
| Job `name:` | required, sentence case | `Notify on failure` |
| `run-name` | omitted for `ci`, `automation`, `reusable` | |

Categories: `ci`, `automation`, `setup`, `deploy`, `ops`, `destroy`,
`release`, `internal`, `reusable`.

A reusable workflow here uses the same category and name as the caller that
calls it. A fleet repo's `ci-terraform-validate.yml` calls
`Coalfire-CF/Actions/.github/workflows/ci-terraform-validate.yml`.

Keep the caller job id `auto-merge` on the Dependabot auto-merge caller.
`scripts/pr-green-merge.sh` ignores check runs named `auto-merge / ...`, and
`tests/automerge-caller-job-id.test.sh` fails if it changes.

## v1.0.0 rename

v1.0.0 renamed every reusable workflow. The `org-*` files are gone at v1.0.0
and later. A caller that bumps its pin must also change the path. Dependabot
only changes the `@ref`, so auto-merge blocks those bumps with
`blocked/major-bump` and `blocked/missing-uses-path`.

To migrate a caller:

1. Rename the caller file to the new name in the table.
2. Change the `uses:` path to the new reusable name, and pin it to the v1.0.0
   SHA. For auto-merge, set `actions_ref` to the same SHA.
3. Set the caller `name:` and job `name:` to the values in
   `templates/bootstrap/`.
4. If a repo ruleset requires one of these checks, update the required
   context. The check name is `<caller job name> / <reusable job name>`.

`scripts/workflow-rename-sweep.sh` does steps 1 to 3 across the fleet.

| Old reusable | New reusable | Old bootstrap caller |
| --- | --- | --- |
| `org-caliper.yml` | `ci-security-caliper.yml` | |
| `org-dependabot-auto-merge.yml` | `automation-dependabot-auto-merge.yml` | `org-dependabot-auto-merge.yml` |
| `org-dependabot-reconcile.yml` | `automation-dependabot-reconcile.yml` | |
| `org-dependabot.yml` | `automation-dependabot-refresh.yml` | `org-dependabot.yml` |
| `org-gitleaks-pr.yml` | `ci-security-gitleaks.yml` | `org-gitleaks-pr.yml` |
| `org-gitleaks-release.yml` | `release-security-gitleaks.yml` | |
| `org-jira-sync.yml` | `automation-jira-sync.yml` | |
| `org-label-sync.yml` | `automation-label-sync.yml` | |
| `org-markdown-lint.yml` | `ci-markdown.yml` | `org-md-lint.yml` |
| `org-opa.yml` | `ci-policy-opa.yml` | |
| `org-release-clean.yml` | `release-clean-archive.yml` | |
| `org-release.yml` | `release-please.yml` | `org-release.yml` |
| `org-repo-bootstrap.yml` | `automation-repo-bootstrap.yml` | |
| `org-slack-notify.yml` | `automation-slack-notify.yml` | |
| `org-terraform-apply.yml` | `deploy-terraform-apply.yml` | |
| `org-terraform-docs.yml` | `ci-terraform-docs.yml` | `org-terraform-docs.yml` |
| `org-terraform-fmt.yml` | `ci-terraform-format.yml` | `org-terraform-fmt.yml` |
| `org-terraform-plan.yml` | `deploy-terraform-plan.yml` | |
| `org-terraform-source-pin.yml` | `ci-terraform-source-pin.yml` | |
| `org-terraform-validate.yml` | `ci-terraform-validate.yml` | `org-terraform-validate.yml` |
| `org-terraform-version-band.yml` | `ci-terraform-version-band.yml` | |
| `org-terraform-version-check.yml` | `automation-terraform-version-check.yml` | |
| `org-terratest.yml` | `ci-terratest.yml` | |
| `org-trivy-exception-review.yml` | `automation-trivy-exception-review.yml` | |
| `org-trivy-pr.yml` | `ci-security-trivy.yml` | |
| `org-trivy-release.yml` | `release-security-trivy.yml` | |

Job ids that changed: `supply_chain_check`, `breaking_change_check`,
`notify_failure`, `gitleaks_scan`, `gitleaks_release_scan`,
`create_jira_issue`, `sync_labels`, `release_clean`, `check_exceptions`,
`trivy_scan` and `trivy_release_scan` now use hyphens. `lint-README` is
`lint-markdown`. Jobs that had no `name:` now have one, which changes their
check names.
