---
name: quant-iac
description: Use when managing QuantCDN or QuantGov as code with Terraform (provider `quantcdn/quant`) or Pulumi (`@quantcdn/pulumi-quant`, TypeScript/JavaScript) - installing and pinning the provider, authenticating (`bearer`/`QUANTCDN_API_TOKEN`, `organization`, `base_url` = the bare dashboard host, `https://dash.quantgov.cloud` on gov), which `quant_*` resources exist (project, domain, header, crawler, rules, KV, Cloud application/environment/volume/cron, AI), importing existing dashboard resources with the exact import IDs, drift (dashboard edits, lists replaced as a whole, one tool per rule, traffic-source bot challenge stays in the dashboard), and errors such as "Provider returned invalid result object after apply", double `/api/v2` paths, "Invalid import ID" and "does not support resource type". Not for rule semantics (`quant-rules-and-routing`) or compose files (`quant-cloud-apps`).
---

# Terraform and Pulumi for Quant

Both tools manage the same platform API through one provider: Terraform `quantcdn/quant` and its
generated Pulumi package `@quantcdn/pulumi-quant`. Resources and arguments are the same in both; Pulumi
uses camelCase. This skill covers setup, auth, the resource list, import, drift and common errors.
For the platform overview, load `quant-platform`.

## Applies to

Both platforms: QuantCDN (`https://dashboard.quantcdn.io`) and QuantGov (`https://dash.quantgov.cloud`).
Identify the platform by the dashboard URL only; ask the customer if you do not know it. Checked
2026-10 against Terraform `quantcdn/quant` v5.14.1 (validated with `terraform validate`) and
`@quantcdn/pulumi-quant` 5.14.1 (type-checked with `tsc`).

| | QuantCDN (public) | QuantGov |
|---|---|---|
| `base_url` / `baseUrl` | `https://dashboard.quantcdn.io` (the default) | `https://dash.quantgov.cloud` |
| API token | Dashboard API token from the QuantCDN profile | Dashboard API token from the QuantGov profile |
| Features | Same resources and arguments | Same resources and arguments; gov adds AU Government restrictions (AI: Australian-resident models only; domains need DNS-validation records) |

Tokens are per platform. A project token (`Quant-Token`) does not work here.

## Terraform setup

Terraform 1.0 or later (the provider uses plugin protocol 6). Pin the provider to the 5.x line:

```hcl
terraform {
  required_providers {
    quant = {
      source  = "quantcdn/quant"
      version = "~> 5.14"
    }
  }
}

variable "quant_organization" {
  type = string
}

provider "quant" {
  organization = var.quant_organization
  base_url     = "https://dash.quantgov.cloud" # gov; omit on QuantCDN
  # The token comes from the QUANTCDN_API_TOKEN environment variable.
}
```

- **Token:** set `QUANTCDN_API_TOKEN` in the shell or CI secret store. Or pass `bearer = var.quant_token`
  with `sensitive = true` on the variable. Never write the token in `.tf` files.
- **Environment variables** (each is an alternative to the argument): `QUANTCDN_API_TOKEN` (`bearer`),
  `QUANTCDN_ORGANIZATION` (`organization`), `QUANTCDN_BASE_URL` (`base_url`),
  `QUANTCDN_TIMEOUT_SECONDS` (`timeout_seconds`, default 120), `QUANTCDN_REQUESTS_PER_SECOND`
  (default 10), `QUANTCDN_MAX_RETRIES` (default 3), `QUANTCDN_BASE_DELAY_MS`, `QUANTCDN_MAX_DELAY_MS`,
  `QUANTCDN_ENABLE_JITTER`. The provider retries 429, 5xx and timeouts with backoff.
- **`base_url` is the bare dashboard host.** The provider adds `/api/v2` or `/api/v3` itself. A value
  ending in `/api/v2` doubles the path and every call fails.
- **State holds secrets.** `write_token`, KV values and basic-auth passwords end up in state. Use a
  remote backend with encryption and restricted access, and commit `.terraform.lock.hcl`.
- `terraform init -upgrade` moves to the newest version the constraint allows.

Example (a project, a domain, a redirect, project headers, a KV item). This validates with
`terraform validate`; `domain` and `url` on rules are lists:

