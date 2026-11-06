#!/usr/bin/env python3
"""Print the org markdownlint policy as canonical JSON.

The policy lives twice: the heredoc that .github/workflows/ci-markdown.yml
writes into every caller's checkout, and the root .markdownlint-cli2.jsonc
this repo lints itself with. The two differ in comments and indentation, so
they are compared after both are parsed.

  markdownlint-policy-extract.py workflow <ci-markdown.yml>
  markdownlint-policy-extract.py jsonc <.markdownlint-cli2.jsonc>
"""
import json
import re
import sys


def strip_jsonc(text):
    """Drop // and /* */ comments outside strings, then trailing commas."""
    out, i, n, in_str = [], 0, len(text), False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
        elif c == '"':
            in_str = True
            out.append(c)
            i += 1
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = n if end < 0 else end + 2
        else:
            out.append(c)
            i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


def heredoc(workflow_text):
    m = re.search(r"cat > \.markdownlint-cli2\.jsonc <<'JSONC'\n(.*?)\n[ \t]*JSONC\n", workflow_text, re.S)
    if not m:
        raise SystemExit("ci-markdown.yml: org config heredoc not found")
    return m.group(1)


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("workflow", "jsonc"):
        raise SystemExit(__doc__)
    text = open(sys.argv[2]).read()
    if sys.argv[1] == "workflow":
        text = heredoc(text)
    print(json.dumps(json.loads(strip_jsonc(text)), sort_keys=True, indent=2))


main()
