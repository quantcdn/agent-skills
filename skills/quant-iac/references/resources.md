# Resources, Pulumi classes and import IDs

Terraform provider `quantcdn/quant` v5.14.1, Pulumi `@quantcdn/pulumi-quant` 5.14.1. Pulumi imports use
the same ID as Terraform. Pulumi type tokens have the form `quant:index:<Class>`, for example
`pulumi import quant:index:Project site shop-prod`.

Per-resource arguments are in the registry docs
(https://registry.terraform.io/providers/quantcdn/quant/latest/docs) and, for Pulumi, in
`node_modules/@quantcdn/pulumi-quant/<resource>.d.ts`.

## CDN project

| Terraform | Pulumi class | Import ID | Notes |
|---|---|---|---|
| `quant_project` | `Project` | machine name | `machine_name` is derived from `name` unless set. Optional basic auth for the whole project (`basic_auth_username` and `basic_auth_password` together) |
| `quant_domain` | `Domain` | `project/domain_id` | Numeric ID. `domain` and `project` force replacement. Exports `dns_engaged` |
| `quant_header` | `Header` | project machine name | One per project; `headers` map replaced as a whole. Computed `id` is a hash of the values |
| `quant_crawler` | `Crawler` | `project:crawler_uuid` (bare uuid = project `default`) | Needs a verified domain to run. Some limits need approval for non-default values |
| `quant_crawler_schedule` | `CrawlerSchedule` | `project:crawler_uuid:schedule_id` | Cron in UTC; several schedules per crawler |

Data sources: `quant_project` (`machine_name`, `with_token` default true; returns sensitive
`write_token`) and `quant_projects`. In Pulumi: `quant.getProject`, `quant.getProjects`.

## Rules

All take `project/rule_uuid`. Set `name`, `project`, `domain`, `url` explicitly. Default `weight` is 0.
Behaviour and field meaning: `quant-rules-and-routing`.

| Terraform | Pulumi class | Rule |
|---|---|---|
| `quant_rule_redirect` | `RuleRedirect` | Redirect (`redirect_to`, `redirect_code`) |
| `quant_rule_proxy` | `RuleProxy` | Proxy to an origin (`to`, `host`, `cache_lifetime`, WAF settings) |
| `quant_rule_headers` | `RuleHeaders` | Response headers for matching URLs |
| `quant_rule_auth` | `RuleAuth` | Basic auth (`auth_user`, `auth_pass`) |
| `quant_rule_custom_response` | `RuleCustomResponse` | Fixed response |
| `quant_rule_serve_static` | `RuleServeStatic` | Serve static content |
| `quant_rule_function` | `RuleFunction` | Run an edge function (`fn_uuid`) |
| `quant_rule_content_filter` | `RuleContentFilter` | Content filter |
| `quant_rule_bot_challenge` | `RuleBotChallenge` | Bot challenge. Traffic source and user agent conditions are not in the provider (dashboard or rules API) |

## KV

| Terraform | Pulumi class | Import ID |
|---|---|---|
| `quant_kv_store` | `KvStore` | `project/store_id` (a rename replaces the store) |
| `quant_kv_item` | `KvItem` | `project/store_id/key` (`secret = true` for secrets; the value is still in state) |

## Quant Cloud

The organisation comes from the provider configuration.

| Terraform | Pulumi class | Import ID |
|---|---|---|
| `quant_application` | `Application` | application name |
| `quant_environment` | `Environment` | `application/env_name` |
| `quant_volume` | `Volume` | `application/environment/volume_id` |
| `quant_cron_job` | `CronJob` | `application/environment/cron_name` |

## AI

Arguments, models and behaviour: `quant-ai`. Gov customers see Australian-resident models only.

| Terraform | Pulumi class | Import ID |
|---|---|---|
| `quant_ai_agent` | `AiAgent` | agent ID |
| `quant_ai_agent_overlay` | `AiAgentOverlay` | `organisation/agent_id` |
| `quant_ai_custom_tool` | `AiCustomTool` | tool name |
| `quant_ai_governance` | `AiGovernance` | organisation name (empty ID = provider organisation) |
| `quant_ai_skill` | `AiSkill` | skill ID |
| `quant_ai_vector_collection` | `AiVectorCollection` | collection ID, or `organisation/collection_id` |
| `quant_ai_vector_document` | `AiVectorDocument` | collection ID, or `collection_id/key` for one document |
| `quant_slack_bot` | `SlackBot` | bot ID |
