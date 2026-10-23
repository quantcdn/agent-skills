---
name: quant-cli
description: Use when working with the `quant` command (npm package `@quantcdn/quant-cli`, Docker image `quantcdn/cli`) on QuantCDN or QuantGov content projects - install and configure it, set the gov endpoint with `-e`, deploy or push static files, publish/unpublish, redirects, purge the cache, upload edge functions (`quant functions`, `functions-add`, the 6.x to 7.0 UUID upgrade), deploy rules (`quant rules`), search records, or export WAF logs (`quant waflogs`). For Quant Cloud apps, environments, logs, ssh or exec, use `qc-cli` instead; `qc` is not this CLI.
---

# quant CLI (content CLI)

`quant` pushes content to a Quant project and manages its CDN settings from a terminal or a CI job.
For the platform overview, the public/gov split and the two APIs, load `quant-platform` first. This
skill covers only the `quant` command.

## Applies to

Both platforms: QuantCDN (public) and QuantGov (gov). `@quantcdn/quant-cli` 7.0.1, Node.js 20 or
later. Checked against the 7.0.1 source and the `quantcdn/cli:7.0.1` image, 2026-10.

`quant` is the **content** CLI. It talks to the content API with a **project token**. It does not
manage Quant Cloud applications or environments. Use `qc` (skill `qc-cli`) for those.

## Install

```bash
npm install -g @quantcdn/quant-cli
quant --version            # 7.0.1
```

Docker, for a pipeline without Node.js. The image runs `quant` as its entrypoint and has no working
directory, so mount your project and set `-w`:

```bash
docker run --rm -v "$PWD":/site -w /site \
  -e QUANT_CLIENT_ID -e QUANT_PROJECT -e QUANT_TOKEN -e QUANT_ENDPOINT \
  quantcdn/cli:7.0.1 deploy dist
```

Pin the image tag to the CLI version you tested.

## Configure

The CLI needs four values: customer (organisation), project, project token, and the content API
endpoint. Find the customer and project names in the dashboard. Create or copy the project token
in the project in the dashboard (Integrations). A dashboard API token from your profile does not
work here.

### Precedence

Highest first:

1. Command-line flags: `-c/--clientid`, `-p/--project`, `-t/--token`, `-e/--endpoint`, `--dir`
2. Environment variables
3. `quant.json` in the current directory
4. Defaults: `endpoint` = `https://api.quantcdn.io/v1`, `dir` = `build`

| Setting | Flag | Environment variable | `quant.json` key |
|---|---|---|---|
| Customer | `-c`, `--clientid` | `QUANT_CLIENT_ID` | `clientid` |
| Project | `-p`, `--project` | `QUANT_PROJECT` | `project` |
| Project token | `-t`, `--token` | `QUANT_TOKEN` | `token` |
| Content API endpoint | `-e`, `--endpoint` | `QUANT_ENDPOINT` | `endpoint` |
| Build directory | `--dir` | `QUANT_DIR` | `dir` |

- The customer variable is `QUANT_CLIENT_ID`. Every `quant` command except `quant rules` reads
  only that name, not `QUANT_CUSTOMER`. With only `QUANT_CUSTOMER` set, they report
  `Missing: clientid`. (`quant rules` also accepts `QUANT_CUSTOMER`. The `customer:` input of
  `quantcdn/deploy-action` is an action input; any secret name works there.)
- The CLI reads `quant.json` from the **current directory only**. `quant init` also saves a copy
  under `~/.quant/`, which the CLI does not read back.
- `quant.json` holds the project token in plain text. Add it to `.gitignore`. In CI, use
  environment variables.
- `quant.json` also stores `enableIndexHtml` after the first deploy, with or without
  `--enable-index-html` (`false` when the flag is absent). You cannot change it later; the CLI
  refuses a conflicting value.
- **Caution:** the **first `quant deploy`** in a directory with no stored `enableIndexHtml` calls the
  CLI's save, whether or not you pass `--enable-index-html`. The save writes the merged config,
  including a token taken from the environment, to `./quant.json` and `~/.quant/config.json`. In CI,
  do not commit `quant.json`; delete it (and `~/.quant/config.json` on a shared runner) after the job.
- A bare `quant` (no command) and many commands with missing arguments open interactive prompts.
  In scripts and for agents, pass every argument and flag.

### Set up

```bash
# Interactive
quant init

# Non-interactive (CI, agents)
quant init -c "$ORG" -p "$PROJECT" -t "$TOKEN" -e "$ENDPOINT" -d dist

quant info          # prints endpoint, customer, project; pings the API
```

