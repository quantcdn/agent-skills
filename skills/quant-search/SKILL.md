---
name: quant-search
description: Use when adding site search to a project on QuantCDN or QuantGov or debugging it - enabling Search or AI Search, how pages get into the index (content changes, a crawler with "AI Search Integration", `quant search index`, `quantcdn/search-action`, the Search API `/search`, `search_record` in a content push), removing or re-indexing pages, facets and filters, dashboard search pages, the embeddable chat widget, modal and search page scripts (`widget.js`, `search-page.js`, `data-site-id`), the AI Search settings (public access, allowed domains, Display URL, rate limits), the AI Search public and management APIs, AI answers and what they cost. Also use for "nothing is indexed", "stale or deleted pages still in results", "results link to the wrong domain", widget calls returning 403, and the search-action `endpoint` on gov. Not for the crawler as a cache or static-copy tool (`quant-domains-cache-purge`) or AI services in general (`quant-ai`).
---

# Site search on Quant

Quant has two search products. Both are enabled per project from the dashboard Search page.
This skill covers enabling them, filling and emptying the index, querying it, and embedding it.
For the platform overview load `quant-platform`.

## Applies to

Both platforms: QuantCDN (`https://dashboard.quantcdn.io`) and QuantGov (`https://dash.quantgov.cloud`).
Identify the platform by the dashboard URL only; ask the customer if you do not know it. The
search features are the same on both. Checked 2026-10 against the public docs,
`@quantcdn/quant-cli` 7.0.1 and `quantcdn/search-action` v2.1.0 (runs `quant` 7.0.1).

| | QuantCDN | QuantGov |
|---|---|---|
| Content API (records) | `https://api.quantcdn.io/v1` | `https://api.quantgov.cloud/v1` |
| `quant -e` value | `https://api.quantcdn.io/v1` (default) | `https://api.quantgov.cloud/v1` |
| search-action v2.1.0 `endpoint` | `https://api.quantcdn.io/v1` (default) | `https://api.quantgov.cloud/v1` (v2.0.0 took it without `/v1`) |
| Dashboard API (AI Search management) | `https://dashboard.quantcdn.io/api/v3` | `https://dash.quantgov.cloud/api/v3` |
| AI answers | Models from the Quant AI catalogue | Australian-resident models only |

For embed code, copy the snippet from your dashboard Search page and use the host it contains.

## Which product

| | Keyword search ("Quant Search") | AI Search |
|---|---|---|
| Matching | Keywords, with facets and filters | Meaning (semantic), natural-language questions, AI-written answers |
| Turn on | Subscription page: add Search to the organisation; Projects, Edit, tick "Enable Search" | Search page, "Enable AI Search" (needs a domain on the project) |
| Filled by | Content changes in the project, `quant search`, the search action, the Search API, CMS plugins | A crawler with "AI Search Integration", content pushed to the project, the AI Search API |
| Front end | Dashboard-built search pages (templates) | Chat widget, modal, search page script, or the public API |
| Cost | Bolt-on subscription per organisation (all its projects) | Billed on usage: page updates and AI answers; searches are not billed. No included allowance; the dashboard shows the rates when you enable it |

A project can have both. When AI Search is enabled, the dashboard Search page shows the AI view.
If the customer only says "add search", ask whether they want keyword search with filters (structured
content: recipes, news, a CMS) or AI answers. Do not guess. The rates for AI Search appear in the
dashboard when you press "Enable AI Search"; read them there and do not quote prices from memory.

## Keyword search

### Enable and configure

1. Add the Search subscription (dashboard, Subscription, Search, "Change plan").
2. Projects, Edit, tick "Enable Search", save.
3. Search, "Edit": set content extractors (XPath) only if the defaults are wrong. Defaults: `title` is the
   first `h1`, `content` is the meta `description`, `image` is `og:image`. A wrong extractor means
   records do not appear.

Once enabled, every content change in the project is tracked in the index, and unpublished or
deleted content is removed. Drupal and WordPress send tags, categories and content type
automatically (Drupal also sends taxonomy terms; add the vocabulary machine name to the facet list).
Static sites that build their own pages do not get facets unless they send records (below).

### Push your own records

Use this for more control than the extractors give, for example a staff directory. Each record is a
JSON object; `title`, `url` and `content` are required, `summary`, `image`, `categories`, `tags` are
optional:

```json
[
  {"title": "Jo Citizen", "url": "/staff/jo-citizen", "summary": "Policy officer",
   "content": "Jo works on ...", "tags": ["policy"], "categories": ["Staff"]}
]
```

