---
name: quant-ci-github-actions
description: Use when writing, fixing or reviewing a CI pipeline that deploys to QuantCDN or QuantGov - GitHub Actions workflows with `quantcdn/deploy-action`, `purge-action`, `search-action` and the Quant Cloud actions (init, compose, environment, state, sync, environment-var, backup), their current versions and pinning by commit SHA, secrets vs repository variables, where the gov values go (`endpoint`, `api-base-url`, `base_url`), static-site and container-app workflows, pull request environments (clone from production, copy the database, delete on close), environment variables, scheduled backups and staging refreshes, and confirming that a green run is really live. Also use for GitLab CI or any other CI system (the `quant` CLI and the platform API; `qc` cannot log in unattended), when a deploy resets scaling to one task, when a step fails with a doubled `/api/v3/api/v3` path, or when a sync or upload step passes but did nothing.
---

# CI pipelines for Quant

Quant publishes GitHub actions for both products: content actions for static sites, and Quant
Cloud actions for container apps. Other CI systems use the `quant` CLI and the platform API. For
the platform overview and the public/gov split, load `quant-platform` first. What a deploy does
(unpublish, revision log, compose contract) is in `quant-static-sites` and `quant-cloud-apps`; this
skill covers the pipeline around it.

## Applies to

Both platforms: QuantCDN (`https://dashboard.quantcdn.io`) and QuantGov (`https://dash.quantgov.cloud`).
Checked 2026-10 against each action's `action.yml` and source at its latest tag, `quant` 7.0.1 and
`qc` 0.7.0. All versions, SHAs, inputs and outputs: [references/actions.md](references/actions.md).

| Value | Public | Gov | Used by |
|---|---|---|---|
| Content API `endpoint` | `https://api.quantcdn.io/v1` (default) | `https://api.quantgov.cloud/v1` | deploy-action, purge-action, `quant` |
| search-action v2.0.0 `endpoint` | `https://api.quantcdn.io` (default) | `https://api.quantgov.cloud` (**no `/v1`**: its CLI adds it) | search-action |
| Rules `api-base-url` | `https://dashboard.quantcdn.io/api/v2` | `https://dash.quantgov.cloud/api/v2` | deploy-action with `rules` |
| Quant Cloud `base_url` | `https://dashboard.quantcdn.io` (default) | `https://dash.quantgov.cloud` | every Quant Cloud action |

Use the bare dashboard host for every Quant Cloud action. The v4 actions also accept
`{dashboard}/api/v3` (the templates use it). The
environment variable action (v1.0.2) accepts **only** the bare host: it does not strip `/api/v3`,
so a value ending `/api/v3` doubles the path (`/api/v3/api/v3/...`, "route could not be found").
Its default is the bare public host and works; on gov set `https://dash.quantgov.cloud`. The bare
host works for every Quant Cloud action. Each credential belongs to one platform. Ask for the
dashboard URL if you do not know the platform.

`quant-cloud-ecr-action` is superseded: the init action logs Docker in to the registry.

## Secrets and variables

| Name | Store as | What it is |
|---|---|---|
| `QUANT_TOKEN` | secret | Project token (project, Integrations). Content actions only |
| `QUANT_API_TOKEN` | secret | Project-scoped platform token for rules (`projects:read`, `rules:read`, `rules:write`) |
| `QUANT_API_KEY` | secret | Dashboard API token (profile, API Tokens). Quant Cloud actions and the platform API |
| `QUANT_ORGANIZATION` | secret (templates) | Organisation name for the Quant Cloud actions |
| `QUANT_CUSTOMER`, `QUANT_PROJECT` | variable | Organisation and project names for the content actions |
| `QUANT_APPLICATION`, `QUANT_BASE_URL`, `QUANT_ENDPOINT` | variable | Application name; gov `base_url`; gov content endpoint |

