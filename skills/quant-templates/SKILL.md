---
name: quant-templates
description: Use when choosing, starting from, copying or writing a Quant starter template (the `quantcdn-templates` GitHub organisation) on QuantCDN or QuantGov - which template fits (app template on Quant Cloud, static SSG template, or static + edge functions and KV such as `ssg-astro-edge-saas`), what the dashboard wizard sets up (repository, project or application, GitHub secrets and variables, database, KV stores), the `quant/meta.json` keys (`template_type`, `requires_db`, `requires_cache`, `requires_s3`, `secrets`, `kv_stores`, `project_settings`), copying a template by hand, and making your own template (layout, Dockerfile, override example, `build-deploy.yaml`, build platform). Also use when a workflow copied from a template deploys into the wrong application or environment or pins `quant-cloud-compose-action@v1`, when a site copied from a template lacks its database, secrets or KV stores, when a template ships a fixed `APP_KEY`, or when a container built from a template exits with `exec format error`.
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
`quant-cloud-environment-action` v4.1.0, `quant-cloud-environment-state-action` v4.0.1,
`deploy-action` v7.0.1 and `purge-action` v7.1.0.

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
| Static | `QUANT_TOKEN` (the project's deploy token) | `QUANT_CUSTOMER`, `QUANT_PROJECT`; on gov also `QUANT_ENDPOINT` |
| Static + edge | as static, plus `QUANT_API_TOKEN` (rules token) | as static, plus `QUANT_BASE_URL` (`{dashboard}/api/v2`) |
| App | `QUANT_API_KEY`, `QUANT_ORGANIZATION` | `QUANT_APPLICATION`, `QUANT_BASE_URL` (`{dashboard}/api/v3`) |

The rules token is issued only when the repository has `quant/edge-rules.json`. It is scoped to the
one project (`projects:read`, `rules:read`, `rules:write`) and expires after 365 days.

The wizard also sets up what the template needs:

- **Apps:** it pre-selects a managed database when `docker-compose.yml` has a database service
  (`image: mysql`, `postgres` or `mariadb`); the engine follows that service, default MySQL. It
  generates the `secrets` from `quant/meta.json` on the `production` environment.
- **Static:** it creates the KV stores and applies `project_settings` from `quant/meta.json`.
- **Gov static:** it sets `QUANT_ENDPOINT` and adds `endpoint: ${{ vars.QUANT_ENDPOINT }}` to the
  deploy and purge steps that have no `endpoint`.
- It removes the template-maintenance files (`ci.yml`, `ci-develop.yml`, `.github/dependabot.yml`).

It does not remove fixed secrets that some compose files ship (see [Fixed secrets](#fixed-secrets-in-some-templates)).
Every later push to `main` deploys.

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
3. Create what `meta.json` declares: secrets on the environment, KV stores (create in format 2,
   declare the indexes, link to the project, write initial values), and project settings such as inline functions.
4. Check the build architecture (apps): the template compose files declare
   `quant.architecture: ARM64`, and the template workflows build `linux/arm64` by default (QEMU on
   `ubuntu-latest`). For faster native builds, set the variable `RUNNER_TYPE=ubuntu-24.04-arm`. See
   [Build platform](#build-platform-apps).
5. Replace the fixed secrets that some compose files ship ([Fixed secrets](#fixed-secrets-in-some-templates)).
6. Delete `ci.yml` (and `ci-develop.yml` if present) if you like: it maintains the template itself.
7. Push to `main`. The init action maps `main` to the `production` environment.

**Check the copied workflow before the first push.** An app workflow must deploy only into your
application and the environment its branch maps to:

- `quant_application: ${{ vars.QUANT_APPLICATION || github.event.repository.name }}`. Do not hard-code
  another application name as the default.
- No fixed environment name. Without an override the init action maps `main` to `production`,
  `develop` to `develop`, and other branches to an environment of the branch name. The templates pass
  `environment_name_override: ${{ vars.QUANT_ENVIRONMENT_OVERRIDE }}`; leave that variable unset.
- Only the steps your deploy needs: checkout, QEMU and Buildx, init, build and push, compose,
  environment, state. Settings such as scaling or idle sleep belong on the environment (dashboard or
  API), not in each deploy.
- Quant Cloud actions at `@v4`, as the current templates use. Older copies pin
  `quantcdn/quant-cloud-compose-action@v1`; change it to `@v4` (same inputs and output).
- `platforms:` matches `quant.architecture` ([Build platform](#build-platform-apps)).

## `quant/meta.json`

The file is an object, or an array with one object (both are read the same way).

| Key | Kinds | Effect |
|---|---|---|
| `template_type` | all | `"app"`, `"ssg"`, or `"base"` (a base image, not a starting point). Records the kind; the pickers list repositories by name (`app-*`, `ssg-*`) |
| `requires_db` | app | Records that the app needs a database. The wizard does not read it: it pre-selects a database from the compose file |
| `requires_cache`, `requires_s3` | app | Recorded only. The wizard does not read them; add a cache or object storage yourself |
| `secrets` | app | `[{"name": "X", "generate": "random", "length": 64}]`: a random value of `length` characters (16-256, default 64), set as a secret on the `production` environment |
| `kv_stores` | static | Stores to create, seed and link, with optional indexes; see [references/meta-json.md](references/meta-json.md) |
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

The template workflows read `vars.BUILD_PLATFORM` (default `linux/arm64`) and `vars.RUNNER_TYPE`
(default `ubuntu-latest`), and have a `docker/setup-qemu-action` step. The compose files declare
`ARM64`, so the defaults match. Keep the two in step:

- Keep `ARM64`: change nothing, or set `RUNNER_TYPE=ubuntu-24.04-arm` for native builds.
- Use x86: change `quant.architecture` to `X86_64` in `x-quant-labels` and set
  `BUILD_PLATFORM=linux/amd64`.

If you change the architecture later, change both. An older copy of a template workflow can default
to `linux/amd64` and have no QEMU step: check it.

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

## Fixed secrets in some templates

These compose files set a published default in the deployed `environment:`. The value overrides an
environment secret of the same name, and the wizard does not remove it:

| Template | Variables |
|---|---|
| `app-statamic` | `APP_KEY` |
| `app-craft-cms` | `CRAFT_SECURITY_KEY`, and `CRAFT_ADMIN_PASSWORD` (default `password`) for the first install |
| `app-emdash` | `EMDASH_AUTH_SECRET`, `EMDASH_PREVIEW_SECRET` (these override the secrets the wizard generates) |

Before the first deploy, generate unique values, set them as environment secrets, and remove the
lines from `docker-compose.yml` (keep local values in the override file). If a site already runs with
a published value, rotate it and change the admin password. `app-laravel` and `app-symfony` keep
`APP_KEY` and `APP_SECRET` out of the compose file; the wizard generates them.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| Container exits at once: `exec format error` | Image built for `linux/amd64`, task is `ARM64`: `BUILD_PLATFORM` is set to `linux/amd64`, or the workflow is an older copy that defaults to it | Build `linux/arm64` (ARM runner or QEMU step), or set `quant.architecture: X86_64` |
| Deploy lands in another application, or in an environment that does not match the branch | The copied init step hard-codes an application default or an environment override | Default to `vars.QUANT_APPLICATION`, else the repository name; remove the override |
| Copied app workflow fails at the environment step | The Quant Cloud application does not exist yet, or `QUANT_APPLICATION` names another one | Create the application first; set `QUANT_APPLICATION` |
| Workflow fails at init: organisation not found or no registry credentials, on gov | `QUANT_BASE_URL` not set, so it calls the public dashboard | Variable `QUANT_BASE_URL` = `https://dash.quantgov.cloud/api/v3` |
| Static deploy 401/403 on gov | No `endpoint` on deploy and purge | `endpoint: https://api.quantgov.cloud/v1` (or `vars.QUANT_ENDPOINT`) |
| App has no `DB_*` variables | Copied by hand, or the compose file has no database service, so the wizard did not pre-select one | Add a managed database to the application (dashboard or API) |
| `PAYLOAD_SECRET` (or another declared secret) missing | Copied by hand; `secrets` are generated only by the wizard | Set the secret on the environment, then redeploy |
| Edge template: `Access to KV store ... is not allowed` | Copied by hand; store not created or not linked | Create the store, link it to the project, seed values |
| Edge template: rules never appear | No `QUANT_API_TOKEN` / `QUANT_BASE_URL`, so the workflow skips `rules` | Add a project-scoped token (`projects:read`, `rules:read`, `rules:write`) and `{dashboard}/api/v2` |
| Lost the one-time owner key from setup | Only its hash is stored | Follow the template README's reset steps |
| Statamic, Craft CMS or EmDash site runs with the template's key or secret | The compose file ships a fixed, published default | [Fixed secrets](#fixed-secrets-in-some-templates): set unique secrets, remove the defaults, redeploy; rotate on existing sites |
| Image pull fails: tag not found | Workflow tag prefix differs from the compose service name | Tag `<service>-<suffix>` |
| Template not in the dashboard picker | Not a public `app-*` or `ssg-*` repository in `quantcdn-templates` | Use **Use this template** and copy by hand |

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
<!-- checked against gh:quantcdn/quant-cloud-environment-action 4.1.0 -->
