# qc command reference

Checked against `@quantcdn/quant-cloud-cli` 0.7.0. Every command that works on an environment
accepts `--org`, `--app` and `--env` overrides unless noted. `--platform` is accepted by most
commands and has no effect in this version; use `qc platform switch`.

## Authentication and platform

| Command | Notes |
|---|---|
| `qc login [-p, --port <port>] [--endpoint <url>]` | Browser OAuth (PKCE). Callback port default 8090. `--endpoint` skips the platform list and saves the platform as `custom`. With a saved platform, first asks Add / Re-authenticate / Cancel (also with `--endpoint`); Re-authenticate on a valid session asks a second confirm, default No |
| `qc logout` | Removes stored credentials |
| `qc whoami` | User, active org/app/env, token expiry |
| `qc platform list\|switch\|current\|remove` | Manage the platforms you are logged in to. `qc plat` is an alias |

## Context

| Command | Notes |
|---|---|
| `qc org list\|select [orgId]\|current` | |
| `qc app list\|select [appId]\|current` | `app select` then offers an environment |
| `qc project list\|select [name]\|current` | Quant (content) projects in the org |
| `qc env list\|select [envId]\|current` | `select` without an argument opens a searchable prompt. `list` takes only `--org`/`--app` |

## Environments

| Command | Notes |
|---|---|
| `qc env create [envName] --clone-from <env> --min-capacity <n> --max-capacity <n>` | Defaults 1 and 10. Takes only `--org`/`--app`. Prompts for a missing name, for a clone source if `--clone-from` is missing and environments exist, and always at the end: "Set '<name>' as active environment?" (hangs CI) |
| `qc env logs [envId] [-f] [-n <lines>]` | Default 100 lines. Follow polls about every 2 s. `-n` trims the platform's response |
| `qc env metrics [envId] [-r <seconds>] [--no-clear]` | Live dashboard; refresh default 5 s |
| `qc env state stop\|start\|redeploy [envId]` | `redeploy --tag <imageTag>` redeploys a given image tag. No confirmation prompt |

## Environment variables (0.7.0 and later)

| Command | Notes |
|---|---|
| `qc env vars list [--json] [--show-values]` | Values print as `********` unless `--show-values` (also in `--json`) |
| `qc env vars get <key>` | Prints the raw value only; exit 1 if not set. No banner when stdout is not a terminal |
| `qc env vars set <key> <value>` | One variable |
| `qc env vars set <key> --stdin` | Value from stdin; keeps it out of argv and shell history |
| `qc env vars set --file <path>` | Sets each `KEY=VALUE` in a .env file, keeps variables not in the file. Refuses the whole file on any bad line, invalid name, duplicate or unclosed quote |
| `qc env vars unset <key> [-y, --yes]` | Confirms on a terminal unless `--yes`. Reports "Nothing changed" for a missing key |

All four take `--org`, `--app`, `--env`. A write does not redeploy; it applies on the next
`qc env state redeploy`. Secrets are not covered; use the dashboard.

## Exec and SSH

| Command | Notes |
|---|---|
| `qc exec run "<cmd>" [--container <name>] [--detach] [--interval <sec>]` | Server-side run, 1 hour cap, interval default 15 s, minimum 5 |
| `qc exec status <runId> [--watch] [--interval <sec>]` | `--watch` reprints output from the start, then streams |
| `qc exec list` | Reports that history listing is not supported yet |
| `qc ssh [--container <name>] [--command <cmd>] [--interactive]` | Needs the `aws` CLI on PATH. No command: interactive `/bin/bash`. With `--command`: non-interactive unless `--interactive` |

## Backups

| Command | Notes |
|---|---|
| `qc backup list [--type database\|filesystem] [--json]` | Default type `database` |
| `qc backup create [--type ...] [--description <text>]` | Prompts for a description if you omit it |
| `qc backup download [backupId] [--type ...] [--output <dir>]` | Default output `./downloads`; prompts to pick a backup if no ID |
| `qc backup delete [--type ...]` | Interactive |

## Crawlers and visual regression

| Command | Notes |
|---|---|
| `qc crawler list [--project <name>]` | |
| `qc crawler run [crawlerId] [--project <name>] [--urls <urls...>]` | |
| `qc vrt [--project a,b] [--threshold 0-1] [--max-pages n] [--max-depth n] [--csv file] [--output-dir dir] [--quant-auth user:pass] [--remote-auth user:pass] [--config path]` | Playwright comparison. Default config `~/.quant/vrt-config.json`. Exits 1 if any page has status FAIL or ERROR |
