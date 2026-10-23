---
name: qc-cli
description: Use when working with the `qc` command (npm package `@quantcdn/quant-cloud-cli`) on Quant Cloud applications and environments on QuantCDN or QuantGov - log in and switch platforms (`qc login`, `qc platform`), set org/app/env context (`.quant.yml`, `--org --app --env`), read logs (`qc env logs`), read or set environment variables (`qc env vars`), run commands (`qc exec run`, `qc ssh`), start/stop/redeploy an environment, create or download backups, or watch metrics. For static sites, content, purge, redirects or edge functions use `quant-cli` instead; `qc` is not the content CLI.
---

# qc CLI (Quant Cloud CLI)

`qc` works with Quant Cloud applications and environments from a terminal: logs, commands,
SSH, state, backups and metrics. For the platform overview, the public/gov split and the APIs,
load `quant-platform` first. For how to build and configure an app (compose file, databases,
scaling), use `quant-cloud-apps`. For static-site and CDN work, use `quant-cli`.

## Applies to

Both platforms: QuantCDN (public) and QuantGov (gov). `@quantcdn/quant-cloud-cli` 0.7.0, Node.js
required. Checked against the 0.7.0 source and the cloud-cli pages of the public docs, 2026-10.
`qc env vars` is new in 0.7.0; run `qc --version` and upgrade if it is missing.

`qc` is the **cloud** CLI. It does not push static content, purge the CDN cache or manage edge
rules. `quant` (skill `quant-cli`) does those. The two tools use different credentials.

## Install

```bash
npm install -g @quantcdn/quant-cloud-cli
qc --version              # 0.7.0
# or, without installing:
npx @quantcdn/quant-cloud-cli
```

## Log in and choose the platform

`qc login` is interactive and needs a browser.

1. Run `qc login`.
2. Choose the platform: **QuantGov Cloud** (`dash.quantgov.cloud`) or **Quant Cloud**
   (`dashboard.quantcdn.io`).
3. Authorise in the browser. The CLI listens for the OAuth (PKCE) callback on
   `http://localhost:8090/callback` and stores tokens in `~/.quant/credentials`.

- If port 8090 is in use, pick another with `-p`: `qc login -p 9090`.
- The callback comes back to the machine that runs `qc`. On a headless server there is no browser
  to complete it; log in on a workstation instead.
- If a platform is already saved, `qc login` first asks **Add another platform**,
  **Re-authenticate current platform** or **Cancel**. If you choose Re-authenticate while the
  current session is still valid, a second prompt asks you to confirm that the session is
  replaced (default No). The platform list appears after that.
- `qc login --endpoint <url>` skips the platform list and saves that host as the platform id
  `custom`. It does not skip the Add / Re-authenticate / Cancel menu.
- `qc whoami` shows the signed-in user, the active org/app/env and token expiry.
  `qc logout` removes the stored credentials.

### Check the platform before you act

The platform comes only from what you chose in `qc login` and `qc platform switch`.

```bash
qc platform list          # every platform you are logged in to
qc platform current       # the active one
qc platform switch        # pick another (interactive)
qc platform remove        # forget one
```

**Known issue (0.7.0):** the `--platform` option on commands and a `platform:` key in `.quant.yml`
are accepted but ignored. Do not use them to target gov or public. Run `qc platform current`
before any command that changes something, especially if you are logged in to both platforms.

## The model: org, app, env

Quant Cloud is organised as **organisation > application > environment**. Almost every command
needs all three. `qc` resolves each from, highest first:

1. Flags: `--org <org>`, `--app <app>`, `--env <env>`
2. `.quant.yml` in the current directory or a parent, up to the git root
3. The saved context (`qc org select`, `qc app select`, `qc env select`)

```yaml
# .quant.yml (commit it; it holds no secrets)
org: example-org
app: example-app
env: production
```

- Use machine names (the names in the dashboard URL), not display names.
- A stale `.quant.yml` in a parent directory silently retargets commands. `qc org current`,
  `qc app current` and `qc env current` show what `qc` will use.
