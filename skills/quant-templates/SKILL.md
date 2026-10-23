---
name: quant-templates
description: Use when choosing, starting from, copying or writing a Quant starter template (the `quantcdn-templates` GitHub organisation) on QuantCDN or QuantGov - which template fits (app template on Quant Cloud, static SSG template, or static + edge functions and KV such as `ssg-astro-edge-saas`), what the dashboard template wizard sets up (repository, project or application, GitHub secrets and variables, database, KV stores), the `quant/meta.json` keys (`template_type`, `requires_db`, `requires_cache`, `requires_s3`, `secrets`, `kv_stores`, `project_settings`), copying a template by hand, and making your own template (layout, Dockerfile, override example, `build-deploy.yaml`, `quant.architecture` vs build platform). Also use when a workflow copied from a template deploys into the wrong application or environment or pins `quant-cloud-compose-action@v1`, when a site copied from a template lacks its database, secrets or KV stores, or when a container built from a template exits with `exec format error`.
---

# Quant templates

Quant's starter templates are public GitHub repositories in the
[`quantcdn-templates`](https://github.com/quantcdn-templates) organisation. Each one is a working
project plus the Quant files it needs: a deploy workflow, and for apps a `Dockerfile` and
`docker-compose.yml`. Start from one in the dashboard, or copy one by hand. For the platform overview
and the public/gov split, load `quant-platform` first.

## Applies to

Both platforms: QuantCDN (`https://dashboard.quantcdn.io`) and QuantGov (`https://dash.quantgov.cloud`).
The templates are the same. Checked 2026-10 against the public, non-archived `quantcdn-templates`
repositories, `quant-cloud-init-action` v4.0.1, `quant-cloud-compose-action` v4.0.0,
`quant-cloud-environment-action` v4.0.0, `quant-cloud-environment-state-action` v4.0.1 and
`deploy-action` v7.0.1.

| | Public | Gov |
|---|---|---|
| Template wizard | `https://dashboard.quantcdn.io` | `https://dash.quantgov.cloud` |
| App workflows: `QUANT_BASE_URL` variable | `https://dashboard.quantcdn.io/api/v3` (default) | `https://dash.quantgov.cloud/api/v3` |
| Static workflows: deploy `endpoint` | `https://api.quantcdn.io/v1` (default) | `https://api.quantgov.cloud/v1` |

In the template app workflows, `QUANT_BASE_URL` keeps the `/api/v3` form because some of them also
build API URLs from it. In your own workflows, pass the bare dashboard host to `base_url`
(see `quant-ci-github-actions`).

The README deploy buttons open the public dashboard. On gov, start from the gov dashboard instead.

## Choose a template

There are three kinds. Pick by what must run when a visitor asks for a page.

| Kind | Repository names | What runs | Deploys with |
|---|---|---|---|
| **App** | `app-*` | Your container on Quant Cloud (a server, often a database) | Cloud actions: init, compose, environment, state (`@v4`) |
| **Static (SSG)** | `ssg-*` | Nothing: CI builds files, Quant serves them | `quantcdn/deploy-action` + `purge-action` |
| **Static + edge** | `ssg-astro-edge-saas` | Edge functions and KV at Quant's edge; no server or database | `deploy-action` with `functions` and `rules` |

- Server rendering, API routes backed by a database, a PHP CMS: **app**.
- Marketing site, blog, docs: **static**. Studio visual editing: `ssg-astro-studio` or
  `ssg-astro-studio-civictheme` (see `quant-studio`).
- Login, per-user data or a small API without running a server: **static + edge**.

Common picks: `app-nextjs` (Next.js SSR), `app-nuxt`, `app-sveltekit`, `app-remix`, `app-astro`,
`app-payloadcms` (Payload + Postgres), `app-drupal`, `app-drupal-cms`, `app-wordpress`,
`app-craft-cms`, `app-laravel`, `app-symfony`, `app-statamic`; `ssg-astro`, `ssg-hugo`, `ssg-nextjs`
(static export), `ssg-nuxt`, `ssg-sveltekit`, `ssg-gatsby`, `ssg-eleventy`, `ssg-jekyll`,
`ssg-docusaurus`. `app-node` and `app-apache-php` are the base images most app templates build on.
Static templates upload the framework's output directory: `ssg-hugo` and `ssg-gatsby` `public`,
`ssg-astro*` `dist`, `ssg-nextjs` `out`, `ssg-nuxt` `.output/public`, `ssg-sveltekit` and
`ssg-docusaurus` `build`, `ssg-eleventy` and `ssg-jekyll` `_site`.
Full list with services, output directories and notes:
[references/catalogue.md](references/catalogue.md). If a framework is not in the list, there is no
template for it: start from the closest one, or import your repository.

## Start from a template in the dashboard

- **Static or Studio:** **Projects > New Project > Start from a template**.
- **App:** **Cloud Apps > New > Starter Kit** (the template list shows the `app-*` repositories).

The wizard creates a GitHub repository from the template, creates the Quant project or Quant Cloud
application, stores the credentials in the repository, and triggers the first deploy. Then:

| Kind | Secrets | Variables |
|---|---|---|
| Static | `QUANT_TOKEN` | `QUANT_CUSTOMER`, `QUANT_PROJECT` |
| Static + edge | `QUANT_TOKEN`, `QUANT_API_TOKEN` (project-scoped rules token) | as static, plus `QUANT_BASE_URL` (`{dashboard}/api/v2`) |
| App | `QUANT_API_KEY`, `QUANT_ORGANIZATION` | `QUANT_APPLICATION`, `QUANT_BASE_URL` |

The wizard also applies the template's `quant/meta.json`: it offers a managed database when the
template sets `requires_db`, generates the declared `secrets`, and for static templates creates the
declared KV stores. It removes the template-maintenance workflow (`ci.yml`) from your copy. Every
later push to `main` deploys. On gov, check that the deploy and purge steps of a static site have
`endpoint: https://api.quantgov.cloud/v1`, and add it if they do not.

## Copy a template by hand

Use this when you fork or copy a template on GitHub instead of using the wizard. **Nothing in
`quant/meta.json` is applied for you.**

1. **Create the target first:** a Quant project (static) or a Quant Cloud application (app). The
   workflow's actions create environments, not the application. For an app
   that needs a database, create the application with a managed database (dashboard toggle, or
   `"database": {"engine": "mysql"}` in the API body; see `quant-cloud-apps`).
2. Add the secrets and variables from the table above. Set `QUANT_APPLICATION` to your application
   name; without it the app workflow uses the repository name. On gov set `QUANT_BASE_URL` to
   `https://dash.quantgov.cloud/api/v3` (apps) and add `endpoint: https://api.quantgov.cloud/v1` to the
   deploy and purge steps (static).
3. Create what `meta.json` declares: secrets on the environment, KV stores (create, link to the
   project, write initial values), and project settings such as inline functions.
4. Check the build architecture (apps): the template compose files declare
   `quant.architecture: ARM64`, but the template workflows build `linux/amd64` unless you set the
   `BUILD_PLATFORM` variable. Set `BUILD_PLATFORM=linux/arm64` (with an ARM runner or a QEMU step),
   or change `quant.architecture` to `X86_64`. See [Build platform](#build-platform-apps).
5. Laravel and Symfony: `app-laravel` (`APP_KEY`) and `app-symfony` (`APP_SECRET`) ship a fixed,
   published default value in the compose `environment:`. Before the first deploy, generate a unique
   secret, set it as an environment secret, and remove the default from the compose file. If a site
   already runs with the published value, rotate it.
6. Delete `ci.yml` if you like: it maintains the template itself (publishes its image or checks its build).
7. Push to `main`. The init action maps `main` to the `production` environment.

**Check the copied workflow before the first push.** An app workflow must deploy only into your
application and the environment its branch maps to:

- `quant_application: ${{ vars.QUANT_APPLICATION || github.event.repository.name }}`. Do not hard-code
  another application name as the default.
- No fixed environment name. Without an override the init action maps `main` to `production`,
  `develop` to `develop`, and other branches to an environment of the branch name.
- Only the steps your deploy needs: checkout, QEMU and Buildx, init, build and push, compose,
  environment, state. Settings such as scaling or idle sleep belong on the environment (dashboard or
  API), not in each deploy.
- Quant Cloud actions at `@v4`. The template workflows pin `quantcdn/quant-cloud-compose-action@v1`;
  `@v4` is the current major with the same inputs and output, so you can change it when you copy.
- `platforms:` matches `quant.architecture` ([Build platform](#build-platform-apps)).

## `quant/meta.json`

The file is an object, or an array with one object (both are read the same way).

| Key | Kinds | Effect |
|---|---|---|
| `template_type` | all | `"app"`, `"ssg"`, or `"base"` (a base image, not a starting point) |
| `requires_db` | app | `true`: the wizard provisions a managed database (MySQL or Postgres) |
| `requires_cache` | app | `true`: the wizard pre-selects a managed cache (injects `REDIS_*`, `CACHE_PREFIX`) |
| `requires_s3` | app | `true`: the wizard pre-selects object storage (injects `S3_*`) |
| `secrets` | app | `[{"name": "X", "generate": "random", "length": 64}]`: a random value of `length` characters, set as a secret on the `production` environment |
| `kv_stores` | static | Stores to create, seed and link; see [references/meta-json.md](references/meta-json.md) |
| `project_settings` | static | Only `{"enable_inline_fn": true}`; setup only turns settings on |
| `title`, `summary`, `content`, `image`, `categories`, `tags`, `url` | all | Describe the template. No effect on what is created |

Who applies it: the dashboard template wizard, for templates in `quantcdn-templates`. Studio publish
also applies `kv_stores` and `project_settings` from a Studio site's own repository. The GitHub
deploy workflow never reads `meta.json`: it deploys functions and rules from
`quant/edge-functions.json` and `quant/edge-rules.json` (format: `quant-edge-functions-and-kv`).
Full key rules, KV value kinds and one-time credentials: [references/meta-json.md](references/meta-json.md).

## Make your own template

The dashboard template picker lists only repositories in the `quantcdn-templates` organisation. Your
own template repository is not listed, and its `meta.json` is not applied. To reuse a template
in your organisation, make it a GitHub template repository, create each site with **Use this template**,
and follow [Copy a template by hand](#copy-a-template-by-hand). Keep a `meta.json` anyway: it records
what each site needs, and Studio publish reads its `kv_stores` and `project_settings`.

### App template layout

```
Dockerfile                          # FROM ghcr.io/quantcdn-templates/app-node or app-apache-php
docker-compose.yml                  # what Quant Cloud imports
docker-compose.override.yml.example # local-only values; copy to docker-compose.override.yml
.dockerignore
.gitignore                          # include docker-compose.override.yml
README.md                           # secrets, variables, local run, gov note
quant/meta.json
quant/entrypoints/                  # start-up hooks, copied to /quant-entrypoint.d/ (.gitkeep if empty)
.github/workflows/build-deploy.yaml
```

Rules (the compose contract is in `quant-cloud-apps`; do not restate it differently):

1. Node apps on `app-node` listen on **3001** (`ENV PORT=3001`) and `EXPOSE 3000`. PHP apps on
   `app-apache-php` listen on 80.
2. Size the task in `x-quant-labels` (`quant.task.cpu`, `quant.task.memory`); the default 256/512 is
   too small for SSR with image optimisation or a CMS.
3. Label local services: `quant.type: mysql` / `postgres` for the database, `quant.type: none` for
   anything else local-only.
4. No `DB_*`, `REDIS_*`, `S3_*` or generated secrets in the deployed `environment:`, not even
   `${DB_HOST:-db}`: they override what the platform injects. Local values go in the override example.
5. The image tag in the workflow starts with the compose **service name**:
   `:<service>-${{ steps.init.outputs.image_suffix_clean }}` (`app-latest` for service `app` on `main`).
6. Build platform matches `quant.architecture` (next section).

Full `Dockerfile`, compose, override and workflow files: [references/own-template.md](references/own-template.md).

### Build platform (apps)

`quant.architecture` in `x-quant-labels` sets the CPU type the task runs on. The workflow's
`platforms:` sets the CPU type of the image. They must match, or the container stops at start with
`exec format error`.

| `quant.architecture` | Build `platforms:` | Runner |
|---|---|---|
| `ARM64` (the templates) | `linux/arm64` | `ubuntu-24.04-arm` (native), or `ubuntu-latest` with `docker/setup-qemu-action@v4` (slower) |
| `X86_64` | `linux/amd64` | `ubuntu-latest` |

The template workflows read `vars.BUILD_PLATFORM` (default `linux/amd64`) and `vars.RUNNER_TYPE`
(default `ubuntu-latest`), and have no QEMU step. The compose files declare `ARM64`, so the defaults
do not match. Choose one and keep the two in step:

- Keep `ARM64`: set the variable `BUILD_PLATFORM=linux/arm64`, and either set
  `RUNNER_TYPE=ubuntu-24.04-arm` or add a `docker/setup-qemu-action` step before Buildx.
- Use x86: change `quant.architecture` to `X86_64` in `x-quant-labels` and keep `linux/amd64`.

If you change the architecture later, change both.

An ARM64 build on an x86 runner uses emulation and is slower. Use an ARM runner (`RUNNER_TYPE`), or
build architecture-independent output (static assets, JS bundles) in a `FROM --platform=$BUILDPLATFORM`
builder stage; install native modules (for example `sharp`) in the target-platform stage.

### Static and static + edge templates

```
package.json                        # build script; your framework config and source
.gitignore
README.md
quant/meta.json                     # template_type "ssg", requires_db false
.github/workflows/deploy.yml        # build, deploy-action, purge-action
quant/edge-functions.json           # edge templates: function manifest (uuid per entry)
quant/edge-functions/*.js           # edge templates: function bodies
quant/edge-rules.json               # edge templates: rules (function_ref = manifest id)
```

- Set `dir:` to the framework's output directory (table: `quant-static-sites`).
- Guard the deploy and purge steps on the credentials, so the template repository, which has none,
  still verifies its build.
- Edge templates: commit a `uuid` for every manifest entry (`quant functions-add` writes one) and
  never change it; one template's UUID works in every project. Pass `functions`, and `rules` only
  when `QUANT_API_TOKEN` and `QUANT_BASE_URL` exist. Format and deploy: `quant-edge-functions-and-kv`.
- The README of a template with a one-time credential must say how to replace a lost one.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| Container exits at once: `exec format error` | Image built for `linux/amd64`, task is `ARM64`: the template workflows default `BUILD_PLATFORM` to `linux/amd64`, while the compose files declare `ARM64` | Set `BUILD_PLATFORM=linux/arm64` (ARM runner or QEMU step), or set `quant.architecture: X86_64` |
| Deploy lands in another application, or in an environment that does not match the branch | The copied init step hard-codes an application default or an environment override | Default to `vars.QUANT_APPLICATION`, else the repository name; remove the override |
| Copied app workflow fails at the environment step | The Quant Cloud application does not exist yet, or `QUANT_APPLICATION` names another one | Create the application first; set `QUANT_APPLICATION` |
| Workflow fails at init: organisation not found or no registry credentials, on gov | `QUANT_BASE_URL` not set, so it calls the public dashboard | Variable `QUANT_BASE_URL` = `https://dash.quantgov.cloud/api/v3` |
| Static deploy 401/403 on gov | No `endpoint` on deploy and purge | `endpoint: https://api.quantgov.cloud/v1` (or `vars.QUANT_ENDPOINT`) |
| App has no `DB_*` variables | Copied by hand; `requires_db` is applied only by the wizard | Create the app with a managed database |
| `PAYLOAD_SECRET` (or another declared secret) missing | Copied by hand; `secrets` are generated only by the wizard | Set the secret on the environment, then redeploy |
| Edge template: `Access to KV store ... is not allowed` | Copied by hand; store not created or not linked | Create the store, link it to the project, seed values |
| Edge template: rules never appear | No `QUANT_API_TOKEN` / `QUANT_BASE_URL`, so the workflow skips `rules` | Add a project-scoped token (`projects:read`, `rules:read`, `rules:write`) and `{dashboard}/api/v2` |
| Lost the one-time owner key from setup | Only its hash is stored | Follow the template README's reset steps |
| Laravel or Symfony site runs with the template's `APP_KEY` or `APP_SECRET` | The compose file ships a fixed, published default | Generate a unique secret, set it on the environment, remove the default, redeploy; rotate on existing sites |
| Image pull fails: tag not found | Workflow tag prefix differs from the compose service name | Tag `<service>-<suffix>` |
| Template not in the dashboard picker | Not in `quantcdn-templates`, or no `template_type` | Use **Use this template** and copy by hand |

## Further reading

- Templates: https://github.com/quantcdn-templates
- Start from a template: https://docs.quantcdn.io/guides/github-integration/start-from-template/
- Import a repository: https://docs.quantcdn.io/guides/github-integration/import-repository/
- Creating an application: https://docs.quantcdn.io/cloud/02-application-management/01-creating-a-new-application/
- Base images: https://docs.quantcdn.io/cloud/01-introduction-to-quant-cloud/06-quant-base-images/
- Related skills: `quant-cloud-apps` (compose contract, base images, databases), `quant-static-sites`
  (output directories, deploy), `quant-edge-functions-and-kv` (manifests, rules, KV),
  `quant-ci-github-actions` (workflows and versions), `quant-studio`, `quant-cms-integrations`

<!-- checked against gh:quantcdn/quant-cloud-compose-action 4.0.0 -->
<!-- checked against gh:quantcdn/deploy-action 7.0.1 -->
