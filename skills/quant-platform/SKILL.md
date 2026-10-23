---
name: quant-platform
description: Use when starting any task on Quant (QuantCDN or QuantGov) - choosing a Quant product, finding out whether a project is on the public or the gov platform, picking the right API host, auth headers, CLI (`quant` or `qc`) or GitHub action, or finding which quant-* skill covers a task. Load this first; it routes to the other Quant skills.
---

# Quant platform

Start here for any Quant task. This skill gives the platform facts every other Quant skill
assumes, and a router to the skill that covers each job.

## Applies to

Both platforms: QuantCDN (public) and QuantGov (gov). Tools: the dashboard, `curl`,
`@quantcdn/quant-cli` 7.0.1 (`quant`), `@quantcdn/quant-cloud-cli` 0.7.0 (`qc`).
Checked against these versions and the public OpenAPI spec (API 4.25.0), 2026-10.

## Which platform

Quant runs two platforms with **the same products**. Some cache, purge and domain behaviour
differs; see `quant-domains-cache-purge`. Identify the platform **only** by the
dashboard the customer signs in to:

| | QuantCDN (public) | QuantGov (gov) |
|---|---|---|
| Dashboard | `https://dashboard.quantcdn.io` | `https://dash.quantgov.cloud` |
| Content API | `https://api.quantcdn.io/v1` | `https://api.quantgov.cloud/v1` |
| Platform API | `https://dashboard.quantcdn.io/api/v2` and `/api/v3` | `https://dash.quantgov.cloud/api/v2` and `/api/v3` |

- If you do not know the dashboard URL, ask the customer. Do not guess.
- Do not try to detect the platform from response headers, DNS records, or IP addresses.
  That is not a supported method, and the answer it gives is not reliable.
- API keys and tokens belong to one platform. A key from one dashboard does not work on the
  other platform.
- The public dashboard host is `dashboard.quantcdn.io`. `dash.quantcdn.io` is wrong.

### What QuantGov adds

QuantGov adds restrictions for Australian Government use and is IRAP assessed. It has the same
products; some cache, purge and domain behaviour differs (see `quant-domains-cache-purge`).

- **AI:** only Australian-resident models are available. A model that the public platform
  lists can be missing on QuantGov.
- **Domains and certificates:** domain setup shows a DNS-validation step. The certificate
  becomes active only after you create the DNS records it shows.

## Products and the skill for each

Load **one** primary skill per task. Skills not installed yet are still the right name to
look for.

| Product or job | Skill |
|---|---|
| Products, public vs gov, API hosts, which tool for which job | `quant-platform` (this skill) |
| The content CLI `quant`: deploy, publish, purge, redirects, functions, rules, search, WAF log export (`quant waflogs`) | `quant-cli` |
| The cloud CLI `qc`: login, platforms, apps, environments, variables, logs, ssh, exec, backups | `qc-cli` |
| Static site and CDN hosting: deploy build output, unpublish, 404 pages, **forms** | `quant-static-sites` |
| Rules and routing: redirects, proxies, headers, auth, bot challenge, rule order, **WAF** | `quant-rules-and-routing` |
| Edge functions, auth and filter functions, scheduled functions, KV stores, secrets | `quant-edge-functions-and-kv` |
| Quant Cloud apps: containers, compose, databases, volumes, scaling, environments | `quant-cloud-apps` |
| Templates: choose a starter (app or static), or write your own template | `quant-templates` |
| CI: GitHub Actions workflows and action versions, other CI systems | `quant-ci-github-actions` |
| Domains, DNS, certificates, cache behaviour, purge, cache warming with the crawler | `quant-domains-cache-purge` |
| Infrastructure as code: Terraform `quantcdn/quant`, Pulumi `@quantcdn/pulumi-quant` | `quant-iac` |
| CMS integrations: Drupal module, WordPress plugin, Drupal/WordPress on Quant Cloud | `quant-cms-integrations` |
| Site search: index (crawler, `quant search`, search action), search API, widget | `quant-search` |
| AI services: inference, streaming, sessions, tools, agents, vector DB, governance | `quant-ai` |
| Quant Studio: create, edit and publish a site, migrate into Studio | `quant-studio` |