- In scripts and for agents, pass `--org --app --env` on every command. Many commands open a
  prompt when a value is missing, and a prompt hangs a CI job.
- `qc env logs`, `qc env metrics` and `qc env state *` also take the environment as a positional
  argument: `qc env logs production`.

## Commands

| Job | Command |
|---|---|
| List orgs, apps, projects | `qc org list`, `qc app list`, `qc project list` |
| Select context | `qc org select [id]`, `qc app select [id]`, `qc env select [name]` |
| List or create environments | `qc env list`, `qc env create <name> --clone-from <env> --min-capacity 1 --max-capacity 10` (both take only `--org`/`--app`, no `--env`) |
| Environment variables | `qc env vars list\|get\|set\|unset` (see below) |
| Read logs | `qc env logs --env production -n 200`, `qc env logs --env production -f` |
| Live metrics | `qc env metrics --env production -r 5` |
| Stop, start, redeploy | `qc env state stop`, `qc env state start`, `qc env state redeploy --tag <imageTag>` |
| Run a command (server side) | `qc exec run "<command>"` |
| Interactive shell or one-shot | `qc ssh`, `qc ssh --command "php -v"` |
| Backups | `qc backup list\|create\|download\|delete --type database\|filesystem` |
| Crawlers, visual regression | `qc crawler run\|list`, `qc vrt` |

Details, flags and prompts: [references/commands.md](references/commands.md).

### Logs

```bash
qc env logs --org example-org --app example-app --env production -f
```

- `-f/--follow` polls about every two seconds and prints new entries. Press Ctrl+C to stop.
- `-n/--lines` (default 100) only trims what the platform returned. If the platform returns fewer
  entries than you asked for, `qc` prints those. A large `-n` does not guarantee that many lines;
  for a longer window use the dashboard logs.
- Logs can lag a deploy. A missing startup line is not proof that startup failed.

### Environment state

```bash
qc env state stop      --org example-org --app example-app --env production
qc env state start     --org example-org --app example-app --env production
qc env state redeploy  --org example-org --app example-app --env production --tag v1.4.2
```

`stop` takes the environment offline. These commands do not ask for confirmation, so check the
target with `qc env current` first.

### Environment variables

```bash
qc env vars list  --org example-org --app example-app --env production          # values masked
qc env vars list  --org example-org --app example-app --env production --json   # also masked
qc env vars get   APP_DEBUG --org example-org --app example-app --env production # raw value
qc env vars set   APP_DEBUG false --org example-org --app example-app --env staging
printf '%s' "$API_TOKEN" | qc env vars set API_TOKEN --stdin \
  --org example-org --app example-app --env production
qc env vars set   --file .env.production --org example-org --app example-app --env production
qc env vars unset OLD_FLAG --yes --org example-org --app example-app --env production
```

- **A change does not redeploy.** It takes effect on the next redeploy. Run
  `qc env state redeploy` (same `--org --app --env`) to apply it now.
- `list` prints `********` for every value unless you add `--show-values`, so a list in a CI log
  does not leak values. `get KEY` prints the raw value and nothing else when stdout is not a
  terminal, so `VALUE=$(qc env vars get KEY ...)` works. `get` exits 1 if the variable is not set.
- Use `--stdin` for sensitive values, so they stay out of argv and shell history.
- `set --file` merges: it sets each variable in the file and keeps variables that are not in the
  file. It checks the whole file first (bad lines, invalid names, duplicate keys, unclosed quotes)
  and changes nothing if any line is wrong.
- `unset` asks for confirmation on a terminal; pass `--yes` in scripts (it does not prompt when
  there is no terminal). Unsetting a variable that is not set reports that nothing changed.
- Names start with a letter or `_`, then letters, digits, `_`, `.` or `-`.
- These are plain environment variables. Secrets are not managed by `qc env vars`; set them in the
  dashboard (**Environment & Secrets**).

