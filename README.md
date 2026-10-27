# Quant agent skills

Skills that teach AI coding agents how to use the Quant platform correctly. There are 15
skills, in the open Agent Skills format. They work with QuantCode, Claude Code, Codex and other
agents.

## Platforms

Quant runs as two platforms with the same products. Some cache, purge and domain behaviour differs
(see `quant-domains-cache-purge`). Identify the platform by the dashboard the customer signs in to:

| Dashboard | Platform |
|---|---|
| `https://dashboard.quantcdn.io` | QuantCDN |
| `https://dash.quantgov.cloud` | QuantGov |

QuantGov adds Australian Government restrictions (for example AI uses Australian-resident models
only) and is IRAP assessed. Every skill states which values differ per platform.

Each skill is a folder under `skills/` with a `SKILL.md` in the open Agent Skills format.

## Install

### QuantCode

QuantCode is Quant's AI coding assistant (`brew install quantcdn/tap/quantcode`). It reads skills
from folders on disk; there is no install command.

1. Get the skills:

   ```
   git clone https://github.com/quantcdn/agent-skills.git
   ```

2. Copy the skill folders where QuantCode looks for them. For all projects:

   ```
   mkdir -p ~/.config/quantcode/skills
   cp -R agent-skills/skills/* ~/.config/quantcode/skills/
   ```

   For one project, copy them into `.quantcode/skills/` in that repository instead.

3. Check that QuantCode finds them. The list must include `quant-platform`:

   ```
   quantcode debug skill
   ```

QuantCode also reads `~/.claude/skills/`, `~/.agents/skills/`, and `.claude/skills/` or
`.agents/skills/` in a project. If you already installed the skills for Claude Code, QuantCode
uses them too. Copy again (step 2) to update.

### Claude Code

```
/plugin marketplace add quantcdn/agent-skills
/plugin install quant@quantcdn
```

### Other agents

Copy the skills folder: copy the folders in `skills/*` into `.claude/skills` (project) or
`~/.claude/skills` (all projects), or into `.agents/skills` or the equivalent directory your
agent reads.

`AGENTS.md`: agents that read `AGENTS.md` (Codex and others) can use the routing table in this
repository's `AGENTS.md`. Copy `AGENTS.md` and `skills/` into your project.

With the skills installer, if it supports this repo:

```
npx skills add quantcdn/agent-skills
```

## Skills

Start at `skills/quant-platform/SKILL.md`. It routes to the other skills.