`quant init` writes `quant.json` and pings the API. If the ping fails, it deletes `quant.json`.

## Public and gov

The **endpoint** is the only difference. The project token belongs to one platform.

| Platform | Dashboard | `-e` / `QUANT_ENDPOINT` |
|---|---|---|
| QuantCDN | `https://dashboard.quantcdn.io` | `https://api.quantcdn.io/v1` (the default) |
| QuantGov | `https://dash.quantgov.cloud` | `https://api.quantgov.cloud/v1` |

- Always include `/v1`. The CLI appends paths to the endpoint as given, so
  `https://api.quantgov.cloud` alone makes every call fail.
- On QuantGov, set the endpoint on every run: in `quant init -e`, in `QUANT_ENDPOINT`, or with
  `-e`. If you forget, the CLI calls the public API with a gov token and fails.
- Ask the customer for the dashboard URL if you do not know it. Do not guess the platform.

## Commands you need most

Full flags, exit behaviour and edge cases: [references/commands.md](references/commands.md).

| Job | Command |
|---|---|
| Deploy a build directory | `quant deploy dist` |
| Preview what a deploy would change | `quant scan --diff-only` |
| Push one page or file | `quant page ./about.html /about`, `quant file ./logo.png /images/logo.png` |
| Publish, unpublish, delete | `quant publish /path`, `quant unpublish /path`, `quant delete /path --force` |
| Redirect | `quant redirect /old /new 301` |
| Purge the cache | `quant purge /about`, `quant purge "/*"`, `quant purge /about --soft-purge`, `quant purge --cache-keys="a b"` |
| Edge functions | `quant functions-add`, then `quant functions quant/edge-functions.json` |
| Edge rules from files | `quant rules quant/edge-rules.json --functions quant/edge-functions.json` |
| Search index records | `quant search index --path=records.json` (also `status`, `unindex`, `clear`) |
| WAF logs to CSV | `quant waflogs --all -o waf.csv` |

Notes:

- `quant deploy` uploads changed files, then unpublishes paths that exist remotely but not locally,
  then purges affected paths. Use `--skip-unpublish`, `--skip-unpublish-regex '<regex>'` and
  `--skip-purge` to change that. Unpublishing is on by default; check it before the first deploy to
  a project that other tools also write to.
- `quant delete` asks for confirmation unless you pass `--force`. It removes **all revisions** of
  the path. Prefer `quant unpublish` when you only want the page offline.
- Quote `"/*"` in `quant purge` so the shell does not expand it.
- Pass the redirect status as the third argument (`301`, `302`, `303`, `307`, `308`; default 302).
- The WAF log command is `waflogs`. `waf:logs` is not a command.
- A Quant project token is per project. To work on several projects, change `-p` and `-t` together.

## Edge functions and the 6.x to 7.0 upgrade

A function is identified by its **UUID**. Keep the UUID in your repository and never change it. A new
UUID creates a new function; the old one stays deployed.

```bash
# Add an entry to a manifest with a new UUID. Uploads nothing. Prints only the UUID.
quant functions-add quant/edge-functions.json quant/edge-functions/api.js \
  --description "API" --id my-api            # --type function|auth|filter (default function)

# Deploy every entry in the manifest.
quant functions quant/edge-functions.json

# Deploy one function. The UUID is the required third argument.
quant function handler.js "My edge function" 43aec1f0-095b-4a76-a9c8-934bf3d49d59
quant auth     auth.js    "My auth function" <uuid>
quant filter   filter.js  "My filter"       <uuid>
```

Manifest entry fields: `uuid` (required), `path`, `type` (lowercase `function`, `edge`, `auth` or
`filter`), `description` (not blank), optional `id` (lowercase slug, unique, used as `function_ref`
by rules). The CLI checks the whole manifest before the first upload.

If a deploy that worked on 6.x now fails on 7.0:

| 7.0 behaviour | Fix |
|---|---|
| `quant functions` refuses the manifest and names each entry without a `uuid` | 6.x derived a UUID from the customer, the project and the entry's `id`; 7.0 needs it written in. Copy the UUID of the function that is already deployed from the dashboard (Compute, Edge Functions) into the entry (the 7.0.0 upgrade notes in the CLI README also show how to print the derived UUID locally) |
| `quant function`, `auth`, `filter` fail without a UUID | Add the UUID as the third argument |
| Duplicates appeared after a 6.x run | 6.x `quant function` without a UUID created a new function on every run. Use the UUID you want to keep, and remove the extra functions in the dashboard |
| A Studio branch environment has a different UUID from its parent | Branch environments are separate projects. Commit the parent's UUID |
| Output says `Deployed <kind> [<uuid>]` | Normal on 7.0. 6.x printed `Created` or `Updated` |

