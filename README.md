# Coalfire Advisory Github Actions

Source repository for github actions used by Coalfire Advisory.

## Setup and usage

Central location to consume actions in other repos.

## Actions

Current list of actions and their usage

### Readme Tree Writer

Creates a Tree structure of the repo and inserts it under the Tree section of a README.md

### Checkov

Static code analysis of terraform. This action is triggered by an opened PR to the main branch.

### Markdown Linter

Markdown linter. Triggered on PR to main branch.

### Release

Creates a new tag and release on the repo.  This action is triggered by a merged PR to the main branch.

### Terraform Validate
#### Private Repository Access
Access to private repositories is controlled using a custom Github App that is installed on Coalfire-CF (Github Organization).

Both the "App ID" and this private key are stored as Github Organization Secrets:
- CF_TF_PULL_PRIVATE_APP_CLIENTID
- CF_TF_PULL_PRIVATE_APP_PRIVATE_KEY

Out of an abundance of caution, the visibility for these secrets is only set for "Private repositories".

#### Usage
These secrets are then used in workflows to allow GHA to pull from private Github Repositories:
(Upstream workflow in this repository)
```yaml
- name: Get Checkout Token
      id: checkout-token
      if: steps.check-secrets.outputs.has_secrets == 'true'
      uses: actions/create-github-app-token@v1
      with:
        app-id: ${{ secrets.APP_CLIENT_ID }}
        private-key: ${{ secrets.APP_PRIVATE_KEY }}
        owner: ${{ github.repository_owner }}
    
    - name: Configure Git
      if: steps.check-secrets.outputs.has_secrets == 'true'
      run: |
        git config --global url."https://actions:${{ steps.checkout-token.outputs.token }}@github.com".insteadOf https://github.com
        git config --global url."https://actions:${{ steps.checkout-token.outputs.token }}@github.com/".insteadOf ssh://git@github.com/ 
```

(Downstream workflow in another pak repository):
```yaml
# First determine if we're in a private repo
jobs:
  check-visibility:
    runs-on: ubuntu-latest
    outputs:
      is_private: ${{ steps.check.outputs.is_private }}
    steps:
      - id: check
        run: |
          REPO_VISIBILITY=$(curl -s -H "Authorization: token ${{ github.token }}" \
          "https://api.github.com/repos/${{ github.repository }}" | jq -r '.private')
          echo "is_private=$REPO_VISIBILITY" >> $GITHUB_OUTPUT

  # Only run this job if we're in a private repo
  private-validation:
    needs: check-visibility
    if: needs.check-visibility.outputs.is_private == 'true'
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-validate.yml@26244cc890299238dcd63dc69dc1499e610d5966
    with:
      terraform_version: 1.11.4
    secrets:
      APP_CLIENT_ID: ${{ secrets.CF_TF_PULL_PRIVATE_APP_CLIENTID }}
      APP_PRIVATE_KEY: ${{ secrets.CF_TF_PULL_PRIVATE_APP_PRIVATE_KEY }}
      
  # Run this job if we're in a public repo (no secrets passed)
  public-validation:
    needs: check-visibility
    if: needs.check-visibility.outputs.is_private != 'true'
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-validate.yml@26244cc890299238dcd63dc69dc1499e610d5966
    with:
      terraform_version: 1.11.4
```

The Organization secrets are only directly referenced in the downstream (calling) workflow.  In my experience, trying to use them in the upstream workflow does not work.

The Github App Token job steps will be skipped if the downstream workflow is a public repository (in which case, access to the secrets is denied).

Adjust "terraform_version" as needed.

### Terraform Docs

Generate Terraform modules documentation then commit and push the changes. Triggered on PR to main branch.

This is a wrapper around [terraform-docs GitHub Actions](https://github.com/terraform-docs/gh-actions).

#### Tree

```
.
└── README.md

```

#### Inputs

| Name | Description | Default | Required |
| ---- | ----------- | ------- | -------- |
| find-dir | name of root directory to extract list of directories | `disabled` | no |
| recursive | if true it will update submodules recursively | `false` | no |
| recursive-path | submodules path to recursively update | `modules` | no |
| working-dir | comma separated list of directories to generate docs for | `.` | no |

#### Usage

**Root module only**

```
name: Org Terraform Docs
on:
    pull_request:
    workflow_call:

jobs:
  terraform-docs:
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-docs.yml@main
```

**Root module and submodules**

```
name: Org Terraform Docs
on:
    pull_request:
    workflow_call:

jobs:
  terraform-docs:
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-docs.yml@main
    with:
      recursive: true
```

**Submodules only**

```
name: Org Terraform Docs
on:
    pull_request:
    workflow_call:

jobs:
  terraform-docs:
    uses: Coalfire-CF/Actions/.github/workflows/org-terraform-docs.yml@main
    with:
      find-dir: modules
```

### **Issues**

Bug fixes and enhancements are managed, tracked, and discussed through the GitHub issues on this repository.

Issues should be flagged appropriately.

- Bug
- Enhancement
- Documentation
- Code

#### Code Owners

- Primary Code owner: Douglas Francis (@douglas-f)
- Backup Code owner: Michael Scribellito (@mscribellito-cf)

The responsibility of the code owners is to approve and Merge PR's on the repository, and generally manage and direct issue discussions.
