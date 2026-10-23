# Quant GitHub actions: versions, inputs and outputs

Read from each action's `action.yml` and source at its latest release tag, 2026-10. "Default" is
the value the action uses when you leave the input out. Pin with the full SHA and keep the version
in a comment: `uses: quantcdn/deploy-action@9bf8cae8497ab6628d4b248db9eb11464f37e1e5 # v7.0.1`.

| Action | Latest | Commit SHA | Major tag |
|---|---|---|---|
| `quantcdn/deploy-action` | v7.0.1 | `9bf8cae8497ab6628d4b248db9eb11464f37e1e5` | `v7` |
| `quantcdn/purge-action` | v7.0.0 | `6010adb4bef33827d7f7d1be8b1d955f693568e4` | `v7` |
| `quantcdn/search-action` | v2.0.0 | `f84efa8ea7a42ef305751608d6b7dea27d175a7f` | none (use the SHA or `v2.0.0`) |
| `quantcdn/quant-cloud-init-action` | v4.0.1 | `1bc52dca113ea1cb2f3d7dcb0edbc7859d76afaf` | `v4` |
| `quantcdn/quant-cloud-compose-action` | v4.0.0 | `3a06db471e3364db3e4691fd522b9c37346d0a19` | `v4` |
| `quantcdn/quant-cloud-environment-action` | v4.0.0 | `936fe16373f3169fa15b61a9117ffa87b3996855` | `v4` |
| `quantcdn/quant-cloud-environment-state-action` | v4.0.1 | `b1b75af5d772bb295bc067f225a7bb3a952bd7a1` | `v4` |
| `quantcdn/quant-cloud-environment-sync-action` | v4.0.0 | `aeb054d52e2067ac7eb6694c07df2c4cde262c5f` | `v4` |
| `quantcdn/quant-cloud-environment-var-action` | v1.0.2 | `ce1ea37c9f7e9169c1c70df35ae3fe6f1111e2c9` | `v1` |
| `quantcdn/quant-cloud-environment-backup-action` | v4.4.2 | `9c46be7346ab2ec78f7dd5e0b0795ce2eff3eca2` | `v4` |

`quantcdn/quant-cloud-ecr-action` is superseded: the init action logs Docker in to the registry.

Check for a newer release before you pin. Release pages can lag the tags, so read the tags:
`git ls-remote --tags --sort=-v:refname https://github.com/quantcdn/<action> 'v*.*.*' | head -2`,
then `gh api repos/quantcdn/<action>/commits/<tag> --jq .sha` for the commit SHA.

## Content actions (static sites)

These call the content API with the **project token** (`QUANT_TOKEN`, from the project's
Integrations page). On gov set `endpoint` on every step.

### `quantcdn/deploy-action` v7.0.1

Runs `quant` 7.0.1 (`quantcdn/cli:7.0.1`, pinned by digest).

| Input | Required | Default | Notes |
|---|---|---|---|
| `customer` | yes | | Organisation name |
| `project` | yes | | Project name |
| `token` | yes | | Project token. Uploads files and functions; never used for rules |
| `dir` | no | none | Build directory, **relative to the workspace**. Empty: no files are deployed |
| `skip-unpublish` | no | `false` | `true`: do not unpublish paths missing from `dir` |
| `skip-unpublish-regex` | no | `""` | Keep paths that match the regex |
| `skip-purge` | no | `false` | Skip the purge of changed paths |
| `force` | no | `false` | Re-send every file (ignore the revision log) |
| `chunk-size` | no | `10` | Upload concurrency |
| `endpoint` | no | `https://api.quantcdn.io/v1` | Gov: `https://api.quantgov.cloud/v1` |
| `revision-log` | no | `false` (no log) | Path of the local revision log, for example `.quant-revision` |
| `enable-index-html` | no | `false` | Keep `index.html` in URLs. Keep the same value in every run |
| `functions` | no | none | Path to `quant/edge-functions.json` (every entry needs a `uuid`) |
| `rules` | no | none | Path to `quant/edge-rules.json`. Needs `api-token` and `api-base-url` |
| `api-token` | no | none | Project-scoped platform token for rules (`projects:read`, `rules:read`, `rules:write`) |
| `api-base-url` | no | none | `{dashboard}/api/v2`: `https://dashboard.quantcdn.io/api/v2` or `https://dash.quantgov.cloud/api/v2` |
| `rules-force` | no | `false` | Overwrite managed rules that someone changed in the dashboard |

Outputs: none. Order of work: rules dry run (when `rules` is set), functions, `dir`, rules.
Upload failures print `Failed to deploy <file>` and the step still passes. Manifest formats:
`quant-edge-functions-and-kv`. Unpublish and revision-log behaviour: `quant-static-sites`.

### `quantcdn/purge-action` v7.0.0

Runs `quant` 6.2.0 (`quantcdn/cli:6.2.0`).

| Input | Required | Default | Notes |
|---|---|---|---|
| `customer` | yes | | |
| `project` | yes | | |
| `token` | yes | | Project token |
| `url_pattern` | no | `""` | Path or pattern, for example `"/*"` or `/blog/*` (quote `"/*"`) |
| `cache_keys` | no | `""` | Space-separated cache keys |
| `soft_purge` | no | `false` | Mark content stale instead of removing it |
| `endpoint` | no | `https://api.quantcdn.io/v1` | Gov: `https://api.quantgov.cloud/v1` |

