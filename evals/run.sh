#!/bin/sh
# Eval harness. Each run is a separate headless Claude Code process (no subagents).
#   evals/run.sh baseline <prompt-file>
#   evals/run.sh with-skill <skill-name> <prompt-file>
#   evals/run.sh route <prompt-file>
# Env: QUANT_EVAL_TIMEOUT (seconds, default 300).
REPO=$(cd "$(dirname "$0")/.." && pwd)
TIMEOUT=${QUANT_EVAL_TIMEOUT:-300}

usage() {
  cat >&2 <<USAGE
Usage:
  evals/run.sh baseline <prompt-file>
  evals/run.sh with-skill <skill-name> <prompt-file>
  evals/run.sh route <prompt-file>
USAGE
  exit 2
}

die() {
  printf 'run.sh: %s\n' "$1" >&2
  exit 2
}

need_prompt() {
  [ -f "$1" ] || die "prompt file not found: $1"
}

need_skill() {
  [ -f "$REPO/skills/$1/SKILL.md" ] || die "unknown skill: $1"
}

# Run a command with a time limit, using whichever tool exists.
with_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$TIMEOUT" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$TIMEOUT" "$@"
  else
    fallback_timeout "$@"
  fi
}

# Watcher: sleep, then kill $1. On TERM it kills its own sleep first.
watch_and_kill() {
  trap 'kill "$nap" 2>/dev/null; exit 0' TERM
  sleep "$TIMEOUT" &
  nap=$!
  wait "$nap"
  kill "$1" 2>/dev/null
}

# Portable limit: run in background, kill after TIMEOUT seconds. Keeps stdin.
fallback_timeout() {
  "$@" <&0 &
  pid=$!
  watch_and_kill "$pid" >/dev/null 2>&1 &
  watcher=$!
  wait "$pid"
  code=$?
  kill "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
  return "$code"
}

# Run claude headless from a fresh empty directory. Args: prompt-file, then claude flags.
# --safe-mode keeps the runner's own CLAUDE.md files, memory, skills, plugins and hooks out of
# the run, so results do not depend on whose machine ran them. It works with a normal login.
run_claude() {
  prompt_file=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
  shift
  work=$(mktemp -d)
  cd "$work" || exit 2
  with_timeout claude -p --safe-mode --strict-mcp-config --disable-slash-commands --allowedTools Read "$@" < "$prompt_file"
  code=$?
  cd "$REPO" && rm -rf "$work"
  return "$code"
}

mode_baseline() {
  need_prompt "$1"
  run_claude "$1" --tools "" --append-system-prompt "You have no tools. Answer directly from your own knowledge."
}

mode_with_skill() {
  need_skill "$1"
  need_prompt "$2"
  dir="$REPO/skills/$1"
  note="Reference files for this skill live in $dir and may be read with the Read tool."
  run_claude "$2" --tools Read --append-system-prompt-file "$dir/SKILL.md" \
    --add-dir "$dir" --append-system-prompt "$note"
}

# Build "name: description" lines for every skill.
skill_index() {
  for f in "$REPO"/skills/*/SKILL.md; do
    [ -e "$f" ] || continue
    name=$(sed -n 's/^name:[[:space:]]*//p' "$f" | head -n 1)
    desc=$(sed -n 's/^description:[[:space:]]*//p' "$f" | head -n 1)
    printf -- '- %s: %s\n' "$name" "$desc"
  done
}

mode_route() {
  need_prompt "$1"
  index=$(mktemp)
  {
    printf 'You route requests to agent skills. Available skills:\n\n'
    skill_index
    printf '\nFor the user prompt, choose the ONE skill you would load.'
    printf ' Reply with only the skill name and nothing else.\n'
  } > "$index"
  run_claude "$1" --tools "" --append-system-prompt-file "$index"
  code=$?
  rm -f "$index"
  return "$code"
}

dispatch() {
  case "${1:-}:$#" in
    baseline:2) mode_baseline "$2" ;;
    with-skill:3) mode_with_skill "$2" "$3" ;;
    route:2) mode_route "$2" ;;
    *) usage ;;
  esac
}

dispatch "$@"
