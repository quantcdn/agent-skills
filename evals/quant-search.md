# quant-search evals

Prompt: Our marketing site is a Hugo static site on QuantCDN (dashboard.quantcdn.io), deployed with `quant deploy`. We want on-site keyword search with a search page that has filters for the `categories` and `tags` of each post. Some pages (a staff directory built by our build script) must be searchable with our own title and summary text, not whatever the HTML gives. Tell me what to enable, how records get indexed, how to push the custom records from a JSON file and from CI, how to make `categories` and `tags` filterable, and how to check the index.
Platform: public
Must include:
- Search is a bolt-on subscription managed per organization (Subscription page), then "Enable Search" is ticked on the project (Projects, Edit); after that content changes are tracked in the index automatically and unpublished or deleted pages are removed
- Custom records: a JSON array in which each record needs `title`, `url` and `content`; optional `summary`, `image`, `categories`, `tags`; pushed with `quant search index --path records.json` (or `POST /search` on the content API with the `Quant-Customer`, `Quant-Project` and `Quant-Token` headers)
- A static site does not get `categories` or `tags` automatically (Drupal and WordPress send them), so the pushed records must carry them
- Facets: `categories` and `tags` must be declared as filterable, with `POST /search/facet` and a JSON array of attribute names (or the Facets list in the dashboard Search edit page); then choose them as facets when creating the search page under Search, Create (pick a template)
- CI: `quantcdn/search-action` (v2) with `operation: index` and the input named `path` (one JSON file), not `index-path`
- Check with `quant search status`, which prints the number of indexed documents
Must not include:
- The name of any search engine vendor or product
- `index-path` or `unindex-path` as inputs of search-action v2
- An invented query endpoint for keyword search

Prompt: We are on QuantGov (https://dash.quantgov.cloud). We want AI-powered search with answers on a public site, indexed from our own domain, plus a GitHub workflow that pushes some extra records after each deploy. Give me the steps, the embed code, the settings we must change before going live, and the exact `endpoint` value for the search action. Is anything different for us because we are on gov?
Platform: gov
Must include:
- Enable with Search, "Enable AI Search" in the QuantGov dashboard; the project needs a domain (the base URL that is crawled), and the index fills when a crawler with the "AI Search Integration" option runs (or content is pushed to the project, or pages are sent with the AI Search API)
- Embed: copy the script snippet from the dashboard Search page (use the host in the snippet; it carries your site ID); the script is `widget.js` (floating chat button) or `search-page.js` with a container element and `data-site-id`, `data-container`, `data-theme`, `data-show-ai-answer`, `data-results-limit`
- Before going live: turn on public access in Settings, and set Allowed domains to the production hosts (an empty list accepts any domain); rate limits can be set
- search-action v2.1.0 on QuantGov: `endpoint: https://api.quantgov.cloud/v1`, the same value `quant` 7.0.1 uses (v2.0.0 ran CLI 2.0.0 and took it without `/v1`)
- The extra records from the action go to the keyword search index (`quant search` records), not into the AI Search index
- Gov difference is behaviour only: QuantGov is IRAP assessed and AI answers use Australian-resident models; the search features themselves are the same
Must not include:
- `https://api.quantgov.cloud` without `/v1` as the search-action v2.1.0 `endpoint`
- `dash.quantcdn.io` or `api.quantcdn.io`
- A script host typed from memory instead of the one in the dashboard snippet

Prompt: Our AI search widget (we pasted the script from the docs) shows the button but every question returns an error, and the browser network tab shows 403 from the search service. After a crawl, the Index tab shows only 40 pages although the site has 300, and the links in the results point at `https://preview-xyz.example-preview.net/...` instead of our real domain. What do I check, in order, and how do I fix each?
Platform: public
Must include:
- 403 on the widget calls: public access is off for the site by default; enable it in Search, Settings, and put the embedding host in Allowed domains (one per line, `*` wildcard allowed); the `allowedDomains` list must include the real site host
- Only pages that return a `200` status code are indexed; redirects, error pages and non-HTML assets are skipped; check the crawler run (Crawler, Runs) for errors, include and exclude patterns, the 50-page limit on an unverified domain, and a JavaScript-rendered site that needs the headless browser option
- Links to the wrong domain: set "Display URL" in the AI Search settings (it rewrites the domain of result and source links), or crawl the real domain; delete the bad pages from the Index tab (by URL or URL pattern) and re-crawl
- Re-index by running the crawler again; no purge is needed first
- Look at the Index tab (search by URL) to verify what is in the index
Must not include:
- Advice to purge the whole index as the first step
- A claim that the crawler warms the cache

Prompt: A product manager asks: "Can we just switch AI Search on for the whole site, crawl it every hour, and turn it off again for a month over summer?" What does it cost and what happens to the index when we disable it? Also, one old page `/news/2019/old` is still returned in results after we deleted it. How do I remove just that page, and how do I wipe and rebuild everything?
Platform: public
Must include:
- AI Search is billed on usage: page updates and AI answers are charged, searches are not; there is no included allowance; the rates are shown in the dashboard when you enable it; cost grows with crawl and publish frequency, so an hourly crawl of a large site costs much more than a weekly one
- Disabling AI Search permanently deletes the search index and all indexed content; enabling again needs a new crawl
- Remove one page: Search, Index tab, select it and Delete (or delete by URL or URL pattern); in keyword search use `quant search unindex --path /news/2019/old` or `DELETE /search` with the `Quant-Url` header
- Wipe: Purge in the Index tab for AI Search, `quant search clear` (or `DELETE /search/all`) for keyword search; then run the crawler again or push the records again
- Re-indexing does not need a purge first
Must not include:
- A claim that disabling only pauses billing and keeps the index
- A price in dollars stated as fact

Prompt: I use the search-action README example in my workflow: `operation: index` with `index-path: search/` and the token inline. The job is green but nothing appears in search. Our org is on QuantCDN. Also what filter syntax can I use on a dashboard search page to show only recipes in category Vegan or Vegetarian?
Platform: public
Must include:
- Released search-action v2 takes `path` (one JSON file from v2.1.0); `index-path` and `unindex-path` from older README copies are not inputs, so the path is empty and nothing is indexed even though the job passes
- The token comes from a secret (`${{ secrets.QUANT_TOKEN }}`), and `customer` and `project` are required; pin the action to the commit SHA for v2.1.0 (a714ca5316f148e934dca97caf8c4409e6092970)
- A `path` the CLI cannot read (a directory or a missing file) prints an error and the step still passes, so read the job log; confirm with `quant search status`
- Search page filters (Search, Create, Filtering) are `field:value` clauses such as `content_type:"recipe"`; an OR of two clauses is shown as `recipe_category:"Vegetarian" OR recipe_category:"Vegan"` in the docs, and the field must exist on the records; check the results in the search preview
Must not include:
- The name of any search engine vendor or product
- `index-path` presented as a working input