```hcl
resource "quant_project" "site" {
  name = "agency-site"
}

resource "quant_domain" "www" {
  project = quant_project.site.machine_name
  domain  = "www.agency.gov.au"
}

resource "quant_rule_redirect" "old_to_new" {
  name          = "old-to-new"
  project       = quant_project.site.machine_name
  domain        = ["any"]
  url           = ["/old"]
  redirect_to   = "/new"
  redirect_code = 301
}

resource "quant_header" "security" {
  project = quant_project.site.machine_name
  headers = {
    "X-Content-Type-Options" = "nosniff"
  }
}

resource "quant_kv_store" "config" {
  project = quant_project.site.machine_name
  name    = "config"
}

resource "quant_kv_item" "flag" {
  project  = quant_project.site.machine_name
  store_id = quant_kv_store.config.id
  key      = "feature_flag"
  value    = "enabled" # add secret = true for secrets
}
```

A new domain on gov needs DNS-validation CNAME records before the certificate is issued; Terraform only
creates the domain. See `quant-domains-cache-purge`. `quant_domain` cannot be renamed: changing
`domain` or `project` deletes and re-creates it.

## Resources

Terraform name, Pulumi class (`quant.<Class>`), and every import ID: [references/resources.md](references/resources.md).

| Area | Resources |
|---|---|
| CDN project | `quant_project`, `quant_domain`, `quant_header` (project-wide custom headers), data sources `quant_project` (can return the write token) and `quant_projects` |
| Crawler | `quant_crawler`, `quant_crawler_schedule` |
| Rules | `quant_rule_redirect`, `quant_rule_proxy`, `quant_rule_headers`, `quant_rule_auth` (basic auth), `quant_rule_custom_response`, `quant_rule_serve_static`, `quant_rule_function`, `quant_rule_content_filter`, `quant_rule_bot_challenge` |
| KV | `quant_kv_store` (`format`), `quant_kv_item`, `quant_kv_index`, `quant_kv_ledger`; data sources `quant_kv_ledger`, `quant_kv_ledger_public_key` |
| Quant Cloud | `quant_application`, `quant_environment`, `quant_volume`, `quant_cron_job` |
| AI | `quant_ai_agent`, `quant_ai_agent_overlay`, `quant_ai_custom_tool`, `quant_ai_governance`, `quant_ai_skill`, `quant_ai_vector_collection`, `quant_ai_vector_document`, `quant_slack_bot`. Arguments and models: `quant-ai` |

Rule fields and behaviour (order, URL patterns, `$*`, WAF modes) are in `quant-rules-and-routing`.
Compose definitions for `quant_application` are in `quant-cloud-apps`. Rules are evaluated in `weight`
order and the default weight is 0, so set `weight` on each rule when the order matters.

## Import existing resources

Use import when the dashboard (or the API) created the resource first. Never delete and re-create to
adopt a resource: a deleted domain or project loses its configuration and content.

1. Write the resource block with the arguments you know (`project`, `name` for rules; see drift below).
2. Import it (`terraform import <address> "<id>"`, or an `import { to = ..., id = "..." }` block).
3. Run `terraform plan`. Edit the block until the plan shows no changes. Do not apply before then.

| Resource | Import ID | Where to find it |
|---|---|---|
| `quant_project` | project machine name, `shop-prod` | Dashboard project settings |
| `quant_domain` | `project/domain_id` (numeric), `shop-prod/9555` | Domains page, or `GET .../projects/{project}/domains` |
| `quant_header` | project machine name | The project that has the headers |
| `quant_rule_*` (all nine) | `project/rule_uuid`, `shop-prod/12345678-1234-1234-1234-123456789abc` | Rules page, or `GET .../projects/{project}/rules` |
| `quant_crawler` | `project:crawler_uuid` (bare uuid = project `default`) | Crawler page, or the crawlers API |
| `quant_crawler_schedule` | `project:crawler_uuid:schedule_id` (integer schedule ID) | Crawler schedules |
| `quant_kv_store` | `project/store_id` | KV stores page |
| `quant_kv_item` | `project/store_id/key` | Store contents |
| `quant_application` | application name | Cloud dashboard |
| `quant_environment` | `application/env_name` | Cloud dashboard |
| `quant_volume` | `application/environment/volume_id` | Environment volumes |
| `quant_cron_job` | `application/environment/cron_name` | Environment cron jobs |
| AI resources | see [references/resources.md](references/resources.md) | |

