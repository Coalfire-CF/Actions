# Coalfire Advisory Github Actions

Source repository for github actions used by Coalfire Advisory.

## Setup and usage

Central location to consume actions in other repos.

## Actions

Current list of actions and their usage

### Checkov

Static code analysis of terraform. This action is triggered by an opened PR to the main branch.

### Markdown Linter

Markdown linter. Triggered on PR to main branch.

### Release

Creates a new tag and release on the repo.  This action is triggered by a merged PR to the main branch.

### Terraform Docs

Generate Terraform modules documentation then commit and push the changes. Triggered on PR to main branch.

This is a wrapper around [terraform-docs GitHub Actions](https://github.com/terraform-docs/gh-actions).

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