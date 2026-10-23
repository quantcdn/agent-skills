# qc-cli evals

Prompt: My agency signs in at https://dash.quantgov.cloud. I installed `qc` on a new laptop. Walk me through logging in, confirming I am on the right platform, and then tailing the logs of the `production` environment of the app `example-app` in org `example-org` without using any saved context. I also added `platform: quantgov` to `.quant.yml` and pass `--platform quantgov` in my script to make sure it hits gov.
Platform: gov
Must include:
- `qc login`, then choosing QuantGov (`dash.quantgov.cloud`) in the platform list; browser OAuth flow with a local callback on port 8090 (`-p` changes it)
- `qc platform current` (and `qc platform list` / `qc platform switch`) to check or change the platform
- A statement that `--platform` and `platform:` in `.quant.yml` do not select the platform in this CLI version, so the script must rely on `qc platform current` / `switch`
- `qc env logs --org example-org --app example-app --env production -f` (or `qc env logs production ...`)
Must not include:
- A recommendation to rely on `--platform quantgov` or `platform:` in `.quant.yml` to select the platform
- `dash.quantcdn.io`
- A claim that `qc` is the content CLI (`quant`)

Prompt: In CI I need to run a database migration script inside the `production` environment of `example-app` (org `example-org`) with `qc exec run`. The script is about 60 lines of PHP with single and double quotes. I tried `qc exec run "sh -c 'php -r \"...\"'"` and the quoting is mangled, and when I pipe the output through grep it is full of strange braille characters. How should I send it, how do I read the result reliably, and what should I expect about timing and how the run ends?
Platform: public
Must include:
- Send the script as base64 (or another encoding that avoids quotes) and decode it in the container, for example `echo $B64 | base64 -d > /tmp/s.php && php /tmp/s.php`; do not nest `sh -c` quoting by hand; shell operators such as `&&` are run through `/bin/sh -c` on the server
- Large inline commands can fail, so keep the payload small (compress or fetch the script instead)
- The braille characters are the spinner on stdout (`qc` before 0.7.0, or run under a pseudo-terminal; 0.7.0 draws no frames off a terminal); upgrade, or strip them in a UTF-8 locale, for example `2>&1 | tr '\r' '\n' | grep -vE '^\s*[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]'`, or grep for a marker line you print
- The run is a fresh one-off container, so allow about a minute before output; the remote exit code becomes the CLI exit code; reattach with `qc exec status <runId> --watch`; Ctrl+C only detaches
- Runs are capped at 1 hour (`TIMED_OUT`) and are non-interactive
- Pass `--org example-org --app example-app --env production` rather than relying on saved context
Must not include:
- A claim that `qc exec list` shows run history
- A claim that Ctrl+C stops the remote command

Prompt: `qc env logs production -n 1000` only prints a few dozen lines, `qc ssh` says AWS CLI is required, and `qc login` does nothing useful on my build server (headless, port 8090 is taken by another service). I also have an old `.quant.yml` in a parent directory that points at a different app and my commands hit the wrong environment. Diagnose each.
Platform: public
Must include:
- `-n/--lines` only trims what the platform returns, so the platform can return fewer entries than asked; use `-f` to follow, or the dashboard for a longer window
- `qc ssh` needs the `aws` CLI installed (and on PATH) because it opens the session through that CLI
- `qc login` needs a browser on a machine that can reach the local callback; use `-p <port>` to change the callback port from 8090, or log in on another machine
- Context priority: flags (`--org/--app/--env`) over `.quant.yml` (searched from the current directory up to the git root) over saved context; fix by passing flags, editing `.quant.yml`, or `qc app current`/`qc env current` to check
Must not include:
- A claim that `-n 1000` is guaranteed to return 1000 lines
- `--platform` as a fix for anything

Prompt: Before a risky release on `example-app` / `production` (org `example-org`) I want a database backup, then I want to stop the environment, start it again, and redeploy a specific image tag. Give the commands, make them non-interactive, and tell me how to download the backup. Our login is saved for the gov platform and the public platform; I want to be sure the commands hit gov.
Platform: gov
Must include:
- `qc backup create --type=database --org example-org --app example-app --env production --description "..."` (type is `database` or `filesystem`; database is the default)
- `qc env state stop`, `qc env state start`, `qc env state redeploy --tag <imageTag>` with `--org/--app/--env` flags
- `qc backup download <backupId> --output <dir>` (and `qc backup list` to find the id)
- Run `qc platform current` first and `qc platform switch` to gov if needed; `--platform` does not do this
- Warn that stop makes the environment unavailable
Must not include:
- `--platform quantgov` as the way to target gov
- `quant` (content CLI) commands for backups or environment state

Prompt: From a CI job (no terminal) I need to set `APP_DEBUG=false` and a secret-ish `API_TOKEN` from a CI variable on the `staging` environment of `example-app` (org `example-org`), print the current variables to the job log, read one value into a shell variable, remove `OLD_FLAG`, and make the app pick the changes up. Earlier the same job also ran `qc env create review-42 --org example-org --app example-app --clone-from staging --env review-42` and hung. Give the commands and explain the hang.
Platform: public
Must include:
- `qc env vars set APP_DEBUG false --org example-org --app example-app --env staging` (needs `qc` 0.7.0 or later)
- `API_TOKEN` is passed with `--stdin` (for example `printf '%s' "$API_TOKEN" | qc env vars set API_TOKEN --stdin ...`) so the value stays out of argv and shell history
- `qc env vars list` masks values unless `--show-values`; `qc env vars get <KEY>` prints only the raw value, so `VALUE=$(qc env vars get KEY ...)` works
- `qc env vars unset OLD_FLAG --yes` (or note that it does not prompt without a terminal)
- Variable changes do not redeploy; run `qc env state redeploy --org example-org --app example-app --env staging` to apply them
- `qc env create` takes only `--org`/`--app` (no `--env`), and always ends with a "Set ... as active environment?" prompt that hangs a non-interactive job
Must not include:
- A claim that `qc env vars set` redeploys the environment
- A recommendation to use `--platform` to pick the platform
- A claim that `qc env vars` manages secrets
