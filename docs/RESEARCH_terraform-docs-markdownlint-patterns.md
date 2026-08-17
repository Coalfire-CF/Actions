# RESEARCH TASK: terraform-docs and markdownlint coexistence patterns

> **Status:** Research, saved 2026-08-17. NOT implemented. Captured from a session
> that started as "is MD013/MD033/MD034/MD060 vs terraform-docs real?" and widened
> into "what do other orgs do instead". Every version claim below was measured in
> that session (binaries run locally, GitHub API reads). Re-verify line refs before
> acting.

## Measured baseline (what we run today)

| Piece | Version | Evidence |
|-------|---------|----------|
| markdownlint-cli2 | 0.23.2 (latest on npm) | `package.json:7` |
| markdownlint | 0.41.1 (latest) | `package-lock.json:535` |
| terraform-docs/gh-actions | v1.4.1 (latest release, 2025-05-13) | `org-terraform-docs.yml:52` |
| terraform-docs in CI | **0.20.0** | action Dockerfile at tag and at pinned SHA |
| terraform-docs latest | 0.24.0 | upstream releases |

Rules that actually fire on 0.20.0 output (rendered a real module, then linted):

- **MD033** inline HTML, from the `<a name="input_x"></a>` anchors. Fires on every row.
- **MD034** bare URLs, from URLs in variable descriptions and the Modules `Source` column.
  Conditional, not universal.
- **MD060** table column style. 0.20.0 emits an unpadded delimiter row (`|------|`), which
  matches no supported style, so the rule picks `aligned` as closest and flags every pipe.
  terraform-docs 0.24.0 pads the delimiter and is MD060 clean.
- **MD013 does not fire.** markdownlint 0.41.1 exempts lines containing a link that are not
  part of a paragraph, and every generated row has `[name](#input\_name)`. A 222 char row
  went unreported while a 116 char paragraph in the same file was flagged. MD013 is off in
  our policy for authored-prose reasons, not for terraform-docs.

Anything inside the `BEGIN_TF_DOCS`/`END_TF_DOCS` markers is rewritten on every regen, so
hand-fixing any of these never survives. The fix has to come from config or the generator.

## What the field does that we do not

### 1. Mainstream module orgs do not lint generated READMEs at all

`terraform-aws-modules/terraform-aws-vpc`, the most-used Terraform module repo, has **no
markdownlint config**. Its `.pre-commit-config.yaml` runs `terraform_fmt`, `terraform_docs`,
`terraform_tflint`, `terraform_validate` and stops there. Cloud Posse avoids the problem a
different way: `README.yaml` plus templating generates the whole README, so no file is part
authored and part generated.

Our conflict exists because we lint a file that is half machine output. Every option below
is a way of not doing that.

### 2. Check mode instead of a bot push

terraform-aws-modules runs pre-commit in CI with `--show-diff-on-failure`. Docs drift is a
red check plus a diff, and the author regenerates locally. No bot commits to PR branches.

We already have the pieces: `terraform-docs --output-check` exists in 0.20.0, and the action
exposes `fail-on-diff`.

