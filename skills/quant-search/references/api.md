# Search API reference

Three separate APIs. Use the one that matches the product (see `SKILL.md`).

## 1. Keyword search records (content API)

Base: `https://api.quantcdn.io/v1` (QuantCDN), `https://api.quantgov.cloud/v1` (QuantGov).
Auth: three headers on every call, with the **project** token (not a dashboard token):

| Header | Value |
|---|---|
| `Quant-Customer` | organisation (customer) ID |
| `Quant-Project` | project ID |
| `Quant-Token` | project token |

| Call | Purpose |
|---|---|
| `GET /search` | Index status: size and configuration. (`quant search status` prints `index.entries`.) |
| `POST /search` | Create or update records. Body: JSON array. `title`, `url`, `content` required. Optional `summary`, `image`, `categories` (array or object of arrays), `tags` |
| `POST /search/facet` | Make attributes filterable. Body: `["categories","tags"]` |
| `DELETE /search` with header `Quant-Url: /about-us` | Remove one record |
| `DELETE /search/all` | Remove every record |

```bash
curl -X POST "$ENDPOINT/search" -H "Quant-Customer: $CUSTOMER" -H "Quant-Project: $PROJECT" \
  -H "Quant-Token: $TOKEN" -d @search-records.json
```

Notes:

- The public API page lists `summary` as required; the CLI, the dashboard docs and the content
  schema require only `title`, `url`, `content`. Send `summary` anyway: it is the snippet in results.
- `content` may contain HTML; tags are stripped.
- A record update re-indexes even when the page body is unchanged.
- Errors: 400 invalid record, 401 bad token, 429 rate limited. The page `api/search` lists the shapes.
- `search_record` in a content push (`POST /v1`) takes `title`, `summary`, `content`, `image`,
  `categories` (object: taxonomy name to array of terms). All keys are optional; extractors fill gaps.
- There is no documented query endpoint for keyword search.
- Search pages built in the dashboard: filter clauses are `field:value`. "Sort Order" (Search, Edit)
  takes a field and a direction (ascending or descending) per rule, applied after text relevance.
- Search pages created in the Drupal module do not appear in the dashboard, and the reverse.

## 2. AI Search management API (dashboard API)

Base: `{dashboard}/api/v3/organisations/{organisation}/projects/{project}/ai-search`
(note the spelling `organisations`). Auth: `Authorization: Bearer <dashboard API token>`; the token
belongs to one platform. Dashboard hosts: `https://dashboard.quantcdn.io`, `https://dash.quantgov.cloud`.

| Call | Purpose |
|---|---|
| `GET /ai-search` | Status: enabled, `siteId`, `pageCount`, `baseUrl`, `status` |
| `POST /ai-search/enable` | Enable. Optional body `baseUrl` (default: the project domain), `crawlerConfig`. 400 if the project has no domain and no `baseUrl`; 409 if already enabled |
| `POST /ai-search/disable` | Disable. **Deletes the index** |
| `GET`, `PUT /ai-search/settings` | Public access (`enabled`, `allowedDomains`, `searchEnabled`, `chatEnabled`, `anonymousSessions`, `sessionTTLMinutes`) and `rateLimits` (`searchPerMinute`, `chatPerMinute`, `perIpPerMinute`). Body keys `publicAccess`, `rateLimits` |
| `GET /ai-search/pages` | List indexed pages. Query: `limit` (max 200), `cursor` (from the previous response), `search` (URL filter) |
| `POST /ai-search/pages` | Ingest pages. Body `{"pages":[{"url","title","content", "summary","tags","topics","contentType","fetchedAt","preProcessed"}]}`; `url`, `title`, `content` required (content up to 500 KB per page); at most 50 pages per call; optional `jobId` |
| `DELETE /ai-search/pages` | Body `{"urls":[...]}` and/or `{"patterns":[...]}` |
| `DELETE /ai-search/index` | Purge the whole index |
| `POST /ai-search/search` | Semantic search. Body `query` (required), `limit` (max 50), `minScore` |
| `POST /ai-search/chat` | Answer with sources. Body `message` (required), `sessionId`, `contextUrl`, `maxContextChunks` (max 20) |
| `GET /ai-search/usage?range=30d` | Usage |
| `GET /ai-search/top-queries?range=30d&limit=` | Popular queries (limit max 100) |
| `GET`, `POST /ai-search/crawls` | List ingest jobs (`limit` max 50); start a crawl with `{"crawler_uuid": "<uuid>"}` (409 if that crawler is already running) |
| `GET /ai-search/crawls/{jobId}` and `/pages` | Job status and per-page results (`limit`, `statusCode`, `processingStatus`) |

Settings defaults: public access off, `searchEnabled` true, `chatEnabled` true, `anonymousSessions`
true, `sessionTTLMinutes` 30 (5 to 1440), rate limits 100 searches (max 1000), 20 chat messages (max 100),
30 requests per IP (max 100) per minute. An empty
`allowedDomains` accepts any domain when public access is on.

## 3. AI Search public API (browser and server, no token)

Host: the embed host shown in the dashboard snippet. Requires public access on; the origin must be
allowed. Only these calls are documented in the dashboard:

```
GET  https://EMBED-HOST/v1/public/sites/{siteId}/search?q=your+query
POST https://EMBED-HOST/v1/public/sites/{siteId}/chat     {"message": "Your question here"}
```

Do not assume other parameters (page, filter, facet) exist for these calls.
