# Compose contract reference

What Quant Cloud reads from a `docker-compose.yml`, and what it injects back. Checked 2026-10
against the public docs (Importing Docker Compose Files), the public OpenAPI (API 4.25.0) and the
public templates and base images in `quantcdn-templates`.

## Top-level task labels

Put these in a top-level `x-quant-labels` block. Local `docker compose` ignores `x-` keys.

| Label | Value | Notes |
|---|---|---|
| `quant.task.cpu` | `256`, `512`, `1024`, `2048`, `4096` | CPU units for the whole task. 1024 = 1 vCPU |
| `quant.task.memory` | MiB, for example `2048` | Must be a valid pair with the CPU (table below) |
| `quant.architecture` | `ARM64` or `X86_64` | Must match the platform your image is built for |

Without task labels a new app gets the platform default, 256 CPU / 512 MiB.

## Valid CPU and memory pairs

| `quant.task.cpu` | vCPU | `quant.task.memory` (MiB) |
|---|---|---|
| 256 | 0.25 | 512, 1024, 2048 |
| 512 | 0.5 | 1024, 2048, 3072, 4096 |
| 1024 | 1 | 2048 to 8192 in steps of 1024 |
| 2048 | 2 | 4096 to 16384 in steps of 1024 |
| 4096 | 4 | 8192 to 30720 in steps of 1024 |

An invalid value is adjusted to the nearest valid one, with a translation warning. Read the
warnings (compose action log, or `translationWarnings` from the validate API) to see what you got.

## Service labels

| Label | Effect |
|---|---|
| `quant.type: none` | The service is not deployed. Use it for local-only helpers (mail catchers, a local Redis). |
| `quant.type: mysql` / `quant.type: postgres` | Marks the local database service. It is not deployed as a container. Use the managed database instead (see below). |
| `quant.cpu`, `quant.memory`, `quant.memory.reservation` | Per-container CPU units and memory (MiB). Optional; task labels set the task size. |

Labels can be written as a map (`quant.type: none`) or a list (`- "quant.type=none"`).

## Compose keys

| Key | On Quant Cloud |
|---|---|
| `image:` with a registry or name and tag (`nginx:1.27`, `ghcr.io/org/img:1.0`) | External image, pulled as written |
| `image:` with a tag only (`latest`) | Internal image in your organisation's Quant Cloud registry |
| `build:` | The platform does not build. The service uses an internal image with the tag `<service>-<suffix>`; CI must push that tag |
| `command:`, `entrypoint:` | Supported, string or list |
| `environment:` | Becomes container-level variables. These win over environment-level variables and over injected secrets |
| `ports:` | The container port is used (`"3000:3000"` and `"3000"` both expose 3000) |
| `volumes:` (named) | Each named volume becomes a persistent volume of the environment; missing ones are created |
| `volumes:` (relative path such as `./src:/var/www/html`) | Read as a logical volume name, so it also becomes a persistent volume mounted over that path |
| `depends_on:` | Supported; conditions `START`, `HEALTHY`, `COMPLETE`, `SUCCESS` |
| `healthcheck:` | Container health check (see below) |
| `working_dir:`, `user:` | Supported |
| `deploy.resources` | Supported: `limits.cpus`, `limits.memory`, `reservations.memory` set the container's CPU and memory |
| `deploy.replicas` | Ignored. The number of running copies comes from the environment's minimum and maximum capacity (scaling settings, `minCapacity`/`maxCapacity`), not from compose |
| `networks`, `secrets`, `configs`, host network, privileged, devices | Not supported. Services reach each other by service name; use Quant Cloud secrets |

## Container health check limits

From the public OpenAPI (`healthCheck` on a container):

| Field | Default | Range |
|---|---|---|
| `interval` | 30 s | 5 to 300 |
| `timeout` | 5 s | 2 to 60 |
| `retries` | 3 | 1 to 10 |
| `startPeriod` | none | 0 to 300 |

The environment's **startup grace period** (`startupGracePeriodSeconds`, default 120, 0 to 3600)
is a separate setting for the load balancer health check. See SKILL.md.

## Image tags

| Where | Rule |
|---|---|
| Internal image tag | `<service>-<suffix>`, where `<service>` is the compose service name |
| Suffix | The init action's `image_suffix_clean` output, for example `latest` for production |
| Production | `<service>-latest`, for example `app-latest` for service `app` |
| Compose `image_suffix` input / `imageSuffix` API field | Rewrites internal tags to `<service>-<suffix>` |

The template workflows tag `app-…` for service `app` and `drupal-…` for service `drupal`. A tag
that starts with anything else (for example the framework name) is never pulled.

## Variables the platform injects

| Source | Variables |
|---|---|
| Managed database | `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` (credentials as secrets) |
| Managed cache (Valkey, Redis-compatible) | `REDIS_ENABLED`, `REDIS_HOST`, `REDIS_SERVICE_PORT` (6379), `REDIS_TLS` (1), `REDIS_USER`, `REDIS_PASSWORD`, `CACHE_PREFIX` |
| Object storage | `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` |
| Generated template secrets | Names the template declares |

An attachment made with a variable prefix (for example `MEDIA`) prefixes every name
(`MEDIA_REDIS_HOST`, `MEDIA_S3_BUCKET`). Cache and object storage values reach a running
environment only after its next deploy.

Never set any of these names in the deployed compose `environment:`. A compose value wins, even a
default such as `DB_HOST: ${DB_HOST:-db}`.

## Base images

### `ghcr.io/quantcdn-templates/app-node`

| Item | Value |
|---|---|
| Proxy port (exposed) | 3000 (`QUANT_PROXY_PORT`) |
| App port | 3001 (`QUANT_APP_PORT`, set in the image; the app must listen there) |
| Proxy request timeout | 30 s (`QUANT_PROXY_TIMEOUT`, in ms, default 30000) |
| Proxy answers | `503 Service Unavailable - App not ready` (nothing listening on the app port), `504 Gateway Timeout` (timeout), `502 Bad Gateway` (other errors) |
| Proxy log line | `[quant-proxy] Error forwarding to app: <reason>` |
| Proxy health path | `/__quant_proxy_health` answers 200 from the proxy itself, even when the app is down |
| Headers | `Quant-Orig-Host` becomes `Host`; `X-Forwarded-Proto` defaults to `https`; `X-Forwarded-For` is set |
| Start-up | Runs executable `/quant-entrypoint.d/*.sh` in order, with `set -e`, then starts the proxy, then your `CMD` |
| User | Drops from root to `node` (UID 1000) |
| Local development | `QUANT_PROXY_ENABLED=false` and map `3000:3001` |

### `ghcr.io/quantcdn-templates/app-apache-php`

| Item | Value |
|---|---|
| Port | 80 |
| PHP tags | `8.4` (also `latest`), `8.3`, `8.2`, `7.4` (legacy) |
| Document root | `DOCUMENT_ROOT` (default `/var/www/html`) |
| Headers | `Quant-Orig-Host` handled in Apache; client IP from `Quant-Client-IP` |
| User | `www-data` remapped to UID/GID 1000 |
| Logs | Apache and PHP log to stdout/stderr |
| PHP settings | `PHP_MEMORY_LIMIT` (256M), `PHP_UPLOAD_MAX_FILESIZE`, `PHP_POST_MAX_SIZE`, `PHP_MAX_EXECUTION_TIME` and others |
| Database TLS | On by default; `DISABLE_DB_TLS=true` only for a local database |
| Mail | `QUANT_SMTP_*` variables configure a relay |