- Tokens are secrets: GitHub masks them in logs and never gives them to workflows from forks.
- Names and URLs are not sensitive. As variables they stay readable in logs (a secret is masked
  as `***` wherever it appears). The templates keep `QUANT_ORGANIZATION` as a secret; either works.
- The two token kinds are not interchangeable: a dashboard API token fails on the content API, and
  a project token fails on the platform API.
- For production, put the secrets in a GitHub **environment** with protection rules and set
  `environment: production` on the job.

## Pin actions by SHA

Why (say this when you pin for someone): a tag can move. `@v4` follows each new 4.x release, and
the repository owner can re-point any tag, so the code that runs can change without a change to
your workflow. A commit SHA cannot change. Pin the full 40-character SHA and keep the version in a
comment, so people and Dependabot can read it:

```yaml
uses: quantcdn/deploy-action@9bf8cae8497ab6628d4b248db9eb11464f37e1e5 # v7.0.1
```

Let Dependabot raise update pull requests: add `.github/dependabot.yml` with an `updates` entry for
`package-ecosystem: github-actions` (directory `/`). It updates the SHA and the comment together.

Use `deploy-action` v7 (v6 runs CLI 6.x and accepts function manifests without UUIDs). Pin
third-party actions (`actions/checkout`, `docker/*`) the same way.

**Look up every SHA. Never write one from memory.** A SHA recalled from training data or guessed
looks valid and is wrong, and the workflow then fails or runs code nobody reviewed. The SHAs in
[references/actions.md](references/actions.md) and [references/workflows.md](references/workflows.md)
(Quant actions, `actions/checkout`, `docker/*`) were looked up for this skill in 2026-10; for any
other action, or to move to a newer release, run the lookup. If you cannot run commands, write a placeholder such as
`actions/checkout@<SHA of the latest release> # vX.Y.Z` and give the user the commands below.

```bash
gh api repos/<owner>/<action>/releases/latest --jq .tag_name       # newest release tag
gh api repos/<owner>/<action>/commits/<tag> --jq .sha              # its commit, also for annotated tags
git ls-remote --tags --sort=-v:refname https://github.com/<owner>/<action> 'v*.*.*' | head -2  # without gh
```

## Static site workflow

