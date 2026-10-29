---
name: quant-cloud-apps
description: "Use when building, configuring, deploying or debugging a containerised app on Quant Cloud (QuantCDN or QuantGov) - the `docker-compose.yml` the platform imports (`x-quant-labels` task CPU/memory/architecture, `quant.type` labels, image tag = compose service name), Dockerfiles on the `app-node` (proxy 3000, app 3001, Next.js `HOSTNAME=0.0.0.0`) and `app-apache-php` base images, managed MySQL/Postgres (`database` in the create body) and injected `DB_*`/cache/storage variables, variables and secrets (redeploy to apply; compose `environment:` overrides injected values), `/quant-entrypoint.d/` hooks, cron, volumes (UID 1000), scaling, single-task mode, idle sleep, health checks and startup grace, backups and database sync. Also use first when a Quant Cloud environment is down or shows a 502/503/504 page (including finding its logs), CI is green but the site is old, or the app cannot reach its database. Static output: `quant-static-sites`; `qc` in depth: `qc-cli`."
---

# Quant Cloud apps

Quant Cloud runs your containers behind Quant's edge. You describe the app in a
`docker-compose.yml`, the platform translates it into its own compose definition, and each
environment runs that definition with your images. For the platform overview and the public/gov
split, load `quant-platform` first.

## Applies to

Both platforms: QuantCDN (`https://dashboard.quantcdn.io`) and QuantGov (`https://dash.quantgov.cloud`).
Features are the same. Only the API host changes: `{dashboard}/api/v3`. Checked 2026-10 against the
public docs, the public OpenAPI spec (API 4.25.0), the `quantcdn-templates` base images and templates,
`quant-cloud-compose-action` v4.0.0, `quant-cloud-environment-action` v4.1.0,
`quant-cloud-init-action` v4.0.1 and `qc` 0.7.0.

Use a cloud app when the code runs a server or needs a database. Plain build output is a static site
(`quant-static-sites`). To start from a ready template, see `quant-templates`.

## The model

- **Application > environment > containers.** An application has environments (`production`,
  `staging`, ...). Each environment runs one or more copies of a **task**: all the containers of your
  compose file, sharing the task's CPU and memory, scaled together.
- **Compose is the contract.** The dashboard (Import from GitHub, or Manual Setup with a compose
  upload), the compose action and the API all translate the same `docker-compose.yml`. The platform
  never runs `docker build`; CI builds and pushes the images.
- **Each environment is separate:** its own variables and secrets, volumes, database and scaling.
  A new environment copies production's configuration and variables, but gets an empty database and
  no secrets from production.

## Write the compose file

```yaml
# Read by Quant Cloud's compose import; ignored by local docker compose.
x-quant-labels:
  quant.task.cpu: "1024"        # 1 vCPU for the whole task
  quant.task.memory: "2048"     # MiB; must be a valid pair for the CPU
  quant.architecture: ARM64     # must match the platform you build the image for

services:
  app:                          # CI pushes the image tag app-<suffix>, e.g. app-latest
    build: .
    ports:
      - "3000:3000"
    environment:
      NODE_ENV: production      # never DB_*, REDIS_*, S3_* or CACHE_PREFIX here
    volumes:
      - media:/data             # named volume = persistent volume on Quant Cloud
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:3000/ || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 60s

  db:                           # local only
    image: postgres:17-alpine
    labels:
      quant.type: postgres      # not deployed; use the managed database
    environment:
      POSTGRES_PASSWORD: local

volumes:
  media:
```

Rules that break deploys when missed:

1. **Size the task.** Without `x-quant-labels` a new app gets 256 CPU / 512 MiB. That is too small for
   server rendering with image optimisation, or a CMS: the task stops answering and is replaced. Start
   SSR or CMS apps at `512`/`1024` or more and adjust from `qc env metrics`. Valid pairs and the
   per-container labels are in [references/compose-contract.md](references/compose-contract.md).
2. **The image tag starts with the service name.** A service with `build:` (or a tag-only `image:`)
   uses an internal image tagged `<service>-<suffix>`. Production is `<service>-latest`. If the
   service is `app`, CI must push `app-latest`, not `nextjs-latest`. Rename the service or the tag
   until they match.
