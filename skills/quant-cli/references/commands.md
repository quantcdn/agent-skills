# quant commands reference

`@quantcdn/quant-cli` 7.0.1. Checked against the source and `docker run --rm quantcdn/cli:7.0.1 <command> --help`.
Return to [SKILL.md](../SKILL.md).

## Global options

Every command accepts these. They override environment variables and `quant.json`.

| Flag | Meaning | Environment variable |
|---|---|---|
| `-c`, `--clientid` | Customer (organisation) | `QUANT_CLIENT_ID` |
| `-p`, `--project` | Project machine name | `QUANT_PROJECT` |
| `-t`, `--token` | Project token (content API) | `QUANT_TOKEN` |
| `-e`, `--endpoint` | Content API endpoint, with `/v1` | `QUANT_ENDPOINT` |
| `--version`, `--help` | | |

`QUANT_DIR` (and `--dir`) sets the default build directory. Default endpoint `https://api.quantcdn.io/v1`
(gov: `https://api.quantgov.cloud/v1`).

## Setup

| Command | Notes |
|---|---|
| `quant` | Interactive menu. Prompts to run `init` if no config exists. Avoid in scripts. |
| `quant init [-c -p -t -e] [-d dir]` | Writes `quant.json` (and a copy under `~/.quant/`), then pings the API. Removes `quant.json` if the ping fails. `-d` default `build`. Prompts when `-c`, `-p` or `-t` is missing. |
| `quant info` | Prints endpoint, customer, project, masked token, total records. Use it as a connection test. |

## Content

| Command | Flags and behaviour |
|---|---|
| `quant deploy [dir]` | `dir` defaults to the configured `dir`. Uploads files whose MD5 differs. Then unpublishes remote paths missing locally and purges affected paths. Flags: `--attachments`, `--skip-unpublish`, `--skip-unpublish-regex <regex>`, `--skip-purge`, `--enable-index-html`, `--chunk-size <n>` (default 10), `--force` (re-upload even if unchanged), hidden `--revision-log <path>` (local MD5 log for faster repeat deploys). |
| `quant page <file> <location>` | Push one HTML file to a URL path. `--enable-index-html`. |
| `quant file <file> <location>` | Push one asset to a URL path. Reports "Skipped" when the content is unchanged. |
| `quant publish [path]` | Publish a revision. `-r`, `--revision` default `latest`. |
| `quant unpublish <path>` | Take a path offline. Revisions are kept. |
| `quant delete <path>` | Remove the path and all its revisions. Asks to confirm; `-f`, `--force` skips the question. |
| `quant scan` | Compare local files with the project. `--diff-only`, `--unpublish-only`, `--skip-unpublish`, `--skip-unpublish-regex`. Use it as a dry run. |
| `quant redirect <from> <to> [status]` | `status` is one of 301, 302 (default), 303, 307, 308. `-d`, `--delete` removes the redirect; `-f`, `--force` skips the question. `to` is still required with `--delete`. An existing identical redirect is reported as skipped. |

`--enable-index-html` keeps `index.html` in URLs. The first run that sets it saves the choice in
`quant.json`; a later conflicting value is an error.

## Cache

`quant purge [path]`

| Form | Effect |
|---|---|
| `quant purge /about` | Purge one path |
| `quant purge "/*"` | Purge everything (quote it) |
| `quant purge --cache-keys="key1 key2"` | Purge by cache key (space separated) |
| `--soft-purge` | Mark as stale instead of removing |

Give a path or `--cache-keys`, not both. With neither, the command opens an interactive prompt. In CI and scripts, always pass a path or `--cache-keys`.

## Edge functions

See SKILL.md for the UUID rules and the 6.x to 7.0 upgrade.