Notes on the router:

- **WAF** is part of `quant-rules-and-routing`. WAF settings and rules are project
  configuration, managed with the same tools as other rules. To export WAF logs through
  the content API, use `quant waflogs`.
- **Crawler**: to fill a search index, use `quant-search`. To warm the cache or to check
  a site, use `quant-domains-cache-purge`.
- **Forms** on a static site are part of `quant-static-sites`.
- **Static site or container app?** Static output (HTML, CSS, JS files) goes to
  `quant-static-sites`. Code that runs a server or needs a database goes to
  `quant-cloud-apps`.

## The two APIs

Quant has two APIs. They use different hosts, different credentials, and different headers.
Do not mix them.

| | Content API | Platform API |
|---|---|---|
| Host (public) | `https://api.quantcdn.io/v1` | `https://dashboard.quantcdn.io/api/v2`, `/api/v3` |
| Host (gov) | `https://api.quantgov.cloud/v1` | `https://dash.quantgov.cloud/api/v2`, `/api/v3` |
| Scope | One project | Organisations you belong to |
| Credential | Project token, from the project in the dashboard | API token from the dashboard profile (can be scoped to organisations), or the `qc` browser OAuth login |
| Auth headers | `Quant-Customer: <org>`, `Quant-Project: <project>`, `Quant-Token: <project token>` | `Authorization: Bearer <token>` |
| Used by | `quant` (most commands), `quantcdn/deploy-action` `endpoint`, purge-action, CMS modules | `qc`, Quant Cloud actions, `quant rules`, Terraform, Pulumi |
| Reference | `https://docs.quantcdn.io/content-api/` | `https://docs.quantcdn.io/cloud-api/` |

Content API: push pages and files, publish and unpublish, redirects, purge, metadata.

```bash
curl https://api.quantcdn.io/v1/ping \
  -H "Quant-Customer: $QUANT_CUSTOMER" \
  -H "Quant-Project: $QUANT_PROJECT" \
  -H "Quant-Token: $QUANT_TOKEN"
```

Platform API, by version:

- `/api/v2`: projects and their configuration (rules, domains, custom headers, crawlers,
  KV, purge) and DNS zones.
- `/api/v3`: Quant Cloud (applications, environments, compose, backups, commands) and AI
  services.

```bash
curl https://dashboard.quantcdn.io/api/v2/organizations/$ORG/projects \
  -H "Authorization: Bearer $QUANT_API_KEY"
curl https://dashboard.quantcdn.io/api/v3/organizations/$ORG/applications \
  -H "Authorization: Bearer $QUANT_API_KEY"
```

For QuantGov, replace the host with the gov value from the table. The paths do not change.

## Which tool for which job

Quant has **two CLIs**. `quant` is the content CLI. `qc` is the cloud CLI. They are not
interchangeable.

| Job | Tool |
|---|---|
| Deploy a static build directory | `quant deploy <dir>` locally; `quantcdn/deploy-action` v7 in CI |
| Push one page or file, publish, unpublish, redirect | `quant page`, `quant file`, `quant publish`, `quant unpublish`, `quant redirect` |
| Purge the cache | `quant purge`; `quantcdn/purge-action` v7 in CI; content API `POST /purge` |
| Deploy edge functions | `quant functions <manifest>`; deploy-action `functions` input |
| Manage rules from files | `quant rules` (needs `QUANT_API_TOKEN` and `QUANT_BASE_URL={dashboard}/api/v2`) |
| Manage Quant Cloud apps and environments, variables, logs, shell, exec, backups | `qc` |
| Build and deploy Quant Cloud apps in CI | Quant Cloud actions v4 (init, environment, compose, state, sync, backup) and environment-var v1 |
| Declare projects, rules, apps as code | Terraform `quantcdn/quant` v5.14, Pulumi `@quantcdn/pulumi-quant` 5.14 (npm only) |
| Anything else, or a one-off check | The dashboard, or `curl` against the API above |

### Platform setting for each tool

