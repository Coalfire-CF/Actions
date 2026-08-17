# Contributing

## Terraform module docs: install the hook

`README.md` in a Terraform module repo is **generated in full** by terraform-docs
from `_header.md` and `_footer.md`. CI verifies it and never pushes a commit to
your branch, so regenerating is your step. Install the hook once per clone:

```bash
pre-commit install
```

Regenerate on demand:

```bash
pre-commit run --all-files
```

Then commit the regenerated `README.md` with your change. If you skip this, the
`terraform-docs / docs` check fails on your PR with the exact diff.

Never edit `README.md` by hand: the next render overwrites it. Edit `_header.md`
or `_footer.md`.

The hook runs a pinned container rather than a local binary, because Homebrew
ships only the latest terraform-docs (0.24.0) and its output differs from the
0.20.0 that CI runs. Docker is required. On macOS, keep clones under your home
directory: Docker Desktop does not share `/tmp` by default, so a clone there
mounts empty and terraform-docs reports a missing config while appearing to run.

Full standard: [docs/ORG_TERRAFORM_DOCS.md](docs/ORG_TERRAFORM_DOCS.md).

## Contributing to this repo

- **Commit messages are conventional commits.** Releases and the changelog are
  produced by release-please from them, so `feat:` and `fix:` decide the version
  bump. A `chore:` or `docs:` commit does not release.
- **Pin every `uses:` by 40-character SHA** with a `# vX.Y.Z` trailing comment.
  CI fails on mutable refs.
- **Add a test under `tests/`** for any script change. CI runs `tests/*.test.sh`.
  Mutation-prove new assertions: perturb the input and confirm the check fails,
  because a check that cannot fail is worse than no check.
- **`shellcheck scripts/*.sh` must pass.**
- **Markdown is linted with `markdownlint-cli2` 0.23.0**, which is the version CI
  runs. Note `package.json` pins 0.23.2 for its dependency tree, so lint locally
  with the CI version if you are chasing a CI-only failure.

Run the checks locally before pushing:

```bash
shellcheck scripts/*.sh
for t in tests/*.test.sh; do bash "$t" || echo "FAILED: $t"; done
npx markdownlint-cli2@0.23.0 '**/*.md'
```
