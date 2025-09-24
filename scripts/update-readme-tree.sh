#!/usr/bin/env bash
set -euo pipefail

# ---- Defaults if config file is missing ----
DEFAULT_FILES=("README.md")
DEFAULT_CHAPTER="Tree"
DEFAULT_INCLUDE=(".")

# Allow override via env (optional)
EXCLUDE_PATTERN="${EXCLUDE_PATTERN:-.git|node_modules|.github}"

CONFIG_PATH=".github/readmetreerc.yml"
FILES=("${DEFAULT_FILES[@]}")
CHAPTER="$DEFAULT_CHAPTER"
INCLUDE=("${DEFAULT_INCLUDE[@]}")

if [[ -f "$CONFIG_PATH" ]]; then
  # Parse chapter
  cfg_chapter="$(grep -E '^[[:space:]]*chapter[[:space:]]*:' "$CONFIG_PATH" \
    | head -n1 | cut -d: -f2- | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [[ -n "${cfg_chapter}" ]] && CHAPTER="${cfg_chapter}"

  # Parse fileNames
  if grep -qE '^[[:space:]]*file[Nn]ames[[:space:]]*:' "$CONFIG_PATH"; then
    mapfile -t list_files < <(awk '
      BEGIN{inList=0}
      /^[[:space:]]*file[Nn]ames[[:space:]]*:/ {inList=1; next}
      inList && /^[[:space:]]*-/ {
        gsub(/^[[:space:]]*-[[:space:]]*/, "", $0);
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0);
        print $0; next
      }
      inList && !/^[[:space:]]*-/ {inList=0}
    ' "$CONFIG_PATH")
    (( ${#list_files[@]} )) && FILES=("${list_files[@]}")
  fi

  # Parse include
  if grep -qE '^[[:space:]]*include[[:space:]]*:' "$CONFIG_PATH"; then
    mapfile -t list_include < <(awk '
      BEGIN{inList=0}
      /^[[:space:]]*include[[:space:]]*:/ {inList=1; next}
      inList && /^[[:space:]]*-/ {
        gsub(/^[[:space:]]*-[[:space:]]*/, "", $0);
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0);
        print $0; next
      }
      inList && !/^[[:space:]]*-/ {inList=0}
    ' "$CONFIG_PATH")
    (( ${#list_include[@]} )) && INCLUDE=("${list_include[@]}")
  fi
fi

# Ensure include paths exist
declare -a EXISTING_INCLUDE=()
for p in "${INCLUDE[@]}"; do
  [[ -e "$p" ]] && EXISTING_INCLUDE+=("$p") || echo "Skipping missing include: $p"
done
(( ${#EXISTING_INCLUDE[@]} == 0 )) && EXISTING_INCLUDE=(".")

# Build tree
tree_output="$(tree -I "$EXCLUDE_PATTERN" --noreport --charset ascii "${EXISTING_INCLUDE[@]}" | sed 's/`/|/g')"

changed=0
for file_name in "${FILES[@]}"; do
  if [[ ! -f "$file_name" ]]; then
    echo "File $file_name not found, skipping."
    continue
  fi

  final_tree="## ${CHAPTER}
\`\`\`
${tree_output}
\`\`\`"

  if grep -q "^## ${CHAPTER}\$" "$file_name"; then
    # Replace existing section
    awk -v chapter="$CHAPTER" -v tree="$final_tree" '
      BEGIN {p=1; found=0}
      $0 ~ "^## "chapter"$" {print tree; p=0; found=1; next}
      $0 ~ /^## / && p==0 {p=1}
      p==1 {print}
      END {if (found==0) print "\n" tree}
    ' "$file_name" > "$file_name.new"
    mv "$file_name.new" "$file_name"
  else
    # Append if missing
    printf "\n%s\n" "$final_tree" >> "$file_name"
  fi
  changed=1
done

# Exit code 10 if updated
(( changed == 1 )) && exit 10 || exit 0
