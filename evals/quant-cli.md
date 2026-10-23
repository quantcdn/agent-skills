# quant-cli evals

Prompt: Our agency signs in at https://dash.quantgov.cloud. In a CI job with no `quant.json`, I want to deploy the `dist` directory with the `quant` CLI using environment variables only, then purge everything. Give me the exact environment variables and commands.
Platform: gov
Must include:
- `npm install -g @quantcdn/quant-cli` (Node 20 or later) or the `quantcdn/cli` Docker image
- Environment variables `QUANT_CLIENT_ID`, `QUANT_PROJECT`, `QUANT_TOKEN`, and `QUANT_ENDPOINT=https://api.quantgov.cloud/v1` (or the `-e` flag with that value)
- `quant deploy dist` and a purge of all content such as `quant purge "/*"`
- The token is the project token from the project in the dashboard (content API), not a dashboard API token
Must not include:
- `QUANT_CUSTOMER` as the variable that `quant` reads
- `api.quantcdn.io` or `dashboard.quantcdn.io` for this customer
- `dash.quantcdn.io`

Prompt: Our agency uses https://dash.quantgov.cloud. I ran `quant init -c myorg -p blog -t $TOKEN -e https://api.quantgov.cloud -d dist` and every command now fails with 404 or "Unable to connect". In CI I exported QUANT_CUSTOMER, QUANT_PROJECT and QUANT_TOKEN and `quant info` says "Missing: clientid". quant.json says project "blog" but my CI env says QUANT_PROJECT=blog-stg. What is wrong, which project wins, and is it safe to commit quant.json?
Platform: gov
Must include:
- The endpoint must include the version path: `https://api.quantgov.cloud/v1`
- The CLI reads `QUANT_CLIENT_ID`, not `QUANT_CUSTOMER` (or use `-c`/`--clientid`)
- Precedence: command-line flags, then environment variables, then `quant.json`, then defaults; so `blog-stg` wins
- Do not commit `quant.json`: it holds the project token (`quant init` also writes a copy under `~/.quant`); use environment variables in CI
Must not include:
- A claim that `quant.json` beats environment variables
- `QUANT_CUSTOMER` as a variable `quant info` or `quant deploy` reads
- `api.quantcdn.io` for this customer

Prompt: We upgraded the CLI from 6.x to 7.0.1. `quant functions quant/edge-functions.json` now refuses the manifest before uploading anything, and `quant function handler.js "My fn"` fails. What changed and how do I fix both without creating duplicate functions?
Platform: public
Must include:
- From 7.0.0 every manifest entry needs an explicit `uuid`, and `quant function`, `quant auth` and `quant filter` need the UUID as a third argument
- The UUID is the function's identity: copy the existing function's UUID from the dashboard into the entry; a new UUID creates a new function
- `quant functions-add <manifest> <path> --description ...` adds an entry with a new UUID and uploads nothing
- 6.x derived a UUID from customer, project and `id`, so existing functions keep their UUID only if it is copied in; type must be lowercase and `description` not blank
Must not include:
- Advice to delete and re-create the functions to get a UUID
- Advice to leave `uuid` out and rely on `id`

Prompt: I use QuantGov (dash.quantgov.cloud). `quant rules quant/edge-rules.json --functions quant/edge-functions.json --dry-run` fails with "Rules require customer, project, QUANT_API_TOKEN and QUANT_BASE_URL". I have QUANT_TOKEN set and `quant deploy` works fine. What do I set?
Platform: gov
Must include:
- `quant rules` ignores `QUANT_TOKEN`, `-t` and the content write token
- `QUANT_API_TOKEN` is a separate project-scoped token with `projects:read`, `rules:read` and `rules:write`
- `QUANT_BASE_URL=https://dash.quantgov.cloud/api/v2` (the dashboard host with `/api/v2`, not the content API host)
- Customer and project still come from `-c`/`-p`, `QUANT_CLIENT_ID`/`QUANT_PROJECT` or `quant.json`
Must not include:
- `https://api.quantgov.cloud/v1` as the value of `QUANT_BASE_URL`
- `QUANT_TOKEN` as the token for `quant rules`

Prompt: I need to deploy my static site to Quant Cloud, and I also want the WAF logs for the last week as CSV. Is `qc` the Quant CLI? Which commands do I run?
Platform: public
Must include:
- `quant` (`@quantcdn/quant-cli`) is the content CLI for static content, CDN and WAF log export; `qc` is the separate cloud CLI for Quant Cloud applications
- `quant deploy <dir>` for the static files
- `quant waflogs --all -o file.csv` (the command is `waflogs`, not `waf:logs`)
Must not include:
- "`qc` is the Quant CLI"
- `quant waf:logs`
