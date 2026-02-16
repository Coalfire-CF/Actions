# Release Artifact Cleaner

## What This Does

> **This workflow REMOVES files from your release artifacts.**
>
> When a GitHub release is created, a **cleaned tarball** is produced that **excludes**
> directories and files you specify (or the defaults listed below). The cleaned tarball
> is uploaded as a release asset alongside the standard GitHub-generated source archives.
>
> **Your repository, branches, and tags are never modified.** Only the tarball asset is affected.

When release-please creates a new release, `org-release.yml` triggers several parallel jobs:

```
release (release-please creates the tag and release)
  |
  ├── release-clean   -- Builds a cleaned tarball (THIS FEATURE)
  ├── checkov-scan    -- Checkov IaC security scan (full repo)
  ├── infracost       -- Infracost cost breakdown (full repo)
  └── trivy-scan      -- Trivy security scan (full repo)
```

The `release-clean` job:

1. Checks out the code at the release tag on an **isolated, ephemeral runner**
2. Validates all inputs against an allowlist (rejects special characters and path traversal)
3. Removes `.git/` (always), plus any configured directories and files
4. Packages the remaining files into `<repo>-<tag>-clean.tar.gz`
5. Generates a SHA256 checksum file (`<repo>-<tag>-clean.tar.gz.sha256`)
6. Uploads both to the GitHub release as downloadable assets
7. Also uploads both as workflow artifacts (retained for 30 days)
8. Writes a step summary with archive details for the Actions run log

**Scan jobs are not affected.** They run on their own runners with a full, unmodified checkout — `.github/`, `docs/`, and everything else are still scanned.

## What Gets Removed by Default

**This is on by default.** If you call `org-release.yml` without any `with:` overrides, the following are stripped from the clean tarball:

### Directories

| Directory | Why |
|-----------|-----|
| `.github/` | CI/CD workflows, issue templates, PR templates — not needed by consumers |
| `docs/` | Repository documentation — not needed at runtime |

### Files

| File | Why |
|------|-----|
| `CHANGELOG.md` | Release history — available on the GitHub release page |
| `release-please-config.json` | Release-please configuration — release tooling only |
| `.release-please-manifest.json` | Release-please state — release tooling only |
| `.gitignore` | Git configuration — not relevant to published artifacts |
| `.gitattributes` | Git configuration — not relevant to published artifacts |

### Always Removed

| Path | Why |
|------|-----|
| `.git/` | Git metadata — always removed, not configurable, never belongs in a release artifact |

**If a listed file or directory does not exist in your repo, it is skipped gracefully — no error, no failure.**

## How to Use

### Default Behavior (No Changes Needed)

If you already call `org-release.yml`, you automatically get clean tarballs on your next release:

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    branches:
      - main

permissions:
  contents: write
  pull-requests: write
  issues: write
  actions: read

jobs:
  create-release:
    uses: Coalfire-CF/Actions/.github/workflows/org-release.yml@main
    secrets: inherit
```

After a release is created, the release page will have:

- `<repo>-<tag>-clean.tar.gz` — the cleaned tarball
- `<repo>-<tag>-clean.tar.gz.sha256` — SHA256 checksum

The tarball extracts into a `<repo>-<tag>/` directory, matching the GitHub auto-generated archive convention.

### Custom Exclusions

Add or change which directories and files are removed:

```yaml
jobs:
  create-release:
    uses: Coalfire-CF/Actions/.github/workflows/org-release.yml@main
    secrets: inherit
    with:
      clean_exclude_dirs: '.github,docs,.ci,tests'
      clean_exclude_files: 'CHANGELOG.md,Makefile,release-please-config.json,.release-please-manifest.json,.gitignore,.gitattributes'
```

Values are **comma-separated, no spaces around commas**. Each entry must match `[a-zA-Z0-9._/-]` — special characters and `..` (path traversal) are rejected.

### Disable Clean Release Entirely

If you do not want a cleaned tarball attached to your releases:

```yaml
jobs:
  create-release:
    uses: Coalfire-CF/Actions/.github/workflows/org-release.yml@main
    secrets: inherit
    with:
      clean_release: false
```

## Inputs Reference

| Input | Type | Default | Description |
|-------|------|---------|-------------|
| `clean_release` | boolean | `true` | Set to `false` to skip clean tarball creation entirely |
| `clean_exclude_dirs` | string | `.github,docs` | Comma-separated directories to remove |
| `clean_exclude_files` | string | `CHANGELOG.md,release-please-config.json,.release-please-manifest.json,.gitignore,.gitattributes` | Comma-separated files to remove |

## Security Controls

| Control | NIST 800-53 | Description |
|---------|-------------|-------------|
| Input validation | SI-10 | All inputs validated against allowlist regex; path traversal (`..`) rejected |
| No shell interpolation | SC-28 | Inputs passed via `env:` blocks, never direct `${{ }}` in shell scripts |
| SHA256 checksum | SI-7 | Integrity verification for the released artifact |
| Step summary | AU-3 | Audit trail of what was built, excluded, and uploaded |
| Least privilege | AC-6 | Only requires `contents: write` and `actions: read`; no `secrets: inherit` |

## Verifying a Download

After downloading the tarball from a release:

```bash
# Verify checksum
sha256sum -c <repo>-<tag>-clean.tar.gz.sha256

# Extract
tar -xzf <repo>-<tag>-clean.tar.gz

# Confirm excluded files are absent
ls <repo>-<tag>/
```

## Complementary: .gitattributes

GitHub's auto-generated source archives (the default `.tar.gz` and `.zip` on every release) respect `.gitattributes` `export-ignore` directives. If you want those auto-generated archives cleaned as well, add a `.gitattributes` to your repo:

```gitattributes
.github/ export-ignore
docs/ export-ignore
CHANGELOG.md export-ignore
release-please-config.json export-ignore
.release-please-manifest.json export-ignore
```

This is **complementary** — the workflow handles the explicit `-clean.tar.gz` asset, `.gitattributes` handles the auto-generated archives. Both approaches leave the repository untouched.

## FAQ

**Q: Will this break my CI scans (Checkov, Trivy, Infracost)?**
No. Each scan job runs on its own isolated runner with a fresh, full checkout. They never see the cleaned copy.

**Q: Does this modify my repository, branches, or tags?**
No. The job checks out code into an ephemeral runner workspace, deletes files from that workspace only, packages the result, and the runner is destroyed when the job finishes.

**Q: What if I list a file/directory that doesn't exist in my repo?**
It is skipped with a log message. The workflow continues without error.

**Q: Does this need any additional secrets?**
No. It only uses the automatic `github.token` — no `secrets: inherit` required for the clean job itself. (The parent `org-release.yml` call still needs `secrets: inherit` for the scan jobs.)

**Q: Can someone inject malicious input through the exclusion lists?**
Inputs are validated against a strict allowlist regex (`^[a-zA-Z0-9._/,-]+$`) and checked for path traversal (`..`). Invalid inputs fail the workflow immediately.
