---
name: quant-ai
description: Use when calling or configuring Quant AI services on QuantCDN or QuantGov - the AI API under `{dashboard}/api/v3/organizations/{org}/ai` (models, buffered `/chat`, SSE `/chat/stream`, async `async true` with polling and `/chat/callback`, embeddings), the OpenAI-compatible `/oai/v1` surface (OpenAI SDKs, LangChain, `base_url`), sessions, tool calling and custom tools (edge functions), agents and agent overlays, skills and skill collections, vector database collections and documents (RAG), workflows with webhook and scheduled triggers (secret or HMAC auth), AI Governance (model allowlist, guardrail presets, filter policies, spend limits), tool approvals (`pending_approval`, the Approvals page), which models are available (QuantGov is Australian-resident only), and Terraform `quant_ai_*`. Also use for 401/403/429 from the AI API, "spend limit reached", "AI services are disabled", `model_not_available_in_region`, and streams that stop part way. Not for website search or the search widget (`quant-search`).
---

# Quant AI services

Quant AI is a set of AI services in the Quant dashboard (AI Services) with a REST API: chat
inference, sessions, tools, agents, skills, a vector database, workflows, and governance.
This skill covers using them as a customer. For the platform overview load `quant-platform`.

## Applies to

Both platforms: QuantCDN (`https://dashboard.quantcdn.io`) and QuantGov (`https://dash.quantgov.cloud`).
Identify the platform by the dashboard URL only; ask the customer if you do not know it. Features
are the same; QuantGov offers Australian-resident models only. Checked 2026-10 against the public
docs, the public API specification (4.25.0) and Terraform `quantcdn/quant` v5.15.1.

| | QuantCDN | QuantGov |
|---|---|---|
| AI API base | `https://dashboard.quantcdn.io/api/v3/organizations/{org}/ai` | `https://dash.quantgov.cloud/api/v3/organizations/{org}/ai` |
| OpenAI-compatible base | `https://dashboard.quantcdn.io/oai/v1` | `https://dash.quantgov.cloud/oai/v1` |
| Workflow webhooks | `https://dashboard.quantcdn.io/webhooks/ai/workflows/{workflowId}` | `https://dash.quantgov.cloud/webhooks/ai/workflows/{workflowId}` |
| Models | The catalogue for the organisation | Australian-resident models only |

`{org}` is the organisation machine name. The path accepts `organizations` and `organisations`.
The AI API is on the dashboard host, not on the content API host (`api.quantcdn.io`).

## Authentication and permissions

- Use a **dashboard API token** (dashboard profile, API Tokens; it starts `qc_`) as
  `Authorization: Bearer <token>`. A project token (`Quant-Token`, Integrations page) is for the
  content API and gets 401 here. A token from the other platform also fails.
- The token acts as its user. Creating tools needs `manage_ai_tools`; agents, skills, workflows and
  vector databases need `manage_ai_agents`; filter policies and governance need the AI governance
  permission; MCP servers need `manage_ai_mcp_servers`. Owners and admins have these.
- `GET /usage` (organisation breakdown) needs the subscription permission; any caller can read its
  own spend with `GET /usage/me`.

## Pick the interface

| Need | Use |
|---|---|
| One answer, short request | `POST /chat` (buffered JSON) |
| Show tokens as they arrive | `POST /chat/stream` (Server-Sent Events) |
| Long runs, big context, client-run tools | `async: true` on `/chat` or `/chat/stream`, then poll |
| Existing OpenAI SDK, LangChain, other OpenAI tools | `/oai/v1` (stateless) |
| A configured assistant (prompt, tools, skills, knowledge) | Agent: `POST /agents/{id}/chat` |
| Multi-step automation, webhooks, schedules | Workflow (dashboard editor) |
| Search over your website pages | AI Search, see `quant-search` |

There is no public WebSocket endpoint. Use `/chat/stream`.

## Models