Set exactly one of `url_pattern` and `cache_keys`; the step fails with both or neither. Outputs: none.

### `quantcdn/search-action` v2.0.0

Runs `quant` **2.0.0** (`quantcdn/cli:2.0.0`). That CLI adds `/v1` to the endpoint itself.

| Input | Required | Default | Notes |
|---|---|---|---|
| `customer` | yes | | |
| `project` | yes | | |
| `token` | yes | | Project token |
| `endpoint` | no | `https://api.quantcdn.io` | **No `/v1`.** Gov: `https://api.quantgov.cloud` |
| `operation` | yes | | `index`, `unindex`, `status` or `clear` |
| `path` | no | | `index`: a directory of `*.json` record files, or one file. `unindex`: the URL path to remove |

Outputs: none. A record file that fails to upload prints an `Error:` line, and the step can still
pass. Read the log.

## Quant Cloud actions (container apps)

These call the platform API with a **dashboard API token** (`QUANT_API_KEY`, from your profile,
API Tokens). The token belongs to one platform. `base_url` selects the platform.

| Action | `base_url` default | Accepts the bare host | Accepts `{dashboard}/api/v3` |
|---|---|---|---|
| init, compose, environment, state, sync | `https://dashboard.quantcdn.io` | yes | yes (removed before use) |
| backup v4.4.2 | `https://dashboard.quantcdn.io/api/v3` | yes | yes (removed before use) |
| environment-var v1.0.2 | `https://dashboard.quantcdn.io` | **yes, and only this** | **no**: v1.0.2 does not strip it, so the path doubles (`/api/v3/api/v3/...`, "route could not be found"). On gov set `https://dash.quantgov.cloud` |

The bare dashboard host (`https://dashboard.quantcdn.io` or `https://dash.quantgov.cloud`) works
for every Quant Cloud action.

### `quantcdn/quant-cloud-init-action` v4.0.1

Checks the organisation and token, logs Docker in to the Quant Cloud image registry, and works
out the application, environment and image suffix from the Git ref. Run it first.

| Input | Required | Default | Notes |
|---|---|---|---|
| `quant_organization` | yes | | Organisation machine name |
| `quant_api_key` | yes | | Dashboard API token |
| `quant_application` | no | repository name | Application name |
| `master_branch_override` | no | `main` and `master` | The one branch that maps to `production` |
| `environment_name_override` | no | from the ref | A fixed environment name. Then the image suffix is that name, and only tags count as production |
| `base_url` | no | `https://dashboard.quantcdn.io` | Gov: `https://dash.quantgov.cloud` (v4 also accepts `/api/v3`) |

| Output | Example |
|---|---|
| `project_exists` | `true` if the application exists |
| `environment_exists` | `true` if the environment exists |
| `quant_application` | `example-app` |
| `environment_name` | `production` |
| `is_production` | `true` |
| `stripped_endpoint` | Registry host without `https://`, for image tags |
| `image_suffix` | `-latest` |
| `image_suffix_clean` | `latest` |

| Git ref | `environment_name` | `image_suffix_clean` |
|---|---|---|
| Branch `main` or `master` | `production` | `latest` |
| Branch `develop` | `develop` | `develop` |
| Branch `feature/new-thing` | `feature-new-thing` | `feature-new-thing` |
| Pull request 123 (`pull_request` events) | `pr-123` | `pr-123` |
| Tag `v1.2.0` | `production` | `v1.2.0` |

Environment names keep only letters and digits (everything else becomes `-`) and are lowercased.
Image suffixes also keep dots. The application is not created by any action: create it first.

### `quantcdn/quant-cloud-compose-action` v4.0.0

Validates `docker-compose.yml` with the platform and returns the translated definition. Same commit
as v1.2.0.

| Input | Required | Default | Notes |
|---|---|---|---|
| `api_key` | yes | | |
| `organization` | yes | | |
| `compose_file` | yes | | Path to the compose file |
| `base_url` | no | `https://dashboard.quantcdn.io` | |
| `image_suffix` | no | | Internal image tags become `<service>-<suffix>` |
| `image_tag_updates` | no | | JSON map of container name to tag, for example `{"app": "v2"}` |

Output: `translated_compose` (JSON for the environment action). Translation warnings appear as
workflow warnings; an invalid file fails the step.

### `quantcdn/quant-cloud-environment-action` v4.0.0

Creates, updates or deletes an environment. Same commit as v1.5.0.

| Input | Required | Default | Notes |
|---|---|---|---|
| `api_key` | yes | | |
| `organization` | yes | | |
| `app_name` | yes | | The application must exist |
| `environment_name` | yes | | |
| `base_url` | no | `https://dashboard.quantcdn.io` | |
| `from_environment` | no | | Clone this environment's configuration. Used only when the environment is created |
| `compose_spec` | no | | `translated_compose`. Required for update; create needs it or `from_environment` |
| `image_suffix` | no | | Image tag suffix applied by the platform |
| `operation` | no | `create` | `create` (updates the environment if it exists), `update` (fails if it does not exist), `delete` (passes if it does not exist) |