Never re-create a function to get a UUID. If a pipeline uses `quantcdn/deploy-action` v6, it keeps
CLI 6.3.0 and is not affected until it moves to v7 (see `quant-ci-github-actions`).

## Rules from files: `quant rules`

`quant rules` deploys function, auth and filter **rules** to a project through the **platform API**,
not the content API. It uses different credentials from every other command.

| | Value |
|---|---|
| `QUANT_API_TOKEN` (or `--api-token`) | A separate project-scoped dashboard token with `projects:read`, `rules:read`, `rules:write` |
| `QUANT_BASE_URL` (or `--api-base-url`) | `{dashboard}/api/v2`, for example `https://dash.quantgov.cloud/api/v2` or `https://dashboard.quantcdn.io/api/v2` |
| Customer, project | `-c`/`-p`, `QUANT_CLIENT_ID` (or `QUANT_CUSTOMER`), `QUANT_PROJECT`, or `quant.json` |

- `quant rules` **ignores** `QUANT_TOKEN`, `-t` and the token in `quant.json`. It never uses the
  content endpoint.
- The base URL must be HTTPS and end in `/api/v2`. The content API URL (`.../v1`) is wrong here.
- Run `quant functions` first, then `quant rules`. Use `--dry-run` to check permissions and preview.

```bash
export QUANT_API_TOKEN=...   QUANT_BASE_URL=https://dash.quantgov.cloud/api/v2
quant rules quant/edge-rules.json --functions quant/edge-functions.json -c ORG -p PROJECT --dry-run
quant functions quant/edge-functions.json -c ORG -p PROJECT
quant rules quant/edge-rules.json --functions quant/edge-functions.json -c ORG -p PROJECT
```

The rules file format and the rule model are in `quant-rules-and-routing`; see
[references/commands.md](references/commands.md#quant-rules) for the CLI's own checks.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| `Missing: clientid` although `QUANT_CUSTOMER` is set | The CLI reads `QUANT_CLIENT_ID` | Export `QUANT_CLIENT_ID`, or pass `-c` |
| 404 or "Unable to connect" on every command | Endpoint without `/v1`, or the public endpoint with a gov token (or the reverse) | Use `https://api.quantcdn.io/v1` or `https://api.quantgov.cloud/v1` to match the dashboard |
| 401 or 403 from `quant deploy` | The content API needs a project token (`Quant-Token`). A dashboard API token is a Bearer token for the platform API and will be rejected (typically 401/403), as will a token from the other platform | Use the project token from this project on this platform |
| `Rules require customer, project, QUANT_API_TOKEN and QUANT_BASE_URL` | `quant rules` ignores `QUANT_TOKEN` | Set `QUANT_API_TOKEN` and `QUANT_BASE_URL={dashboard}/api/v2` |
| `Rules require an HTTPS portal /api/v2 URL` | `QUANT_BASE_URL` is the content API URL, has no `/api/v2`, or is not HTTPS | Set it to `{dashboard}/api/v2` |
| `quant waf:logs` is not found | The command is `waflogs` | `quant waflogs --all -o waf.csv` |
| Cannot disable index.html URLs | `quant.json` stores `enableIndexHtml` from the first deploy | Match the stored setting; it cannot change |
| The project token is in a committed `quant.json` | `quant init` writes the token to the file | Rotate the token in the dashboard, add `quant.json` to `.gitignore`, use env vars in CI |
| A command hangs in CI | It opened an interactive prompt for a missing argument | Pass every argument; add `--force` to `delete` |
| Manifest refused before upload (7.0) | An entry has no `uuid`, a bad `type` or a blank `description` | See the upgrade table above |
| `quant` cannot see a Quant Cloud app | Wrong CLI | Use `qc` (skill `qc-cli`) |

## Further reading

- Get started: https://docs.quantcdn.io/content-cli/get-started/
- Commands reference: https://docs.quantcdn.io/content-cli/commands/
- Edge functions: https://docs.quantcdn.io/content-cli/commands/functions/
- CI pipelines: https://docs.quantcdn.io/content-cli/guides/continuous-integration/
- Source and 7.0.0 upgrade notes: https://github.com/quantcdn/quant-cli#upgrading-from-6x-to-700
- Related skills: `quant-platform` (hosts, auth), `qc-cli`, `quant-static-sites`,
  `quant-edge-functions-and-kv`, `quant-rules-and-routing`, `quant-ci-github-actions`

<!-- checked against npm:@quantcdn/quant-cli 7.0.1 -->
