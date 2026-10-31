# Workflow recipes

Every GitHub workflow here passes `actionlint`. All actions are pinned by commit SHA with the
version in a comment (Quant versions in [actions.md](actions.md)). Replace `example-*` names with
your own.

Gov values: every Quant Cloud action takes `base_url` = the bare dashboard host
(`https://dash.quantgov.cloud`; the v4 actions and environment-var v1.0.3 also accept `/api/v3`);
every content action takes `endpoint` = `https://api.quantgov.cloud/v1` (search-action from v2.1.0).

## Static site

Secret `QUANT_TOKEN`; variables `QUANT_CUSTOMER`, `QUANT_PROJECT`; on gov also `QUANT_ENDPOINT`.
Set `dir` to your framework's output directory (`public` for Hugo; table in `quant-static-sites`).

```yaml
name: Deploy static site to Quant

on:
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: quant-static-${{ github.ref }}
  cancel-in-progress: false        # queue runs; do not stop a deploy halfway

jobs:
  deploy:
    runs-on: ubuntu-latest
    env:
      QUANT_ENDPOINT: ${{ vars.QUANT_ENDPOINT || 'https://api.quantcdn.io/v1' }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1

      - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0
        with:
          node-version: '22'
          cache: npm

      - run: npm ci
      - run: npm run build            # a failed build ends the job here

      - name: Check the build output
        run: test -s dist/index.html  # never deploy an empty or partial directory

      - uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0
        with:
          path: .quant-revision
          key: quant-revision-${{ github.ref }}-${{ github.run_id }}
          restore-keys: quant-revision-${{ github.ref }}-

      - name: Deploy
        uses: quantcdn/deploy-action@d6d776177f9fbdf781a7d09c071185a9e509fcc3 # v7.1.1
        with:
          customer: ${{ vars.QUANT_CUSTOMER }}
          project: ${{ vars.QUANT_PROJECT }}
          token: ${{ secrets.QUANT_TOKEN }}
          endpoint: ${{ env.QUANT_ENDPOINT }}
          dir: dist                   # relative to the workspace
          revision-log: .quant-revision
          skip-purge: true

      - name: Purge
        uses: quantcdn/purge-action@540559574168b65a2310781a1656b06f45e01a71 # v7.1.1
        with:
          customer: ${{ vars.QUANT_CUSTOMER }}
          project: ${{ vars.QUANT_PROJECT }}
          token: ${{ secrets.QUANT_TOKEN }}
          endpoint: ${{ env.QUANT_ENDPOINT }}
          url_pattern: "/*"
```

## Pull request environments

One environment per pull request, named `pr-<number>` by the init action. It uses the same
secrets and variables as the app workflow in `SKILL.md`; the compose service is `app`. The first
run creates the environment as a copy of production's configuration, waits until creation
completes, then copies production's database. Later pushes update and redeploy it. Closing or
merging the pull request deletes it.

- Pull requests from forks get no secrets, so both jobs skip them.
- `from_environment` is used only when the environment is created. The new environment gets
  production's configuration and variables, an empty database (the sync fills it) and no secrets:
  set any secrets the app needs on the environment.
- Environment creation is asynchronous. The environment's `creationStatus` (platform API) is
  `creating`, then `completed` or `failed`. The wait step polls it before the sync.
- The sync step passes with a warning when the platform refuses the sync (for example, the app has
  no database). The next step fails the job when `skipped` is `true`.
- Each preview environment runs and costs like any other environment until it is deleted. Check
  the dashboard for `pr-*` environments whose pull request is already closed (for example, a
  cleanup run that failed) and delete them.

