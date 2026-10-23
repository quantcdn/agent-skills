#!/usr/bin/env bats

setup() { ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"; }

@test "no arguments prints usage" {
  run "$ROOT/evals/run.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]]
}

@test "unknown mode prints usage" {
  run "$ROOT/evals/run.sh" bogus x
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]]
}

@test "baseline with missing prompt file fails" {
  run "$ROOT/evals/run.sh" baseline /nonexistent/prompt.txt
  [ "$status" -eq 2 ]
  [[ "$output" == *"prompt file"* ]]
}

@test "with-skill with unknown skill fails" {
  echo hi > "$BATS_TEST_TMPDIR/p.txt"
  run "$ROOT/evals/run.sh" with-skill no-such-skill "$BATS_TEST_TMPDIR/p.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"skill"* ]]
}

@test "with-skill with too few arguments prints usage" {
  run "$ROOT/evals/run.sh" with-skill only-one
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]]
}

@test "fallback timeout does not wait for the limit when claude exits at once" {
  fake="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$fake"
  printf '#!/bin/sh\necho pong\n' > "$fake/claude"
  chmod +x "$fake/claude"
  echo hi > "$BATS_TEST_TMPDIR/p.txt"
  start=$(date +%s)
  out=$(PATH="$fake:/usr/bin:/bin" QUANT_EVAL_TIMEOUT=30 "$ROOT/evals/run.sh" baseline "$BATS_TEST_TMPDIR/p.txt" 2>&1)
  end=$(date +%s)
  [ "$out" = "pong" ]
  [ $((end - start)) -lt 5 ]
}

@test "baseline runs claude with no tools" {
  fake="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$fake"
  printf '#!/bin/sh\nfor a in "$@"; do printf "[%%s]" "$a"; done\n' > "$fake/claude"
  chmod +x "$fake/claude"
  echo hi > "$BATS_TEST_TMPDIR/p.txt"
  base=$(PATH="$fake:/usr/bin:/bin" "$ROOT/evals/run.sh" baseline "$BATS_TEST_TMPDIR/p.txt")
  [[ "$base" == *"[--tools][]"* ]]
  [[ "$base" == *"[--append-system-prompt][You have no tools."* ]]
}

@test "with-skill runs claude with only the Read tool available" {
  fake="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$fake"
  printf '#!/bin/sh\nfor a in "$@"; do printf "[%%s]" "$a"; done\n' > "$fake/claude"
  chmod +x "$fake/claude"
  echo hi > "$BATS_TEST_TMPDIR/p.txt"
  skill=$(ls "$ROOT/skills" | head -n 1)
  with=$(PATH="$fake:/usr/bin:/bin" "$ROOT/evals/run.sh" with-skill "$skill" "$BATS_TEST_TMPDIR/p.txt")
  [[ "$with" == *"[--tools][Read]"* ]]
  [[ "$with" == *"[--allowedTools][Read]"* ]]
}

@test "route runs claude with no tools" {
  fake="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$fake"
  printf '#!/bin/sh\nfor a in "$@"; do printf "[%%s]" "$a"; done\n' > "$fake/claude"
  chmod +x "$fake/claude"
  echo hi > "$BATS_TEST_TMPDIR/p.txt"
  route=$(PATH="$fake:/usr/bin:/bin" "$ROOT/evals/run.sh" route "$BATS_TEST_TMPDIR/p.txt")
  [[ "$route" == *"[--tools][]"* ]]
}

@test "every mode runs claude in safe mode, isolated from user CLAUDE.md and memory" {
  fake="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$fake"
  printf '#!/bin/sh\nfor a in "$@"; do printf "[%%s]" "$a"; done\n' > "$fake/claude"
  chmod +x "$fake/claude"
  echo hi > "$BATS_TEST_TMPDIR/p.txt"
  skill=$(ls "$ROOT/skills" | head -n 1)
  base=$(PATH="$fake:/usr/bin:/bin" "$ROOT/evals/run.sh" baseline "$BATS_TEST_TMPDIR/p.txt")
  with=$(PATH="$fake:/usr/bin:/bin" "$ROOT/evals/run.sh" with-skill "$skill" "$BATS_TEST_TMPDIR/p.txt")
  route=$(PATH="$fake:/usr/bin:/bin" "$ROOT/evals/run.sh" route "$BATS_TEST_TMPDIR/p.txt")
  [[ "$base" == *"[--safe-mode]"* ]]
  [[ "$with" == *"[--safe-mode]"* ]]
  [[ "$route" == *"[--safe-mode]"* ]]
}
