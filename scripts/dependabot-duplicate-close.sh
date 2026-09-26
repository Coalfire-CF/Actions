#!/usr/bin/env bash
#
# Close open Dependabot PRs that a newer open Dependabot PR already covers.
#
# Dependabot does not close an old ungrouped PR when a config change (grouping,
# group-by) makes it open a new PR for the same dependency, so both stay open.
# A PR is a duplicate when a NEWER open Dependabot PR in the same repo bumps
# the same dependency AND changes every file the older PR changes (README.md
# ignored: terraform-docs rewrites it on some PRs and not others). Different
# directories never match, so per-directory PRs are left alone.
#
# Closing a Dependabot PR makes Dependabot skip that version. That is harmless
# here because the newer PR carries the same or a later update.
#
# Env:
#   REPO     owner/name (required)
#   DRY_RUN  "true" (default) logs would-close only; "false" closes.
#
# Prints one "CLOSE <repo>#<old> (covered by #<new>): <title>" line per duplicate
# and a final "SUMMARY <repo> open=<n> duplicates=<m>" line.

set -euo pipefail

: "${REPO:?REPO (owner/name) is required}"
DRY_RUN="${DRY_RUN:-true}"

prs="$(gh pr list -R "$REPO" --author 'app/dependabot' --state open --limit 200 \
  --json number,title,createdAt,files)"

# Dependency key from the title. Handles "bump X from a to b", "bump X in /d",
# "update X requirement from ...". Terraform git module names differ between
# grouped (label::github::Coalfire-CF/repo::ref) and ungrouped (label::repo)
# titles, so normalise both to label::repo. Group titles ("bump the x group")
# yield null and are never matched.
dupes="$(printf '%s' "$prs" | jq -c '
  def depkey:
    (try (.title | capture("(?i)(?:bump|update) (?:the )?(?<d>\\S+?)(?: requirement)?(?: from | in |$)").d) catch null)
    | if . == null then null
      elif test("::") then
        split("::") as $p
        | $p[0] + "::" + ((if $p[1] == "github" then $p[-2] else $p[1] end) | split("/") | last)
      else ascii_downcase end;
  def codefiles: [.files[].path | select(test("(^|/)README\\.md$") | not)];
  [ .[] | . + {key: depkey, cf: codefiles} ] as $all
  | [ $all[] as $old
      | select($old.key != null and ($old.cf | length) > 0)
      | ([ $all[]
           | select(.number != $old.number
                    and .createdAt > $old.createdAt
                    and .key == $old.key
                    and (($old.cf - .cf) | length) == 0) ]
         | sort_by(.createdAt) | last) as $new
      | select($new != null)
      | {old: $old.number, new: $new.number, title: $old.title} ]
')"

total="$(printf '%s' "$prs" | jq 'length')"
count="$(printf '%s' "$dupes" | jq 'length')"

while IFS=$'\t' read -r old new title; do
  [ -n "$old" ] || continue
  echo "CLOSE ${REPO}#${old} (covered by #${new}): ${title}"
  if [ "$DRY_RUN" = "false" ]; then
    gh pr close "$old" -R "$REPO" --comment "Closed as a duplicate of #${new}, which bumps the same dependency in the same files. Opened before the current dependabot.yml grouping; Dependabot keeps #${new} up to date."
  fi
done < <(printf '%s' "$dupes" | jq -r '.[] | [(.old|tostring), (.new|tostring), .title] | @tsv')

echo "SUMMARY ${REPO} open=${total} duplicates=${count} dry_run=${DRY_RUN}"
