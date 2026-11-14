# Quant AI API reference

Base: `{dashboard}/api/v3/organizations/{org}/ai` (`organisations` also accepted).
`{dashboard}` is `https://dashboard.quantcdn.io` or `https://dash.quantgov.cloud`.
Auth: `Authorization: Bearer <dashboard API token>`. Source: the public API specification and
https://docs.quantcdn.io/ai/api-reference/.

## Endpoints

| Area | Method and path | Notes |
|---|---|---|
| Models | `GET /models?feature=chat\|embeddings\|vision\|streaming\|all`, `GET /models/{modelId}` | Use IDs from this list only |
| Chat | `POST /chat` | Buffered JSON; `async: true` returns 202 |
| | `POST /chat/stream` | Server-Sent Events; `async: true` returns 202 |
| | `GET /chat/executions/{requestId}` | Poll async runs |
| | `POST /chat/callback` | Client tool results for `waiting_callback` |
| Embeddings | `POST /embeddings` | `input` string or up to 100 strings, `modelId`, `dimensions`, `normalize` |
| Sessions | `GET`/`POST /sessions`, `GET`/`PUT`/`DELETE /sessions/{id}`, `PUT /sessions/{id}/extend` | |
| Built-in tools | `GET /tools`, `GET /tools/names`, `GET /tools/executions`, `GET /tools/executions/{id}` | |
| Custom tools | `GET`/`POST /custom-tools`, `GET`/`DELETE /custom-tools/{toolName}` | POST with an existing name updates |
| Agents | `GET`/`POST /agents`, `GET`/`PUT`/`DELETE /agents/{id}`, `POST /agents/{id}/chat` | |
| Agent overlays | `GET`/`PUT`/`DELETE /agents/{id}/overlay` | Platform agents only; PUT replaces the whole overlay, so send every field; `version` for compare-and-swap (409 on conflict) |
| Skills | `GET`/`POST /skills`, `GET`/`PUT`/`DELETE /skills/{id}`, `POST /skills/import`, `POST /skills/{id}/sync` | |
| Skill collections | `GET /skills/collections`, `POST /skills/import-collection`, `POST /skills/collections/{ns}/sync`, `DELETE /skills/collections/{ns}` | Delete removes all skills in the namespace |
| Vector DB | `GET`/`POST /vector-db/collections`, `GET`/`DELETE /vector-db/collections/{id}` | 409 if the name exists |
| | `GET`/`POST`/`DELETE /vector-db/collections/{id}/documents`, `POST .../query` | |
| Files | `GET`/`POST /files`, `GET`/`DELETE /files/{id}` | |
| Governance | `GET`/`PUT /governance`, `GET /governance/spend` | AI governance permission |
| Auto mode | `GET`/`PUT`/`DELETE /auto-mode` | GET: scope `ai:use`; PUT, DELETE: scope `ai:manage` and the AI governance permission. See [Auto mode](#auto-mode) |
| Filter policies | `GET`/`POST /filter-policies`, `GET`/`PUT`/`DELETE /filter-policies/{id}`, `PUT .../enable`, `PUT .../disable` | |
| Usage | `GET /usage` (subscription permission), `GET /usage/me` (own usage) | |
| Other | `/tasks`, `/orchestrations` (start, pause, resume, cancel, batches), `/slack-bots`, `GET /mcp-servers` | See the docs pages |

There are no workflow endpoints. Workflows are built in the dashboard and started by their
triggers.

## Chat request (`/chat`, `/chat/stream`)

| Field | Notes |
|---|---|
| `modelId` | Required. From `GET /models` |
| `messages` | Required. `role` (`user`, `assistant`, `system`) and `content` (a string, or blocks: `text`, `image`, `video`, `document` with base64 `source.bytes`) |
| `systemPrompt` | Optional system prompt |
| `maxTokens` | Default 4096, 1 to 65536 (model limits apply) |
| `temperature` | Default 0.7, 0 to 2 |
| `topP`, `stopSequences` | `stopSequences` max 4 |
| `responseFormat` | `{"type": "json", "jsonSchema": {...}}` for structured output on models that support it |
| `toolConfig` | `tools[].toolSpec` (`name`, `description`, `inputSchema.json`), `autoExecute`, `allowedTools` |
| `allowedTools` | Top-level alias of `toolConfig.allowedTools` |
| `sessionId` | Continue a session; omit for stateless calls |
| `async` | `true` returns 202 with `requestId`, `pollUrl` |
| `longContext` | Large-context routing for very large payloads |
| `guardrails` | Per-request guardrail settings; organisation presets still apply |

Media: images png, jpeg, gif, webp; video mp4, mov, mkv, webm; documents pdf, csv, docx, xlsx
(with `name`). The whole payload is at most 25 MB.

Buffered response: `response.content` (text), `response.toolUse` (when the model asks for tools),
`model`, `requestId`, `finishReason`, `usage`.

## Stream events (`/chat/stream`)

```
id: chunk-0
event: start
data: {"requestId":"abc123","model":"...","streaming":true}

id: chunk-1
event: content
data: {"delta":"Hello","complete":false}

id: chunk-3
event: done
data: {"complete":true,"usage":{"inputTokens":8,"outputTokens":15,"totalTokens":23}}
```

An error after the stream starts is an `event: error` with a JSON `data` (`error`, often
`statusCode`). The HTTP status stays 200. Ignore event types you do not use. A stream that ends
without `done` did not finish.

## Async execution

1. Send the chat request with `"async": true`. Response 202: `requestId`, `status: "queued"`, `pollUrl`.
2. Poll `GET /chat/executions/{requestId}` (URL-encode the ID). Start at 1 s, back off to 30 s,
   stop after 15 minutes.
3. Status `waiting_callback`: the body has `callbackId` and `pendingTools` (`toolUseId`, `name`,
   `input`). Run the tools and send:

   ```json
   {"callbackId": "...", "toolResults": [{"toolUseId": "...", "result": {"status": "shipped"}}]}
   ```

   to `POST /chat/callback`. 404 means the callback was already used or the run ended.
4. Status `complete`: `result.response.content` and `result.usage`. Status `failed`: `error`.

Agent chat with `async: true` runs all tools on the platform and never waits for a callback.

## Agent chat (`POST /agents/{id}/chat`)

`message` (required), `sessionId`, `userId`, `stream`, `async`, `system` (added to the agent
prompt), `maxToolIterations` (1 to 1000), `allowedCollections` (per-request override),
`longContext`.

## Custom tool (`POST /custom-tools`)

| Field | Notes |
|---|---|
| `name` | Required. Lowercase letters, digits, underscores; starts with a letter or underscore |
| `description` | Required. The model reads it |
| `edgeFunctionCode` | Required. JavaScript; receives a POST with JSON `{toolName, input, orgId}` and returns JSON with `result` or `error` |
| `inputSchema` | Required. A JSON Schema object |
| `isAsync` | For work over 5 s; the function returns `{executionId}` and the platform polls |
| `timeoutSeconds` | 5 to 300, default 30 |
| `responseMode` | `llm` (model rewrites the output) or `direct` (output goes to the user) |
| `outputSchema`, `outputSchemaDescription`, `category` | Optional |

## Vector database

Create: `name` (3 to 50 characters: lowercase letters, digits, hyphens, underscores),
`embeddingModel`, optional `description`, `dimensions`. List embedding models with
`GET /models?feature=embeddings`; the model cannot change after creation.

Upload: `{"documents": [{"content": "...", "key": "faq-returns", "metadata": {"title": "...",
"source_url": "...", "section": "...", "tags": ["faq"]}}]}`. Up to 100 documents; `content` 10 to
10,000 characters. Chunking defaults: `chunkSize` 1000 (500 to 2000), `chunkOverlap` 200 (0 to 500).
The same `key` replaces the earlier document.

Query: `query` or `vector` (not both), `limit` 1 to 20 (default 5), `threshold` 0 to 1 (default 0.7),
`includeEmbeddings`, `filter.exact` (metadata equals, AND), `filter.contains` (array contains any).
`listByMetadata: true` with a `filter` lists documents without semantic search (cursor pagination,
`sortBy` `created_at` or `document_id`). Results: `documentId`, `content`, `similarity`, `metadata`.

Delete documents: one of `purgeAll: true`, `documentIds`, `keys`, or
`metadata: {"field": "...", "values": [...]}`.

## Governance (`PUT /governance`)

`aiEnabled` and `modelPolicy` (`unrestricted`, `allowlist`, `blocklist`) are required; `modelList`,
`mandatoryGuardrailPreset` (`official`, `official-sensitive`, `protected`), `mandatoryFilterPolicies`,
`spendLimits`, `version`. `spendLimits` (US cents): `monthlyBudgetCents`, `dailyBudgetCents`,
`perUserMonthlyBudgetCents`, `perUserDailyBudgetCents`, `perTokenMonthlyBudgetCents`,
`perTokenDailyBudgetCents`, `warningThresholdPercent`, `interfaceLimits` (per label: `monthlyCents`,
`dailyCents`), `userOverrides` and `tokenOverrides` (`monthlyCents`, `dailyCents`, `unlimited`).
Interface labels include `api-gateway`, `streaming`, `workflow`, `orchestration`, `embedding`,
`slack`, `ai-search`.

## Auto mode

Auto mode lets QuantCode pick a model for each task. An orchestrator model plans and delegates,
and tasks run on one of three ordered role lists: `fast` (quick, simple tasks), `standard` (most
coding tasks) and `deep` (hard problems and code review). The first model in a list is tried
first and the rest are fallbacks. Code review uses the first `deep` model; put your strongest
model first in that list. Dashboard: AI, Governance, Auto mode, then **Save auto mode** (separate from
the governance save).

| Call | Response |
|---|---|
| `GET /auto-mode` | `{"autoMode": <config or null>, "eligible": <report or null>}`. `null` means not configured |
| `PUT /auto-mode` | 200 `{"autoMode": {...}}` |
| `DELETE /auto-mode` | 200 `{"autoMode": null}`. The setting goes back to not configured |

The token needs the scope `ai:use` (and permission to use AI services) for GET, and `ai:manage`
(and the AI governance permission) for PUT and DELETE.

```bash
curl -s -X PUT "$AI/auto-mode" -H "Authorization: Bearer $QUANT_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"enabled": true,
       "orchestratorModel": "ORCHESTRATOR_MODEL_ID",
       "group": {"revision": 3, "roles": {
         "fast": ["FAST_MODEL_ID"],
         "standard": ["STANDARD_MODEL_ID"],
         "deep": ["DEEP_MODEL_ID", "FALLBACK_DEEP_MODEL_ID"]}},
       "watcherIntervalMinutes": 5,
       "maxParallelTasks": 4,
       "enforcement": "default",
       "autonomousDefault": false}'
```

Take every model ID from `GET /models` (or the dashboard list) for your platform.

| Field | Notes |
|---|---|
| `enabled` | Boolean |
| `orchestratorModel` | Model ID of the orchestrator. Required when `enabled` is true |
| `group.roles.fast`, `.standard`, `.deep` | Ordered lists of 0 to 5 model IDs; the first is tried first |
| `group.revision` | Integer. Send the value you read; omit it on the first save. Returned on every response |
| `watcherIntervalMinutes` | 0 to 60. The watcher checks running tasks at this interval; 0 turns it off |
| `maxParallelTasks` | 1 to 16. Omit for no limit |
| `enforcement` | `default`: developers can turn auto mode off. `required`: they cannot, and the organisation's model choices are locked in QuantCode's config |
| `autonomousDefault` | Boolean. Autonomous jobs use auto mode unless the job chooses (see below) |
| `updatedAt`, `updatedBy` | Response only |

Errors from PUT:

| Status | Meaning | Fix |
|---|---|---|
| 400 "Some auto-mode models are not eligible for this organisation" | One or more models cannot be used; the body has the `eligible` report | Remove every ineligible model, then save |
| 409 "Config was modified by another user. Please reload and try again." | The `group.revision` you sent is stale | GET again, apply your change, retry |
| 409 "Save the organisation governance settings first" | The organisation has no governance settings yet | Save AI Governance once (`PUT /governance`), then save auto mode |
| 422 | The body has the wrong shape | Check each field against the table above |

The eligibility report lists each model as `{"modelId", "resolvedId", "eligible", "reason"}`.
`reason` is present when `eligible` is false:

| `reason` | Meaning |
|---|---|
| `unknown` | Not a known model |
| `no_tools` | The model does not support tool use (for example an embedding model) |
| `policy` | Blocked by the organisation's approved-models allowlist or blocklist |
| `residency` | Not available in the platform's region |

On QuantGov every save is stored with `enforcement: "required"`, whatever you send, and only
Australian-resident models are eligible. A model that is not available in Australia is refused
with `residency`.

### Autonomous jobs

`POST /api/v2/organizations/{org}/ai/jobs` (dashboard host) takes an optional boolean `autoMode`:

| `autoMode` | Result |
|---|---|
| `true` | The job uses auto mode. 400 if the organisation has no enabled setting, or (with the `eligible` report) if the orchestrator or a whole role has no eligible model |
| `false` | The job never uses auto mode |
| Omitted | Auto mode when the setting is enabled and `autonomousDefault` is true. If the models are not usable, the job still runs without auto mode, and the 201 reply carries `autoModeNotice` with the reason |

In an auto-mode job, `code` and `debug` use the `standard` role, `plan` and `review` use `deep`,
and the orchestrator uses `orchestratorModel`. A job's `overrides`, and a model that the
organisation set on an agent overlay, win over auto mode.

### Audit records

When the organisation has the AI audit ledger on, inference events from auto-mode tasks record
`autoMode: {"role", "revision"}` next to the model. QuantCode sends the role and revision as
labels, so treat the recorded model as the authoritative record of what ran.

## Errors

| Status | Meaning |
|---|---|
| 400 | Auto-mode models not eligible (with the `eligible` report) |
| 401 | No token, wrong token type, or a token from the other platform |
| 403 | No permission; AI disabled for the organisation; model not approved; QuantGov model not available (`model_not_available_in_region`) |
| 404 | Unknown agent, session, collection, execution or callback |
| 409 | Collection name exists; overlay version conflict; auto-mode revision conflict; auto mode saved before governance |
| 422 | Invalid request (for example `/oai/v1`, governance, auto mode) |
| 429 | Spend limit reached; wait for the daily or monthly reset |

## OpenAI-compatible API

Base URL `{dashboard}/oai/v1`; the dashboard API token is the API key.

- Endpoints: `POST /chat/completions` (buffered and `stream: true`, `tools`, `tool_choice`,
  `stream_options.include_usage`), `POST /embeddings`, `GET /models`, `GET /models/{model}`.
- The organisation comes from the token. If the token covers several, set the
  `OpenAI-Organization` header to the organisation machine name.
- Differences: one choice only (`n > 1` unsupported); `frequency_penalty`, `presence_penalty`,
  `seed`, `logprobs`, `logit_bias` are accepted and ignored; streams report `stop` instead of
  `length` on truncation.
- Not included: images, audio, moderations, Assistants and Responses APIs, batches.
