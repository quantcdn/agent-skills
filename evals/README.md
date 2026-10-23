# Evals

Each skill has `evals/<skill>.md`: a list of prompts in this format.

```
Prompt: <what the user asks>
Platform: public|gov
Must include:
- <fact the answer states>
Must not include:
- <wrong fact or leak>
```

`evals/routing.md` is a table of `Prompt | Expected skill`. Exactly one skill is primary per prompt.

## Run an eval

Each run is a separate headless Claude Code process in a fresh empty directory. Do not use subagents.
Put one prompt in a plain text file, then:

```
evals/run.sh baseline prompt.txt                     # no skills
evals/run.sh with-skill quant-cli prompt.txt         # skill appended, folder readable
evals/run.sh route prompt.txt                        # prints the one skill name chosen
```

Every run uses `claude -p --safe-mode`. Safe mode leaves out the runner's own customisations:
user and project `CLAUDE.md` files, auto-memory, installed skills, plugins, hooks and MCP servers.
It works with a normal Claude Code login (no API key needed), so results do not depend on whose
machine ran them. Admin-managed policy settings still apply. (`--bare` would also isolate the run,
but it accepts only an API key.) Results in the table below from before 2026-10-23 W1 were run
without safe mode; the prompts re-run in W1 used it.

Baseline runs have no tools at all (`--tools ""`), so they cannot read local files.
With-skill runs can only read files (`--tools Read`). Route runs have no tools (`--tools ""`).
Set `QUANT_EVAL_TIMEOUT` (seconds, default 300) to change the limit per run.
Runs cost tokens. Do not run them in CI.

## Score

1. Run the prompt as baseline. Read the answer.
2. Run the same prompt with the skill. Read the answer.
3. For each `Must include` line, mark pass or fail. For each `Must not include` line, mark pass if absent.
4. The skill must pass every line with the skill and should fail some lines at baseline.
5. Record the results in the commit message of the skill task.

## Route check

Run `evals/run.sh route` for every row in `evals/routing.md`. The output must equal the expected skill.

## Release results (2026-10-23)

Run before v1.0.0. Every prompt in each `evals/<skill>.md` was run with the skill
(`evals/run.sh with-skill`). Each `Must include` and `Must not include` line was scored by reading
the answer. A line passes if the answer states the fact (include) or does not present the wrong
fact as advice (not include). Raw outputs are kept outside git.

Final wave W1 (same day) fixed the skill gaps and unfair lines behind the 10 failed lines, added
prompts, and re-ran 15 prompts with the skill in safe mode (see "Run an eval"). Prompts that failed
a line were fixed and re-run; the table shows the latest run of each prompt. Prompts that W1 did not
re-run keep their release result.

| Skill | Prompts | Lines passed | Lines total | Failed lines |
|---|---|---|---|---|
| `qc-cli` | 5 | 37 | 37 | |
| `quant-ai` | 5 | 46 | 46 | |
| `quant-ci-github-actions` | 5 | 40 | 40 | |
| `quant-cli` | 5 | 31 | 31 | |
| `quant-cloud-apps` | 5 | 37 | 37 | |
| `quant-cms-integrations` | 5 | 37 | 37 | |
| `quant-domains-cache-purge` | 5 | 38 | 38 | |
| `quant-edge-functions-and-kv` | 5 | 32 | 32 | |
| `quant-iac` | 5 | 39 | 39 | |
| `quant-platform` | 5 | 32 | 32 | |
| `quant-rules-and-routing` | 6 | 39 | 39 | |
| `quant-search` | 5 | 38 | 38 | |
| `quant-static-sites` | 6 | 38 | 38 | |
| `quant-studio` | 5 | 35 | 36 | P2: does not mention the Import from Website path and Migration screen (failed in both W1 runs; the prompt asks about redirects, not import) |
| `quant-templates` | 5 | 35 | 35 | |
| **Total** | 77 | **554** | **555** | 1 failed line (follow-up) |

### Final fix wave (2026-10-23)

After the final review, these prompts were re-run with the skill in safe mode (`evals/run.sh with-skill`):

| Prompt | Lines passed | Notes |
|---|---|---|
| `quant-cloud-apps` P1 to P5 (all) | 37 of 37 | P3 states the 120 s default and a 600 s example but not the 3600 s maximum; scored as a pass |
| `quant-studio` P2 | 7 of 8 | Still does not mention the Import from Website path (the prompt asks about redirects); open |
| `quant-templates` P2, P4 | 13 of 13 | Re-run after the template build-platform and compose-action changes |
| `quant-platform` P4 | 6 of 6 | Re-run after the "same products" line change |
| `quant-ci-github-actions` P2 | 9 of 9 | Re-run after the bare `base_url` change |

Must-not lines that now say "names a cloud vendor or managed service" replaced lists of vendor
names; the earlier answers did not name any vendor, so their scores do not change. The table
above (release results) still applies to every prompt not listed here.

### Routing

`evals/run.sh route` on every row of `evals/routing.md`: **53 of 53** rows route to the expected skill.

### Codex (AGENTS.md only)

`codex exec -s read-only` ran in a temporary directory that held only `AGENTS.md`. Five rows
(WAF proxy rule, inline `{{QUANT_FN}}`, GitLab pipeline, Drupal module install, Drupal host name
error): **5 of 5** named the expected skill.

### Follow-ups

W1 changes for the 10 release failures:

- Skill text added: `quant-cli` P3 (6.x derived the UUID from customer, project and `id`),
  `quant-cms-integrations` P4 (log in to the gov platform before `qc exec`/`qc ssh`),
  `quant-search` P4 (keyword wipe with `quant search clear`; no included allowance),
  `quant-static-sites` P3 (`force` when a restored file is skipped), `quant-studio` P3 (a provided
  `_quant404` is never overwritten), `quant-iac` P4 (Pulumi matches the Terraform provider).
- Eval lines judged unfair and rewritten: `quant-ci-github-actions` P1 (the prompt does not ask why
  tags move), `quant-cms-integrations` P2 (the prompt does not ask where the Drupal token lives),
  `quant-studio` P2 (the prompt does not ask about feature parity), `quant-iac` P4 (registry docs
  were not asked for). Also `qc-cli` P2 (`--detach` parenthetical removed), `quant-ai` P3 (scoped to
  the daily limit asked) and P5 (`bearer` or `QUANTCDN_API_TOKEN`).
- `quant-ci-github-actions` now tells agents to look up third-party SHAs, never recall them; P1 has a
  line for it.

Open: `quant-studio` P2 Import-from-Website line (see table). Prompts that W1 did not re-run were not
re-checked against the W1 skill edits.