Output: `environment_name`.

**Scaling:** every create and update also sends `minCapacity` and `maxCapacity`, default `1`.
This replaces the minimum and maximum tasks set in the dashboard. To keep your values, pass
`min_capacity` and `max_capacity` (the action reads them, but `action.yml` does not declare them,
so GitHub prints an "Unexpected input" warning). Or, for an environment that exists and whose
compose file did not change, skip this step and run only the state action.

### `quantcdn/quant-cloud-environment-state-action` v4.0.1

| Input | Required | Default | Notes |
|---|---|---|---|
| `api_key` | yes | | |
| `organization` | yes | | |
| `application` | yes | | Note: not `app_name` |
| `environment` | yes | | Note: not `environment_name` |
| `base_url` | no | `https://dashboard.quantcdn.io` | |
| `action` | no | `redeploy` | `redeploy`, `stop` or `start` |

Outputs: none. Retries the request up to five times. It returns when the platform accepts the
request; it does not wait for the new containers.

### `quantcdn/quant-cloud-environment-sync-action` v4.0.0

Copies the database or the files of `source` into `environment_name` (the **target**).

| Input | Required | Default | Notes |
|---|---|---|---|
| `api_key` | yes | | |
| `organization` | yes | | |
| `app_name` | yes | | |
| `environment_name` | yes | | Target; it is overwritten |
| `source` | yes | | Source environment |
| `type` | no | `database` | `database` or `filesystem` |
| `wait` | no | `false` | `true`: poll until the sync completes or fails |
| `wait_interval` | no | `10` | Seconds between polls |
| `max_retries` | no | `30` | Polls before the step fails (30 x 10 s = 5 minutes) |
| `base_url` | no | `https://dashboard.quantcdn.io` | |

Outputs: `sync_id`, `success`, `skipped`. If the platform answers 400 (for example, the
application has no database), the step prints a warning, sets `skipped` to `true` and **passes**.
Check `skipped`. The action cannot sync into `production`. Syncs that read from production need
the `trigger_prod_sync` permission.

### `quantcdn/quant-cloud-environment-var-action` v1.0.2

Manages **environment variables**. It does not create secrets: values it sets are plain variables
that anyone with access to the environment can read. Keep secrets in the dashboard
(**Environment & Secrets**).

| Input | Required | Default | Notes |
|---|---|---|---|
| `api_key` | yes | | |
| `organization` | yes | | |
| `app_name` | yes | | |
| `environment_name` | yes | | |
| `base_url` | no | `https://dashboard.quantcdn.io` | Bare host only (gov `https://dash.quantgov.cloud`); a value ending `/api/v3` fails |
| `operation` | no | `list` | `list`, `set`, `clear` (delete every variable), `delete` |
| `replace` | no | `false` | `set` only: replace the whole list, removing variables not in the input |
| `env_file` | no | | `set`: path to a `.env` file |
| `json_vars` | no | | `set`: JSON object of variables |
| `variables` | no | | `set`: `KEY=VALUE` pairs, split on newlines **and commas** (a value with a comma breaks; use `json_vars`) |
| `keys` | no | | `delete`: keys to delete, newline or comma separated |

Sources merge in order `env_file`, `json_vars`, `variables` (later wins). Outputs: `variables`
(JSON with values, from `list`), `count`, `updated_count`, `deleted_count`, `failed_count`. A `set`
with any failed key fails the step. Changes reach the containers only after a redeploy.

### `quantcdn/quant-cloud-environment-backup-action` v4.4.2

| Input | Required | Default | Notes |
|---|---|---|---|
| `api_key` | yes | | |
| `organization` | yes | | |
| `app_name` | yes | | |
| `environment_name` | yes | | |
| `base_url` | no | `https://dashboard.quantcdn.io/api/v3` | Bare host also works |
| `operation` | no | `create` | `create`, `list`, `download`, `delete` |
| `backup_name` | no | `backup-<env>-<time>` | `create`: stored as the backup description |
| `backup_id` | no | | `download`: an ID or `latest`. `delete`: one ID |
| `older_than_days` | no | | `delete`: delete every backup of `type` older than this |
| `sort_order` | no | `desc` | `list` |
| `filter_status` | no | | `list`: `completed`, `failed` or `running` |
| `wait` | no | `false` | `create`: wait until the backup completes |
| `wait_interval` | no | `10` | Seconds |
| `max_retries` | no | `30` | Polls before the step fails |
| `type` | no | `database` | `database` or `filesystem` |

Outputs: `backup_id`, `backup_list`, `download_url`, `resolved_backup_id`, `resolved_backup_name`,
`resolved_backup_created_at`, `deleted_count`, `deleted_backups`, `success`.

- `older_than_days` deletes **every** backup of that type older than the cut-off, including backups
  made in the dashboard. Run it once per `type`.
- `download` prints the download URL in the job log. Anyone who can read the log can use the URL
  until it expires; in a public repository that is everyone.
