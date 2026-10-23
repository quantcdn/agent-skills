# quant-platform evals

Prompt: I am new to Quant. I have an Astro marketing site (static output in `dist/`) with a contact form, and I want to deploy it from my laptop now and from GitHub Actions later. Which Quant products and which command-line tool do I use, and where are the docs?
Platform: public
Must include:
- Static site hosting on QuantCDN, with Quant forms for the contact form
- The content CLI `quant` (`@quantcdn/quant-cli`) with `quant deploy dist`, not the cloud CLI `qc`
- `quantcdn/deploy-action` v7 for GitHub Actions
- Docs at `https://docs.quantcdn.io`
Must not include:
- `qc` as the tool that deploys static files
- `deploy-action@v6` or older
- `dash.quantcdn.io`

Prompt: Our agency signs in at https://dash.quantgov.cloud. Give me one curl command that lists our organisation's projects, and one curl command that pushes a single HTML page to a project.
Platform: gov
Must include:
- Project list on the platform API: `https://dash.quantgov.cloud/api/v2/organizations/<org>/projects`
- Platform API auth: `Authorization: Bearer <API token>`
- Page push on the content API: `https://api.quantgov.cloud/v1`
- Content API auth: `Quant-Customer`, `Quant-Project`, `Quant-Token` headers with the project token
Must not include:
- `api.quantcdn.io` or `dashboard.quantcdn.io` for this customer
- `Quant-Token` on the platform API
- Any CDN or cloud vendor name

Prompt: I copied the token from my project's page in the Quant dashboard and called `curl -H "Quant-Token: $TOKEN" https://dashboard.quantcdn.io/api/v3/organizations/acme/applications`. I get 401 Unauthorized. What is wrong?
Platform: public
Must include:
- The project token is for the content API (`api.quantcdn.io/v1` with `Quant-Customer`/`Quant-Project`/`Quant-Token`) only
- The platform API needs `Authorization: Bearer` with an API token from the dashboard (or the `qc` OAuth login)
- API tokens belong to one platform; a QuantGov token does not work on QuantCDN
Must not include:
- Advice to keep `Quant-Token` on the platform API
- `dash.quantcdn.io`

Prompt: A client says their site might be on QuantGov rather than QuantCDN. Can I tell from the HTTP response headers? What actually differs between the two platforms?
Platform: gov
Must include:
- Identify the platform by the dashboard the client signs in to: `dashboard.quantcdn.io` = QuantCDN, `dash.quantgov.cloud` = QuantGov
- Do not use response headers to decide
- Both platforms have the same products; some cache, purge and domain behaviour differs
- QuantGov adds Australian Government restrictions, is IRAP assessed, and AI uses Australian-resident models only
Must not include:
- A header, DNS, or IP based detection method
- Any CDN or cloud vendor name (for example the names of the underlying CDN or cloud providers)

Prompt: Our agency is on QuantGov (we sign in at dash.quantgov.cloud). We want to call the Quant AI chat API with a model from the public docs examples, add our custom domain, and deploy our static site from GitHub with the Quant deploy action. What will be different from the public QuantCDN examples?
Platform: gov
Must include:
- AI: QuantGov offers Australian-resident models only, so a model in a public example can be unavailable
- Domains: QuantGov domain setup shows a DNS-validation step; the certificate is active only after those DNS records exist
- deploy-action: `api-base-url: https://dash.quantgov.cloud/api/v2` and `endpoint: https://api.quantgov.cloud/v1`
- Otherwise the features are the same as QuantCDN
Must not include:
- Names a certificate authority, cloud vendor or managed service
- Any CDN or cloud vendor name
- `deploy-action@v6` or older