Adopting it would delete the Dependabot actor gate and the drift-report step
(`org-terraform-docs.yml:55-85`), and would sidestep the known problem that a
GITHUB_TOKEN push does not retrigger required checks (upstream gh-actions issue #107).

**But it cuts against this fleet.** Provider bumps change the version tables, so every
Dependabot PR would go red and need a human regen, which is exactly the toil the
auto-merge machinery exists to remove. Recommendation: keep pushing, and record this as a
deliberate divergence rather than an oversight.

### 3. Split generated docs into their own file

terraform-docs can target `docs/terraform.md` with `output.mode: replace`. markdownlint
then ignores one path and **every rule stays on everywhere else**, no pragmas and no
policy relaxation. This is the cleanest end state.

Cost: inputs and outputs stop rendering on the repo landing page (a link replaces them),
and it is a fleet-wide README restructure. Only worth it if we want strict linting.

### 4. pre-commit as the local half of every check we run in CI

`antonbabenko/pre-commit-terraform` (rev-pinned) is the ecosystem standard, and it covers
work we do as separate `org-*` workflows: fmt, docs, validate, tflint. Full migration is
large. The cheap slice is worth taking on its own: ship a `.pre-commit-config.yaml` in the
bootstrap baseline pinned to the same terraform-docs version CI uses, so an author can
regenerate before pushing instead of waiting for a bot commit.

### 5. Local and CI parity for the lint policy itself

`org-markdown-lint.yml:64-69` deletes every repo-local markdownlint config and heredocs a
canonical one. Two consequences:

- A developer running markdownlint locally gets different results than CI.
- The policy is duplicated in the workflow heredoc and in `.markdownlint-cli2.jsonc`, with a
  "keep the two in sync" comment (`.markdownlint-cli2.jsonc:3-5`) as the only guard.

markdownlint-cli2 resolves `extends` against a module name or path, so either of these gives
one source of truth:

- **a.** `org-repo-bootstrap` delivers the canonical config as a baseline file (the sweeper
  already exists) and CI verifies it by checksum instead of deleting it.
- **b.** The workflow curls the config from `Coalfire-CF/Actions` at a pinned SHA.

Option a also gives developers the parity from the previous point.

### 6. Installing a pinned release binary

If we do move terraform-docs off 0.20.0, `jaxxstorm/action-install-gh-release` (used by
terraform-aws-modules) is the maintained way to pin a GitHub release binary, rather than a
hand-rolled curl plus sha256 step. Note the action is a dead end for version moves: v1.4.1
is the latest release, quay `edge` and `latest` are the same April 2025 build, and the
upstream bump requests (#164 for 0.23.0, #168 for 0.24.0) are open and unmerged.

## The reference standard: Azure Verified Modules (copy this)

AVM publishes this as a written, versioned requirement with a canonical config file, so it
can be cited and copied rather than reinvented.

- **Requirement:** `TFNFR2 - Module Documentation Generation`, severity **MUST**, at
  <https://azure.github.io/Azure-Verified-Modules/spec/TFNFR2>. Source:
  `Azure/Azure-Verified-Modules`, `docs/content/specs-defs/includes/terraform/shared/non-functional/TFNFR2.md`.
- **Canonical config to copy:** `docs/static/includes/terraform-docs.yml` in that repo.
- **Live reference repo:** `Azure/terraform-azurerm-avm-res-storage-storageaccount`.

What the canonical config does, and how it differs from us:

| Decision | AVM | Us today |
|----------|-----|----------|
| Formatter | `markdown document` ("this is required") | `markdown table` (action default) |
| Authored prose | `_header.md` / `_footer.md` partials | inline in README.md |
| README.md | 100 percent generated, `output.mode: replace` | hand-authored with two spliced-in sections |
| Tool version | `version: "0.16.0"` pinned **in the config**, enforced by terraform-docs | whatever the action image ships (0.20.0), unpinned for devs |
| Lint pragmas | emitted by the `content:` template | none, so the org policy is relaxed fleet-wide instead |
| Bot PRs | dedicated auto-fix workflow | every PR gets a bot push |

Three things this settles:

1. **Pragmas emitted from the generator template are the standard, not a hack.** The AVM
   canonical config literally contains `<!-- markdownlint-disable MD033 -->` before
   `{{ .Requirements }}` and `<!-- markdownlint-disable MD013 -->` before `{{ .Inputs }}`.
   Same mechanism I validated on 0.20.0. Two rules, scoped, generated every time.
2. **`markdown document` instead of `markdown table` removes a whole class of problems.**
   No table rows means no MD060 and no wide-row MD013 argument at all. AVM marks the
   formatter choice as required.
3. **`version:` in `.terraform-docs.yml` is the fix for dev-versus-CI drift**, enforced by
   terraform-docs itself. That closes the gap I raised about a developer on brew-latest
   generating different output than CI.

### Second and third datapoints

- **GoogleCloudPlatform / Cloud Foundation Toolkit** (`terraform-google-modules/terraform-google-network`):
  docs are generated by `make generate_docs`, which runs a **pinned** Docker image
  (`cft/developer-tools:1.25`), and CI runs `test_lint.sh` from the same image
  (`build/lint.cloudbuild.yaml`). One pinned image gives local and CI parity by
  construction. No bot pushes.
- **terraform-aws-modules** (`terraform-aws-vpc`): pre-commit (`terraform_fmt`,
  `terraform_docs`, `terraform_tflint`, `terraform_validate`, rev-pinned to
  `pre-commit-terraform v1.108.1`), and CI runs pre-commit with
  `--show-diff-on-failure`. **No markdownlint config at all.** No bot pushes.

### How AVM solves the Dependabot gap

`.github/workflows/dependabot-precommit.yml`, gated `if: startsWith(github.head_ref,
'dependabot/')`: checkout the PR branch, run pre-commit, then commit
`chore(deps): apply pre-commit fixes` and push. Bots get an auto-fix push; humans fix
locally and CI only verifies. That is the split I proposed, confirmed by a shipped standard.

### The tree section has no equivalent anywhere

None of the surveyed fleets publish a directory tree in the README. `org-tree-readme.yml`
is bespoke, and it is the second writer that causes the marker collision (issue #278) and
roughly 90 lines of awk. Under an AVM-shaped layout the tree has nowhere natural to live:
`header-from`/`footer-from` each take a single file, so a tree generator writing a partial
would clobber authored prose. Options are to drop it, or give it its own linked file.

## The structural fix: one writer per file, no markers, no PR mutation

The rule relaxations and the pragma comments are symptoms. The cause is that two
generators splice into one hand-authored file on PR branches and each pushes a commit.
That single design choice produces all of the following:

- `org-tree-readme.yml:152-176`, an awk state machine to replace a section in place.
- `org-tree-readme.yml:179-218`, self-heal for a `BEGIN_TF_DOCS` marker that the other
  writer stripped (issue #278). Two writers, one file.
- Hand-emitted blank lines so the generated section satisfies MD022, MD031 and MD047.
- Two separate actor-gated pushes, plus the Dependabot read-only drift report
  (`org-terraform-docs.yml:55-85`), plus `cancel-in-progress` care so a main-writing run
  is never cancelled.
- Marker comments and lint pragmas inside an authored file.

### Target shape

1. **`docs/terraform.md` is 100 percent generated.** `output.mode: replace` with
   `output.template: "{{ .Content }}"`. Measured on 0.20.0: no BEGIN/END markers in the
   output at all, and byte-identical on rerun. Note terraform-docs does **not** create the
   parent directory (exit 1, "no such file or directory"), so the job needs `mkdir -p docs`
   or the dir ships with the baseline.
2. **`docs/tree.md` is 100 percent generated.** A whole-file write replaces the awk
   splicer, the self-heal, and the blank-line bookkeeping. Roughly 90 lines of
   `org-tree-readme.yml` become `tree ... > docs/tree.md`.
3. **`README.md` becomes fully hand-authored** with two links. markdownlint then runs
   default rules against it, and `ignores` covers the two generated paths. The MD013,
   MD033, MD034 and MD060 relaxations can be dropped fleet-wide, and no pragma is ever
   needed.
4. **Regenerate on `push: main`, not on PR branches.** The workflow already supports this
   mode (`org-terraform-docs.yml:47-49`). PR branches stop being mutated, which removes
   both actor gates, the drift report, and the "did required checks rerun" problem. The
   fact that a GITHUB_TOKEN push does not retrigger workflows becomes useful here: it
   prevents the regen loop for free.
   - Cost: docs on main lag by one merge, so a release cut right after a merge could ship
     stale docs. Fix by ordering the regen ahead of the release job.
   - Optional PR-time feedback without mutation: `terraform-docs --output-check` as a
     read-only check that fails with a diff.

### What it costs

A fleet-wide README restructure across the template-bearing repos, one PR each, using the
existing sweep machinery (`scripts/pr-template-sweep.sh` pattern plus `org-repo-bootstrap`).
The one real trade-off is a product decision: inputs and outputs no longer render on the
repo landing page, a link goes there instead.

## Recommended order

1. **Now, no pattern change.** Wrap the generated block in pragmas emitted by the generator,
   via a canonical `.terraform-docs.yml` using `output.template`. Verified on 0.20.0: the
   README lints to 0 issues with MD033, MD034 and MD060 all enabled, and authored prose
   outside the block still reports. Requires blanking `output-file`/`output-method` at
   `org-terraform-docs.yml:62-63`, because the action documents that its CLI flags override
   config-file `output:` keys. Zero fleet repos have a local `.terraform-docs.yml`, so there
   is no divergence to reconcile.
2. **Then re-enable MD033, MD034, MD060** in both copies of the policy
   (`.markdownlint-cli2.jsonc:33-34,42` and `org-markdown-lint.yml:96-97,105`). Order
   matters: step 1 must land first or README-touching PRs go red. Leave MD013 off.
3. **Then fix the two-copies problem** (item 5). Independent of terraform-docs and the
   highest-value cleanup here.
4. **Then ship `.pre-commit-config.yaml` in the baseline** (item 4, cheap slice).
5. **Optional, only if strict linting is the goal:** move generated docs to their own file
   (item 3), which makes items 1 and 2 unnecessary.
6. **Rejected for this fleet:** check mode instead of bot push (item 2). Document the reason.