Never hard-code a model ID from memory or a blog post. List the models this organisation can use:

```bash
AI="https://dashboard.quantcdn.io/api/v3/organizations/$ORG/ai"   # gov: https://dash.quantgov.cloud/...
curl -s "$AI/models?feature=chat" -H "Authorization: Bearer $QUANT_API_TOKEN"
```

`feature` is `chat`, `embeddings`, `vision`, `streaming` or `all`. `GET /models/{modelId}` shows one
model. On QuantGov the list holds only Australian-resident models. An organisation can also
restrict models with an approved-models policy (see Governance). Image generation is not
available; do not offer it.

## Chat

```bash
curl -s -X POST "$AI/chat" -H "Authorization: Bearer $QUANT_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"modelId": "MODEL_ID_FROM_LIST",
       "messages": [{"role": "user", "content": "What is the capital of Australia?"}],
       "systemPrompt": "Answer in one sentence.", "maxTokens": 1024, "temperature": 0.3}'
```

The same call on QuantGov only changes the host (`https://dash.quantgov.cloud/...`) and needs an
Australian-resident `modelId`. The answer is in `response.content`, with `finishReason` and `usage`.

Streaming: send the same body to `$AI/chat/stream` (use `curl -N`). The response is
`text/event-stream`:

```
event: start    data: {"requestId":"...","model":"...","streaming":true}
event: content  data: {"delta":"Hello","complete":false}
event: done     data: {"complete":true,"usage":{"inputTokens":8,"outputTokens":15,"totalTokens":23}}
```

Join the `delta` values. Handle `event: error`: an error after the stream starts arrives as an
error event inside the HTTP 200 response, not as an HTTP status. Ignore unknown event types.

Async: add `"async": true`. The call returns 202 with `requestId` and `pollUrl`. Poll
`GET $AI/chat/executions/{requestId}` (start at 1 s, back off to 30 s, give up after 15 min).
Statuses: `pending`, `running`, `waiting_callback`, `complete`, `failed`.

Other fields (`topP`, `stopSequences`, `responseFormat` for JSON output, image, video and document
blocks up to 25 MB in total): [references/api.md](references/api.md).

## Sessions

A session keeps the conversation on the server so you send only the new message.

```bash
curl -s -X POST "$AI/sessions" -H "Authorization: Bearer $QUANT_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"userId": "user-123", "sessionGroup": "support-web", "expirationMinutes": 120}'
```

`userId` is required. `expirationMinutes` defaults to 60 (5 to 1440). Pass the returned
`sessionId` in each `/chat` or `/chat/stream` call. Omit it for stateless calls. Extend with
`PUT /sessions/{id}/extend` (`additionalMinutes`, max 1440); list with `GET /sessions?userId=&sessionGroup=`;
delete with `DELETE /sessions/{id}`. Sessions expire: extend them before that, or create a new one.

## Tools

Three kinds:

1. **Client tools (you run them).** Declare them in the request; the model answers with `toolUse`:

   ```json
   "toolConfig": {"tools": [{"toolSpec": {"name": "lookup_order",
     "description": "Look up an order by number",
     "inputSchema": {"json": {"type": "object",
       "properties": {"order_number": {"type": "string"}}, "required": ["order_number"]}}}}]}
   ```

   A sync response stops with `response.toolUse` (one object or an array: `toolUseId`, `name`,
   `input`). For the full loop, send the request with `async: true`, poll
   `GET /chat/executions/{requestId}` until `waiting_callback`, run the tools listed in
   `pendingTools`, then `POST /chat/callback` with `callbackId` and `toolResults`
   (`toolUseId`, `result`). Poll again until `complete`. Each `callbackId` works once.
2. **Built-in tools.** `GET /tools` lists them. To let the platform run them, set
   `toolConfig.autoExecute: true` with an `allowedTools` list (required). Long tools return an
   `executionId`; poll `GET /tools/executions/{executionId}`.
