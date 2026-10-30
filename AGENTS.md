# Agent instructions

Skills for the Quant platform. You can copy this file and the `skills/` folder into your
own project. To change the skills themselves, see `CONTRIBUTING.md`.

1. Start at `skills/quant-platform/SKILL.md`. It routes to the other skills.
2. Load one primary skill per task. The router table in `quant-platform` names it.

## Routing

| Task | Skill |
|---|---|
| Products, public vs gov, which tool for which job | `quant-platform` |
| `quant` content CLI | `quant-cli` |
| `qc` cloud CLI | `qc-cli` |
| Deploy static output | `quant-static-sites` |
| Redirects, proxies, headers, rule order, bot challenge, WAF | `quant-rules-and-routing` |
| Forms on a static site | `quant-static-sites` |
| Edge functions and KV | `quant-edge-functions-and-kv` |
| Containerised apps, compose, environments | `quant-cloud-apps` |
| Use or write a template | `quant-templates` |
| CI pipelines: GitHub Actions workflows, GitLab and other CI | `quant-ci-github-actions` |
| Domains, DNS, certificates, cache, purge | `quant-domains-cache-purge` |
| Terraform and Pulumi | `quant-iac` |
| Drupal and WordPress | `quant-cms-integrations` |
| Site search, and the crawler that fills the index | `quant-search` |
| The crawler for cache warming or site checks | `quant-domains-cache-purge` |
| AI services | `quant-ai` |
| Slack updates, screenshots, questions and external-agent permission requests | `quant-slack` |
| Studio | `quant-studio` |

## Which platform

Identify the platform only by the customer's dashboard.

| Dashboard | Platform |
|---|---|
| `dashboard.quantcdn.io` | public |
| `dash.quantgov.cloud` | gov |

Ask the customer for the dashboard URL if you do not know it. Do not guess from headers.
Use the values for that platform:

- Content API: `https://api.quantcdn.io/v1` (public) or `https://api.quantgov.cloud/v1` (gov).
- Quant Cloud GitHub actions take `base_url` = the bare dashboard host (gov: `https://dash.quantgov.cloud`).
  The bare host works for every Quant Cloud action. The v4 actions also accept `{dashboard}/api/v3`.
- `deploy-action` takes `api-base-url` (`{dashboard}/api/v2`) and `endpoint` (the content API).
- Terraform and Pulumi take `base_url` = the bare dashboard host (no `/api/v2` or `/api/v3`).
- `qc`: run `qc login` and choose the platform, then `qc platform switch`. From `qc` 0.7.1,
  `--platform <id>` or `platform:` in `.quant.yml` targets another logged-in platform for one
  command; older versions ignore both.

Public and gov have the same products; some cache, purge and domain behaviour differs (see
`quant-domains-cache-purge`). Gov adds AU Government restrictions.