```yaml
name: PR environment

on:
  pull_request:
    types: [opened, synchronize, reopened, closed]

permissions:
  contents: read

concurrency:
  group: quant-pr-${{ github.event.pull_request.number }}
  cancel-in-progress: false          # never cancel a run that may be deleting

env:
  QUANT_BASE_URL: ${{ vars.QUANT_BASE_URL || 'https://dashboard.quantcdn.io' }}
  QUANT_APP: ${{ vars.QUANT_APPLICATION || github.event.repository.name }}

jobs:
  deploy:
    # Forks get no secrets: skip them. Closed PRs go to the cleanup job.
    if: github.event.action != 'closed' && github.event.pull_request.head.repo.full_name == github.repository
    runs-on: ${{ vars.RUNNER_TYPE || 'ubuntu-latest' }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: docker/setup-qemu-action@99012661954931238ded8c8b007157a8430204e1 # v4.4.0
      - uses: docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069 # v4.4.1

      - name: Initialize Quant Cloud     # PR -> environment pr-<n>, image suffix pr-<n>
        id: init
        uses: quantcdn/quant-cloud-init-action@ef36e08b9c21e6fc432f1673b49d7776657d3822 # v4.0.2
        with:
          quant_organization: ${{ secrets.QUANT_ORGANIZATION }}
          quant_api_key: ${{ secrets.QUANT_API_KEY }}
          quant_application: ${{ env.QUANT_APP }}
          base_url: ${{ env.QUANT_BASE_URL }}

      - name: Build and push
        uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc # v7.4.0
        with:
          context: .
          platforms: ${{ vars.BUILD_PLATFORM || 'linux/arm64' }}
          push: true
          tags: ${{ steps.init.outputs.stripped_endpoint }}/${{ secrets.QUANT_ORGANIZATION }}/${{ steps.init.outputs.quant_application }}:app-${{ steps.init.outputs.image_suffix_clean }}

      - name: Translate docker-compose.yml
        id: compose
        uses: quantcdn/quant-cloud-compose-action@71b65046ed3f40a6a5fa7f96688fc37b3fb86d61 # v4.0.1
        with:
          api_key: ${{ secrets.QUANT_API_KEY }}
          organization: ${{ secrets.QUANT_ORGANIZATION }}
          compose_file: docker-compose.yml
          image_suffix: ${{ steps.init.outputs.image_suffix_clean }}
          base_url: ${{ env.QUANT_BASE_URL }}

      - name: Create (cloned from production) or update
        uses: quantcdn/quant-cloud-environment-action@99bca1ffbfa3c0f1dcd31aad3aecedee86fb837d # v4.1.1
        with:
          api_key: ${{ secrets.QUANT_API_KEY }}
          organization: ${{ secrets.QUANT_ORGANIZATION }}
          app_name: ${{ steps.init.outputs.quant_application }}
          environment_name: ${{ steps.init.outputs.environment_name }}
          operation: ${{ steps.init.outputs.environment_exists == 'true' && 'update' || 'create' }}
          from_environment: production   # used only when the environment is created
          compose_spec: ${{ steps.compose.outputs.translated_compose }}
          base_url: ${{ env.QUANT_BASE_URL }}

      - name: Wait until the new environment is created
        if: steps.init.outputs.environment_exists != 'true'
        env:
          QUANT_API_KEY: ${{ secrets.QUANT_API_KEY }}
          ORG: ${{ secrets.QUANT_ORGANIZATION }}
          APP: ${{ steps.init.outputs.quant_application }}
          ENV_NAME: ${{ steps.init.outputs.environment_name }}
        run: |
          API="${QUANT_BASE_URL%/api/v3}/api/v3"
          URL="$API/organizations/$ORG/applications/$APP/environments/$ENV_NAME"
          for i in $(seq 1 40); do
            STATUS=$(curl -fsS -H "Authorization: Bearer $QUANT_API_KEY" "$URL" | jq -r '.creationStatus // empty')
            if [ "$STATUS" = "completed" ]; then exit 0; fi
            if [ "$STATUS" = "failed" ]; then echo "::error::Environment creation failed"; exit 1; fi
            echo "Waiting ($i/40): creationStatus=${STATUS:-unknown}"
            sleep 15
          done
          echo "::error::Environment not created after 10 minutes"
          exit 1

      - name: Copy the production database (first run only)
        id: sync
        if: steps.init.outputs.environment_exists != 'true'
        uses: quantcdn/quant-cloud-environment-sync-action@f2af81fba5c61313589ab2e25fe889f7a4ffed84 # v4.1.1
        with:
          api_key: ${{ secrets.QUANT_API_KEY }}
          organization: ${{ secrets.QUANT_ORGANIZATION }}
          app_name: ${{ steps.init.outputs.quant_application }}
          environment_name: ${{ steps.init.outputs.environment_name }}   # the target
          source: production
          type: database
          wait: true
          base_url: ${{ env.QUANT_BASE_URL }}

      - name: Fail if the sync was skipped
        if: steps.sync.outputs.skipped == 'true'
        run: |
          echo "::error::Database sync skipped (see the warning above)"
          exit 1

      - name: Redeploy
        if: steps.init.outputs.environment_exists == 'true'
        uses: quantcdn/quant-cloud-environment-state-action@64ba68816e09e22c9015f07f44f5c0538ce09374 # v4.0.2
        with:
          api_key: ${{ secrets.QUANT_API_KEY }}
          organization: ${{ secrets.QUANT_ORGANIZATION }}
          application: ${{ steps.init.outputs.quant_application }}
          environment: ${{ steps.init.outputs.environment_name }}
          action: redeploy
          base_url: ${{ env.QUANT_BASE_URL }}

  cleanup:
    if: github.event.action == 'closed' && github.event.pull_request.head.repo.full_name == github.repository
    runs-on: ubuntu-latest
    steps:
      - name: Delete the PR environment
        uses: quantcdn/quant-cloud-environment-action@99bca1ffbfa3c0f1dcd31aad3aecedee86fb837d # v4.1.1
        with:
          api_key: ${{ secrets.QUANT_API_KEY }}
          organization: ${{ secrets.QUANT_ORGANIZATION }}
          app_name: ${{ env.QUANT_APP }}
          environment_name: pr-${{ github.event.pull_request.number }}
          operation: delete            # succeeds if the environment is already gone
          base_url: ${{ env.QUANT_BASE_URL }}
```