3. **Custom tools.** Your JavaScript, deployed as an edge function and callable by agents. Create in
   the dashboard (AI Tools, Create, including the AI-assisted creator) or with
   `POST /custom-tools`: `name` (lowercase letters, digits, underscores), `description`,
   `edgeFunctionCode`, `inputSchema` (a JSON Schema object), optional `isAsync`, `timeoutSeconds`
   (5 to 300, default 30), `responseMode` (`llm` or `direct`), `category`. Posting the same `name`
   again updates the tool. Test it on the tool page before you assign it. Delete a tool only after
   you remove it from every agent.

## Agents

An agent is a saved assistant: model, system prompt, temperature, max tokens (1 to 200,000), tools,
skills, vector collections, guardrail preset and filter policies. Only models that support tool use
can be agent models.

- Dashboard: AI Agents, Create Agent (five-step wizard); test in the chat panel on the agent page.
- API: `POST /agents` with `name`, `description`, `systemPrompt`, `modelId` (required), and
  `allowedTools`, `allowedCollections`, `assignedSkills`, `guardrailPreset`
  (`official`, `official-sensitive`, `protected`), `filterPolicies`, `group`.
- Chat: `POST /agents/{agentId}/chat` with `message`, optional `sessionId`, `userId`, `stream`, `async`.
  Without `sessionId` a new session is created. The agent runs its tools itself.
- Pre-built platform agents can be adjusted per organisation with an overlay
  (`PUT /agents/{agentId}/overlay`: model, tools, skills, `systemPromptAppend`); PUT replaces the whole overlay.

## Skills

A skill is reusable instructions an agent applies when its trigger condition matches. Fields:
`name`, `content`, `triggerCondition` (required), `description`, `requiredTools`, `tags`. Make sure
the agent also has the skill's required tools.

- Dashboard: AI Skills, Create Skill; or Import from GitHub (repository, file path, branch).
- API: `POST /skills`; `POST /skills/import` (`source.type` `github`); `POST /skills/import-collection`
  imports a directory of skills (each subfolder with a `SKILL.md`) under a `namespace`
  (lowercase, digits, hyphens, 3 to 63 characters, cannot be renamed). Sync with
  `POST /skills/{id}/sync` or `POST /skills/collections/{namespace}/sync`.
- Agents get skills by ID (`assignedSkills`) or by namespace in the dashboard.

## Vector database

Collections hold documents as embeddings for agents to search (RAG). Dashboard: Vector Database.

1. Create: `POST /vector-db/collections` with `name` (3 to 50 characters), `embeddingModel` (from
   `GET /models?feature=embeddings`). **The embedding model cannot be changed later**: create a new
   collection and upload the documents again.
2. Upload: `POST /vector-db/collections/{id}/documents` with `documents` (up to 100 per request;
   `content` 10 to 10,000 characters; optional `key` for upsert and `metadata`). Documents are chunked.
3. Query: `POST .../query` with `query` (or `vector`), `limit` (1 to 20), `threshold` (default 0.7).
4. Delete documents: `DELETE .../documents` with `purgeAll`, `documentIds`, `keys` or `metadata`.
   Deleting a collection cannot be undone.

Give agents collections with `allowedCollections`. `POST /embeddings` returns raw embeddings.
For search on your website (crawled pages, widget, search page) use AI Search in `quant-search`,
not a vector collection. Field details: [references/api.md](references/api.md).

## Workflows and webhooks

Workflows are built in the dashboard only (Workflows, Create Workflow): a visual editor with
trigger, AI model, tool, condition, transform and wait-for-input nodes. Each save is a revision. The
public API and Terraform have no workflow resource.

Triggers (a workflow can have more than one): Manual (Execute in the editor), Schedule (cron, for
example `0 2 * * *`), Webhook. The
Triggers page lists the webhook URL. The POST body is available to nodes as `{{webhook.payload.*}}`.