Full pinned workflow: [references/workflows.md](references/workflows.md#static-site). Secret
`QUANT_TOKEN`; variables `QUANT_CUSTOMER`, `QUANT_PROJECT`; on gov also `QUANT_ENDPOINT`
(`https://api.quantgov.cloud/v1`, passed as `endpoint` to deploy and purge). Steps: checkout, build,
check the output, restore the revision log, `deploy-action` (`dir` relative, `skip-purge: true`),
`purge-action` (`url_pattern: "/*"`).

- The deploy **unpublishes every project path that is not in `dir`**. A failed or partial build
  must stop the job before the deploy: keep the build in its own step and check the output
  (`test -s dist/index.html`).
- Upload failures only warn (`Failed to deploy <file>`); the step stays green. Read the log.
- Edge functions and rules, search records: [references/workflows.md](references/workflows.md).

## Container app workflow

Secrets `QUANT_API_KEY`, `QUANT_ORGANIZATION`; variables `QUANT_APPLICATION`, on gov
`QUANT_BASE_URL`, and optionally `QUANT_MIN_CAPACITY`, `QUANT_MAX_CAPACITY`, `BUILD_PLATFORM`,
`RUNNER_TYPE`. Create the application first (dashboard or API); the actions create environments,
not applications. The compose service here is `app`.

```yaml
name: Build and deploy to Quant Cloud

on:
  push:
    branches: [main, develop]

permissions:
  contents: read

concurrency:
  group: quant-cloud-${{ github.ref }}
  cancel-in-progress: false

env:
  QUANT_BASE_URL: ${{ vars.QUANT_BASE_URL || 'https://dashboard.quantcdn.io' }}

jobs:
  deploy:
    runs-on: ${{ vars.RUNNER_TYPE || 'ubuntu-latest' }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: docker/setup-qemu-action@99012661954931238ded8c8b007157a8430204e1 # v4.4.0
      - uses: docker/setup-buildx-action@f87e5991a6d7451dcb8d9637bfbc97413f497069 # v4.4.1

      - name: Initialize Quant Cloud      # validates access and logs Docker in to the registry
        id: init
        uses: quantcdn/quant-cloud-init-action@1bc52dca113ea1cb2f3d7dcb0edbc7859d76afaf # v4.0.1
        with:
          quant_organization: ${{ secrets.QUANT_ORGANIZATION }}
          quant_api_key: ${{ secrets.QUANT_API_KEY }}
          quant_application: ${{ vars.QUANT_APPLICATION || github.event.repository.name }}
          base_url: ${{ env.QUANT_BASE_URL }}

      - name: Build and push
        uses: docker/build-push-action@c3c9e263c25d99ce0380d002d59b67737d91b0dc # v7.4.0
        with:
          context: .
          platforms: ${{ vars.BUILD_PLATFORM || 'linux/arm64' }}   # must match quant.architecture
          push: true
          # Tag prefix = compose service name ("app"); main -> app-latest, develop -> app-develop
          tags: ${{ steps.init.outputs.stripped_endpoint }}/${{ secrets.QUANT_ORGANIZATION }}/${{ steps.init.outputs.quant_application }}:app-${{ steps.init.outputs.image_suffix_clean }}
          cache-from: type=gha,scope=app
          cache-to: type=gha,mode=max,scope=app

      - name: Translate docker-compose.yml
        id: compose
        uses: quantcdn/quant-cloud-compose-action@3a06db471e3364db3e4691fd522b9c37346d0a19 # v4.0.0
        with:
          api_key: ${{ secrets.QUANT_API_KEY }}
          organization: ${{ secrets.QUANT_ORGANIZATION }}
          compose_file: docker-compose.yml
          image_suffix: ${{ steps.init.outputs.image_suffix_clean }}
          base_url: ${{ env.QUANT_BASE_URL }}

      - name: Create or update the environment
        uses: quantcdn/quant-cloud-environment-action@936fe16373f3169fa15b61a9117ffa87b3996855 # v4.0.0
        with:
          api_key: ${{ secrets.QUANT_API_KEY }}
          organization: ${{ secrets.QUANT_ORGANIZATION }}
          app_name: ${{ steps.init.outputs.quant_application }}
          environment_name: ${{ steps.init.outputs.environment_name }}
          operation: ${{ steps.init.outputs.environment_exists == 'true' && 'update' || 'create' }}
          compose_spec: ${{ steps.compose.outputs.translated_compose }}
          base_url: ${{ env.QUANT_BASE_URL }}
          # The action sends min and max tasks on every run (default 1). Set them to
          # your environment's scaling. Not in action.yml: GitHub warns "Unexpected input".
          min_capacity: ${{ vars.QUANT_MIN_CAPACITY || '1' }}
          max_capacity: ${{ vars.QUANT_MAX_CAPACITY || '1' }}

      - name: Redeploy
        if: steps.init.outputs.environment_exists == 'true'
        uses: quantcdn/quant-cloud-environment-state-action@b1b75af5d772bb295bc067f225a7bb3a952bd7a1 # v4.0.1
        with:
          api_key: ${{ secrets.QUANT_API_KEY }}
          organization: ${{ secrets.QUANT_ORGANIZATION }}
          application: ${{ steps.init.outputs.quant_application }}
          environment: ${{ steps.init.outputs.environment_name }}
          action: redeploy
          base_url: ${{ env.QUANT_BASE_URL }}
```

How the init action maps the Git ref (the image tag is `<service>-<image_suffix_clean>`):

| Ref | Environment | Image tag for service `app` |
|---|---|---|
| `main` or `master` | `production` | `app-latest` |
| `develop` | `develop` | `app-develop` |
| `feature/login` | `feature-login` | `app-feature-login` |
| Pull request 42 | `pr-42` | `app-pr-42` |
| Tag `v1.2.0` | `production` | `app-v1.2.0` |

- **The image tag starts with the compose service name**, and `platforms` matches
  `quant.architecture` (`ARM64` = `linux/arm64`). Details: `quant-cloud-apps`, `quant-templates`.
- **Scaling:** the environment action sends a minimum and maximum task count on every create and
  update, default 1, which replaces the scaling set in the dashboard. Pass `min_capacity` and
  `max_capacity` as above (GitHub warns "Unexpected input" because `action.yml` does not declare
  them; the action reads them). Or skip the environment step for an existing environment whose
  compose file did not change, and run only the state action.
- `operation: create` also updates an environment that exists; `update` fails if it does not.

## Pull request environments

Full workflow: [references/workflows.md](references/workflows.md#pull-request-environments).

1. Trigger on `pull_request` with `types: [opened, synchronize, reopened, closed]`. The init action
   names the environment `pr-<number>` and the image suffix `pr-<number>`.
2. Skip pull requests from forks (`github.event.pull_request.head.repo.full_name ==
   github.repository`): they get no secrets.
3. Create with the environment action and `from_environment: production` (used only on create).
   The new environment has production's configuration and variables, an empty database, and no
   secrets.
4. Wait until the environment's `creationStatus` is `completed` (platform API), then run the sync
   action with `source: production`, `type: database`, `wait: true`. Fail the job if its `skipped`
   output is `true`.
5. On `closed` (merged or not), run the environment action with `operation: delete` for
   `pr-${{ github.event.pull_request.number }}`. It passes if the environment is already gone.

## Variables, backups and syncs

Workflows: [references/workflows.md](references/workflows.md#variables-backups-and-a-staging-refresh).

- The environment variable action sets **plain variables, not secrets**: anyone with access to the
  environment can read them. Set secrets in the dashboard (**Environment & Secrets**). The
  `variables` input splits on newlines and commas; use `json_vars` for values with commas.
  `replace: true` and `operation: clear` remove variables you did not list.
- Containers read variables and secrets at start: redeploy (state action) after a change.
- Backups: `create` with `wait: true`, per `type` (`database`, `filesystem`). `delete` with
  `older_than_days` removes every backup of that type older than the cut-off, including manual ones.
  `download` prints a usable download URL in the job log; avoid it in public repositories.
- Sync copies `source` into `environment_name` (the target, overwritten). Back up the target first.
  It cannot target `production`. A refused sync passes with `skipped: true`; check it.

## A green run is not a live deploy

The Quant Cloud actions ask the platform to deploy and return. They do not wait for the new
containers to start or pass health checks, so a release that crash-loops still gives a green run.
After each deploy, confirm it with `qc env list` (running vs desired), `qc env logs`, and the
dashboard **Deployments** tab: see "Deploy and verify" in `quant-cloud-apps`. To make CI wait,
poll the environment's `deploymentStatus` (step in
[references/workflows.md](references/workflows.md#optional-wait-for-the-deployment-in-ci)).

Static deploys have the same gap in a different form: missing uploads only warn.

## Other CI systems

- **Static sites:** run `quant` (`npm install -g @quantcdn/quant-cli`, or the `quantcdn/cli:7.0.1`
  image with its entrypoint cleared) with `QUANT_CLIENT_ID` (not `QUANT_CUSTOMER`), `QUANT_PROJECT`,
  `QUANT_TOKEN` and, on gov, `QUANT_ENDPOINT=https://api.quantgov.cloud/v1`. Then
  `quant deploy dist` and `quant purge "/*"`. Details: `quant-cli`.
- **Quant Cloud:** `qc login` needs a browser (OAuth) and has no token option, so do not use `qc`
  in unattended jobs. Call the platform API with `curl` and `Authorization: Bearer $QUANT_API_KEY`:
  `PUT {dashboard}/api/v3/organizations/{org}/applications/{app}/environments/{env}/state` with
  `{"action": "redeploy"}`. Registry login and image push:
  [references/workflows.md](references/workflows.md#any-ci-build-push-and-redeploy-an-app-with-curl).
- Store tokens in the CI system's masked secret store, never in the repository.
- GitLab CI example: [references/workflows.md](references/workflows.md#gitlab-ci).

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| Green run, site still serves the old release | The actions do not wait for healthy containers | `qc env list`, `qc env logs`, Deployments tab; optional `deploymentStatus` poll |
| Scaling back to 1 task after every deploy | Environment action sends min/max 1 on each update | Pass `min_capacity`/`max_capacity`, or redeploy only |
| `route api/v3/api/v3/... could not be found` (environment-var action) | `base_url` ends in `/api/v3`; v1.0.2 does not strip it, unlike the v4 actions | `base_url: https://dashboard.quantcdn.io` (gov `https://dash.quantgov.cloud`) |
| Init fails: organisation not found or no registry credentials, on gov | No `base_url`, so it called the public dashboard | Set `base_url` on every Quant Cloud action |
| Static deploy 401/403 on gov | `endpoint` missing (defaults to public) | `endpoint: https://api.quantgov.cloud/v1` on deploy and purge |
| search-action records fail on gov | `endpoint` ends in `/v1`; v2.0.0's CLI adds another `/v1` | `endpoint: https://api.quantgov.cloud` |
| Pages vanish after a deploy | Build produced a partial `dir`, or content made outside the build | Fail the job on a bad build; `skip-unpublish-regex`; `quant-static-sites` |
| Environment step: application not found | The application does not exist; actions create only environments | Create the application first; check `QUANT_APPLICATION` |
| Sync step green but nothing copied | Platform refused it (for example no database); step sets `skipped` | Check `skipped`; give the app a database |
| PR environment has an empty database | Sync not run, or run before creation completed | Wait for `creationStatus: completed`, then sync with `wait: true` |
| PR environments pile up | Cleanup job missing or failed | `operation: delete` on `closed`; delete leftovers in the dashboard |
| Secret value readable in the dashboard | Set with the environment variable action | Set it as a secret in the dashboard; delete the variable |
| `qc` hangs or asks for a browser in CI | `qc login` is interactive | Use the platform API with `curl` |
| `Missing: clientid` from `quant` in CI | `QUANT_CUSTOMER` set instead of `QUANT_CLIENT_ID` | Set `QUANT_CLIENT_ID` |

## Further reading

- GitHub actions overview: https://docs.quantcdn.io/cloud/12-github-actions/01-overview/
- Deploy via CI/CD (static): https://docs.quantcdn.io/guides/continuous-integration/
- `quant` in CI/CD: https://docs.quantcdn.io/content-cli/guides/continuous-integration/
- Action repositories: https://github.com/quantcdn (`deploy-action`, `purge-action`, `search-action`,
  `quant-cloud-*-action`)
- Related skills: `quant-platform`, `quant-static-sites` (deploy behaviour), `quant-cloud-apps`
  (compose contract, verify a deploy), `quant-templates` (template workflows), `quant-cli`, `qc-cli`,
  `quant-edge-functions-and-kv` (manifests), `quant-domains-cache-purge`

<!-- checked against gh:quantcdn/deploy-action 7.0.1 -->
<!-- checked against gh:quantcdn/search-action 2.0.0 -->
<!-- checked against gh:quantcdn/quant-cloud-init-action 4.0.1 -->
<!-- checked against gh:quantcdn/quant-cloud-compose-action 4.0.0 -->
<!-- checked against gh:quantcdn/quant-cloud-environment-action 4.0.0 -->
<!-- checked against gh:quantcdn/quant-cloud-environment-state-action 4.0.1 -->
<!-- checked against gh:quantcdn/quant-cloud-environment-var-action 1.0.2 -->
