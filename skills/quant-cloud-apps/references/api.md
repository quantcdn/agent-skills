# Quant Cloud API reference for apps

The platform API for Quant Cloud is `{dashboard}/api/v3`. Checked 2026-10 against the public
OpenAPI spec (API 4.25.0).

| Platform | Base URL |
|---|---|
| Public | `https://dashboard.quantcdn.io/api/v3` |
| Gov | `https://dash.quantgov.cloud/api/v3` |

Authenticate with `Authorization: Bearer <token>`, using an API token from the dashboard profile
(Profile, API Tokens). The token belongs to one platform. The examples set:

```bash
BASE=https://dashboard.quantcdn.io/api/v3     # gov: https://dash.quantgov.cloud/api/v3
AUTH="Authorization: Bearer $QUANT_API_KEY"
ORG=example-org APP=example-app ENV=production
E="$BASE/organizations/$ORG/applications/$APP/environments/$ENV"
```

## Validate a compose file (no deploy)

```bash
jq -Rs '{compose: .}' docker-compose.yml |
  curl -sS -X POST -H "$AUTH" -H 'Content-Type: application/json' --data @- \
    "$BASE/organizations/$ORG/compose/validate" |
  jq '{warnings: .translationWarnings, cpu: .translatedComposeDefinition.taskCpu,
       memory: .translatedComposeDefinition.taskMemory,
       images: [.translatedComposeDefinition.containers[] | {name, imageReference}]}'
```

- Add `"imageSuffix": "latest"` to the JSON (or `?imageSuffix=latest`) to see the internal tags
  the platform will pull.
- A 422 response means the YAML is invalid. `translationWarnings` lists skipped services, adjusted
  sizes and how volumes were read.
- `translatedComposeDefinition` is the JSON you send as `composeDefinition` below. The compose
  action's `translated_compose` output is the same thing.

## Create an application

`POST $BASE/organizations/$ORG/applications`

```json
{
  "appName": "records-api",
  "composeDefinition": {
    "taskCpu": 512,
    "taskMemory": 1024,
    "architecture": "ARM64",
    "containers": [
      {
        "name": "app",
        "imageReference": { "type": "internal", "identifier": "app-latest" },
        "exposedPorts": [3000],
        "essential": true
      }
    ]
  },
  "database": { "engine": "mysql" },
  "minCapacity": 1,
  "maxCapacity": 1
}
```

| Field | Notes |
|---|---|
| `appName`, `composeDefinition` | Required |
| `database` | An **object**. `engine`: `mysql` (default) or `postgres`. Optional `storageGb` (default 20) and `multiAz` (default false). Omit the field for no database |
| `filesystem` | Optional shared filesystem: `{"required": true, "mountPath": "/mnt/data"}` |
| `environment` | Optional initial variables for `production`: `[{"name": "...", "value": "..."}]` |
| `minCapacity`, `maxCapacity` | Default 1 and 1 |

Send `database` exactly in this shape. A field with another name (`db`, `mysql`) or a non-object
value does not create a database. The create call is asynchronous: confirm afterwards that the
app has a database (dashboard: environment details shows the database; the Backups tab has
**Database Backups**) and that the environment has the `DB_*` secrets.

`composeDefinition` fields used most:

| Field | Notes |
|---|---|
| `taskCpu`, `taskMemory` | Same values as `quant.task.cpu` / `quant.task.memory` |
| `architecture` | `ARM64` or `X86_64` |
| `containers[]` | `name`, `imageReference` (`internal` = tag only, `external` = full image), `exposedPorts`, `environment`, `secrets`, `mountPoints`, `healthCheck`, `dependsOn`, `command`, `entryPoint`, `user`, `workingDirectory`, `cpu`, `memory`, `memoryReservation`, `essential` |
| `minCapacity`, `maxCapacity` | Task count range |
| `singleTaskOnly` | `true`: at most one running task. `false`: scaling allowed. Omitted: the platform turns it on when it detects stateful containers |
| `startupGracePeriodSeconds` | Default 120, 0 to 3600 |

## Environments

| Job | Call |
|---|---|
| List (with running and desired counts) | `GET $BASE/organizations/$ORG/applications/$APP/environments` |
| Get one, with runtime details | `GET $E` |
| Create (clone config) | `POST .../environments` with `envName`, `cloneConfigurationFrom`, optional `minCapacity`, `maxCapacity`, `singleTaskOnly`, `startupGracePeriodSeconds`, `composeDefinition`, `imageSuffix` |
| Replace the compose definition (redeploys) | `PUT $E` |
| Change top-level fields only (CPU, memory, capacity) | `PATCH $E/compose` |
| Read the compose definition | `GET $E/compose` |
| Redeploy, stop, start | `PUT $E/state` with `{"action": "redeploy"}` (optional `imageTag`) |
| Logs | `GET $E/logs` |
| Metrics | `GET $E/metrics` |

`PATCH $E/compose` replaces the whole `containers` array if you send it. Leave it out to change
only the top-level fields.

## Environment variables

`GET` or `PUT` (replace the list) on `$E/variables`; `PUT` or `DELETE` on `$E/variables/{name}`
for one variable. A change reaches the containers only after a
redeploy.

## Cron jobs

`POST $E/cron`

```json
{
  "name": "nightly-cleanup",
  "scheduleExpression": "cron(0 2 * * ? *)",
  "command": ["php", "artisan", "schedule:run"],
  "targetContainerName": "app",
  "isEnabled": true
}
```

The expression has six fields (minutes, hours, day of month, month, day of week, year), in UTC. Use
`?` in one of the two day fields. `GET $E/cron/{name}/runs` lists runs.

## Ad-hoc commands

`POST $E/commands` starts a run in a temporary container; `GET $E/commands/{id}` returns status
and output. `qc exec run` wraps this (skill `qc-cli`).

## Backups, restore and sync

| Job | Call |
|---|---|
| List or create backups | `GET|POST $E/backups/{type}`, `type` = `database` or `filesystem` |
| Download | `GET $E/backups/{type}/{backupId}/download` |
| Restore a database backup into this environment | `POST $E/backups/{backupId}/restore-database` (the backup can come from another environment of the same app); poll `GET $E/restores/{restoreId}` |
| Sync into this environment from another | `POST $E/sync/{type}` with `{"sourceEnvironment": "production"}`; `$E` is the **target** |
| Sync history | `GET $E/sync/{type}` |

## Idle sleep

`PUT $E/idle-sleep` with `{"enabled": true, "idleMinutes": 30}` (10 to 1440). `GET` returns the
setting and the state (`awake`, `sleeping`, `waking`).

## Scaling policies

`GET|PUT|DELETE $E/scaling-policies`: `metric` = `CPUUtilization`, `MemoryUtilization` or `RPS`, with a
`targetValue` (percent, or requests per second per task).
