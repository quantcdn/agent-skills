# Your own template: files

Starting points for an app template and a static template. Replace `example` names. The compose
rules behind these files are in `quant-cloud-apps`; the deploy-action inputs are in
`quant-static-sites` and `quant-edge-functions-and-kv`.

## App: `Dockerfile` (Node)

```dockerfile
ARG NODE_VERSION=22
FROM node:${NODE_VERSION}-bookworm-slim AS build
WORKDIR /build
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM ghcr.io/quantcdn-templates/app-node:${NODE_VERSION}
WORKDIR /app
COPY quant/entrypoints/ /quant-entrypoint.d/
RUN find /quant-entrypoint.d -name "*.sh" -exec chmod +x {} \;
# Copy the framework's server output
COPY --from=build --chown=node:node /build/dist ./
# The base image's proxy listens on 3000 and forwards to the app on 3001
ENV PORT=3001
EXPOSE 3000
CMD ["node", "server.js"]
```

Next.js standalone: copy `.next/standalone`, `.next/static` and `public`, and start with
`CMD ["sh", "-c", "HOSTNAME=0.0.0.0 exec node server.js"]`.

## App: `Dockerfile` (PHP)

```dockerfile
ARG PHP_VERSION=8.4
FROM ghcr.io/quantcdn-templates/app-apache-php:${PHP_VERSION}
ENV DOCUMENT_ROOT=/var/www/html/public
WORKDIR /var/www/html
COPY src/composer.json src/composer.lock* ./
RUN composer install --no-dev --no-scripts --optimize-autoloader
COPY src/ ./
RUN composer dump-autoload --optimize --no-dev
COPY quant/entrypoints/ /quant-entrypoint.d/
RUN find /quant-entrypoint.d -name "*.sh" -exec chmod +x {} \; && chown -R www-data:www-data /var/www/html
EXPOSE 80
```

The base image handles `Quant-Orig-Host` and the client IP, logs to stdout/stderr, and runs
`www-data` as UID/GID 1000. Put migrations and cache warm-up in `quant/entrypoints/*.sh` (they run at
every container start; keep them idempotent).

## App: `docker-compose.yml`

```yaml
x-quant-labels:
  quant.task.cpu: "512"
  quant.task.memory: "1024"
  quant.architecture: ARM64        # build linux/arm64 to match

services:
  app:                             # image tag prefix: app-<suffix>
    build: .
    ports:
      - "80:80"                    # Node on app-node: "3000:3000"
    environment:
      APP_ENV: production          # no DB_*, REDIS_*, S3_* or generated secrets here
    volumes:
      - app_files:/var/www/html/storage
    depends_on:
      - db

  db:                              # local only; Quant Cloud uses the managed database
    image: mysql:8.4
    labels:
      quant.type: mysql
    environment:
      MYSQL_DATABASE: app
      MYSQL_USER: app
      MYSQL_PASSWORD: app
      MYSQL_ROOT_PASSWORD: root
    volumes:
      - db_data:/var/lib/mysql

volumes:
  app_files:
  db_data:
```

## App: `docker-compose.override.yml.example`

```yaml
# Copy to docker-compose.override.yml for local development.
# docker compose reads it automatically; Quant Cloud does not. Keep it out of git.
services:
  app:
    environment:
      DB_HOST: db
      DB_PORT: "3306"
      DB_DATABASE: app
      DB_USERNAME: app
      DB_PASSWORD: app
      DISABLE_DB_TLS: "true"       # local MySQL has no TLS
      SESSION_SECRET: local-only
    volumes:
      - ./src:/var/www/html        # source bind mount: local only
  db:
    ports:
      - "3306:3306"
```

For a Node app on `app-node`, also set `QUANT_PROXY_ENABLED: "false"` and map `"3000:3001"`.

## App: `.github/workflows/build-deploy.yaml`

Secrets `QUANT_API_KEY`, `QUANT_ORGANIZATION`. Variables `QUANT_APPLICATION` (your application;
default the repository name), `QUANT_BASE_URL` (gov: the bare host `https://dash.quantgov.cloud`; the v4 actions also accept `/api/v3`), and
optionally `BUILD_PLATFORM`, `RUNNER_TYPE`.

