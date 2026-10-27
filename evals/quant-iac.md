# quant-iac evals

Prompt: We are on QuantGov (https://dash.quantgov.cloud). Write the Terraform for a new project `agency-site` with the domain `www.agency.gov.au` and a 301 redirect from `/old` to `/new`. Show the provider setup, how to pin the provider version, and how to give it the API token without putting the token in the code.
Platform: gov
Must include:
- A `required_providers` block with `source = "quantcdn/quant"` and a `~> 5.14` style version constraint
- Provider `base_url = "https://dash.quantgov.cloud"` (the bare dashboard host) plus `organization`
- The token comes from the `QUANTCDN_API_TOKEN` environment variable (or a sensitive variable); `QUANTCDN_ORGANIZATION` and `QUANTCDN_BASE_URL` can also be set by environment
- `quant_project`, `quant_domain` (with `project = quant_project.<name>.machine_name`) and `quant_rule_redirect` (with `domain`, `url`, `redirect_to`, `redirect_code`), with `name` and `project` set explicitly on the rule
- Terraform adds the API path itself: `base_url` must not end in `/api/v2` or `/api/v3`
Must not include:
- A `base_url` that ends in `/api/v2` or `/api/v3`
- A token written as a literal in the provider block
- `dashboard.quantcdn.io` for this customer
- A `~> 1.0` or other pre-v5 version constraint

Prompt: Our team built a QuantCDN project (dashboard.quantcdn.io) by hand: one project `shop-prod`, two domains, a redirect rule, a proxy rule and the project headers. We now want Terraform to own all of it. How do we bring the existing resources under Terraform without recreating anything, what import ID does each resource take, and how do we avoid fighting the dashboard afterwards?
Platform: public
Must include:
- Write the resource blocks first, then `terraform import`; check with `terraform plan` until it shows no changes
- Import IDs: `quant_project` = project machine name; `quant_domain` = `project/domain_id` (numeric domain ID); `quant_rule_redirect` and `quant_rule_proxy` = `project/rule_uuid`; `quant_header` = project machine name
- The domain ID comes from the dashboard Domains page or the domains API; the rule UUID from the dashboard Rules page or the rules API list call
- Pick one tool per rule: a rule that Terraform manages should no longer be edited in the dashboard, because the next plan shows the dashboard edit as drift and apply reverts it
- A list in the configuration (`url`, `domain`, `ip_is` and so on) replaces the whole stored list, so a value added in the dashboard is removed on the next apply
Must not include:
- An import ID in the form `organization/project/...` for a rule or a domain
- A suggestion to delete and re-create the resources
- `dash.quantgov.cloud` for this customer

Prompt: `terraform apply` for our Quant crawler on QuantCDN fails with: `Error: Provider returned invalid result object after apply ... .browser_config. All values must be known after apply. This is a bug in the provider, which should be reported in the provider's own issue tracker.` Our config is valid and the plan looked fine. What does this mean, what do we do, and is our state safe?
Platform: public
Must include:
- It is a provider bug, not a configuration mistake: the provider left a computed attribute unknown after the API call; it is not caused by the token, `base_url` or the config
- Upgrade the provider to the latest `quantcdn/quant` release (v5.14.0 or later fixes the `browser_config` case) with `terraform init -upgrade`, after checking the version constraint allows it
- If it still happens on the latest release, report the resource type and attribute in the provider's GitHub issue tracker
- Run `terraform plan` (or `terraform state show`) after the failed apply: the API call may have succeeded and created or changed the object, so read the plan before a second apply, and import the object if state lost it
Must not include:
- A suggestion that the token or `base_url` is wrong
- A suggestion to edit the state file by hand as the first step
- A claim that the apply certainly rolled back the change

Prompt: I am on QuantGov (dash.quantgov.cloud) and want to use Pulumi with TypeScript to create a project, a domain and a Quant Cloud application. Which package do I install, how do I configure the token, organisation and gov host, and show me the code. Is there a Python package?
Platform: gov
Must include:
- `npm install @quantcdn/pulumi-quant`; only the Node.js SDK is published, so there is no Python (PyPI) package
- `pulumi config set --secret quant:bearer <token>`, `pulumi config set quant:organization <org>`, and `pulumi config set quant:baseUrl https://dash.quantgov.cloud` (bare host, no `/api/v2`); `QUANTCDN_API_TOKEN` and the other `QUANTCDN_*` environment variables also work
- TypeScript using `import * as quant from "@quantcdn/pulumi-quant"` with `new quant.Project`, `new quant.Domain` and `new quant.Application` (camelCase properties, for example `appName`, `composeDefinition`)
- The resources and arguments match the Terraform provider, with camelCase names (so Terraform documentation and examples carry over)
- To adopt an existing resource, use `pulumi import` with the same ID format as `terraform import` (for example `project/domain_id` for a domain)
Must not include:
- A Python (`pulumi_quant`) package install
- A `quant:baseUrl` that ends in `/api/v2` or `/api/v3`
- `dashboard.quantcdn.io` for this customer

Prompt: We manage our QuantCDN rules in Terraform. A colleague added a bot challenge rule limited to cloud-hosting traffic sources in the dashboard and now our `terraform plan` keeps showing changes to the redirect rules and the project headers. We also want Terraform to create that bot challenge rule. What is going on, and what is the right split between Terraform and the dashboard?
Platform: public
Must include:
- Traffic source (and user agent) conditions are not in the Terraform provider (only the dashboard and the rules API set them), so a bot challenge rule scoped by traffic source stays out of Terraform and is not declared there
- Rules that Terraform manages are compared on every plan; dashboard edits show as drift, and apply overwrites them; keep one tool per rule
- `quant_header` (project headers) is one resource per project and its `headers` map is replaced as a whole, so headers added in the dashboard are removed on apply
- Use `terraform plan -refresh-only` (or plain `terraform plan`) to see what changed; put the wanted value into the configuration or stop managing the rule in Terraform
- Set `name` and `project` explicitly on each rule; they are optional in the schema but computed from the API when omitted
Must not include:
- A claim that Terraform can set the traffic source condition
- A suggestion to import the dashboard bot challenge rule into Terraform and then edit it there