Every webhook has its own secret. Choose the auth mode on the trigger:

| Mode | Caller sends |
|---|---|
| `secret` (default) | `Authorization: Bearer <secret>`, or `?token=<secret>` |
| `hmac` (GitHub style, POST only) | `X-Hub-Signature-256: sha256=<HMAC-SHA256 of the raw body with the secret>` |

```bash
URL=https://dashboard.quantcdn.io/webhooks/ai/workflows/$WORKFLOW_ID   # copy from the Triggers page
curl -s -X POST "$URL" -H "Authorization: Bearer $WEBHOOK_SECRET" \
  -H "Content-Type: application/json" -d '{"input": "Process this"}'           # secret mode
BODY='{"smoke":true}'
SIG="sha256=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | awk '{print $NF}')"
curl -s -X POST "$URL" -H "X-Hub-Signature-256: $SIG" -H "Content-Type: application/json" \
  --data-binary "$BODY"                                                          # hmac mode
```

A valid call returns 202 with an `executionId`. A missing or wrong secret or signature returns 401
and the workflow does not start; an unknown workflow returns 404. **Reveal** shows the current
secret and does not change it. **Rotate** creates a new secret; every caller with the old one gets
401 until updated. For GitHub: set Auth to HMAC, Reveal, then in the repository Settings, Webhooks
use the URL, content type `application/json`, the secret, and the events you need. GitHub's first
`ping` delivery also runs the workflow.

Executions (`pending`, `running`, `paused` at a wait-for-input node, `completed`, `failed`) show
each node's input, output and timing. Give input to a paused execution in the dashboard.

## Governance and spend

AI Services, AI Governance (needs the AI governance permission), `GET`/`PUT /governance`, or
`quant_ai_governance`. Settings apply to every AI surface in the organisation: dashboard, API,
`/oai/v1`, Slack bots, workflows.

- **AI Access**: off blocks all AI requests (403 "AI services are disabled for this organisation").
- **Mandatory guardrail preset** (`official`, `official-sensitive`, `protected`) and **mandatory
  filter policies** apply to every request, whatever the agent says. Filter policies block or redact
  words or regex matches (AI Services, Filter Policies).
- **Approved models**: unrestricted, allowlist or blocklist. A blocked model returns 403
  "Model ... is not approved for use in this organisation".
- **Spend limits** (USD; the API and Terraform take cents): organisation monthly and daily, per user,
  per API token, per interface (for example api-gateway, streaming, workflow, embedding), with
  per-user and per-token overrides or `unlimited`. A warning threshold sends alerts first.
- When a limit is reached, requests return **429** ("... AI spend limit reached") until the window
  resets: next day for daily caps, next month for monthly caps. Current Spend in the dashboard, or
  `GET /governance/spend`, shows month-to-date and today.

## Tool approvals

An organisation can require a person's approval before chosen platform tools run. Quant turns this
on per organisation (contact Quant; there is no self-serve switch). A tool call that needs approval
does not run: its result is `pending_approval` with a proposal ID (`p_...`). A person decides on
the dashboard page AI Services, **Approvals** (Approve, Approve for session, Reject with a reason),
or in the QuantCode prompt. The outcome reaches the conversation on the next user turn as a
`[Platform notice]`, and the model reads the result with `check_tool_execution_status`. In
QuantCode, **Escape** means "decide later": no decision is sent and the proposal stays pending.
`quantcode run` and autonomous mode never approve. Details: [references/tool-approvals.md](references/tool-approvals.md).

## Terraform and Pulumi

Resources: `quant_ai_agent`, `quant_ai_agent_overlay`, `quant_ai_custom_tool`, `quant_ai_skill`,
`quant_ai_vector_collection`, `quant_ai_vector_document`, `quant_ai_governance` (one per
organisation). Required fields and an example: [references/terraform.md](references/terraform.md).
Workflows, triggers, sessions, filter policies and MCP servers are not Terraform resources.
Provider setup (`base_url` is the bare dashboard host, `https://dash.quantgov.cloud` on gov), Pulumi
names and import IDs: `quant-iac`.

