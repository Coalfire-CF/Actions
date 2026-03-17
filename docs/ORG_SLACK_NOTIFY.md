# Slack Notifications

## What This Does

Sends Slack notifications from GitHub Actions workflows. Supports three notification types:

- **Release** — posts to Slack when a new version is released, including version, highlights, and a changelog link
- **Failure** — posts to Slack when a workflow job fails, including workflow name, repo, and a link to the failed run
- **Health Check** — pings a URL and posts to Slack with UP/DOWN status and HTTP code

## Prerequisites

1. **Slack App** — A Slack app with `chat:write` bot scope installed to your workspace
2. **Org Secret** — `SLACK_BOT_TOKEN` stored as a GitHub org-level secret containing the bot's `xoxb-` token
3. **Bot Invite** — The bot must be invited to each channel: `/invite @Slack App Name`
4. **Channel ID** — Right-click the channel in Slack → View channel details → scroll to the bottom to find the Channel ID (starts with `C`)

## How It Works

### Release and Failure Notifications (built-in)

All reusable workflows in this repo accept an optional `slack_channel_id` input. When provided, the workflow automatically sends a Slack notification on failure. The `org-release.yml` workflow also sends a release notification when a new version is cut.

No extra jobs are needed in downstream repos. Just add `slack_channel_id` to your existing workflow calls.

### Downstream Usage

Add `slack_channel_id` and `secrets: inherit` to any workflow call:

```yaml
# Release workflow — gets both release and failure notifications
jobs:
  create-release:
    uses: Coalfire-CF/Actions/.github/workflows/org-release.yml@v0.4.0
    secrets: inherit
    with:
      slack_channel_id: 'CXXXXXXXXX'
```

```yaml
# PR workflows — get failure notifications
jobs:
  checkov-scan:
    uses: Coalfire-CF/Actions/.github/workflows/org-checkov.yml@v0.4.0
    secrets: inherit
    with:
      slack_channel_id: 'CXXXXXXXXX'
```

If `slack_channel_id` is omitted, no notifications are sent. Existing repos are unaffected.

### Supported Workflows

All reusable workflows support `slack_channel_id`:

| Workflow | Notification Type |
| -------- | ----------------- |
| `org-release.yml` | Release + Failure |
| `org-checkov.yml` | Failure |
| `org-gitleaks-pr.yml` | Failure |
| `org-trivy-pr.yml` | Failure |
| `org-terraform-validate.yml` | Failure |
| `org-terraform-fmt.yml` | Failure |
| `org-terraform-docs.yml` | Failure |
| `org-tree-readme.yml` | Failure |
| `org-markdown-lint.yml` | Failure |
| `org-dependabot.yml` | Failure |
| `org-jira-sync.yml` | Failure |
| `org-trivy-exception-review.yml` | Failure |

### Health Check (standalone)

For apps with a public health endpoint, create a dedicated workflow in the downstream repo:

```yaml
name: Health Check

on:
  schedule:
    - cron: '*/5 * * * *'

jobs:
  check:
    uses: Coalfire-CF/Actions/.github/workflows/org-slack-notify.yml@v0.4.0
    secrets: inherit
    with:
      notification-type: health-check
      channel-id: 'C08M58XQKME'
      app-name: 'My App'
      app-url: 'https://my-app.example.com/health'
```

### Direct Usage (advanced)

The `org-slack-notify.yml` workflow can also be called directly for custom notification scenarios:

```yaml
jobs:
  notify:
    uses: Coalfire-CF/Actions/.github/workflows/org-slack-notify.yml@v0.4.0
    secrets: inherit
    with:
      notification-type: release    # release, failure, or health-check
      channel-id: 'C08M58XQKME'
      app-name: 'my-repo'
      release-version: 'v1.2.0'
      release-highlights: '- Added feature X'
      changelog-url: 'https://github.com/Coalfire-CF/my-repo/blob/main/CHANGELOG.md'
```

## Inputs Reference

| Input | Required | Type | Description |
| ----- | -------- | ---- | ----------- |
| `notification-type` | Yes | `release` / `failure` / `health-check` | Type of notification to send |
| `channel-id` | Yes | string | Slack channel ID (starts with `C`) |
| `app-name` | No | string | Display name (defaults to repo name) |
| `release-version` | For release | string | Version tag |
| `release-highlights` | No | string | Release body / changelog content |
| `changelog-url` | No | string | Link to full changelog |
| `app-url` | For health-check | string | URL to health check |