```bash
quant search index --path records.json     # a file; the CLI checks title, url, content
quant search status                          # number of indexed documents
quant search unindex --path /staff/jo-citizen
quant search clear                           # removes every record
```

On QuantGov add `-e https://api.quantgov.cloud/v1` (or set `QUANT_ENDPOINT`). The CLI reads the
customer, project and token the same way as other `quant` commands (`quant-cli`).

Three ways to send records:

1. A JSON file with `quant search index --path` (above) or the search action (below).
2. `POST /search` on the content API with the same JSON array.
3. **With the page:** add a `search_record` object to the content payload of a `POST /v1` content push
   (`title`, `summary`, `content`, `image`, `categories`; all optional, extractors fill gaps). Use this
   when the build already pushes each page, so the record and the page stay together.

Records update independently of content: they are re-indexed even if the page body did not change.
Raw API calls and the facet call: [references/api.md](references/api.md).

### Facets, filters and search pages

An attribute is filterable only after the Search API is told about it:

```bash
curl -X POST "$ENDPOINT/search/facet" -H "Quant-Customer: $CUSTOMER" -H "Quant-Project: $PROJECT" \
  -H "Quant-Token: $TOKEN" -d '["categories", "tags"]'
```

`$ENDPOINT` is the content API from the table above. Then build a page: Search, "Create" under
search pages, pick a template, enter the search URL and optional title, tick the facets to show,
optionally add filters, then set facet position, tag display and custom CSS. The page is generated
as project content; edit it in the Content section to change the layout.

Filters limit a page to a subset, for example `content_type:"recipe"` or
`recipe_category:"Vegetarian" OR recipe_category:"Vegan"`. The field must exist on the records. Check
the results in the search preview before you publish the page. "Sort Order" rules (Search, Edit)
rank results after text relevance.

Keyword search has no documented public query endpoint. Query it through a dashboard search page.
Do not invent one. For a query API use AI Search.

### Index from CI

```yaml
      - name: Index search records
        uses: quantcdn/search-action@a714ca5316f148e934dca97caf8c4409e6092970 # v2.1.0
        with:
          customer: ${{ vars.QUANT_CUSTOMER }}
          project: ${{ vars.QUANT_PROJECT }}
          token: ${{ secrets.QUANT_TOKEN }}
          endpoint: https://api.quantgov.cloud/v1  # gov only; omit on QuantCDN
          operation: index                         # index | unindex | status | clear
          path: search/records.json                # one JSON file, not a directory
```

The action reads `path`. `index-path` and `unindex-path` are not inputs of v2 (older copies of the
README named them), so a workflow that uses them runs green and indexes nothing. From v2.1.0 `path`
for `index` is one JSON file: a directory prints a read error (`EISDIR`) and the step still passes.
Use one step per file. Read the log, then confirm with `operation: status` or `quant search status`. Pinning, secrets and gov values: `quant-ci-github-actions`.

## AI Search

### Enable and index

1. Prerequisites: an active project with a domain (or the preview domain; this is the base URL that
   is crawled and linked).
2. Search, "Enable AI Search". This creates the index; it is billed on usage (see above).
3. Fill it. Pick one or more:
   - **Crawler:** Crawler, Configs, edit the config, switch on "AI Search Integration", then run it
     (Run, All URLs) or schedule it. This is the normal way. Crawler setup (domain verification,
     50-page limit on unverified domains, include and exclude patterns, headless browser,
     schedules): `quant-domains-cache-purge` and https://docs.quantcdn.io/dashboard/crawler/.
   - **Content pushes:** content pushed to the project with the API or `quant` is indexed too.
   - **AI Search API:** send pages yourself (`POST .../ai-search/pages`), see
     [references/api.md](references/api.md).
4. Check: Search, Index tab lists indexed pages and dates; filter by URL. Search, Preview tab tests the
   widget and search page in light and dark themes.

Only pages that return `200` are indexed. Redirects, error pages and non-HTML assets are skipped.
Text is cleaned (navigation, footers), split into chunks and embedded. Cost follows page updates, so
a frequent crawl of a large site costs more than a weekly one.

### Re-index, remove, disable

- **Re-index:** run the crawler again. It updates existing entries and adds new ones. No purge first.
- **Remove pages:** Index tab, select pages, Delete; or delete by URL pattern (all pages under a path).
  The API takes `urls` and `patterns`.
- **Purge:** the Purge action empties the AI Search index; run the crawler to rebuild. For keyword
  search records you push yourself, `quant search clear` (or `DELETE /search/all`) removes every
  record; push them again to rebuild. A purge is only for a full wipe, never needed to re-index.
- **Disable:** "Disable" permanently deletes the index and everything in it. Enabling again needs a new
  crawl. Disable is not a pause.

