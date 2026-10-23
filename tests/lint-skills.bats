#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK="$(mktemp -d)"
}

teardown() { rm -rf "$WORK"; }

stage() { # fixture-name [folder-name]
  mkdir -p "$WORK/skills/${2:-$1}"
  cp -R "$ROOT/tests/fixtures/$1/." "$WORK/skills/${2:-$1}/"
}

@test "good-skill passes" {
  stage good-skill
  run "$ROOT/scripts/lint-skills.sh" "$WORK"
  [ "$status" -eq 0 ]
}

@test "bad-name fails with name" {
  stage bad-name
  run "$ROOT/scripts/lint-skills.sh" "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"*"name"* ]]
}

@test "no-description fails with description" {
  stage no-description
  run "$ROOT/scripts/lint-skills.sh" "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"description"* ]]
}

@test "missing Common problems heading fails" {
  stage good-skill
  sed -i.bak '/^## Common problems/d' "$WORK/skills/good-skill/SKILL.md"
  run "$ROOT/scripts/lint-skills.sh" "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Common problems"* ]]
}

@test "name differing from folder fails" {
  stage good-skill other-folder
  run "$ROOT/scripts/lint-skills.sh" "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"name"* ]]
}

@test "description not starting with Use when fails" {
  stage good-skill
  sed -i.bak 's/^description: Use when/description: Run when/' "$WORK/skills/good-skill/SKILL.md"
  run "$ROOT/scripts/lint-skills.sh" "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Use when"* ]]
}

@test "broken relative link fails" {
  stage good-skill
  rm "$WORK/skills/good-skill/references/extra.md"
  run "$ROOT/scripts/lint-skills.sh" "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"link"* ]]
}

@test "broken link in a references file fails" {
  stage good-skill
  echo "See [missing](missing.md)." >> "$WORK/skills/good-skill/references/extra.md"
  run "$ROOT/scripts/lint-skills.sh" "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"references/extra.md: broken link missing.md"* ]]
}

@test "unknown skill name after see fails" {
  stage good-skill
  echo "For more, see \`quant-nope\`." >> "$WORK/skills/good-skill/SKILL.md"
  run "$ROOT/scripts/lint-skills.sh" "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown skill quant-nope"* ]]
}

@test "unknown skill name in a Related skills line fails" {
  stage good-skill
  echo "- Related skills: \`good-skill\`, \`qc-missing\`" >> "$WORK/skills/good-skill/references/extra.md"
  run "$ROOT/scripts/lint-skills.sh" "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown skill qc-missing"* ]]
}

@test "unknown skill name in the AGENTS.md routing table fails" {
  stage good-skill
  printf '| Task | Skill |\n|---|---|\n| Thing | `quant-gone` |\n' > "$WORK/AGENTS.md"
  run "$ROOT/scripts/lint-skills.sh" "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AGENTS.md: unknown skill quant-gone"* ]]
}

@test "backticked non-skill names elsewhere pass" {
  stage good-skill
  echo "Uses \`quant-cloud-init-action\` and the \`quant-token\` header." >> "$WORK/skills/good-skill/SKILL.md"
  run "$ROOT/scripts/lint-skills.sh" "$WORK"
  [ "$status" -eq 0 ]
}