```yaml
name: Build and deploy to Quant Cloud

on:
  push:
    branches: [main]

concurrency:
  group: build-and-deploy-${{ github.ref }}
  cancel-in-progress: true

env:
  QUANT_BASE_URL: ${{ vars.QUANT_BASE_URL || 'https://dashboard.quantcdn.io' }}

jobs:
  deploy:
    # ubuntu-24.04-arm builds natively; ubuntu-latest builds arm64 under QEMU (slower)
    runs-on: ${{ vars.RUNNER_TYPE || 'ubuntu-latest' }}
    steps:
      - uses: actions/checkout@v5

      - uses: docker/setup-qemu-action@v4

      - uses: docker/setup-buildx-action@v4

      - name: Initialize Quant Cloud
        id: init
        uses: quantcdn/quant-cloud-init-action@v4
        with:
          quant_organization: ${{ secrets.QUANT_ORGANIZATION }}
          quant_api_key: ${{ secrets.QUANT_API_KEY }}
          quant_application: ${{ vars.QUANT_APPLICATION || github.event.repository.name }}
          base_url: ${{ env.QUANT_BASE_URL }}

      - name: Build and push
        uses: docker/build-push-action@v7
        with:
          context: .
          # Must match quant.architecture: ARM64 -> linux/arm64, X86_64 -> linux/amd64
          platforms: ${{ vars.BUILD_PLATFORM || 'linux/arm64' }}
          push: true
          # Prefix = the compose service name ("app")
          tags: ${{ steps.init.outputs.stripped_endpoint }}/${{ secrets.QUANT_ORGANIZATION }}/${{ steps.init.outputs.quant_application }}:app-${{ steps.init.outputs.image_suffix_clean }}
          cache-from: type=gha,scope=app
          cache-to: type=gha,mode=max,scope=app

      - name: Translate docker-compose.yml
        id: compose
        uses: quantcdn/quant-cloud-compose-action@v4
        with:
          api_key: ${{ secrets.QUANT_API_KEY }}
          organization: ${{ secrets.QUANT_ORGANIZATION }}
          compose_file: docker-compose.yml
          image_suffix: ${{ steps.init.outputs.image_suffix_clean }}
          base_url: ${{ env.QUANT_BASE_URL }}

      - name: Create or update the environment
        uses: quantcdn/quant-cloud-environment-action@v4
        with:
          api_key: ${{ secrets.QUANT_API_KEY }}
          organization: ${{ secrets.QUANT_ORGANIZATION }}
          app_name: ${{ steps.init.outputs.quant_application }}
          environment_name: ${{ steps.init.outputs.environment_name }}
          operation: ${{ steps.init.outputs.environment_exists == 'true' && 'update' || 'create' }}
          compose_spec: ${{ steps.compose.outputs.translated_compose }}
          base_url: ${{ env.QUANT_BASE_URL }}

      - name: Redeploy
        if: ${{ steps.init.outputs.environment_exists == 'true' }}
        uses: quantcdn/quant-cloud-environment-state-action@v4
        with:
          api_key: ${{ secrets.QUANT_API_KEY }}
          organization: ${{ secrets.QUANT_ORGANIZATION }}
          application: ${{ steps.init.outputs.quant_application }}
          environment: ${{ steps.init.outputs.environment_name }}
          action: redeploy
          base_url: ${{ env.QUANT_BASE_URL }}
```

The init action maps `main` to `production` and the image suffix `latest`, so this run pushes
`app-latest`. A green run means the deploy was requested; check the environment afterwards
(`quant-cloud-apps`, "Deploy and verify").

## Static: `.github/workflows/deploy.yml`

Variables `QUANT_CUSTOMER`, `QUANT_PROJECT`, optional `QUANT_ENDPOINT` (gov:
`https://api.quantgov.cloud/v1`). Secret `QUANT_TOKEN`. Pin actions as `quant-ci-github-actions`
says; tags are shown here for reading.

```yaml
name: Deploy to Quant

on:
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    env:
      # The template repository itself has no credentials: it only verifies the build.
      DEPLOY_CONFIGURED: ${{ vars.QUANT_CUSTOMER != '' && vars.QUANT_PROJECT != '' && secrets.QUANT_TOKEN != '' }}
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v4
        with:
          node-version: '22'
      - run: npm install
      - run: npm run build

      - name: Deploy
        if: env.DEPLOY_CONFIGURED == 'true'
        uses: quantcdn/deploy-action@v7
        with:
          customer: ${{ vars.QUANT_CUSTOMER }}
          project: ${{ vars.QUANT_PROJECT }}
          token: ${{ secrets.QUANT_TOKEN }}
          endpoint: ${{ vars.QUANT_ENDPOINT || 'https://api.quantcdn.io/v1' }}
          dir: dist                      # the framework's output directory
          skip-purge: true

      - name: Purge
        if: env.DEPLOY_CONFIGURED == 'true'
        uses: quantcdn/purge-action@v7
        with:
          customer: ${{ vars.QUANT_CUSTOMER }}
          project: ${{ vars.QUANT_PROJECT }}
          token: ${{ secrets.QUANT_TOKEN }}
          endpoint: ${{ vars.QUANT_ENDPOINT || 'https://api.quantcdn.io/v1' }}
          url_pattern: "/*"
```

Static + edge: add to the deploy step

```yaml
          functions: quant/edge-functions.json
          rules: ${{ secrets.QUANT_API_TOKEN != '' && vars.QUANT_BASE_URL != '' && 'quant/edge-rules.json' || '' }}
          api-token: ${{ secrets.QUANT_API_TOKEN }}
          api-base-url: ${{ vars.QUANT_BASE_URL }}     # {dashboard}/api/v2
```

## Checklist

1. `quant/meta.json` with `template_type` and, for apps, `requires_db` and `secrets`.
2. Apps: `PORT=3001` / `EXPOSE 3000` on `app-node`; port 80 on `app-apache-php`.
3. Apps: `x-quant-labels` task size and `quant.architecture`; build platform matches.
4. Apps: local database labelled `quant.type: mysql` or `postgres`; no injected names in
   `environment:`; local values only in the override example.
5. Apps: image tag prefix = compose service name.
6. Static: `dir:` = output directory; `endpoint` from `QUANT_ENDPOINT` for gov.
7. Edge: a committed `uuid` on every manifest entry; rules use `function_ref`.
8. README: secrets and variables to set, how to run locally, the gov values, and (edge) how to
   replace a lost one-time credential.
9. Build the image (`docker build .`) or the site (`npm run build`) before you push.
