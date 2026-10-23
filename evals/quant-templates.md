# quant-templates evals

Prompt: I am starting three new projects on Quant and want to begin from Quant's own templates: (1) a marketing site built with Hugo, (2) a Next.js app with server rendering and API routes, (3) a small team dashboard with login and saved data but no server or database to run. Which template repository should each start from, what kind of template is each, and how does each one deploy? When I create them from the dashboard, which GitHub secrets and variables does the wizard set?
Platform: public
Must include:
- Hugo: `quantcdn-templates/ssg-hugo`, a static (SSG) template: CI builds the site and `quantcdn/deploy-action` uploads the output (`public`) to a Quant project
- Next.js SSR: `quantcdn-templates/app-nextjs`, an app template: CI builds a container image and deploys it to a Quant Cloud application with the cloud actions
- Dashboard with login and data, no server: `quantcdn-templates/ssg-astro-edge-saas` (Orbit), a static site plus edge functions and KV stores
- Static templates get `QUANT_CUSTOMER` and `QUANT_PROJECT` variables and a `QUANT_TOKEN` secret
- App templates get `QUANT_API_KEY` and `QUANT_ORGANIZATION` secrets and a `QUANT_APPLICATION` variable
Must not include:
- A template repository that does not exist in `quantcdn-templates` (for example `ssg-vitepress`, `ssg-mkdocs`, `app-django` or `app-express`)
- The Next.js SSR app deployed as a static export to the content API

Prompt: We are on QuantGov (https://dash.quantgov.cloud). We copied `quantcdn-templates/app-nuxt` into our own GitHub organisation by hand (not through the dashboard) to use as our internal starter. We added the `QUANT_API_KEY` and `QUANT_ORGANIZATION` secrets. The first run failed to reach the API, and after we fixed that, the deploy goes green but the container exits at once with `exec format error`. What do we set, and why does the container fail?
Platform: gov
Must include:
- Set the repository variable `QUANT_BASE_URL` to `https://dash.quantgov.cloud/api/v3` (every Quant Cloud action reads it as `base_url`)
- The compose file declares `quant.architecture: ARM64`, so the image must be built for `linux/arm64`; an `exec format error` means it was built for `linux/amd64`
- Fix: build for `linux/arm64` (repository variable `BUILD_PLATFORM`, with QEMU on an x86 runner or an ARM runner such as `ubuntu-24.04-arm`), or change the compose file to `X86_64` and build `linux/amd64`; keep the two in step
- Create the Quant Cloud application first and set `QUANT_APPLICATION` (otherwise the workflow uses the repository name)
- Pin the cloud actions at `@v4` (including `quantcdn/quant-cloud-compose-action@v4`)
Must not include:
- `dashboard.quantcdn.io` as the API host for this customer
- `quant-cloud-compose-action@v1`

Prompt: Our agency wants its own reusable Quant template: a Laravel app on Quant Cloud with a MySQL database and a random `SESSION_SECRET` generated for each new site. Show the repository layout and the `quant/meta.json`, and tell me if the Quant dashboard will list our template in its template picker and apply the `meta.json` for us.
Platform: public
Must include:
- Layout: `Dockerfile`, `docker-compose.yml`, `docker-compose.override.yml.example`, `quant/meta.json`, `quant/entrypoints/`, `.github/workflows/build-deploy.yaml`
- `meta.json` with `"template_type": "app"`, `"requires_db": true` and `"secrets": [{"name": "SESSION_SECRET", "generate": "random", "length": 64}]` (an object or a one-element array)
- The dashboard template picker lists only repositories in the `quantcdn-templates` organisation; the agency's own repository is not listed and its `meta.json` is not applied
- For a site made from the agency template: create the application with a managed database (dashboard toggle or `"database": {"engine": "mysql"}`) and set the secret on the environment yourself
- The compose file keeps the local MySQL service with `quant.type: mysql` and has no `DB_*` values in the deployed `environment:`
Must not include:
- A claim that the dashboard will list the agency's own template or apply its `meta.json`
- `QUANT_APPLICATION || 'templates'`, an idle-sleep step, or `environment_name_override: ${{ github.event.repository.name }}` in the workflow

Prompt: I am copying the `build-deploy.yaml` from a Quant app template into my own repository for our production app `shop-api`. My copy has `quant_application: ${{ vars.QUANT_APPLICATION || 'templates' }}`, `environment_name_override: ${{ github.event.repository.name }}`, a step "Enable idle sleep" that calls the idle-sleep API, and `quantcdn/quant-cloud-compose-action@v1`. Which of these should I keep for production?
Platform: public
Must include:
- Replace the `templates` default: set `QUANT_APPLICATION` to `shop-api` (or default to the repository name); `templates` is not your application
- Remove `environment_name_override` (or leave it empty) so the init action maps branches to environments: `main` deploys to `production`
- Remove the idle-sleep step for production; idle sleep is for non-production environments and is set on the environment (dashboard or API), not in each deploy
- Use `quantcdn/quant-cloud-compose-action@v4` (same inputs as v1)
Must not include:
- Keeping `'templates'` as the application default
- Keeping the idle-sleep step for the production environment

Prompt: I created a site from the `ssg-astro-edge-saas` (Orbit) template in the Quant dashboard. What did template setup do with the `kv_stores` in `quant/meta.json`, what happens to the owner key it showed me once, and if a colleague instead copies the repository by hand into a new project, what must they do themselves so the API functions, rules and KV work?
Platform: public
Must include:
- Template setup creates each store in `kv_stores`, writes its `initial_values` (existing keys are kept), and links the store to the project
- A one-time credential (`"reveal": "once"`) is shown once at setup and only its SHA-256 hash is stored; if it is lost, follow the template README's reset steps
- A manual copy gets none of this: create the KV store, link it to the project, and write the initial values yourself
- Rules in `quant/edge-rules.json` deploy only when the workflow has a `QUANT_API_TOKEN` secret and a `QUANT_BASE_URL` variable (`{dashboard}/api/v2`); without them deploy-action skips the rules
- Functions deploy from `quant/edge-functions.json` with the committed `uuid` of each entry
Must not include:
- A claim that the GitHub deploy workflow creates KV stores or seeds KV values
- The content `QUANT_TOKEN` presented as enough for rules
