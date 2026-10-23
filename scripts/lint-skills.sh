#!/bin/sh
# Lint every skills/*/SKILL.md under a directory (default: repo root).
# Prints "FAIL <path>: <reason>" per problem. Exit 1 if any problem.
root=${1:-.}
status=0

fail() {
  printf 'FAIL %s: %s\n' "$1" "$2"
  status=1
}

# Print the frontmatter block (between the first two --- lines).
frontmatter() {
  awk 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} NR>1 {print}' "$1"
}

# Print one frontmatter field value (single-line YAML), quotes stripped.
field() {
  frontmatter "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -n 1 |
    sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
}

check_frontmatter() {
  [ -n "$(frontmatter "$1")" ] || fail "$1" "missing YAML frontmatter"
}

check_name() { # file folder
  name=$(field "$1" name)
  [ -n "$name" ] || { fail "$1" "missing name"; return; }
  printf '%s' "$name" | grep -Eq '^[a-z0-9-]{1,64}$' ||
    fail "$1" "name '$name' must match ^[a-z0-9-]{1,64}\$"
  [ "$name" = "$2" ] || fail "$1" "name '$name' must equal folder name '$2'"
}

check_description() {
  desc=$(field "$1" description)
  [ -n "$desc" ] || { fail "$1" "missing description"; return; }
  [ "${#desc}" -le 1024 ] || fail "$1" "description is longer than 1024 chars"
  case $desc in
    "Use when"*) ;;
    *) fail "$1" "description must start with 'Use when'" ;;
  esac
}

check_heading() { # file heading
  grep -qxF "$2" "$1" || fail "$1" "missing heading '$2'"
}

check_headings() {
  check_heading "$1" "## Applies to"
  check_heading "$1" "## Common problems"
  check_heading "$1" "## Further reading"
}

# Print relative link targets (no scheme, no anchor-only) one per line.
link_targets() {
  grep -o ']([^)]*)' "$1" | sed -e 's/^](//' -e 's/)$//' -e 's/#.*$//' |
    grep -Ev '^$|^[a-zA-Z][a-zA-Z0-9+.-]*:'
}

check_links() { # file
  dir=$(dirname "$1")
  link_targets "$1" | while IFS= read -r target; do
    [ -e "$dir/$target" ] || printf 'FAIL %s: broken link %s\n' "$1" "$target"
  done
}

# Print skill names a file refers to: `name` after "see", "load" or "skill(s)",
# every backticked name on a "Related skills" line, and table cells that hold
# only a backticked name. Backticks are literal in these patterns.
# shellcheck disable=SC2016
skill_refs() {
  {
    grep -oE '([Ss]ee|[Ll]oad|[Ss]kills?:?) `(quant|qc)-[a-z0-9-]+`' "$1"
    grep -E 'Related skills' "$1" | grep -oE '`(quant|qc)-[a-z0-9-]+`'
    grep -oE '^\| `(quant|qc)-[a-z0-9-]+` \||\| `(quant|qc)-[a-z0-9-]+` \|$' "$1"
  } | grep -oE '`[a-z0-9-]+`' | tr -d '`' | sort -u
}

check_skill_refs() { # file
  skill_refs "$1" | while IFS= read -r name; do
    [ -f "$root/skills/$name/SKILL.md" ] || printf 'FAIL %s: unknown skill %s\n' "$1" "$name"
  done
}

# Print FAIL lines for broken links and unknown skill names in a file.
check_refs() { # file
  check_links "$1"
  check_skill_refs "$1"
}

report() { # output of a check
  if [ -n "$1" ]; then
    printf '%s\n' "$1"
    status=1
  fi
}

check_skill() { # file
  folder=$(basename "$(dirname "$1")")
  check_frontmatter "$1"
  check_name "$1" "$folder"
  check_description "$1"
  check_headings "$1"
  report "$(check_refs "$1")"
  for ref in "$(dirname "$1")"/references/*.md; do
    [ -e "$ref" ] || continue
    report "$(check_refs "$ref")"
  done
}

for file in "$root"/skills/*/SKILL.md; do
  [ -e "$file" ] || continue
  check_skill "$file"
done
for file in "$root/AGENTS.md" "$root/README.md"; do
  [ -e "$file" ] || continue
  report "$(check_skill_refs "$file")"
done
exit "$status"