| Command | Notes |
|---|---|
| `quant functions-add <manifest> <path> --description <text> [--type function\|auth\|filter] [--id <slug>]` | Adds an entry with a new version 4 UUID. Creates the manifest if absent. Errors if the path or `id` is already in it. Uploads nothing. Prints only the UUID. `--description` and `<path>` are required. |
| `quant functions <manifest>` | Validates every entry, then deploys. Entry: `uuid`, `path`, `type`, `description` required; `id` optional. `uuid` is checked for shape only (8-4-4-4-12 hex). `type` is lowercase `function`, `edge`, `auth` or `filter`. `uuid` and `id` must be unique. Errors name each bad entry and nothing uploads. |
| `quant function <file> <description> <uuid>` | One function. |
| `quant auth <file> <description> <uuid>` | One auth function (returns 201 to let the request continue). |
| `quant filter <file> <description> <uuid>` | One filter function. |

A function a rule references through `function_ref` or `function_uuid` needs an RFC 4122 UUID
(version 1 to 5). `functions-add` writes version 4.

## quant rules

`quant rules <file> [--functions <manifest>] [--api-token] [--api-base-url] [--dry-run] [--force]`

- Credentials: `QUANT_API_TOKEN` and `QUANT_BASE_URL` (`{dashboard}/api/v2`), or `--api-token` and
  `--api-base-url`. The token is a separate project-scoped dashboard token with `projects:read`,
  `rules:read`, `rules:write`. Tokens that the dashboard creates for a template expire after one year.
- `QUANT_TOKEN`, `-t`, the token in `quant.json` and the content endpoint are never used.
- Customer comes from `-c`, `QUANT_CLIENT_ID`, `QUANT_CUSTOMER` or `quant.json`; project from `-p`,
  `QUANT_PROJECT` or `quant.json`.
- The URL must be HTTPS (HTTP only for localhost), end in `/api/v2`, and have no user info, query or
  fragment. The CLI does not follow redirects.
- Manifest: `version: 1`, a stable `namespace`, and a `rules` array (up to 100 rules, 64 KiB). Each rule
  has a unique lowercase `id` (`^[a-z][a-z0-9-]{0,47}$`), `type` (`function`, `auth`, `filter`), `urls`
  (each starts with `/`), a numeric `weight` (lower runs first; -100000 to 100000), and `function_ref` (an `id` in the
  `--functions` manifest with the same type) or `function_uuid`, not both. Optional: `name`, `domains`,
  `methods`, `disabled`.
- A deploy changes only rules with the same namespace and `id` and keeps all others. Omit a rule to
  keep it; set `disabled: true` to turn it off.
- Rules deployed this way are read-only in the dashboard and the rules API. If someone changed one
  outside code, the deploy writes nothing, exits non-zero and lists the changed fields. `--force`
  overwrites those rules; the token's user must have permission to delete projects, or the API returns
  403. It never takes over a rule this manifest did not create.
- `--dry-run` checks permissions and previews without writing.
- Put authentication rules at a lower `weight` than the functions they protect. A negative weight
  runs before rules added in the dashboard.

Order: `quant functions ...` first, so the UUIDs exist, then `quant rules ...`.

## Search

`quant search <status|index|unindex|clear>`

| Operation | Notes |
|---|---|
| `status` | Prints the number of indexed documents |
| `index --path=records.json` | JSON array of records. Each needs `title`, `url`, `content`. Optional `summary`, `image`, `categories`, `tags`, plus any custom fields |
| `unindex --path=/url` | Remove one URL |
| `clear` | Remove every record. No confirmation |

## WAF logs

`quant waflogs [-f fields] [-o file.csv] [--all] [--size n]`

- Default prints 10 records. `--size` sets records per request. `--all` pages through every record.
- `-o` writes CSV. `-f a,b` limits the printed fields. Run once without `-f` to see the field names.
- Needs the project token to have access to the project's WAF logs.

## Docker

`docker run --rm -v "$PWD":/site -w /site -e QUANT_CLIENT_ID -e QUANT_PROJECT -e QUANT_TOKEN -e QUANT_ENDPOINT quantcdn/cli:7.0.1 <command>`

The entrypoint is `quant`, so pass the command (for example `deploy dist`) without repeating `quant`.
The image is multi-architecture (amd64, arm64) and sets `NODE_OPTIONS=--max-old-space-size=8192`.
