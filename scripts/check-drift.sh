#!/bin/sh
# Report skills whose "checked against <tool> <version>" markers are older than the latest release.
#   scripts/check-drift.sh [repo-root]
# Marker form (one per line, usually in an HTML comment at the end of SKILL.md):
#   checked against npm:<package> <version>      latest from the npm registry
#   checked against gh:<owner>/<repo> <version>  latest semver tag on GitHub
#   checked against tf:<namespace>/<name> <version>  latest Terraform registry provider
# Env: DRIFT_LOOKUP  file of "<tool> <latest>" lines; replaces the network (tests).
#      GITHUB_TOKEN  optional, raises the GitHub rate limit.
# Output: "DRIFT <skill> <tool> <stated> -> <latest>". Exit 0 clean, 1 drift, 2 lookup error.
ROOT=${1:-$(cd "$(dirname "$0")/.." && pwd)}

fetch() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -fsS -H "Authorization: Bearer $GITHUB_TOKEN" "$1"
  else
    curl -fsS "$1"
  fi
}

latest_npm() {
  fetch "https://registry.npmjs.org/$(printf '%s' "$1" | sed 's|/|%2F|')/latest" |
    sed -n 's/.*"version":"\([^"]*\)".*/\1/p' | head -n 1
}

latest_gh() {
  fetch "https://api.github.com/repos/$1/tags?per_page=100" |
    sed -n 's/.*"name": *"\([^"]*\)".*/\1/p' |
    grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' | sort -V | tail -n 1
}

latest_tf() {
  fetch "https://registry.terraform.io/v1/providers/$1" |
    sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -n 1
}

latest_remote() {
  case $1 in
    npm:*) latest_npm "${1#npm:}" ;;
    gh:*) latest_gh "${1#gh:}" ;;
    tf:*) latest_tf "${1#tf:}" ;;
  esac
}

# Print the latest version for a tool, from the fixture file or the network.
latest_for() {
  if [ -n "${DRIFT_LOOKUP:-}" ]; then
    awk -v t="$1" '$1==t {print $2; exit}' "$DRIFT_LOOKUP" | sed 's/^v//'
  else
    latest_remote "$1" 2>/dev/null
  fi
}

# Print "<skill> <tool> <version>" for every marker.
markers() {
  grep -rE --include='*.md' 'checked against (npm|gh|tf):[^ ]+ v?[0-9]' "$ROOT/skills" |
    sed -E 's|^.*/skills/([^/]+)/.*checked against ([^ ]+) v?([0-9][^ ]*).*$|\1 \2 \3|' |
    sort -u
}

# True when $1 is a strictly lower version than $2.
older() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" = "$1" ]
}

check_marker() { # skill tool stated
  latest=$(latest_for "$2")
  if [ -z "$latest" ]; then
    printf 'check-drift: no latest version for %s\n' "$2" >&2
    return 2
  fi
  if older "$3" "$latest"; then
    printf 'DRIFT %s %s %s -> %s\n' "$1" "$2" "$3" "$latest"
    return 1
  fi
  return 0
}

main() {
  status=0
  list=$(markers)
  [ -n "$list" ] || exit 0
  while read -r skill tool stated; do
    check_marker "$skill" "$tool" "$stated"
    code=$?
    [ "$code" -gt "$status" ] && status=$code
  done <<LIST
$list
LIST
  # Exit 2 (lookup error) outranks drift so a broken lookup is never reported as clean.
  exit "$status"
}

main