| Skill | Use it for |
|---|---|
| `quant-platform` | Entry point and router: products, public vs gov, the two APIs, which tool for which job |
| `quant-cli` | The `quant` content CLI: install, config and endpoint (public and gov), deploy, purge, edge functions (6.x to 7.0 UUIDs), `quant rules`, WAF logs |
| `qc-cli` | The `qc` cloud CLI: login and platforms, org/app/env context, logs, environment variables, `exec` and `ssh`, environment state, backups |
| `quant-static-sites` | Static output on Quant: output directory per framework, `quant deploy` vs deploy-action, unpublish behaviour, `enableIndexHtml`, custom 404, revisions and rollback, purge, Quant Forms and submission export |
| `quant-rules-and-routing` | Project rules: how a request is matched (first match wins, ending actions, path-only patterns, `$*` vs `$1`, mode fields), proxy settings and the 502 Proxy Error page, WAF modes and rate limits (`thresholds` merged by type), bot challenge scoping and how a pass is bound, traffic source, user agent and ASN conditions through the API, managing rules from the dashboard, API, `quant rules` and Terraform, and testing a change |
| `quant-edge-functions-and-kv` | Edge functions, auth functions (201 to continue, 503 when the auth function is unavailable), content filters, inline `{{QUANT_FN:uuid}}` and scheduled functions; the function body contract; `quant/edge-functions.json` and `quant/edge-rules.json` with deploy-action; KV store IDs, linking, `kvStore.open` handles, `for await` paging with `maxPages`, `KVError` codes, secrets, counters, limits, ledgers and `verifyChain` |
| `quant-cloud-apps` | Containerised apps on Quant Cloud: the compose contract (`x-quant-labels` sizing, `quant.type` labels, image tag = service name, no shadowing of injected variables), the `app-node` and `app-apache-php` base images, managed databases (`database` create body), cache and object storage variables, variables and secrets, start-up hooks, health checks and startup grace, deploy verification, single-task mode, scaling, idle sleep, cron, volumes, backups and sync |
| `quant-templates` | Quant starter templates (`quantcdn-templates`): choosing an app, static or static + edge template, what the dashboard wizard sets up, copying a template by hand, the `quant/meta.json` keys (`requires_db`, `secrets`, `kv_stores`, `project_settings`), and writing your own template (layout, Dockerfile, override example, workflow, build platform matching `quant.architecture`) |
| `quant-ci-github-actions` | CI pipelines: every Quant GitHub action with its current version, SHA, inputs and outputs; pinning by SHA; secrets vs variables; gov `endpoint`/`api-base-url`/`base_url`; static and container-app workflows; pull request environments (clone, database copy, delete on close); variables, backups and staging refresh; confirming a green run is live; GitLab and other CI with `quant` and the platform API |
| `quant-domains-cache-purge` | Custom domains and certificates (DNS records per platform, QuantGov DNS-validation states, one project per host), the cache headers Quant uses and its defaults, purging by path, `/*`, wildcard patterns and cache keys, soft purge, purge timing, when to purge, cache warming, and the crawler as a static-copy tool (schedules, limits) |
| `quant-iac` | Terraform `quantcdn/quant` and Pulumi `@quantcdn/pulumi-quant` (Node.js only): install and version pin, token and `base_url` (bare dashboard host, gov `https://dash.quantgov.cloud`), the resource list by area, importing existing resources with exact import IDs, drift (one tool per rule, lists replaced whole, traffic-source bot challenge rules kept out of Terraform), "Provider returned invalid result object after apply", a TypeScript example and common errors |
| `quant-cms-integrations` | Drupal and WordPress with Quant: the Drupal module (`drupal/quantcdn`, 1.x for Drupal 10, 2.x for Drupal 11) and the WordPress plugin, connection fields and the API endpoint per platform (host only, no `/v1`), webserver URL and host header, first full push (`drush quant:run-queue`, `wp quant process_queue`), what is pushed on save, unpublish and delete, static push vs running the CMS on Quant Cloud (database variables, SMTP, files on volumes, cron, trusted hosts, `WP_HOME`), editor access after go-live and the go-live checklist |
| `quant-search` | Site search: keyword search (Subscription, "Enable Search", records via `quant search`, `quantcdn/search-action` v2 `path`, `/search` API and facets, dashboard search pages) and AI Search (enable, crawler "AI Search Integration", re-index and delete, public access, allowed domains, Display URL, widget, modal and search page scripts, public and management APIs, usage billing), gov hosts and the no-`/v1` action endpoint, and why widgets return 403 |
| `quant-ai` | Quant AI services: the AI API on the dashboard host (`/api/v3/organizations/{org}/ai`) with a dashboard API token, listing models (QuantGov: Australian-resident only), buffered, streaming (SSE events) and async chat, sessions, client, built-in and custom tools, agents and overlays, skills and collections, vector collections and documents, workflows with webhook and schedule triggers (secret and HMAC auth, Reveal and Rotate), governance and spend limits (403 and 429), tool approvals (`pending_approval`, the Approvals page, QuantCode prompts; enabled by Quant per organisation), the OpenAI-compatible `/oai/v1` surface, and the Terraform `quant_ai_*` resources |
| `quant-studio` | Quant Studio, the visual editor and CMS for Astro sites in GitHub: when to choose it, creating a project from a Studio template or a repository, editing entries and components, drafts, branches and preview environments, pull-request review, publishing (GitHub workflow vs Quant Builder Build & Publish), the custom 404 (`_quant404`), migrating a site in, redirects (Astro `redirects` are meta-refresh pages; use Quant redirect rules for real 301s; paths match case-insensitively), roles and `studio:*` token scopes |

## Documentation

- Quant documentation: https://docs.quantcdn.io/
- Content CLI: https://docs.quantcdn.io/content-cli/
- Cloud CLI: https://docs.quantcdn.io/cloud-cli/
- Custom error pages: https://docs.quantcdn.io/custom-error-pages/
- Public dashboard: https://dashboard.quantcdn.io
- Gov dashboard: https://dash.quantgov.cloud

## Develop

```
bats tests/                 # lint, leak-check and drift tests
scripts/lint-skills.sh      # validate every skills/*/SKILL.md
scripts/leak-check.sh       # scan for internal strings
scripts/check-drift.sh      # compare checked-against versions with the latest releases
```

See `CONTRIBUTING.md` for the full checks and the private name-list leak check.

Skill body headings, in order: `## Applies to`, task sections, `## Common problems`,
`## Further reading`. See `evals/README.md` to test a skill.

## Licence

MIT. See `LICENSE`.
