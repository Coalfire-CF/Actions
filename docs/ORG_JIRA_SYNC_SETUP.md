# Jira Integration Setup

This document explains how to configure the GitHub-to-Jira issue sync workflow.

## Which Authentication Method Should You Use?

The workflow supports two authentication methods. Choose the one that matches your Jira deployment:

| Jira Type | Authentication Method | Token Type |
|-----------|----------------------|------------|
| **Jira Cloud** (yourcompany.atlassian.net) | Basic Authentication | API Token (`JIRA_API_TOKEN`) |
| **Jira Data Center/Server** (self-hosted) | Bearer Token | Personal Access Token (`JIRA_PAT`) |

**Note**: If you previously had issues with Basic Auth being disabled, you're likely using **Jira Data Center/Server** and should use the Personal Access Token (PAT) method.

## Authentication Methods

### Option 1: Jira Cloud (API Token + Basic Auth)

Navigate to your repository Settings → Secrets and variables → Actions → Secrets

#### `JIRA_API_TOKEN` (Secret)
- **Type**: Repository Secret
- **Description**: Your Jira Cloud API token for authentication
- **How to get it**:
  1. Log into your Jira account
  2. Go to https://id.atlassian.com/manage-profile/security/api-tokens
  3. Click "Create API token"
  4. Give it a name (e.g., "GitHub Actions")
  5. Copy the token and save it as a secret
- **Note**: API tokens created before December 15, 2024 will expire between March 14 and May 12, 2026

You will also need to set the `JIRA_USER_EMAIL` secret (see below).

### Option 2: Jira Data Center/Server (Personal Access Token)

Navigate to your repository Settings → Secrets and variables → Actions → Secrets

#### `JIRA_PAT` (Secret)
- **Type**: Repository Secret
- **Description**: Your Personal Access Token for Jira Data Center/Server
- **How to get it**:
  1. Log into your Jira instance
  2. Click your avatar at the top right and select "Profile"
  3. Select "Personal access tokens" in the left-hand menu
  4. Click "Create token"
  5. Give it a name (e.g., "GitHub Actions") and set expiration as needed
  6. Copy the token and save it as a secret
- **Note**: PATs are only available for Jira Data Center/Server (v8.14+), not Jira Cloud
- **Authentication**: Uses Bearer token authentication (no email required)

## Required Secrets (All Configuration)

**Important**: All configuration values are stored as secrets to prevent exposure in public repositories.

Navigate to your repository Settings → Secrets and variables → Actions → Secrets

### 1. `JIRA_BASE_URL` (Secret)
- **Type**: Repository Secret
- **Description**: Your Jira instance URL
- **Example Cloud**: `https://yourcompany.atlassian.net`
- **Example Data Center**: `https://jira.yourcompany.com`
- **Format**: No trailing slash
- **Required for**: Both authentication methods

### 2. `JIRA_USER_EMAIL` (Secret)
- **Type**: Repository Secret
- **Description**: The email address associated with your Jira API token
- **Example**: `your.email@company.com`
- **Required for**: Jira Cloud (API Token authentication) only
- **Not needed for**: Jira Data Center/Server (PAT authentication)

### 3. `JIRA_PROJECT_KEY` (Secret)
- **Type**: Repository Secret
- **Description**: The project key where issues will be created
- **Example**: `PROJ` or `DEV`
- **How to find it**: Look at your Jira project URL or any issue key (the letters before the dash)
- **Required for**: Both authentication methods

### 4. `JIRA_ISSUE_TYPE_ID` (Secret)
- **Type**: Repository Secret
- **Description**: The numeric ID of the issue type you want to create
- **Common values**:
  - `10001` - Story
  - `10002` - Task
  - `10003` - Bug
  - `10004` - Epic
- **How to find it**:
  ```bash
  # Use this curl command to list available issue types:
  curl --request GET \
    --url 'https://yourcompany.atlassian.net/rest/api/3/issue/createmeta?projectKeys=YOUR_PROJECT_KEY&expand=projects.issuetypes.fields' \
    --header 'Authorization: Basic YOUR_BASE64_ENCODED_CREDENTIALS' \
    --header 'Accept: application/json' | jq '.projects[].issuetypes[] | {id, name}'
  ```
- **Required for**: Both authentication methods

### 5. `JIRA_LABEL` (Secret)
- **Type**: Repository Secret
- **Description**: Label to add to all synced Jira issues
- **Example**: `github-sync`, `automated`, or `from-github`
- **Note**: This helps identify issues that were created automatically from GitHub
- **Required for**: Both authentication methods

### 6. `JIRA_API_VERSION` (Secret) - Optional
- **Type**: Repository Secret
- **Description**: Jira REST API version to use
- **Default**: `3` (used if not specified)
- **When to change**: Set to `2` if you're using an older Jira Data Center/Server instance
- **Example**: `2` or `3`
- **Required for**: Optional - only set if you need API v2

## Workflow Behavior

When a GitHub issue is opened:
1. The workflow creates a corresponding Jira issue
2. The Jira issue includes:
   - Same title as the GitHub issue
   - Same description as the GitHub issue body
   - Link back to the original GitHub issue
   - The specified label
3. The Jira issue key and URL are logged in the workflow output (visible only to those with repository access)

## Testing the Setup

1. Create a test GitHub issue in your repository
2. Check the Actions tab to see if the workflow runs successfully
3. Verify the Jira issue was created in your project
4. Confirm the GitHub issue has a comment with the Jira link

## Troubleshooting

### Authentication Failed (401)

**For Jira Cloud (API Token):**
- Verify `JIRA_API_TOKEN` is correct and hasn't been regenerated
- Ensure `JIRA_USER_EMAIL` matches the account that created the API token
- Check that the API token hasn't expired (tokens created before Dec 15, 2024 expire in 2026)
- Verify Basic Authentication is enabled in your Jira Cloud instance

