#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK="$(mktemp -d)"
  mkdir -p "$WORK/skills/demo"
  printf '%s\n' '---' 'name: demo' '---' \
    '<!-- checked against npm:@quantcdn/quant-cli 7.0.1 -->' \
    '<!-- checked against gh:quantcdn/deploy-action 7.0.1 -->' > "$WORK/skills/demo/SKILL.md"
}

teardown() { rm -rf "$WORK"; }

@test "stated equals latest exits 0" {
  printf '%s\n' 'npm:@quantcdn/quant-cli 7.0.1' 'gh:quantcdn/deploy-action v7.0.1' > "$WORK/latest.txt"
  DRIFT_LOOKUP="$WORK/latest.txt" run "$ROOT/scripts/check-drift.sh" "$WORK"
  [ "$status" -eq 0 ]
  [[ "$output" != *DRIFT* ]]
}

@test "stated older than latest prints DRIFT and exits 1" {
  printf '%s\n' 'npm:@quantcdn/quant-cli 7.1.0' 'gh:quantcdn/deploy-action 7.0.1' > "$WORK/latest.txt"
  DRIFT_LOOKUP="$WORK/latest.txt" run "$ROOT/scripts/check-drift.sh" "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT demo npm:@quantcdn/quant-cli 7.0.1 -> 7.1.0"* ]]
  [[ "$output" != *"DRIFT demo gh:"* ]]
}

@test "tool missing from the lookup file exits 2" {
  printf '%s\n' 'npm:@quantcdn/quant-cli 7.0.1' > "$WORK/latest.txt"
  DRIFT_LOOKUP="$WORK/latest.txt" run "$ROOT/scripts/check-drift.sh" "$WORK"
  [ "$status" -eq 2 ]
}

@test "drift plus a lookup error still prints DRIFT and exits 2" {
  printf '%s\n' 'npm:@quantcdn/quant-cli 7.1.0' > "$WORK/latest.txt"
  DRIFT_LOOKUP="$WORK/latest.txt" run "$ROOT/scripts/check-drift.sh" "$WORK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"DRIFT demo npm:@quantcdn/quant-cli 7.0.1 -> 7.1.0"* ]]
}

@test "no marker lines exits 0" {
  rm "$WORK/skills/demo/SKILL.md"
  printf '%s\n' '---' 'name: demo' '---' > "$WORK/skills/demo/SKILL.md"
  DRIFT_LOOKUP=/dev/null run "$ROOT/scripts/check-drift.sh" "$WORK"
  [ "$status" -eq 0 ]
}

@test "every real skill marker parses to a known source" {
  run grep -rhE 'checked against ' "$ROOT/skills"
  [ "$status" -eq 0 ]
  markers="$output"
  run grep -vE 'checked against (npm|gh|tf):[^ ]+ [0-9]+\.[0-9]+\.[0-9]+ -->$' <<<"$markers"
  # grep -v exits 1 when every line matched the marker form.
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}