### Embed

Copy the snippet from the dashboard (Search, embed section). Shape:

```html
<script src="https://EMBED-HOST/v1/widget.js" data-site-id="YOUR_SITE_ID"
        data-position="bottom-right"></script>
```

```html
<div id="quant-search"></div>
<script src="https://EMBED-HOST/v1/search-page.js" data-site-id="YOUR_SITE_ID"
        data-container="quant-search" data-theme="auto"
        data-show-ai-answer="true" data-results-limit="10"></script>
```

`EMBED-HOST` is the host in the snippet your dashboard shows. The site ID is on the Search
settings page. All attributes (chat widget, modal, search page), CSS variables, the iframe option and
the public API: [references/embed.md](references/embed.md). Do not invent other attributes.

### Settings before going live

Search, Settings. Public access is **off** for a new site until you enable it, and widgets and the
public API return 403 until then.

- Public access on, search on, chat on, anonymous sessions on or off.
- **Allowed domains:** one per line, `*` wildcard allowed (`example.gov.au`, `*.example.gov.au`).
  An empty list accepts any domain. Set the production hosts.
- **Display URL:** rewrites the domain of result and source links. Set it when content was crawled from
  a preview or internal host.
- **Rate limits:** per minute for searches, chat messages and per IP.
- **AI answer safety:** a level that screens questions; changing it needs the AI governance permission.

Public access lets anyone on the allowed domains use AI answers, which are billed.

### Query it

Public API (needs public access on; host from the dashboard):
`GET https://EMBED-HOST/v1/public/sites/{siteId}/search?q=your+query` and
`POST .../chat` with `{"message": "..."}`. Management API (dashboard API token as Bearer, `/api/v3`):
status, enable, disable, settings, pages, search, chat, crawls, usage, top queries. Parameters and
limits: [references/api.md](references/api.md). A semantic search body is `{"query": "...", "limit": 10}`
with `limit` at most 50.

For the model catalogue, chat inference and other AI services use `quant-ai`.

## Gov

QuantGov has the same search features. Differences are behaviour: use the gov hosts above, copy embed
snippets from `dash.quantgov.cloud`, and AI answers come from Australian-resident models only.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| Widget button shows, questions fail, network tab shows 403 | Public access is off, or the embedding host is not in Allowed domains | Search, Settings: enable public access, add the host |
| Index tab empty or short after a crawl | Only `200` HTML pages are indexed; 50-page limit on an unverified domain; JavaScript site; include/exclude patterns | Read the run in Crawler, Runs; verify the domain; enable the headless browser; fix patterns; rerun |
| Crawl runs but nothing reaches AI Search | "AI Search Integration" is off in that crawler config | Switch it on and rerun |
| Results link to a preview or other domain | Content was crawled from another host | Set Display URL; delete those pages by pattern; recrawl the real domain |
| Deleted page still in results | Index not updated | Keyword: `quant search unindex --path /url`; AI Search: delete the page in the Index tab; if a page you deleted from the site stays in the AI index, delete it there too |
| Keyword records missing | Wrong extractor, or a record missing `title`, `url` or `content` | Check Search, Edit extractors; run `quant search index` and read errors |
| `quant search index` works, action job green, nothing indexed | The workflow used `index-path` (v2 reads `path`), or `path` is a directory (v2.1.0 reads one file) | `path` = one JSON file; read the job log; `operation: status` |
| Action fails on gov | `endpoint` does not match the version: v2.1.0 needs `/v1`; v2.0.0 adds its own | v2.1.0: `https://api.quantgov.cloud/v1` |
| Facets not shown on the search page | Attribute not declared filterable | `POST /search/facet`, then pick the facet in the page |
| Filter shows too much or nothing | Field missing from the records, or a typo in the value | Check the field name on the records and the search preview |
| Cost higher than expected | Frequent crawls or many AI answers | Lower the crawl frequency; limit with rate limits and allowed domains |

## Further reading

- Keyword search: https://docs.quantcdn.io/dashboard/search/ and the records API https://docs.quantcdn.io/api/search/
- `quant search`: https://docs.quantcdn.io/content-cli/commands/search/
- AI Search: https://docs.quantcdn.io/ai/ai-search/get-started/ (also chat widget, search page, managing the index, settings)
- Crawler: https://docs.quantcdn.io/dashboard/crawler/
- Related skills: `quant-platform`, `quant-cli`, `quant-ci-github-actions`, `quant-domains-cache-purge`,
  `quant-cms-integrations`, `quant-ai`

<!-- checked against gh:quantcdn/search-action 2.1.0 -->