## Variables, backups and a staging refresh

`QUANT_HOST` here is the **bare** dashboard host, because the environment variable action fails
with `/api/v3`. The other Quant Cloud actions accept it too.

- The variable action sets **plain variables**, not secrets. Do not send passwords or keys through
  it; set those as secrets in the dashboard (**Environment & Secrets**).
- Containers read variables at start, so redeploy after a change.
- `older_than_days` deletes every backup of that `type` older than the cut-off, including backups
  made by hand. The matrix runs it once per type.
- The refresh backs up staging first, because the sync overwrites it. A sync cannot target
  production.

```yaml
name: Quant Cloud operations

on:
  schedule:
    - cron: '0 15 * * *'             # 15:00 UTC daily
  workflow_dispatch:

permissions:
  contents: read

env:
  QUANT_HOST: ${{ vars.QUANT_HOST || 'https://dashboard.quantcdn.io' }}
  APP: ${{ vars.QUANT_APPLICATION }}

jobs:
  set-variables:
    if: github.event_name == 'workflow_dispatch'
    runs-on: ubuntu-latest
    steps:
      - name: Set variables (plain variables, not secrets)
        uses: quantcdn/quant-cloud-environment-var-action@54290b4e129254a1074a37be0d74fa7837ccd480 # v1.0.4
        with:
          api_key: ${{ secrets.QUANT_API_KEY }}
          organization: ${{ secrets.QUANT_ORGANIZATION }}
          app_name: ${{ env.APP }}
          environment_name: staging
          base_url: ${{ env.QUANT_HOST }}
          operation: set
          variables: |
            APP_ENV=staging
            LOG_LEVEL=debug

      - name: Redeploy so the containers read the new values
        uses: quantcdn/quant-cloud-environment-state-action@64ba68816e09e22c9015f07f44f5c0538ce09374 # v4.0.2
        with:
          api_key: ${{ secrets.QUANT_API_KEY }}
          organization: ${{ secrets.QUANT_ORGANIZATION }}
          application: ${{ env.APP }}
          environment: staging
          action: redeploy
          base_url: ${{ env.QUANT_HOST }}

  backup:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        type: [database, filesystem]
    steps:
      - name: Back up production
        uses: quantcdn/quant-cloud-environment-backup-action@2d268c726e9c35472b028fbfab660600d4f2d2aa # v4.4.4
        with:
          api_key: ${{ secrets.QUANT_API_KEY }}
          organization: ${{ secrets.QUANT_ORGANIZATION }}
          app_name: ${{ env.APP }}
          environment_name: production
          base_url: ${{ env.QUANT_HOST }}
          operation: create
          type: ${{ matrix.type }}
          backup_name: nightly-${{ github.run_id }}
          wait: true
          max_retries: '60'            # 60 x 10 s = 10 minutes

      - name: Delete backups older than 30 days
        uses: quantcdn/quant-cloud-environment-backup-action@2d268c726e9c35472b028fbfab660600d4f2d2aa # v4.4.4
        with:
          api_key: ${{ secrets.QUANT_API_KEY }}
          organization: ${{ secrets.QUANT_ORGANIZATION }}
          app_name: ${{ env.APP }}
          environment_name: production
          base_url: ${{ env.QUANT_HOST }}
          operation: delete
          type: ${{ matrix.type }}
          older_than_days: '30'

  refresh-staging:
    needs: backup
    runs-on: ubuntu-latest
    steps:
      - name: Back up staging first (the sync overwrites it)
        uses: quantcdn/quant-cloud-environment-backup-action@2d268c726e9c35472b028fbfab660600d4f2d2aa # v4.4.4
        with:
          api_key: ${{ secrets.QUANT_API_KEY }}
          organization: ${{ secrets.QUANT_ORGANIZATION }}
          app_name: ${{ env.APP }}
          environment_name: staging
          base_url: ${{ env.QUANT_HOST }}
          operation: create
          type: database
          wait: true

      - name: Copy production's database into staging
        id: sync
        uses: quantcdn/quant-cloud-environment-sync-action@f2af81fba5c61313589ab2e25fe889f7a4ffed84 # v4.1.1
        with:
          api_key: ${{ secrets.QUANT_API_KEY }}
          organization: ${{ secrets.QUANT_ORGANIZATION }}
          app_name: ${{ env.APP }}
          environment_name: staging       # the target
          source: production
          type: database
          wait: true
          base_url: ${{ env.QUANT_HOST }}

      - name: Fail if the sync was skipped
        if: steps.sync.outputs.skipped == 'true'
        run: |
          echo "::error::Sync skipped (see the warning above)"
          exit 1
```

