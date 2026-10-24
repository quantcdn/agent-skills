# quant-ai evals

Prompt: Our org `acme` is on QuantCDN (dashboard.quantcdn.io). I am building a support chat page with a small Node backend. Show me the curl calls for: finding which chat model IDs we can use, a single buffered chat call, the same call streamed token by token, keeping a multi-turn conversation for one user on the server side, and letting the model call our own `lookup_order` function that we execute ourselves. Which token do I use, and is there a WebSocket endpoint I should use instead of streaming?
Platform: public
Must include:
- Base URL `https://dashboard.quantcdn.io/api/v3/organizations/acme/ai` (the dashboard host with `/api/v3`; `organisations` spelling also accepted), not `api.quantcdn.io`
- Auth is `Authorization: Bearer <token>` with a dashboard API token (from the dashboard profile, API Tokens), not a project token or `Quant-*` headers
- List models first with `GET /models` (filter `?feature=chat`) and use an ID from that list as `modelId`; do not hard-code a model ID from memory
- Buffered `POST /chat` with `modelId` and `messages` (role and content), optional `maxTokens`, `temperature`, `systemPrompt`; streaming is `POST /chat/stream`, returning Server-Sent Events with `start`, `content` (text in `delta`) and `done` (with usage) events
- Sessions: `POST /sessions` with a required `userId` (optional `sessionGroup`, `expirationMinutes` default 60, max 1440), then pass `sessionId` in chat calls; `PUT /sessions/{id}/extend` to keep it alive
- Client tools: `toolConfig.tools[].toolSpec` with `name`, `description`, `inputSchema.json`; the model asks for the tool with `toolUse` (`toolUseId`, `name`, `input`); the documented loop for a client-run tool is `async: true`, poll until `waiting_callback`, then `POST /chat/callback` with `callbackId` and `toolResults`
- No public WebSocket endpoint is documented; use `/chat/stream` (SSE), or `async: true` with polling for long runs
Must not include:
- `api.quantcdn.io/api/v3`
- A `wss://` host
- The name of a cloud AI service vendor (other than inside a model ID)