### Backups

```bash
qc backup create   --org example-org --app example-app --env production \
  --type database --description "Before release"
qc backup list     --org example-org --app example-app --env production --type database
qc backup download <backupId> --org example-org --app example-app --env production \
  --type database --output ./backups
```

- `--type` is `database` (the default) or `filesystem`.
- Without `--description`, `backup create` stops to ask for one. Always pass it in scripts.
- `qc backup delete` is interactive and permanent.

## Run commands: `qc exec` and `qc ssh`

| | `qc exec run` | `qc ssh --command` |
|---|---|---|
| Where it runs | A one-off container, server side | Inside a live container, through your terminal session |
| Laptop sleeps or drops | Run continues | Command stops |
| Interactive input | No | Yes (`--interactive`) |
| Needs | Just `qc` | The `aws` CLI on your PATH, and SSH enabled for the environment in the dashboard |
| Maximum length | 1 hour, then status `TIMED_OUT` | While the session holds |

Use `exec` for migrations, imports and unattended jobs. Use `ssh` to debug a running container.

```bash
qc exec run "drush cron" --org example-org --app example-app --env production
qc exec run "./import.sh" --detach ...        # prints a run ID and returns
qc exec status <runId> --watch ...            # reattach; reprints output from the start
qc exec status <runId> ...                    # one-shot status and output
```

### How an exec run behaves

- **Fresh container.** Each run starts a new one-off container from the environment's image. Files
  you wrote in an earlier run or in a live container are not there, and startup logic in your image
  can run again. Do not assume the container is idle or empty.
- **Startup delay.** Expect about a minute before the first output while the container starts.
  Polling is every 15 seconds by default (`--interval`, minimum 5), so output arrives in batches.
- **Exit code.** The remote exit code becomes the `qc` exit code. A finished run prints
  `Completed (exit N)`.
- **Ctrl+C only detaches.** The run continues on the server. `qc` prints the reattach command.
- **Non-interactive.** A command that waits for input hangs until the one-hour cap.
- **No history.** `qc exec list` reports that run-history listing is not supported yet. Keep the
  run ID from `qc exec run`, and capture output while the run is live.
- **Container.** `--container <name>` picks one; the default is the first container in the task
  definition.

### Quoting: send scripts as base64

A command containing `&&`, `;` or `|` is run through `/bin/sh -c` on the server. Write it flat:

```bash
qc exec run "echo start && ./migrate.sh"        # good
qc exec run "sh -c 'echo start && ./migrate.sh'" # nested quoting gets mangled
```

For anything with quotes, write the script to a file and send it encoded. Base64 contains only
letters, digits, `+`, `/` and `=`, so no layer needs to unquote it:

```bash
B64=$(base64 < migrate.php | tr -d '\n')
qc exec run "echo $B64 | base64 -d > /tmp/migrate.php && php /tmp/migrate.php" \
  --org example-org --app example-app --env production
```

- Keep inline payloads small. A very large command string can be rejected by the platform. If it
  is, compress first (`gzip -9c file | base64 | tr -d '\n'`, then `base64 -d | gunzip` in the
  container) or have the container fetch the script from a place it can reach.
- Do not put passwords in the command string. Read them from the container's own environment
  variables. The command is stored with the run.
- Print a clear marker line at the end of your script (for example `MIGRATION_OK`) so you can
  check success without parsing the whole output.

### Read the output: strip the spinner