## OpenAI-compatible API

Point any OpenAI SDK at `{dashboard}/oai/v1` with the dashboard API token as the API key:

```python
from openai import OpenAI
client = OpenAI(api_key=os.environ["QUANT_API_TOKEN"], base_url="https://dash.quantgov.cloud/oai/v1")
models = [m.id for m in client.models.list()]          # pick from this list
resp = client.chat.completions.create(model=models[0], messages=[{"role": "user", "content": "Hello"}])
```

The organisation comes from the token; if the token covers several, set the `OpenAI-Organization`
header to the organisation machine name. Endpoints, unsupported parameters and the differences from
OpenAI: [references/api.md](references/api.md#openai-compatible-api). Use the native API for
sessions, agents, vector search and governance.

## Gov

QuantGov has the same AI features. Use the `dash.quantgov.cloud` hosts above. Only Australian-resident
models are offered: list them, never copy a model ID from QuantCDN examples or the internet. A
request for a model that is not available returns 403 with `model_not_available_in_region`. The
guardrail presets follow the Australian PSPF classifications (OFFICIAL, OFFICIAL:Sensitive, PROTECTED).

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| 401 on every call | Project token or `Quant-*` headers; token from the other platform; expired token | Dashboard API token from this platform as `Authorization: Bearer` |
| Calls to `api.quantcdn.io/api/v3/...` fail | Older docs showed the content API host | Use the dashboard host and the org machine name |
| 403 "AI services are disabled for this organisation" | AI Access is off in AI Governance | An admin turns it on |
| 403 `model_not_available_in_region` | QuantGov request for a model that is not Australian-resident | `GET /models` and use a listed ID |
| 403 "not approved for use in this organisation" | Approved-models policy | Pick an approved model or ask an admin to change the policy |
| 403 on create or delete | The token's user lacks the AI permission | Use an owner or admin token, or grant the role |
| 429 "... AI spend limit reached" | A governance budget is used up | Wait for the reset, or an admin raises the cap or adds an override; read `GET /governance/spend`. Do not retry in a loop |
| Stream stops part way, HTTP 200 | An `event: error` arrived in the stream, or the connection closed before `done` | Handle `error` events; treat a stream with no `done` as failed; use `async: true` for long runs |
| `finish_reason` says `stop` but text is cut (`/oai/v1` stream) | Streams report `stop` on max-token truncation | Raise `max_tokens`; check usage |
| Agent ignores a skill or tool | Not assigned, or the skill's required tool is missing | Assign both; test in the agent chat panel |
| Agent tool calls fail after a change | Tool deleted or removed from the agent | Re-assign or redeploy the tool |
| Tool result `pending_approval`; the tool does not run | The organisation requires approval for that tool | Decide on AI Services, Approvals; the result arrives on the next turn ([tool approvals](references/tool-approvals.md)) |
| Webhook 401 | Wrong mode, secret rotated, body changed after signing | Reveal the secret; sign the exact raw body; match the auth mode |
| Vector query returns nothing | `threshold` too high, wrong collection, no documents | Lower `threshold` (for example 0.5), check the collection ID, list documents |
| Website pages not answerable | Used a vector collection for site search | Use AI Search (`quant-search`) |

## Further reading

- Docs: https://docs.quantcdn.io/ai/overview/ (API reference, OpenAI compatibility, agents, tools,
  skills, vector database, workflows, webhook secrets, governance, filter policies, Slack bots, MCP servers)
- Related skills: `quant-platform`, `quant-search`, `quant-iac`, `quant-edge-functions-and-kv`

<!-- checked against tf:quantcdn/quant 5.15.1 -->