Prompt: We are a state agency on QuantGov (https://dash.quantgov.cloud). Our developers use LangChain and the official OpenAI Python SDK. How do we point them at Quant AI, which models can we use, and can we also generate images for our newsletter through the same API? One developer pasted `anthropic.claude-sonnet-4-20250514-v1:0` from a blog post and gets a 403.
Platform: gov
Must include:
- OpenAI-compatible base URL `https://dash.quantgov.cloud/oai/v1`; the Quant dashboard API token (`qc_...`) is the `api_key` (sent as Bearer); `OpenAI-Organization` header selects the org when the token covers several
- Supported endpoints: `chat/completions` (buffered and `stream: true`, tools, `tool_choice`), `embeddings`, `models`, `models/{model}`
- QuantGov offers Australian-resident models only; list them with `GET /oai/v1/models` (or `GET /models` on the native API, or the dashboard) and use an ID from that list
- A model that is not available on QuantGov is rejected with 403 (error `model_not_available_in_region`); a model blocked by the org's governance model policy also returns 403 ("not approved for use in this organisation")
- Image generation is not available (not part of `/oai/v1`)
- Compatibility limits: one choice only (`n > 1` unsupported); some parameters (`frequency_penalty`, `presence_penalty`, `seed`, `logprobs`, `logit_bias`) are accepted but ignored
Must not include:
- `dashboard.quantcdn.io` as the gov base URL
- The name of a cloud AI service vendor (other than inside a model ID)
- A list of model IDs presented as the gov catalogue
- An image generation endpoint

Prompt: Our Quant AI integration on QuantCDN worked for weeks. Today: (1) a script using our project token from the Integrations page gets 401 from `/api/v3/organizations/acme/ai/chat`; (2) the main app gets HTTP 429 with "Daily AI spend limit reached"; (3) a colleague's call returns 403 "AI services are disabled for this organisation"; (4) our `/chat/stream` calls sometimes return 200 but the text stops part way through on long answers. What is happening in each case and what do we do?
Platform: public
Must include:
- 401: the AI API needs a dashboard API token as `Authorization: Bearer`; the project token (`Quant-Token`) belongs to the content API
- 429 means a governance spend limit was reached (here a daily one: organisation, per-user, per-token or per-interface); requests stay rejected until the daily window resets the next day; check spend in AI Governance, Current Spend or `GET /governance/spend`; an admin with the governance permission can raise the limit or add an override
- 403 "AI services are disabled": the AI Access master toggle in AI Governance is off; an admin must turn it on
- Streaming errors after the stream starts arrive as an `event: error` SSE event inside the 200 response, so the client must read event types (not only `content`) and handle `done`
- For long runs use `async: true` and poll `GET /chat/executions/{requestId}` (statuses pending, running, waiting_callback, complete, failed) with backoff
Must not include:
- Advice to retry a 429 in a tight loop
- A host other than the customer's dashboard host for the AI API

Prompt: We want a Quant AI workflow that runs when GitHub opens a pull request in our repo, plus a nightly run. How do we create the workflow (can we do it with the API or Terraform?), where is the webhook URL, how does GitHub authenticate to it, how do we get and rotate the secret, and how can we test the webhook with curl before pointing GitHub at it? We are on QuantCDN.
Platform: public
Must include:
- Workflows are built in the dashboard visual editor (Workflows, Create Workflow); the public API and Terraform have no workflow resource or endpoints
- Webhook URL from the Triggers page, shape `https://dashboard.quantcdn.io/webhooks/ai/workflows/{workflowId}`; the request body is available as `{{webhook.payload.*}}`
- Auth modes: `secret` (default, `Authorization: Bearer <secret>` or `?token=<secret>`) and `hmac` (`X-Hub-Signature-256: sha256=<HMAC-SHA256 of the raw body>`, POST only) for GitHub
- Reveal shows the current secret without changing it; Rotate makes a new one and the old one stops working (401) until every caller is updated
- A missing or wrong secret or bad signature returns 401 and never starts the workflow; a valid call returns 202 with an `executionId`
- Scheduled trigger with a cron expression for the nightly run
Must not include:
- A workflow create endpoint under `/ai/workflows`
- A `quant_ai_workflow` Terraform resource

Prompt: We manage QuantGov with Terraform. Add a support agent with a returns-policy skill and a knowledge base of our FAQ documents, a custom tool `lookup-order` written as an edge function, and org-wide spend caps of A$1000 a month. Also, our public website needs AI search over its pages - should that use the same vector collection? And can we change the collection's embedding model later? Put the complete HCL in your answer.
Platform: gov
Must include:
- Provider `base_url = "https://dash.quantgov.cloud"` (bare host, no `/api/v2`), the token as `bearer` or the `QUANTCDN_API_TOKEN` environment variable, `organization`
- `quant_ai_agent` needs `name`, `description`, `model_id`, `system_prompt`; attach `assigned_skills`, `allowed_tools`, `allowed_collections`; pick `model_id` from the models list (gov: Australian-resident models only)
- `quant_ai_skill` needs `name`, `content`, `trigger_condition`
- `quant_ai_vector_collection` (`name`, `embedding_model`) and `quant_ai_vector_document` (`documents` with `content`, optional `key` and `metadata`)
- `quant_ai_custom_tool`: `name` allows only lowercase letters, digits and underscores, so `lookup-order` must be renamed (for example `lookup_order`); `input_schema` via `jsonencode`, `edge_function_code`, `timeout_seconds` 5 to 300
- `quant_ai_governance` (one per organisation) with `spend_limits.monthly_budget_cents`; budgets are set in USD cents, not AUD
- The embedding model cannot be changed after creation; create a new collection and upload the documents again
- Website search is AI Search (`quant-search`), not a vector collection
Must not include:
- `base_url` ending in `/api/v2` or `/api/v3`
- A `quant_ai_workflow` resource
- A hyphen in the custom tool `name`

Prompt: Our organisation uses Quant AI with tool approvals. In QuantCode a prompt said "Cloud tool `create_ticket` (write) needs your approval" and I pressed Escape. Our nightly `quantcode run` job also called the same tool and the model said it is waiting for approval. Did Escape reject the call, how do we approve both, and how do we turn tool approvals on for our second organisation?
Platform: public
Must include:
- Escape (or "Decide later") closes the prompt without a decision; the proposal stays pending and is not rejected
- Decide on the dashboard page AI Services, Approvals: Approve, Approve for session (own interactive request only, when allowed) or Reject with an optional reason
- `quantcode run` (and autonomous mode) never answers an approval prompt; a person decides on the Approvals page
- After the decision, the outcome arrives on the next user turn as a `[Platform notice]`, and the model reads the result with `check_tool_execution_status` and the proposal ID
- Tool approval is enabled per organisation by Quant; contact Quant (there is no self-serve switch)
Must not include:
- A claim that Escape rejects the call
- An API setting or header that turns approvals on

