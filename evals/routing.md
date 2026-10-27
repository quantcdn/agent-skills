# Routing evals

Exactly one primary skill per prompt.

| Prompt | Expected skill |
|---|---|
| What is Quant and which product should I use for a marketing site with a contact form? | quant-platform |
| Is my account on the public or the gov platform, and which API host do I call? | quant-platform |
| How do I push a static build directory to Quant with the `quant` command? | quant-cli |
| What does `quant purge` do and how do I do a soft purge from my terminal? | quant-cli |
| How do I log in with `qc` and switch to the gov platform? | qc-cli |
| How do I run a command inside a running environment with `qc exec`? | qc-cli |
| My Astro build output is in `dist/`. How do I deploy it as a static site? | quant-static-sites |
| How do unpublished pages and custom 404 pages work on a static site? | quant-static-sites |
| Add a redirect from /old to /new and make the match case-insensitive. | quant-rules-and-routing |
| Why does my second rule never match? Which rule wins? | quant-rules-and-routing |
| My proxy rule has the WAF enabled but it does not block SQL injection. How do I make it block? | quant-rules-and-routing |
| Australians are getting the bot challenge although the rule says country is not AU. | quant-rules-and-routing |
| Write an edge function that checks a header and returns JSON. | quant-edge-functions-and-kv |
| How do I store and read a key in a KV store from a function? | quant-edge-functions-and-kv |
| My KV `for await` loop in an edge function throws LIMIT_EXCEEDED. | quant-edge-functions-and-kv |
| My auth function rule lets everyone through to /members. What is wrong? | quant-edge-functions-and-kv |
| Show a per-visitor greeting inside a cached static page with `{{QUANT_FN:...}}`. | quant-edge-functions-and-kv |
| My container needs 1 vCPU and a MySQL database. What goes in the compose file? | quant-cloud-apps |
| My Quant Cloud environment returns a 502 page. How do I read its logs? | quant-cloud-apps |
| Which template should I start from for a Next.js app with server rendering? | quant-templates |
| How do I write my own template repo with a `quant/meta.json`? | quant-templates |
| Which GitHub Action deploys my static site and which version do I pin? | quant-ci-github-actions |
| Write a workflow that builds an image and creates an environment on push. | quant-ci-github-actions |
| Our GitLab pipeline must deploy the static site and redeploy a Quant Cloud environment without a person logging in. | quant-ci-github-actions |
| Add a custom domain and tell me which CNAME to set and why the certificate is pending. | quant-domains-cache-purge |
| Purge one URL from the cache after a content change. | quant-domains-cache-purge |
| Can the Quant crawler warm the cache after a full purge, and how do I schedule it? | quant-domains-cache-purge |
| Which Cache-Control header should my origin send so Quant keeps pages for ten minutes? | quant-domains-cache-purge |
| Manage my project and rules with Terraform. | quant-iac |
| Declare a Quant application in Pulumi with TypeScript. | quant-iac |
| terraform apply fails with Provider returned invalid result object after apply on our crawler. | quant-iac |
| How do I import my existing dashboard rules into Terraform state? | quant-iac |
| Install the Drupal module and push content to Quant. | quant-cms-integrations |
| What is the go-live checklist for WordPress on Quant Cloud? | quant-cms-integrations |
| Add site search with a crawler and an embeddable search box. | quant-search |
| My AI search widget returns 403 and the Index tab only shows 40 pages. | quant-search |
| How do I push custom search records from CI after a deploy, and what endpoint does the gov search action need? | quant-search |
| Facets for categories and tags are not showing on my dashboard search page. | quant-search |
| Call the chat inference API with streaming and a tool. | quant-ai |
| Which AI models can a gov customer use? | quant-ai |
| Our workflow webhook returns 401 after we rotated the secret. How do we sign the GitHub delivery? | quant-ai |
| Point the OpenAI Python SDK at Quant and fix a 429 spend limit reached error. | quant-ai |
| Create a site in Studio and publish it. | quant-studio |
| Migrate my redirects into a Studio site. | quant-studio |
| My Studio site shows the generic 404 after a GitHub workflow deploy. How do I get my custom 404? | quant-studio |
| Should I deploy my Hugo site as a static site or as a container app? | quant-static-sites |
| I have a Node API with a database. Static site or cloud app? | quant-cloud-apps |
| My Next.js app on the app-node image returns 503 App not ready after deploy. | quant-cloud-apps |
| Where do I put a script that runs database migrations each time my container starts? | quant-cloud-apps |
| Show me the available starter templates for a static blog. | quant-templates |
| I copied a Quant template repository by hand instead of using the dashboard. What must I set up that the wizard would have done? | quant-templates |
| Deploy from my laptop with the cloud CLI or the content CLI? | quant-platform |
| My WordPress plugin says Unable to connect to local webserver when I push to Quant. | quant-cms-integrations |
| Drupal on Quant Cloud says the provided host name is not valid for this server. | quant-cms-integrations |
| An AI tool call in our org returns pending_approval. Where do I approve it? | quant-ai |
