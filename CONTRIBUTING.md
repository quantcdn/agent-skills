# Contributing

## Rules for editing this repo

- Write only what a customer can do with their own API key or token, `quant`, `qc`, `curl`, and the dashboard.
- Never add internal IDs, hosts, bucket names, or vendor names. Run `scripts/leak-check.sh`.
- Keep the README skills table and the `AGENTS.md` routing table accurate.
- Run the checks below before you commit.

## Checks

Run these before every commit:

```
bats tests/
scripts/lint-skills.sh
scripts/leak-check.sh
shellcheck scripts/*.sh evals/run.sh
actionlint
```

`scripts/lint-skills.sh` checks each skill's frontmatter and headings, the relative links in
`SKILL.md` and `references/*.md`, and that every skill name a file refers to exists.

`scripts/check-drift.sh` compares the tool versions in each skill with the latest releases.
It needs network access. A weekly workflow runs it and opens one issue when a version drifts.

Each skill states what it was checked against in a line at the end of `SKILL.md`:

```
<!-- checked against npm:@quantcdn/quant-cli 7.0.1 -->
```

Supported sources are `npm:<package>`, `gh:<owner>/<repo>` (latest semver tag) and
`tf:<namespace>/<name>` (Terraform registry). Update the marker when you re-check a skill.

## Leak check with a private name list

`scripts/leak-check.sh` always scans for generic patterns: 12-digit account IDs, network and
security-group IDs, ARNs, IPv4 addresses and private-key headers. Named strings (internal
hosts, header names, product and repository names, customer names) are kept in a private list
outside the repository. Maintainers run the check with that list before every release:

1. Get the private list file from a maintainer. Keep it outside this repository.
   Each line is one case-insensitive fixed string. A line that starts with `re:` is an extended
   regular expression. Blank lines and lines that start with `#` are ignored.
2. Run the check on the whole repository:

   ```
   QUANT_LEAK_LIST=/path/to/private-list.txt scripts/leak-check.sh
   ```

3. Fix every `LEAK <file>:<line>` line. The command exits 0 when the repository is clean.

CI loads the same list from the `LEAK_PATTERNS` repository secret. When the secret is not
available (for example on a pull request from a fork), CI runs the generic patterns only.

The check never prints a private pattern. A match from the private list shows as
`LEAK <file>:<line>: private pattern #<n>`, where `n` is the line number in the list file.
Public CI logs therefore do not expose the list. Pull requests from forks cannot read the
secret, so CI runs the generic check only on them. Before you merge an external pull request,
run the full check with the private list on your machine.

Never commit the list file. Never paste its contents into an issue or a pull request.
