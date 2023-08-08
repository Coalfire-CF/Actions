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

#### Inputs

| Name | Description | Default | Required |
| ---- | ----------- | ------- | -------- |
| recursive | if true it will generate documentation for submodules recursively | false | no |

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