## Static site with edge functions and rules

```yaml
      - name: Deploy site, edge functions and rules
        uses: quantcdn/deploy-action@d6d776177f9fbdf781a7d09c071185a9e509fcc3 # v7.1.1
        with:
          customer: ${{ vars.QUANT_CUSTOMER }}
          project: ${{ vars.QUANT_PROJECT }}
          token: ${{ secrets.QUANT_TOKEN }}                  # content token: files and functions
          endpoint: ${{ vars.QUANT_ENDPOINT || 'https://api.quantcdn.io/v1' }}
          dir: dist
          functions: quant/edge-functions.json
          rules: quant/edge-rules.json
          api-token: ${{ secrets.QUANT_API_TOKEN }}          # project-scoped rules token
          api-base-url: ${{ vars.QUANT_RULES_BASE_URL }}     # {dashboard}/api/v2
```

The rules URL is `{dashboard}/api/v2`, not the `/api/v3` that the Quant Cloud actions use. The
static + edge templates call this variable `QUANT_BASE_URL`, and the app templates use the same
name for `/api/v3`. In a repository with both kinds of workflow, use two names. Manifest format and
drift handling: `quant-edge-functions-and-kv`.

## Search records

```yaml
      - name: Index search records
        uses: quantcdn/search-action@908ed45742d8f9c80abe4155b93b0c9d13a90ba5 # v2.1.1
        with:
          customer: ${{ vars.QUANT_CUSTOMER }}
          project: ${{ vars.QUANT_PROJECT }}
          token: ${{ secrets.QUANT_TOKEN }}
          endpoint: https://api.quantgov.cloud/v1 # gov (v2.1.0 needs /v1). Public: omit.
          operation: index
          path: search/records.json               # one JSON file (an array of records), not a directory
```

If `path` is a directory, the step passes and indexes nothing. Use one step per file, or merge the
files into one array first (for example `jq -s 'add' search/*.json > search/records.json`).

## Optional: wait for the deployment in CI

The Quant Cloud actions return when the platform accepts the deploy. To make the job wait, poll
the environment after the redeploy step. `deploymentStatus` is `IN_PROGRESS`, `COMPLETED` or
`FAILED`; `deploymentFailureReason` says why a deployment failed. Right after the request the
status can still describe the previous deployment, so the step waits a minute first. This is a
check, not a guarantee: still read the logs when a release behaves oddly (`quant-cloud-apps`).

Append this step to the app workflow, after the redeploy step:

```yaml
      - name: Wait for the deployment to finish
        env:
          QUANT_API_KEY: ${{ secrets.QUANT_API_KEY }}
          ORG: ${{ secrets.QUANT_ORGANIZATION }}
          APP: ${{ steps.init.outputs.quant_application }}
          ENV_NAME: ${{ steps.init.outputs.environment_name }}
        run: |
          API="${QUANT_BASE_URL%/api/v3}/api/v3"
          URL="$API/organizations/$ORG/applications/$APP/environments/$ENV_NAME"
          sleep 60                       # let the new deployment register
          for i in $(seq 1 40); do
            BODY=$(curl -fsS -H "Authorization: Bearer $QUANT_API_KEY" "$URL")
            STATUS=$(echo "$BODY" | jq -r '.deploymentStatus // empty')
            echo "($i/40) deploymentStatus=$STATUS running=$(echo "$BODY" | jq -r .runningCount) desired=$(echo "$BODY" | jq -r .desiredCount)"
            if [ "$STATUS" = "COMPLETED" ]; then exit 0; fi
            if [ "$STATUS" = "FAILED" ]; then
              echo "::error::$(echo "$BODY" | jq -r '.deploymentFailureReason // "deployment failed"')"
              exit 1
            fi
            sleep 15
          done
          echo "::error::Deployment still in progress after 10 minutes"
          exit 1
```