The rule UUID must be a real UUID (version 1 to 5), otherwise import fails with "invalid UUID format".
List calls: `{dashboard}/api/v2/organizations/{org}/projects/{project}/rules` with
`Authorization: Bearer <token>`.

## Drift

Terraform compares the configuration with the live platform on every plan, and apply overwrites
anything that differs.

- **One tool per resource.** A rule that Terraform manages should not be edited in the dashboard.
  The edit shows as drift on the next plan and apply reverts it. See `quant-rules-and-routing`.
- **Lists and maps are replaced as a whole.** `url`, `domain`, `ip_is`, `country_is` and other lists
  on a rule, and the `headers` map of `quant_header`, are sent in full. A value someone added in the
  dashboard is removed on apply. `quant_header` is one resource per project (all project headers),
  so two `quant_header` blocks for one project overwrite each other.
- **Set `name` and `project` on every rule.** They are optional in the schema and filled in from the
  API when omitted, so a config without them can look correct and still be missing the project.
- **Keep traffic-source-scoped bot challenge rules out of Terraform.** Traffic source and user agent
  conditions are not in the provider (the rules API sets them, see `quant-rules-and-routing`). A rule
  that uses them stays in the dashboard or the API; do not import it and then edit it there. If
  Terraform must own a bot challenge rule, scope it by country.
- **`auth` means basic auth in Terraform.** `quant_rule_auth` takes `auth_user` and `auth_pass`; a
  `type: auth` rule in a `quant rules` manifest is an auth function, a different rule. Rules that
  `quant rules` or the deploy-action `rules` input manage should not also be in Terraform.
- **Inspect without changing:** `terraform plan -refresh-only` shows what the platform has that state
  does not. Then either copy the wanted value into the configuration or stop managing that resource.
- **Destroy is real.** Removing `quant_project` from the configuration deletes the project through the
  API. Add `lifecycle { prevent_destroy = true }` to projects and domains you cannot lose.

## "Provider returned invalid result object after apply"

```
Error: Provider returned invalid result object after apply
... .browser_config. All values must be known after apply.
This is a bug in the provider, which should be reported in the provider's own issue tracker.
```

This is a provider bug, not a configuration, token or `base_url` mistake. The provider finished the API
call but left a computed attribute unknown, and Terraform rejects that. Past cases: `quant_crawler`
`browser_config` (fixed in v5.14.0) and two new `quant_environment` task-mode fields (fixed in v5.12.0).

1. Do not run a second apply yet. The API call probably succeeded, so the object exists or has changed.
   Run `terraform plan` and `terraform state show <address>`. A resource that failed on create can be
   marked tainted, and the next apply would replace it: read the plan first.
2. Upgrade: `terraform init -upgrade` (check the version constraint allows the latest 5.x).
3. If it still fails on the latest release, report the resource type, attribute name and provider
   version in the issue tracker at https://github.com/quantcdn/terraform-provider-quant/issues.
4. If the object exists but state lost it, import it (table above).

## Pulumi (TypeScript or JavaScript)

npm (Node.js) only; no PyPI package.

```bash
npm install @quantcdn/pulumi-quant @pulumi/pulumi
pulumi config set --secret quant:bearer <api-token>
pulumi config set quant:organization <org>
pulumi config set quant:baseUrl https://dash.quantgov.cloud   # gov; omit on QuantCDN
```

Environment variables work too (`QUANTCDN_API_TOKEN`, `QUANTCDN_ORGANIZATION`, `QUANTCDN_BASE_URL`, and
the same tuning variables as Terraform). `baseUrl` is the bare dashboard host, never with `/api/v2`.
On first use Pulumi downloads the provider plugin from GitHub releases, so the machine needs outbound
access to `github.com`. The package version follows the Terraform provider version.