**For Jira Data Center/Server (PAT):**
- Verify `JIRA_PAT` is correct and hasn't been regenerated
- Check that the PAT hasn't expired (check expiration date when you created it)
- Ensure you have Bearer token authentication enabled
- Verify your Jira version supports PATs (v8.14+ for Jira, v4.15+ for JSM, v7.9+ for Confluence)

### Project Not Found (404)
- Verify `JIRA_PROJECT_KEY` is correct
- Ensure your Jira user has permission to create issues in that project

### Invalid Issue Type
- Use the createmeta API endpoint (shown above) to find valid issue type IDs
- Ensure the issue type is available in your project

### Permission Denied
- Verify your Jira user has "Create Issues" permission in the project
- Check if the project settings allow the specified issue type

### API Version Issues
- If you get 404 errors on the `/rest/api/3/issue` endpoint, try setting `JIRA_API_VERSION` to `2`
- Older Jira Data Center/Server instances may only support API v2

## Quick Reference

All configuration values are **Repository Secrets** (Settings → Secrets and variables → Actions → Secrets)

### For Jira Cloud

**Required Secrets:**
- `JIRA_API_TOKEN` - Your API token from id.atlassian.com
- `JIRA_BASE_URL` - Your Atlassian URL (e.g., `https://yourcompany.atlassian.net`)
- `JIRA_USER_EMAIL` - Email associated with the API token
- `JIRA_PROJECT_KEY` - Project key (e.g., `PROJ`)
- `JIRA_ISSUE_TYPE_ID` - Issue type ID (e.g., `10002`)
- `JIRA_LABEL` - Label for synced issues (e.g., `github-sync`)

**Optional Secrets:**
- `JIRA_API_VERSION` - Set to `2` if needed, defaults to `3`

### For Jira Data Center/Server

**Required Secrets:**
- `JIRA_PAT` - Your Personal Access Token from Jira profile
- `JIRA_BASE_URL` - Your Jira instance URL (e.g., `https://jira.yourcompany.com`)
- `JIRA_PROJECT_KEY` - Project key (e.g., `PROJ`)
- `JIRA_ISSUE_TYPE_ID` - Issue type ID (e.g., `10002`)
- `JIRA_LABEL` - Label for synced issues (e.g., `github-sync`)

**Optional Secrets:**
- `JIRA_API_VERSION` - Set to `2` for older instances, defaults to `3`

**Note:** `JIRA_USER_EMAIL` is NOT needed for PAT authentication

## Usage in Your Repository

To use this workflow in your repository, create a workflow file (e.g., `.github/workflows/jira-sync.yml`) with the following content:

### For Jira Cloud (API Token)

```yaml
name: Sync GitHub Issue to Jira

on:
  issues:
    types: [opened]

jobs:
  sync_to_jira:
    uses: Coalfire-CF/Actions/.github/workflows/org-jira-sync.yml@main
    with:
      issue_title: ${{ github.event.issue.title }}
      issue_body: ${{ github.event.issue.body }}
      issue_number: ${{ github.event.issue.number }}
      issue_url: ${{ github.event.issue.html_url }}
    secrets:
      JIRA_API_TOKEN: ${{ secrets.JIRA_API_TOKEN }}
      JIRA_BASE_URL: ${{ secrets.JIRA_BASE_URL }}
      JIRA_USER_EMAIL: ${{ secrets.JIRA_USER_EMAIL }}
      JIRA_PROJECT_KEY: ${{ secrets.JIRA_PROJECT_KEY }}
      JIRA_ISSUE_TYPE_ID: ${{ secrets.JIRA_ISSUE_TYPE_ID }}
      JIRA_LABEL: ${{ secrets.JIRA_LABEL }}
      JIRA_API_VERSION: ${{ secrets.JIRA_API_VERSION }}
      JIRA_PAT: ${{ secrets.JIRA_PAT }}
```

### For Jira Data Center/Server (Personal Access Token)

```yaml
name: Sync GitHub Issue to Jira

on:
  issues:
    types: [opened]

jobs:
  sync_to_jira:
    uses: Coalfire-CF/Actions/.github/workflows/org-jira-sync.yml@main
    with:
      issue_title: ${{ github.event.issue.title }}
      issue_body: ${{ github.event.issue.body }}
      issue_number: ${{ github.event.issue.number }}
      issue_url: ${{ github.event.issue.html_url }}
    secrets:
      JIRA_PAT: ${{ secrets.JIRA_PAT }}
      JIRA_BASE_URL: ${{ secrets.JIRA_BASE_URL }}
      JIRA_PROJECT_KEY: ${{ secrets.JIRA_PROJECT_KEY }}
      JIRA_ISSUE_TYPE_ID: ${{ secrets.JIRA_ISSUE_TYPE_ID }}
      JIRA_LABEL: ${{ secrets.JIRA_LABEL }}
      JIRA_API_VERSION: ${{ secrets.JIRA_API_VERSION }}
      JIRA_API_TOKEN: ${{ secrets.JIRA_API_TOKEN }}
      JIRA_USER_EMAIL: ${{ secrets.JIRA_USER_EMAIL }}
```

**Important Notes:**
- All secrets must be passed explicitly when calling the reusable workflow
- You can use **organization secrets** or **repository secrets** - both work identically
- Even if a secret is not needed for your authentication method (e.g., `JIRA_USER_EMAIL` for PAT auth), you still need to include it in the secrets list (it will simply be ignored)
- Replace `@main` with a specific version tag (e.g., `@v1.0.0`) for production use