## GitLab CI

`qc` cannot log in unattended: `qc login` opens a browser for OAuth and has no token option. In
any CI system that is not GitHub Actions, use `quant` for static sites and the platform API with
`curl` for Quant Cloud (the same calls the actions make). Keep `QUANT_TOKEN` and `QUANT_API_KEY` in
masked (and protected) CI/CD variables.

`quant` reads `QUANT_CLIENT_ID` (not `QUANT_CUSTOMER`), `QUANT_PROJECT`, `QUANT_TOKEN` and
`QUANT_ENDPOINT`. The `quantcdn/cli` image's entrypoint is `quant`, so clear it for GitLab.

```yaml
stages: [build, deploy]

build:
  stage: build
  image: node:22
  script:
    - npm ci
    - npm run build
    - test -s dist/index.html          # fail before deploy if the output is empty
  artifacts:
    paths: [dist/]

deploy-static:
  stage: deploy
  needs: [build]
  image:
    name: quantcdn/cli:7.2.0
    entrypoint: [""]                    # the image's entrypoint is quant; GitLab needs a shell
  variables:
    QUANT_ENDPOINT: https://api.quantgov.cloud/v1   # public: https://api.quantcdn.io/v1
    # QUANT_CLIENT_ID, QUANT_PROJECT, QUANT_TOKEN: masked CI/CD variables
  cache:
    key: quant-revision-$CI_COMMIT_REF_SLUG
    paths: [.quant-revision]
  script:
    - quant deploy dist --revision-log .quant-revision --skip-purge
    - quant purge "/*"
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

redeploy-app:
  stage: deploy
  image: alpine:3.20
  variables:
    QUANT_API: https://dash.quantgov.cloud/api/v3   # public: https://dashboard.quantcdn.io/api/v3
    ORG: agency
    APP: intranet
    ENV_NAME: production
    # QUANT_API_KEY: masked CI/CD variable (dashboard API token)
  script:
    - apk add --no-cache curl
    - >-
      curl -fsS -X PUT
      -H "Authorization: Bearer $QUANT_API_KEY"
      -H "Content-Type: application/json"
      -d '{"action": "redeploy"}'
      "$QUANT_API/organizations/$ORG/applications/$APP/environments/$ENV_NAME/state"
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

GitLab caches can be overwritten, so a fixed cache key keeps the revision log current.

## Any CI: build, push and redeploy an app with `curl`

This is what the init and state actions do. The registry credentials are short-lived; request new
ones in each run. The image path is `<registry>/<organisation>/<application>:<service>-<suffix>`.
Building `linux/arm64` on an x86 machine needs emulation (QEMU/binfmt) or an ARM machine.

```sh
#!/bin/sh
# Build, push and redeploy a Quant Cloud app from any CI. Needs docker (with buildx), curl, jq.
# QUANT_API_KEY: dashboard API token, from the CI system's secret store.
set -eu
QUANT_API=${QUANT_API:-https://dashboard.quantcdn.io/api/v3}   # gov: https://dash.quantgov.cloud/api/v3
ORG=example-org
APP=example-app
ENV_NAME=production
TAG=app-latest              # <compose service>-<suffix>; production uses -latest
AUTH="Authorization: Bearer $QUANT_API_KEY"

# 1. Registry credentials (short-lived) and login.
CREDS=$(curl -fsS -H "$AUTH" "$QUANT_API/organizations/$ORG/applications/ecr-login")
REGISTRY=$(printf '%s' "$CREDS" | jq -r .endpoint | sed -E 's#^https?://##')
printf '%s' "$CREDS" | jq -r .password |
  docker login "$REGISTRY" --username "$(printf '%s' "$CREDS" | jq -r .username)" --password-stdin

# 2. Build for the architecture in x-quant-labels (ARM64 -> linux/arm64) and push.
docker buildx build --platform linux/arm64 -t "$REGISTRY/$ORG/$APP:$TAG" --push .

# 3. Redeploy: the environment starts tasks from the new image.
curl -fsS -X PUT -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"action": "redeploy"}' \
  "$QUANT_API/organizations/$ORG/applications/$APP/environments/$ENV_NAME/state"
```

To change the compose definition from another CI system, use the API calls in
`quant-cloud-apps` (validate the compose file, then `PUT` the environment). The `PUT` redeploys.