| Tool | Setting | QuantCDN | QuantGov |
|---|---|---|---|
| `quant` | endpoint (`quant init`, `-e`) | `https://api.quantcdn.io/v1` | `https://api.quantgov.cloud/v1` |
| `quant rules` | `QUANT_BASE_URL` | `https://dashboard.quantcdn.io/api/v2` | `https://dash.quantgov.cloud/api/v2` |
| `qc` | `qc login`, choose the platform; then `qc platform switch` | Quant Cloud (`quantcdn`) | QuantGov Cloud (`quantgov`) |
| Quant Cloud actions v4 | `base_url` | `https://dashboard.quantcdn.io` (default, bare host) | `https://dash.quantgov.cloud` |
| `quantcdn/deploy-action` | `api-base-url` / `endpoint` | `https://dashboard.quantcdn.io/api/v2` / `https://api.quantcdn.io/v1` | `https://dash.quantgov.cloud/api/v2` / `https://api.quantgov.cloud/v1` |
| `quantcdn/deploy-action` rules deployment | `api-token` with `api-base-url` | A project-scoped token is required together with `api-base-url` | Same |
| Terraform, Pulumi | `base_url` / `baseUrl` | `https://dashboard.quantcdn.io` | `https://dash.quantgov.cloud` |

- `qc` has no working platform flag. The `--platform` option on commands and the `platform:`
  key in `.quant.yml` are ignored. Use `qc login` (or `qc login --endpoint <dashboard URL>`,
  which saves the platform as `custom`), then `qc platform switch`. Run
  `qc platform current` before you act.
- Use the bare dashboard host for `base_url` on every Quant Cloud action. It works for all of
  them, including the environment variable action (v1.0.2). The v4 actions also accept the
  `/api/v3` form.
- Terraform and Pulumi add the API path themselves. Give them the bare dashboard host only.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| 401 from `{dashboard}/api/v2` or `/api/v3` with a project token | The project token and `Quant-*` headers belong to the content API | Send `Authorization: Bearer <API token>` from the dashboard profile, or use `qc` |
| 401 from the content API | Missing `Quant-Customer` or `Quant-Project`, or a token for a different project | Send all three `Quant-*` headers with the values for that project |
| 401 or "not found" with a token that works elsewhere | The token belongs to the other platform | Create the token in the dashboard of the platform that hosts the project |
| `qc` shows QuantCDN apps for a QuantGov user | `--platform` and `.quant.yml` `platform:` are ignored | `qc login` and choose QuantGov, then `qc platform switch`; check `qc platform current` |
| Terraform or Pulumi API calls fail | `base_url` ends with `/api/v2` or `/api/v3`, so the provider doubles the path | Set `base_url` to the bare dashboard host |
| A QuantGov Cloud action changes nothing, or the app is not found | `base_url` not set, so the action called QuantCDN | Set `base_url: https://dash.quantgov.cloud` (the bare host) on every Quant Cloud action |
| An AI model from the public catalogue is missing on QuantGov | QuantGov offers Australian-resident models only | Pick a model from the QuantGov model list; see `quant-ai` |
| A QuantGov domain stays "pending" | The DNS-validation records do not exist yet | Create the DNS records the dashboard shows; see `quant-domains-cache-purge` |
| `qc` cannot deploy a static site; `quant` cannot see Quant Cloud apps | Wrong CLI for the job | Static content: `quant`. Quant Cloud apps: `qc` |

## Further reading

- QuantCDN and QuantGov: https://docs.quantcdn.io/platform/quantcdn-and-quantgov/
- Welcome and product overview: https://docs.quantcdn.io/welcome/
- Content API: https://docs.quantcdn.io/api/get-started-content/ and https://docs.quantcdn.io/content-api/
- Platform API: https://docs.quantcdn.io/api/get-started-projects/ and https://docs.quantcdn.io/cloud-api/
- Content CLI: https://docs.quantcdn.io/content-cli/get-started/
- Cloud CLI: https://docs.quantcdn.io/cloud-cli/get-started/

<!-- checked against npm:@quantcdn/quant-cli 7.0.1 -->
<!-- checked against npm:@quantcdn/quant-cloud-cli 0.7.0 -->
