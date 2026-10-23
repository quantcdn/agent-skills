# quant-cloud-apps evals

Prompt: I have a Next.js 15 app (App Router, `next/image`, server rendering) and want to run it on Quant Cloud using Quant's Node base image `ghcr.io/quantcdn-templates/app-node`. It needs 1 vCPU and 2 GB of memory and a managed Postgres database that my code reads from `DB_HOST`, `DB_USERNAME`, `DB_PASSWORD` and `DB_DATABASE`. Locally I run Postgres in compose. CI pushes the image with the init action. Write the `Dockerfile` and `docker-compose.yml`, and tell me what image tag CI must push for production.
Platform: public
Must include:
- The app listens on port 3001 (`PORT=3001`) because the base image's proxy listens on 3000; the container exposes 3000
- `HOSTNAME=0.0.0.0` for the Next.js standalone server (set at run time, for example `CMD ["sh", "-c", "HOSTNAME=0.0.0.0 exec node server.js"]`)
- Top-level `x-quant-labels` with `quant.task.cpu: "1024"` and `quant.task.memory: "2048"`
- The local Postgres service carries the label `quant.type: postgres` (so it is not deployed as a container) and the managed database's `DB_*` values are injected by the platform
- No `DB_*` values (not even `${DB_HOST:-db}` defaults) in the deployed `environment:`; local values go in `docker-compose.override.yml`
- The image tag starts with the compose service name: `<service>-latest` for production (for service `app`, `app-latest`)
Must not include:
- `PORT=3000` for the Next.js server behind the base image
- `DB_HOST: ${DB_HOST:-db}` (or any `DB_HOST` value) in the deployed compose `environment:`
- An image tag that starts with the framework name (for example `nextjs-latest`) while the service is `app`

Prompt: We are on QuantGov (https://dash.quantgov.cloud). I want to create a Quant Cloud application `records-api` with the API from a script, with a MySQL database, 0.5 vCPU / 1 GB. Last time we sent `"db": "mysql"` in the body and got "initiated successfully" but the app had no database. Show the request and explain what went wrong.
Platform: gov
Must include:
- `POST https://dash.quantgov.cloud/api/v3/organizations/{org}/applications` with `Authorization: Bearer <token>`
- The body field is `database` as an object: `"database": {"engine": "mysql"}` (`engine` is `mysql` or `postgres`)
- `appName` and `composeDefinition` are required; task size via `taskCpu: 512` and `taskMemory: 1024` in `composeDefinition`
- After creation the platform injects `DB_HOST`, `DB_USERNAME`, `DB_PASSWORD` and `DB_DATABASE` into the environment
- Confirm the database exists (dashboard Database / Backups tab, or the app's details) instead of trusting the create response
Must not include:
- `dashboard.quantcdn.io` or `api.quantcdn.io` for this customer
- `"db": "mysql"` or `"database": true` presented as a valid shape
- `X-Api-Secret`

Prompt: Our Quant Cloud environment `production` of app `shop` (org `acme`) shows "Service Unavailable - App not ready" and sometimes "Gateway Timeout". The GitHub Actions deploy run was green. We use the app-node base image. The app runs a database migration at start-up that takes about four minutes. Tell me how to diagnose this with the tools I have and what to change.
Platform: public
Must include:
- A green CI run only means the deploy was requested; the state/environment actions do not wait for the new container to become healthy
- Check with `qc env logs --org acme --app shop --env production` (or the dashboard Logs) and `qc env list` / dashboard for running vs desired count
- "Service Unavailable - App not ready" comes from the base image proxy when nothing listens on port 3001 (app not started yet, crashed, or listening on the wrong port or host); "Gateway Timeout" is the proxy's 30-second request timeout
- Raise the startup grace period (default 120 s, up to 3600) above the worst-case boot time, for example 300-600 s
- Move long migrations out of the request path or make them idempotent: a `/quant-entrypoint.d/` script, or run them with `qc exec run`
Must not include:
- Names a cloud vendor or managed service, or uses a cloud vendor CLI command
- A claim that a green CI run proves the new version is live

Prompt: Our Drupal app on Quant Cloud cannot connect to its managed MySQL database after we moved to compose import. The error says it cannot resolve host `db`. Our docker-compose.yml has `environment: DB_HOST: ${DB_HOST:-db}` and `DB_PASSWORD: ${DB_PASSWORD:-drupal}` on the `drupal` service so it works locally. We also changed `DB_PASSWORD` in the dashboard secrets an hour ago and nothing changed. What is wrong?
Platform: public
Must include:
- A value in the compose `environment:` is container-level configuration and wins over the variables and secrets the platform injects, so the container gets `db` instead of the managed database host
- Remove `DB_*` from the deployed compose file and put local values in `docker-compose.override.yml` (not deployed)
- Changes to environment variables or secrets take effect only after a redeploy (dashboard Redeploy or `qc env state redeploy`)
- The platform manages the injected database secrets (`DB_HOST`, `DB_USERNAME`, `DB_PASSWORD`, `DB_DATABASE`); do not overwrite them by hand
Must not include:
- A suggestion to keep `${DB_HOST:-db}` and set `DB_HOST` in the dashboard as the fix
- Names a cloud vendor or managed service

Prompt: My PHP app on `ghcr.io/quantcdn-templates/app-apache-php` writes uploads to `/var/www/html/uploads`, which I mount from a named volume in compose. Uploads fail with permission denied. The environment runs a single task (the dashboard shows single-task mode) and every deploy causes about a minute of downtime. I also want a nightly `php artisan schedule:run`-style job and to refresh staging with production's database each week. How do I fix and set up each of these on Quant Cloud?
Platform: public
Must include:
- Files on Quant Cloud volumes belong to UID/GID 1000; the process that writes must run as UID 1000 (the base image's `www-data` is remapped to 1000); `chown` to 1000 in the image or run as `1000:1000`
- Single-task mode allows at most one running task, so a deploy stops the old task before the new one starts; to avoid the gap, turn single-task mode off (`singleTaskOnly: false`) where the app allows it and run at least two tasks
- A cron job in the environment's Cron Jobs settings (or the cron API), schedules in UTC, runs in a temporary container
- Database sync from production into staging (dashboard Sync tab, sync API or sync action); production sync needs the `trigger_prod_sync` permission; back up the target first
Must not include:
- `chmod 777` as the recommended fix
- A crontab inside the long-running web container as the recommended approach
- Names a cloud vendor or managed service
