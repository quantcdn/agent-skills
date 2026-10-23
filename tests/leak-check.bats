#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK="$(mktemp -d)"
  mkdir "$WORK/scan"
}

teardown() { rm -rf "$WORK"; }

@test "leaky fixture fails with four LEAK lines" {
  run "$ROOT/scripts/leak-check.sh" "$ROOT/tests/fixtures/leaky"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c '^LEAK ')" -eq 4 ]
}

@test "good-skill passes" {
  run "$ROOT/scripts/leak-check.sh" "$ROOT/tests/fixtures/good-skill"
  [ "$status" -eq 0 ]
}

@test "private key header fails" {
  printf -- '-----BEGIN RSA %s KEY-----\n' PRIVATE > "$WORK/scan/key.md"
  run "$ROOT/scripts/leak-check.sh" "$WORK/scan"
  [ "$status" -eq 1 ]
}

@test "named strings pass without a private list" {
  echo "Customer Acme-Corp asked." > "$WORK/scan/note.md"
  run "$ROOT/scripts/leak-check.sh" "$WORK/scan"
  [ "$status" -eq 0 ]
}

@test "private list entries match case-insensitively" {
  printf 'acme-corp\n\n' > "$WORK/list.txt"
  echo "Customer Acme-Corp asked." > "$WORK/scan/note.md"
  QUANT_LEAK_LIST="$WORK/list.txt" run "$ROOT/scripts/leak-check.sh" "$WORK/scan"
  [ "$status" -eq 1 ]
  [[ "$output" == *"LEAK"*"note.md:1"* ]]
}

@test "private list comments are ignored" {
  printf '# note\n' > "$WORK/list.txt"
  echo "A # note in prose." > "$WORK/scan/note.md"
  QUANT_LEAK_LIST="$WORK/list.txt" run "$ROOT/scripts/leak-check.sh" "$WORK/scan"
  [ "$status" -eq 0 ]
}

@test "relative private list path resolves from the caller" {
  printf 'acme-corp\n' > "$WORK/list.txt"
  echo "Acme-Corp" > "$WORK/scan/note.md"
  cd "$WORK"
  QUANT_LEAK_LIST=list.txt run "$ROOT/scripts/leak-check.sh" "$WORK/scan"
  [ "$status" -eq 1 ]
}

@test "missing private list file fails" {
  QUANT_LEAK_LIST="$WORK/nope.txt" run "$ROOT/scripts/leak-check.sh" "$WORK/scan"
  [ "$status" -eq 1 ]
  [[ "$output" == *"list file not found"* ]]
}

@test "allowed addresses do not match" {
  echo "Bind 0.0.0.0 or 127.0.0.1 locally." > "$WORK/scan/note.md"
  run "$ROOT/scripts/leak-check.sh" "$WORK/scan"
  [ "$status" -eq 0 ]
}

@test "excluded paths are not scanned" {
  mkdir -p "$WORK/scan/tests/fixtures" "$WORK/scan/.superpowers"
  echo "vpc-""0abc1234def5" > "$WORK/scan/tests/fixtures/a.md"
  echo "vpc-""0abc1234def5" > "$WORK/scan/.superpowers/b.md"
  run "$ROOT/scripts/leak-check.sh" "$WORK/scan"
  [ "$status" -eq 0 ]
}

@test "last private list line without trailing newline still matches" {
  printf 'other\nacme-corp' > "$WORK/list.txt"
  echo "Acme-Corp" > "$WORK/scan/note.md"
  QUANT_LEAK_LIST="$WORK/list.txt" run "$ROOT/scripts/leak-check.sh" "$WORK/scan"
  [ "$status" -eq 1 ]
}

@test "filenames with spaces are scanned" {
  echo "vpc-""0abc1234def5" > "$WORK/scan/with space.md"
  run "$ROOT/scripts/leak-check.sh" "$WORK/scan"
  [ "$status" -eq 1 ]
  [[ "$output" == *"with space.md:1:"* ]]
}

@test "filenames with colons keep the full name and line number" {
  echo "ok" > "$WORK/scan/a:b.md"
  echo "vpc-""0abc1234def5" >> "$WORK/scan/a:b.md"
  run "$ROOT/scripts/leak-check.sh" "$WORK/scan"
  [ "$status" -eq 1 ]
  [[ "$output" == "LEAK ./a:b.md:2: "* ]]
}

@test "regex list entries: stage prose passes but stage host fails" {
  printf 're:\\bstage\\.[a-z0-9-]+\\.\n' > "$WORK/list.txt"
  echo "Use backstage. And this stage. is fine." > "$WORK/scan/a.md"
  QUANT_LEAK_LIST="$WORK/list.txt" run "$ROOT/scripts/leak-check.sh" "$WORK/scan"
  [ "$status" -eq 0 ]
  printf "Host %s.example.cloud\n" stage > "$WORK/scan/b.md"
  QUANT_LEAK_LIST="$WORK/list.txt" run "$ROOT/scripts/leak-check.sh" "$WORK/scan"
  [ "$status" -eq 1 ]
}

@test "private list match prints its number, never the pattern text" {
  printf '# header\nzq-fake-private-7731\n' > "$WORK/list.txt"
  echo "See ZQ-FAKE-PRIVATE-7731 here." > "$WORK/scan/note.md"
  QUANT_LEAK_LIST="$WORK/list.txt" run "$ROOT/scripts/leak-check.sh" "$WORK/scan"
  [ "$status" -eq 1 ]
  [[ "$output" == *"LEAK ./note.md:1: private pattern #2"* ]]
  [[ "$output" != *"zq-fake-private"* ]]
  [[ "$output" != *"7731"* ]]
}

@test "private regex entry prints its number, never the pattern text" {
  printf 're:zq-regex-[0-9]+-secret\n' > "$WORK/list.txt"
  echo "zq-regex-42-secret" > "$WORK/scan/note.md"
  QUANT_LEAK_LIST="$WORK/list.txt" run "$ROOT/scripts/leak-check.sh" "$WORK/scan"
  [ "$status" -eq 1 ]
  [[ "$output" == *"LEAK ./note.md:1: private pattern #1"* ]]
  [[ "$output" != *"zq-regex"* ]]
}

@test "generic pattern matches still print the pattern text" {
  echo "vpc-""0abc1234def5" > "$WORK/scan/note.md"
  run "$ROOT/scripts/leak-check.sh" "$WORK/scan"
  [[ "$output" == *"LEAK ./note.md:1: vpc-"* ]]
}