From 0.7.0, `qc` draws no spinner frames when stdout is not a terminal (a pipe, a log file, CI);
it prints only the final `✔`/`✖` lines. Version 0.6.x and earlier, and any tool that runs `qc`
under a pseudo-terminal, still write the spinner to **stdout** with carriage returns (`\r`) and
braille frames (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`). These frames bury the real lines and can make `grep` treat the
stream as binary. If you see them, filter the output. The braille characters in the pattern only
match in a UTF-8 locale, so set one (for example `LC_ALL=C.UTF-8`, or `en_US.UTF-8` on macOS):

```bash
export LC_ALL=C.UTF-8
qc exec run "..." --org example-org --app example-app --env production 2>&1 \
  | tr '\r' '\n' | grep -vE '^[[:space:]]*[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]' | grep -v '^[[:space:]]*$'
```

To keep only your markers, `grep -aE 'MIGRATION_OK|Completed'` instead. Check the exit status
with `${PIPESTATUS[0]}` in bash (or `set -o pipefail`), because the pipeline hides the `qc` exit code.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| Commands hit the wrong platform, or `--platform quantgov` has no effect | `--platform` and `platform:` in `.quant.yml` are ignored by 0.7.0 | `qc platform current`, then `qc platform switch` |
| `qc login` waits forever or cannot start | No browser on the machine, or port 8090 is busy | Log in on a workstation, or use `qc login -p <port>` |
| `qc login` shows a menu instead of the platform list | A platform is already saved | Choose Add another platform, or Re-authenticate |
| `No organization/application/environment specified` | Nothing in flags, `.quant.yml` or saved context | Pass `--org --app --env`, or run the `select` commands |
| Command targets the wrong app or env | A `.quant.yml` in a parent directory (up to the git root) | `qc app current`, `qc env current`; fix the file or pass flags |
| A script hangs | A command opened a prompt (`env select`, `env create` without a name or `--clone-from`, `backup create` without `--description`, `backup delete`, `env vars unset` on a terminal without `--yes`) | Pass every value as a flag |
| A script hangs after `qc env create` printed success | `env create` always ends with "Set '<name>' as active environment?" | Run it where a person can answer, or create the environment with the API or the environment action in CI |
| `qc env vars set` worked but the app still sees the old value | A variable change does not redeploy | `qc env state redeploy` |
| `qc env vars` is not a command | `qc` older than 0.7.0 | `npm install -g @quantcdn/quant-cloud-cli` |
| `qc env logs -n 1000` prints far fewer lines | `-n` trims the platform's response; it cannot add lines | Use `-f`, or the dashboard logs |
| `AWS CLI is required but not installed` from `qc ssh` | `qc ssh` runs through the `aws` CLI | Install the `aws` CLI so it is on your PATH; enable SSH for the environment in the dashboard |
| `403` on `qc ssh` or `qc exec run` | Your user lacks access on this environment | Ask an org admin for access |
| Output is full of `⠋` characters and `\r` | `qc` before 0.7.0, or run under a pseudo-terminal | Upgrade, or pipe through the filter above in a UTF-8 locale |
| Quoting is mangled in `qc exec run` | Nested `sh -c` quotes | Send the script as base64 |
| `Failed to create command run` on a long command | Inline command is too large | Compress, or fetch the script in the container |
| No output for a minute after `exec run` | The one-off container is starting | Wait; poll interval is 15 s |
| `exec run` ends `TIMED_OUT` | Run reached the one-hour cap | Split the job, or use a scheduled job on the environment |
| `qc exec list` shows nothing | Run history is not supported yet | Keep the run ID; use `qc exec status <runId>` |
| `qc` cannot see a static project or purge the cache | Wrong CLI | Use `quant` (skill `quant-cli`) |

## Further reading

- Get started: https://docs.quantcdn.io/cloud-cli/get-started/
- Commands: https://docs.quantcdn.io/cloud-cli/commands/
- Remote commands guide: https://docs.quantcdn.io/cloud-cli/guides/remote-commands/
- SSH guide: https://docs.quantcdn.io/cloud-cli/guides/ssh/
- Backups guide: https://docs.quantcdn.io/cloud-cli/guides/backups/
- Related skills: `quant-platform` (public vs gov), `quant-cloud-apps` (build and configure
  apps), `quant-cli` (content CLI), `quant-ci-github-actions` (CI instead of `qc`)

<!-- checked against npm:@quantcdn/quant-cloud-cli 0.7.0 -->
