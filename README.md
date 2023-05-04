# ACE-ToolingTemplate

Template repository for management of ACE code. This repo should be used as the framework for maintaining ACE code that is not a part of the Launchpad stack

## Description

- Terraform Version:
- Cloud(s) supported:{Government/Commercial}
- Product Version/License:
- FedRAMP Compliance Support: {}
- DoD Compliance Support:{IL4/5}
- Misc Framework Support:
- Launchpad validated version:

### Setup and usage

Describes what changes are needed to leverage this code. Likely should have several sub headings including items as

- process/structure for code modifications in the version of Launchpad listed above
- modules/output/variable updates
- removal of existing LP technology

#### Code Location

Code should be stored in terraform/app/code

#### Code updates

Ensure that vars zyx are in regional/global vars

### **Issues**

Bug fixes and enhancements are managed, tracked, and discussed through the GitHub issues on this repository.

Issues should be flagged appropriately.

- Bug
- Enhancement
- Documentation
- Code

#### Code Owners

- Primary Code owner: Douglas Francis (@douglas-f)
- Backup Code owner: James Westbrook (@i-ate-a-vm)

The responsibility of the code owners is to approve and Merge PR's on the repository, and generally manage and direct issue discussions.

### Repository Settings

Settings that should be applied to repos

#### Branch Protection

##### main Branch

- Require a pull request before merging
- Require Approvals
- Dismiss stale pull requests approvals when new commits are pushed
- Require review from Code Owners

##### other branches

- add as needed

##### Markdown Linter

- Triggered by a Pull Request on the main branch
- Makes use of the markdown-lint.yml and the customrules.js files, and will lint the README.md file present in the project's Top Level Directory and create a comment on the Pull Request with its body as any markdown formatting errors that are found or if there are none, then it will output 'Markdown Valid' as the body of the comment
- The only change that may need to be made is if the README.md file is not in the Top Level Directory, then the file path value must be changed in markdown-lint.yml, line 21

##### Checkov Scan

- Triggered by a Pull Request on the main branch
- Makes use of the checkov.yml file, and will scan the Terraform code present in the directory for any security or compliance misconfigurations using graph-based scanning and will create a comment on the Pull Request with its body as the findings from the scan
- No changes truly need to be made
