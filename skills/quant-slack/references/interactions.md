# Interactive questions and permission requests

Availability: requires the Slack interactions API release enabled on the selected environment.
This contract is being delivered with that release; do not claim it exists when the API returns
404. Ordinary messages/files remain usable independently.

Paths are relative to `{dashboard}/api/v3/organizations/{org}/ai/slack-bots/{botId}`.
Use the same explicit `ai:slack` bearer token as for messages.

## Create a request

`POST /interactions` with a required `Idempotency-Key` and JSON:

```json
{
  "channel": "CHANNEL_FROM_DISCOVERY",
  "text": "May I publish the reviewed landing page revision? This will replace the current page.",
  "actions": [
    { "id": "publish", "label": "Publish", "style": "primary" },
    { "id": "wait", "label": "Not yet" }
  ],
  "responseMode": "single",
  "expiresInSeconds": 3600,
  "metadata": { "jobId": "build-142" }
}
```

Optional: `threadTs` for a thread and `allowedUsers` to restrict responses to specific Slack user
IDs. Request restrictions only narrow the bot's permissions. There are 1–5 actions; IDs must be
unique, 1–64 letters/digits/underscore/hyphen, labels 1–75 characters. Optional styles are
`primary` and `danger`. `text` is 1–3000 characters; `metadata` is a JSON object up to 4096 bytes.
Expiry is 60–86400 seconds, default 3600. Raw Block Kit and arbitrary callback URLs are not accepted.

Choose action IDs that make sense for the task: `approve`/`reject`, `retry`/`skip`, or choices
such as `option_a`/`option_b`. The platform does not interpret an action ID as an execution grant.

Persist the returned `interactionId`. Creation may return 202 while delivery/recording is in
progress. `pending` means the card is ready for a response. An idempotency key is bound to the
request and creator; changed content with the same key returns 422. Keep the same key on retries.

## Wait for a response

`GET /interactions/{interactionId}` with the same token. Start with a five-second polling interval,
back off during long waits, honour 429/Retry-After, and stop at expiry or the task's wait limit.
Perform independent work while waiting if it does not depend on the answer.

- `creating`, `dispatching`, `delivering`, `resolving`: recording/delivery is in progress. No approval yet.
- `pending`: awaiting a person.
- `responded`: inspect `response.actionId`, `response.userId`, `response.workspaceId` and `response.at`.
- `cancelled` or `expired`: do not perform the permission-dependent operation.
- `delivery_unknown`: Slack may have received the card, but confirmation is missing. Do not
  automatically create a replacement or treat any click as approval; report the uncertainty.

The single-response mode records one eligible response. The card is then closed. The requesting
integration cannot submit a human response through its token. Status access is bound to the
creating organisation, bot, user and token; token rotation does not transfer ownership automatically.

## Cancel

When the request is no longer relevant, `POST /interactions/{interactionId}/cancel` with an empty
JSON object. Cancellation cannot overwrite an already recorded response. Read the returned state.

## Meaning and evidence

Keep the request ID alongside the operation so the response can be traced. The recorded respondent
is a Slack user in a Slack workspace. Apply the workflow's own authorisation requirements before
acting. The API does not execute work, resume arbitrary agents or independently verify their
subsequent actions. The recorded response is preserved through the platform's audit/ledger path.

Webhooks, free-text answers, modals, multiple respondents and quorum are not part of this version.