3. **Do not shadow injected variables.** A value under `environment:` is container-level and wins over
   the variables and secrets the platform injects. `DB_HOST: ${DB_HOST:-db}` still pins the container
   to a fixed value, so the app dials `db`. Keep local values in `docker-compose.override.yml`, which
   docker compose reads locally and Quant Cloud does not.
4. **Label local-only services.** `quant.type: mysql` or `quant.type: postgres` on the local database,
   `quant.type: none` on anything else that must not deploy (a local Redis, a mail catcher).
5. **Volumes are real.** Every entry under a service's `volumes:` becomes a persistent volume,
   including a relative bind mount such as `./src:/var/www/html`, which then hides the code in your
   image. Put source-code bind mounts in the override file.
6. **Architecture matches the build.** `ARM64` with `linux/arm64` images, `X86_64` with `linux/amd64`.
   A mismatch stops the container at start (`exec format error`).
7. **No** `networks`, `secrets`, `configs`, privileged or host networking. Services reach each other
   by service name.

Check before you deploy: the compose action prints translation warnings, and the validate API
returns them without deploying ([references/api.md](references/api.md#validate-a-compose-file-no-deploy)).
Read every warning: adjusted sizes, skipped services and how each volume was read.

### Architecture and runner choice

Match the environment to the pushed image: `X86_64` needs `linux/amd64`, `ARM64` needs
`linux/arm64`. The current customer template workflow defaults to single-architecture amd64
on `ubuntu-latest`; published Quant template images are multi-architecture. Customer source
builds push into the application's own internal registry.

Set `BUILD_PLATFORM` to the target and `RUNNER_TYPE` to the runner label. For ARM64 on Quant
Cloud, recommend the customer's own native ARM64 runner (for example `RUNNER_TYPE=quant-arm64`
and `BUILD_PLATFORM=linux/arm64`). QEMU on x86_64 can be much slower for compilation and
compression. Keep a conditional QEMU step for cross-architecture or multi-architecture builds;
skip it for a native single-architecture build. The runner needs Docker and Buildx.

Workflows with per-environment selection read `BUILD_PLATFORMS` (JSON keyed by the Quant
environment name) before `BUILD_PLATFORM`. Preserve other entries when changing one environment.
Older workflow copies require the selection and QEMU steps; setting a variable alone does not
add emulation. Build the new variant before deploying an architecture change, and inspect the
registry index with `docker buildx imagetools inspect <image>` to verify the target exists.

## Images

### Node: `ghcr.io/quantcdn-templates/app-node`

The base image runs a small proxy on **port 3000** (exposed) that forwards to your app on
**127.0.0.1:3001**. It sets `Host` from Quant's `Quant-Orig-Host` header and adds `X-Forwarded-*`.

- Your server must listen on **3001** (`ENV PORT=3001`) and on an address the proxy reaches. Keep
  `EXPOSE 3000`.
- **Next.js standalone:** it binds to `$HOSTNAME`, and the container runtime can set `HOSTNAME` to the
  container's own name. Force it at exec time:
  `CMD ["sh", "-c", "HOSTNAME=0.0.0.0 exec node server.js"]`.
- Proxy answers: `503 Service Unavailable - App not ready` when nothing listens on 3001;
  `504 Gateway Timeout` after 30 s (`QUANT_PROXY_TIMEOUT`, ms); `502 Bad Gateway` for other errors.
  Each logs `[quant-proxy] Error forwarding to app: <reason>`.
- The process runs as `node` (UID 1000). Locally, set `QUANT_PROXY_ENABLED=false` and map `3000:3001`.

```dockerfile
FROM node:22-bookworm-slim AS build
WORKDIR /build
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM ghcr.io/quantcdn-templates/app-node:22
WORKDIR /app
COPY quant/entrypoints/ /quant-entrypoint.d/
RUN find /quant-entrypoint.d -name "*.sh" -exec chmod +x {} \;
COPY --from=build --chown=node:node /build/.next/standalone ./
COPY --from=build --chown=node:node /build/.next/static ./.next/static
COPY --from=build --chown=node:node /build/public ./public
ENV PORT=3001
EXPOSE 3000
CMD ["sh", "-c", "HOSTNAME=0.0.0.0 exec node server.js"]
```

### PHP: `ghcr.io/quantcdn-templates/app-apache-php`

Apache with mod_php on **port 80**; tags `8.4` (`latest`), `8.3`, `8.2`, `7.4`. It handles
`Quant-Orig-Host` and the client IP in Apache, logs to stdout/stderr, and runs as `www-data` remapped
to UID/GID 1000. Set `DOCUMENT_ROOT` (for example `/var/www/html/public`) and `PHP_*` variables for
limits. Its database connections use TLS; set `DISABLE_DB_TLS=true` only for a local database.

### Your own image

Any image works. It must listen on the port you expose, write logs to stdout/stderr, and run the
process that writes to volumes as UID 1000.

## Databases, cache and object storage

- **Managed MySQL or Postgres** is chosen when you create the app: the dashboard toggle, or in the API
  body `"database": {"engine": "mysql"}` (or `"postgres"`). It must be an object under the key
  `database`; other shapes do not create a database. Each environment gets its own database.
- The platform injects `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME` and `DB_PASSWORD` (the
  credentials as secrets) and manages them. Do not set or edit them yourself. Connect with TLS.
- **Cache** (Valkey, Redis-compatible) and **object storage** are organisation resources you attach
  to an environment. They inject `REDIS_*` and `CACHE_PREFIX`, or `S3_*`. Redeploy after attaching.
  Prefix every cache key with `CACHE_PREFIX`; a key outside it fails with `NOPERM`.

Variable lists: [references/compose-contract.md](references/compose-contract.md#variables-the-platform-injects).
API body: [references/api.md](references/api.md#create-an-application).

## Variables and secrets

- Set them per environment in the dashboard (**Environment & Secrets**), the API, or with
  `qc env vars set KEY VALUE --org --app --env` (`qc` 0.7.0+; also `list`, `get`, `unset`,
  `set --file .env`, `set KEY --stdin`). Use secrets for anything sensitive; secret values cannot be
  read back, and `qc env vars` does not manage secrets (use the dashboard).
- **A change reaches the containers only after a redeploy** (dashboard **Redeploy**,
  `qc env state redeploy`, or the state action).
- Precedence, highest first: container-level variables (including compose `environment:`), then
  environment-level variables, then secrets.

## Start-up: hooks, health checks, grace period

- **Hooks:** put `*.sh` files in `/quant-entrypoint.d/` in the image (templates copy `quant/entrypoints/`).
  They run at every container start, in alphabetical order, before the main process. They must be
  executable and have a shebang. A failing script stops the container from starting. Keep them
  idempotent: they run at every start of every task.
- **Container health check:** the compose `healthcheck` (`start_period` up to 300 s).
- **Startup grace period:** how long the load balancer ignores failing health checks after a task
  starts. Default **120 s**, up to 3600, set on the environment (dashboard, next to scaling, or
  `startupGracePeriodSeconds`). It is a ceiling: a task that is healthy sooner serves sooner. If boot
  work (migrations, cache warm-up) takes longer, raise it above the worst case, or the platform
  replaces the task mid-boot and the deploy loops.

## Deploy and verify

GitHub Actions flow (full workflow and versions: `quant-ci-github-actions`):

1. `quantcdn/quant-cloud-init-action@v4`: logs in to the registry; outputs `stripped_endpoint`,
   `quant_application`, `environment_name`, `environment_exists`, `image_suffix_clean`.
2. Build and push `<stripped_endpoint>/<org>/<app>:<service>-<image_suffix_clean>`.
3. `quantcdn/quant-cloud-compose-action@v4` with `image_suffix` translates the compose file.
4. `quantcdn/quant-cloud-environment-action@v4` creates or updates the environment. From v4.1.0
   it keeps the scaling set in the dashboard unless you set `min_capacity` and `max_capacity`.
   v4.0.0 reset the scaling to one task on every deploy.
5. `quantcdn/quant-cloud-environment-state-action@v4` with `action: redeploy` for an existing one.

On gov set `base_url: https://dash.quantgov.cloud` (the bare dashboard host) on every Quant Cloud action.
The bare host works for every action; the v4 actions also accept `{dashboard}/api/v3`.

**A green run is not a live deploy.** The actions ask the platform to deploy and return; they do
not wait for the new task to become healthy. Check after each deploy:

```bash
qc env list --org example-org --app example-app                # running/desired per environment
qc env logs --org example-org --app example-app --env production -f
```

The dashboard **Deployments** tab shows each deployment's status and error. A crash-looping or
unpullable release leaves running below desired, and its logs (or the deployment error) say why.

**Single-task mode** allows at most one running task. A deploy then stops the old task before the
new one starts, so every deploy is a short outage. The platform turns it on when it detects stateful
containers, unless you set `singleTaskOnly`. For zero-downtime deploys on a stateless app, set
`singleTaskOnly: false` and a minimum of 2 tasks.

## Run the app

- **Scaling:** min and max tasks per environment; auto-scaling on CPU %, memory % or requests per
  second per task. A fixed count is min = max. The app must keep no local state across tasks.
- **Idle sleep:** after 10 to 1440 idle minutes (default 30) the containers stop; the next visitor
  sees a loading page for one to three minutes. Database, volumes and caches keep running. Cron,
  exec and backups do not wake it. Best for non-production and editorial environments.
- **Cron:** dashboard **Cron Jobs**, or the cron API. Six-field schedule in **UTC**, for example
  `cron(0 2 * * ? *)`. Each run starts a temporary container from the environment's image, with its
  variables and volumes; run history shows output and exit code. Do not run `crond` in the web container.
- **One-off commands:** `qc exec run "<cmd>"` (temporary container) or `qc ssh` (live container).
  Details and quoting: `qc-cli`.
- **Volumes:** a volume is shared storage: every task of the environment sees the same files. Files
  belong to UID/GID 1000. If a write fails with permission denied, run the writer
  as UID 1000 (`user: "1000:1000"`, or the base images' `node` / `www-data`) and `chown` image paths
  to 1000. Do not `chmod 777`.
- **Add a volume to an existing environment:** a new environment copies production's volumes, but
  an existing environment does not get new volume definitions. Add the volume to each environment
  that needs it, in one of these ways:
  - Deploy the changed compose file (compose action plus environment action, the dashboard import,
    or the API). A redeploy alone does not read the compose file.
  - In the dashboard, define the volume on the environment's **Volumes** tab. Then, on **Edit
    Config**, add a mount point for it in the container.
- **Sensitive files:** put files that must not be public (private uploads, exports, keys) on their
  own volume, mounted outside the document root. Do not put them in a subdirectory of a public
  uploads volume.
- **Backups:** dashboard **Backups** (database and filesystem), `qc backup create|list|download`,
  or the backup action. A filesystem backup includes every volume of the environment. A database
  backup can be restored into another environment of the same app. Use these backups, not an app
  module that writes scheduled database dumps to a volume: those dumps grow without limit and stay
  on the same storage as the site.
- **Database and filesystem sync:** dashboard **Sync** on the **target** environment, the sync API,
  or the sync action. Syncs that involve production need the `trigger_prod_sync` permission. Back
  up the target first; a sync overwrites it.

API calls for all of these: [references/api.md](references/api.md).

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| Deploy fails, running stays below desired, deployment error says the image tag is not found | CI pushed a tag that does not start with the compose service name | Push `<service>-<suffix>` (`app-latest` for service `app`), or rename the service |
| `503 Service Unavailable - App not ready` (app-node) | Nothing listens on 3001: app still starting, crashed, wrong port, or Next.js bound to another host | `qc env logs`; `PORT=3001`; `HOSTNAME=0.0.0.0` at exec |
| `504 Gateway Timeout` after 30 s (app-node) | The request took longer than the proxy timeout | Make the request faster, or raise `QUANT_PROXY_TIMEOUT` |
| `[quant-proxy] Error forwarding to app: socket hang up` | The app process died mid-request | Read the log lines above it for the crash |
| Tasks restart during every deploy; logs show boot work cut off | Boot is longer than the startup grace period | Raise the grace period above worst-case boot; move migrations to a hook or `qc exec` |
| App slow, then replaced; `qc env metrics` near 100% CPU or memory | Task too small (often the 256/512 default) | Set `quant.task.cpu`/`quant.task.memory`, redeploy |
| App dials `db` or `localhost` for its database | Compose `environment:` sets `DB_*` and overrides the injected values | Remove them from the deployed compose; use the override file |
| No `DB_*` variables at all | The app was created without a database (wrong body shape, or toggle off) | Create it with `"database": {"engine": ...}`; check the app shows a database |
| Variable or secret change has no effect | Running containers keep the values they started with | Redeploy |
| Cache variables missing after attaching | Attachments render on the next deploy | Redeploy |
| `NOPERM` from the cache | Key written outside `CACHE_PREFIX` | Prefix keys with `CACHE_PREFIX` |
| `permission denied` writing to a volume | Writer is not UID 1000 | Run as UID 1000; `chown` to 1000 |
| A directory is missing at runtime, or empty after every deploy | It is not on a volume: the path is not in the image, or the image copy is replaced | Add a volume at that path (see [Run the app](#run-the-app)) |
| A volume added to `docker-compose.yml` never appears | CI only builds and redeploys; it does not deploy the compose file. Or the environment existed before the volume | Run the compose and environment actions in CI, or add the volume in the dashboard for each environment |
| Every deploy causes a short outage | Single-task mode, or one task | `singleTaskOnly: false` and min 2 tasks if the app is stateless |
| CI green but the site shows the old version | Deploy still rolling, or new tasks failing | `qc env list`, `qc env logs`, dashboard **Deployments** |
| Container exits at once with `exec format error` | Image architecture differs from `quant.architecture` | Build for the matching platform |
| Hook in `/quant-entrypoint.d/` never runs | Not `.sh`, not executable, or in a subdirectory | `chmod +x`, `.sh`, top level |
| Container never starts after adding a hook | The hook exits non-zero | Fix it, or let non-critical steps fail softly |
| Translation warning "Task-level memory adjusted" | Invalid CPU/memory pair | Choose a pair from the table |
| Code missing on Quant Cloud, present locally | A `./src:/path` bind mount became a persistent volume over the code | Move the bind mount to `docker-compose.override.yml` |

## Further reading

- Importing Docker Compose files: https://docs.quantcdn.io/cloud/01-introduction-to-quant-cloud/05-importing-docker-compose/
- Creating an application: https://docs.quantcdn.io/cloud/02-application-management/01-creating-a-new-application/
- Environment variables and secrets: https://docs.quantcdn.io/cloud/06-managing-env-vars-and-secrets/01-managing-environment-variables/
- Persistent storage: https://docs.quantcdn.io/cloud/07-persistent-storage-volumes/01-understanding-persistent-storage/
  (mount points: `#container-mount-points`); define a volume:
  https://docs.quantcdn.io/cloud/07-persistent-storage-volumes/03-defining-a-new-volume/
- Scaling and idle sleep: https://docs.quantcdn.io/cloud/08-scaling-your-application/03-idle-sleep/
- Startup grace period: https://docs.quantcdn.io/cloud/09-monitoring-application-health/03-startup-grace-period/
- Cron jobs: https://docs.quantcdn.io/cloud/10-managing-cron-jobs/01-configuring-cron-jobs/
- Start-up scripts: https://docs.quantcdn.io/cloud/12-deployment-hooks/01-post-deployment-scripts/
- Managed cache: https://docs.quantcdn.io/cloud/13-managed-cache/01-managed-valkey-cache/
- Backups and sync: https://docs.quantcdn.io/cloud/03-environment-management/08-managing-backups/
- Base images: https://docs.quantcdn.io/cloud/01-introduction-to-quant-cloud/06-quant-base-images/
  (source: https://github.com/quantcdn-templates/app-node, https://github.com/quantcdn-templates/app-apache-php)
- Related skills: `quant-platform`, `qc-cli` (logs, exec, ssh, backups), `quant-templates` (choose or
  write a template), `quant-ci-github-actions` (full workflow), `quant-iac` (Terraform/Pulumi),
  `quant-cms-integrations` (Drupal and WordPress)

<!-- checked against gh:quantcdn/quant-cloud-init-action 4.0.1 -->
<!-- checked against gh:quantcdn/quant-cloud-compose-action 4.0.0 -->
<!-- checked against gh:quantcdn/quant-cloud-environment-action 4.1.0 -->
<!-- checked against gh:quantcdn/quant-cloud-environment-state-action 4.0.1 -->
