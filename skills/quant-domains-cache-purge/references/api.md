# Domains, purge and crawler API calls

`$DASH` is the bare dashboard host: `https://dashboard.quantcdn.io` (QuantCDN) or
`https://dash.quantgov.cloud` (QuantGov). `$CONTENT` is the content API: `https://api.quantcdn.io/v1`
or `https://api.quantgov.cloud/v1`. Dashboard API calls use a dashboard API token
(`Authorization: Bearer`); the content API uses the project token.

## Domains (`/api/v2`)

Base: `$DASH/api/v2/organizations/$ORG/projects/$PROJECT/domains`

| Call | Result |
|---|---|
| `GET /` | Array of domains |
| `POST /` with `{"domain":"www.example.com"}` | The new domain |
| `GET /{id}` | One domain |
| `DELETE /{id}` | 204 |
| `POST /{id}/renew` | 202; requests the certificate now (QuantCDN) |

There is no update call. To change the host name, delete the domain and add the new one.

Domain fields:

| Field | Meaning |
|---|---|
| `id` | Numeric ID used in the paths above and in Terraform import (`project/id`) |
| `domain` | Host name |
| `dns_engaged` | `1` when Quant sees your DNS pointing at it, `0` before |
| `dns_go_live_records` | Records that send traffic to Quant: `type` (`CNAME`, `A` or `ALIAS`), `name` (`@` for the apex), `value`, `description` |
| `dns_validation_records` | QuantGov: certificate validation records (`name`, `type` usually `CNAME`, `value`). Present while validation is pending |

```bash
# Print the records to create for one domain
curl -s "$DASH/api/v2/organizations/$ORG/projects/$PROJECT/domains/$ID" \
  -H "Authorization: Bearer $QUANT_API_KEY" |
  jq '{dns_engaged, dns_go_live_records, dns_validation_records}'
```

## Purge (content API)

```bash
# One path
curl -s -X POST "$CONTENT/purge" \
  -H "Quant-Customer: $ORG" -H "Quant-Project: $PROJECT" -H "Quant-Token: $PROJECT_TOKEN" \
  -H "Quant-Url: /about"

# Whole project
curl -s -X POST "$CONTENT/purge" ... -H "Quant-Url: /*"

# Cache keys (space separated), soft purge (QuantCDN)
curl -s -X POST "$CONTENT/purge" ... -H "Cache-Keys: section:blog env:prod" -H "Soft-Purge: true"
```

Send either `Quant-Url` or `Cache-Keys`. The response is 200 when the purge is accepted; the cache
clears shortly after. 400: neither header. 403: the token does not match the customer and project.

## Crawlers (`/api/v2`)

Base: `$DASH/api/v2/organizations/$ORG/projects/$PROJECT/crawlers`. `{uuid}` is the crawler UUID
from the create or list response.

| Call | Notes |
|---|---|
| `GET /` | List |
| `POST /` | Create; `domain` required |
| `GET /{uuid}`, `PATCH /{uuid}`, `DELETE /{uuid}` | Read, update, delete |
| `POST /{uuid}/run` | Optional body `{"urls":["/","/about"]}`; 409 if a run is active |
| `GET /{uuid}/runs`, `GET /{uuid}/runs/{run_id}` | Run history |
| `GET /{uuid}/schedules`, `POST /{uuid}/schedules` | Body `{"name":"Nightly","schedule_cron_string":"0 16 * * *"}` |
| `GET`, `PATCH`, `DELETE /{uuid}/schedules/{id}` | One schedule |

Schedules use a 5-field cron expression (minute, hour, day of month, month, day of week) in **UTC**.
A local time such as 02:00 in Sydney moves by one UTC hour with daylight saving; update the
schedule or accept the shift.

```bash
curl -s -X POST "$DASH/api/v2/organizations/$ORG/projects/$PROJECT/crawlers/$UUID/schedules" \
  -H "Authorization: Bearer $QUANT_API_KEY" -H "Content-Type: application/json" \
  -d '{"name":"Nightly","schedule_cron_string":"0 16 * * *"}'
```

Crawler fields (create and update):

| Field | Default | Notes |
|---|---|---|
| `name`, `domain` | | `domain` with protocol, for example `https://www.example.com` |
| `start_urls` | | Paths to start link discovery from |
| `urls` | | Only these paths; no link discovery. Do not combine with `start_urls` |
| `sitemap` | `/sitemap.xml` | List of `{url, recursive}` |
| `include`, `exclude` | | Regular expressions (`^/admin`, `\.pdf$`) |
| `browser_mode` | `false` | Headless browser for JavaScript sites |
| `workers` | 2 | 1 to 20; a non-default value needs a verified domain |
| `delay` | 4 | Seconds, 0 to 10; a non-default value needs a verified domain |
| `depth` | -1 | -1 unlimited, 0 start pages only |
| `max_html` | 50 unverified | 0 unlimited (verified domains) |
| `max_hits` | 0 | All requests including assets; 0 unlimited; needs verification to change |
| `max_errors` | 100 | Stop after this many errors; 0 never stops |
| `status_ok` | `[200]` | Status codes whose content is stored |
| `headers`, `user_agent` | | Sent with each request |
| `allowed_domains` | | Extra hosts whose assets are captured |
| `webhook_url`, `webhook_auth_header`, `webhook_extra_vars` | | Notifications: crawl started, completed, failed |

Unverified domains: 50 pages per crawl, 20 starting URLs, 2 workers, 4-second delay. Verify with a
DNS TXT record or a file; the dashboard shows the instructions in the config's Domain verification
column.
