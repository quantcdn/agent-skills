# Messages and files

All paths are relative to `{dashboard}/api/v3/organizations/{org}/ai`. Use
`Authorization: Bearer <dashboard token>` and `Accept: application/json`; writes also need
`Content-Type: application/json`. Examples use placeholders, not real IDs or credentials.

## Discover and read

`GET /slack-bots/api-enabled` returns `bots`, each with `botId`, `name`, `workspaceId` and
`channels:[{id,name,isPrivate}]`. Use a returned bot and allowed channel.

- `GET /slack-bots/{botId}/channels/{channel}/messages?limit=20` returns recent root messages.
- `GET /slack-bots/{botId}/threads/{channel}/{threadTs}?limit=100` returns a thread.
- Follow the returned cursor for additional pages. Preserve Slack timestamps as strings.

## Send an update

`POST /slack-bots/{botId}/messages`, with a stable `Idempotency-Key` (8–128 visible ASCII
characters) for this logical post:

```json
{
  "channel": "CHANNEL_FROM_DISCOVERY",
  "text": "The preview build is ready. I am checking the mobile layout next."
}
```

The response includes `channel`, `ts`, `threadTs` and `permalink`. To continue the same thread,
include `threadTs` set to the root message's `ts` in subsequent requests. The API adds attribution
to the token's user; do not claim to be a different person.

Broadcast control strings are rendered literally. Real person mentions use `<@SLACK_USER_ID>`;
use them only when appropriate to the authorised task. Do not rely on a plain `@name` to notify.
A message posted via this API does not automatically trigger a bot reply.

Links: write `<https://example.com/pull/12|example/repo#12>` for a link with a label, or a bare
`https://` URL. Only `https` links become links; `http:`, `mailto:` and other schemes, channel
links and user groups are shown as text. Punctuation directly after a bare URL is not part of it.
For a list of links, put one per line with a short label, for example:

```text
Open PRs:
- <https://github.com/example/app/pull/12|example/app#12> (checks passing)
- <https://github.com/example/site/pull/4|example/site#4> (checks pending)
```

## Rich messages with Markdown

Add `"format": "markdown"` to post standard Markdown: headings, bold and italic, bullet and
numbered lists, task lists, tables, block quotes, code blocks with a language, and
`[text](https://…)` links. Without `format` (or with `"mrkdwn"`) the text is Slack mrkdwn, as above.

```json
{
  "channel": "CHANNEL_FROM_DISCOVERY",
  "format": "markdown",
  "text": "## Nightly report\n\n| Check | Result |\n|---|---|\n| Image scan | 0 high or critical |\n| Open PRs | [example/app#12](https://github.com/example/app/pull/12) |\n\nNext: merge after review."
}
```

- Use it for anything with structure: a status table, a list of PRs or findings, steps.
- The same safety rules apply: `<@SLACK_USER_ID>` mentions work (at most 10), only `https`
  links become links, and broadcasts (`@here`, `@channel`, `<!channel>`) are shown as text.
- The rendered text can be at most 12,000 characters; the request `text` is still 1–8000.
- Headings all render at the same size in Slack. Images in Markdown become links, not pictures;
  use the image upload below for a picture.
- Put a mention on its own line before a heading or table, not on the same line.

## Upload an image

`POST /slack-bots/{botId}/files` with the same authentication and a stable idempotency key:

```json
{
  "channel": "CHANNEL_FROM_DISCOVERY",
  "threadTs": "ROOT_MESSAGE_TIMESTAMP",
  "content": "STANDARD_BASE64_IMAGE_BYTES",
  "filename": "preview.png",
  "title": "Mobile preview",
  "altText": "Screenshot of the updated landing page at mobile width",
  "text": "Here is the current mobile layout."
}
```

The caption follows the same rules as message text, including links.

`channel` and `content` are required; omit `threadTs` for a new root post. The image must be PNG,
JPEG, GIF or WebP, at most 4 MiB decoded. `content` is standard base64 without whitespace or a
`data:` prefix. The filename extension must match the detected image type. Use a JSON file and
`--data-binary @file.json` rather than putting megabytes of base64 in command arguments.

The response includes `fileId` and, when available, `permalink`. Read the channel/thread back if
confirmation is needed. Slack app installation needs `files:write`; a missing Slack scope is a bot
installation issue, not a reason to expand the dashboard token beyond `ai:slack`.

Message/file idempotency lasts ten minutes. After an ambiguous result, inspect the target thread
before retrying outside that window. Do not assume the same lifetime for interaction requests.