```typescript
import * as quant from "@quantcdn/pulumi-quant";

const project = new quant.Project("site", { name: "agency-site" });

new quant.Domain("www", {
    project: project.machineName,
    domain: "www.agency.gov.au",
});

new quant.RuleRedirect("old-to-new", {
    name: "old-to-new",
    project: project.machineName,
    domains: ["any"],
    urls: ["/old"],
    redirectTo: "/new",
    redirectCode: "301",
});

new quant.Application("app", {
    appName: "agency-app",
    composeDefinition: {
        containers: [{
            name: "web",
            imageReference: { type: "external", identifier: "nginx:stable" },
            exposedPorts: [80],
        }],
        taskCpu: 512,
        taskMemory: 1024,
        minCapacity: 1,
        maxCapacity: 2,
    },
});
```

- The Pulumi package is generated from the Terraform provider: the same resources and arguments,
  so the Terraform registry docs apply with camelCase names.
- Class names are in the table (`quant.RuleRedirect`, `quant.KvStore`, `quant.CronJob`). Arguments are
  camelCase; the list arguments `domain` and `url` on rules are `domains` and `urls`; `redirect_code`
  is a string. Check `node_modules/@quantcdn/pulumi-quant/<resource>.d.ts` for exact names and types.
- **Import** uses the same IDs as Terraform: `pulumi import quant:index:Domain www agency-site/9555`, or
  `{ import: "agency-site/9555" }` in the resource options.
- Drift, replacement and destroy rules above apply unchanged. Use `pulumi refresh` where Terraform
  uses `plan -refresh-only`. Mark secrets with `pulumi.secret(...)`.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| Every call fails with 404 or an HTML error page | `base_url` ends in `/api/v2` or `/api/v3`, so the path is doubled | Set the bare dashboard host (`https://dash.quantgov.cloud`) |
| "Missing QuantCDN API bearer token" or "organization" | No `bearer`/`organization` argument and no `QUANTCDN_*` variable in the shell or CI job | Export `QUANTCDN_API_TOKEN` and `QUANTCDN_ORGANIZATION` |
| 401 or 403 on every call | Token from the other platform, a project `Quant-Token`, or a token without permission | Create a dashboard API token on the platform that `base_url` points at |
| Calls reach the wrong platform | `base_url` unset (default is the public dashboard) | Set `base_url` / `quant:baseUrl` for gov |
| "does not support resource type `quant_application`" (or kv, environment...) | Old version pinned (for example `~> 1.0`), or a local development build overrides the registry provider | Use `~> 5.14`, run `terraform init -upgrade`, remove `dev_overrides` from the CLI config |
| "Invalid import ID": "the ID must follow the pattern project/uuid" | Wrong number of parts, or a name where the UUID/ID is needed | Use the ID table; rule IDs are `project/uuid`, domain IDs `project/numeric_id` |
| "Provider returned invalid result object after apply" | Provider bug: a computed attribute stayed unknown | See the section above |
| Plan shows changes after a dashboard edit | Drift on a managed resource | Copy the value into the config, or stop managing it in Terraform; never both |
| `context deadline exceeded`, many 429 | Slow API or too many parallel calls | Raise `timeout_seconds`, lower `requests_per_second`, run `terraform apply -parallelism=4` |
| Domain stays pending after apply | Terraform creates the domain only; DNS and certificate are separate | Create the DNS records. See `quant-domains-cache-purge` |
| Pulumi cannot find the `quant` plugin | First-run plugin download from GitHub is blocked | Allow `github.com`, or run `pulumi plugin install resource quant <version> --server github://api.github.com/quantcdn/terraform-provider-quant` |
| A rule edit in the dashboard is lost | Terraform replaced the rule's lists on apply | One tool per rule; see Drift |

## Further reading

- Terraform registry: https://registry.terraform.io/providers/quantcdn/quant/latest/docs
- Provider source, issues and per-resource docs: https://github.com/quantcdn/terraform-provider-quant
- Terraform guide: https://docs.quantcdn.io/terraform/getting-started/
- Pulumi guide: https://docs.quantcdn.io/pulumi/getting-started/
- Related skills: `quant-platform`, `quant-rules-and-routing`, `quant-domains-cache-purge`,
  `quant-cloud-apps`, `quant-edge-functions-and-kv`, `quant-ci-github-actions` (run Terraform in CI), `quant-ai`

<!-- checked against tf:quantcdn/quant 5.14.1 -->
<!-- checked against npm:@quantcdn/pulumi-quant 5.14.1 -->
