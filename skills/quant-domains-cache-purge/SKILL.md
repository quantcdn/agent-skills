---
name: quant-domains-cache-purge
description: Use when putting a custom domain on a QuantCDN or QuantGov project or debugging one - adding it (dashboard, `/api/v2` domains API, Terraform `quant_domain`), the DNS records (CNAME for subdomains, A records or ALIAS/ANAME for the apex), certificate states (QuantCDN issues after DNS points at Quant, "Renew"; QuantGov shows DNS-validation CNAME records, "DNS Validation Pending", "TLS Pending"), "Domain already exists", wildcard domains. Also use for how Quant caches a response (`Cache-Control`, `s-maxage`, `private`/`no-store`, `Surrogate-Control`, defaults, query strings, browser caching) and for purging - by path, `/*`, wildcard patterns, cache keys (`Cache-Keys`), soft purge, timing, what purges automatically, when to purge after a deploy or rule change - and for cache warming or the crawler as a static-copy tool (schedules, limits, domain verification). Not for rule fields (`quant-rules-and-routing`) or the crawler that fills a search index (`quant-search`).
---

# Domains, caching and purge on Quant

A project serves traffic for the domains attached to it. Quant caches responses at the edge and
keeps them until they expire or you purge them. This skill covers the domain lifecycle, the cache
headers Quant uses, purging, and the crawler. For the platform overview, load `quant-platform`.

## Applies to

Both platforms: QuantCDN (`https://dashboard.quantcdn.io`) and QuantGov (`https://dash.quantgov.cloud`).
Identify the platform by the dashboard URL only; ask the customer if you do not know it. Checked
2026-10 against the dashboard API (`/api/v2`), `@quantcdn/quant-cli` 7.0.1, `quantcdn/purge-action`
v7 and Terraform `quantcdn/quant` v5.14.

| | QuantCDN (public) | QuantGov |
|---|---|---|
| Domains API | `https://dashboard.quantcdn.io/api/v2` | `https://dash.quantgov.cloud/api/v2` |
| Purge (content API) | `https://api.quantcdn.io/v1` | `https://api.quantgov.cloud/v1` |
| Certificate | Issued automatically after DNS points at Quant; "Renew" button | You add DNS-validation CNAME records first; the dashboard may not show a "Renew" button |
| Apex record | A records (addresses shown in the dashboard) | ALIAS/ANAME to the host name shown in the dashboard |
| Wildcard domain `*.example.com` | Not allowed | Allowed, for the certificate only |
| `/blog/*` purge pattern | Not a wildcard (see Purge) | Purges every path under `/blog/` |
| Soft purge | Available | Not available; every purge removes content |
| Purge completes | A few seconds | Can take a few minutes |
| `Surrogate-Control` header | Honoured | Not honoured; use `Cache-Control: s-maxage` |

## Add a domain

Enter the host name only (`www.example.com`): no protocol, no path. Add every host you serve
(`example.com` and `www.example.com` are two domains).

- **Dashboard:** project, Domains, "Add domain". The page then shows the DNS records to create.
- **API** (dashboard API token, `Authorization: Bearer`):

  ```bash
  curl -s -X POST "$DASH/api/v2/organizations/$ORG/projects/$PROJECT/domains" \
    -H "Authorization: Bearer $QUANT_API_KEY" -H "Content-Type: application/json" \
    -d '{"domain":"www.example.com"}'
  ```

  `$DASH` is the bare dashboard host for the platform. `GET .../domains` and `GET .../domains/{id}`
  return `dns_engaged` (0 or 1), `dns_go_live_records` (traffic records) and, on QuantGov,
  `dns_validation_records`. More calls: [references/api.md](references/api.md).
- **Terraform:** one `quant_domain` per host. Provider `base_url` is the bare dashboard host
  (`https://dash.quantgov.cloud` on gov), never with `/api/v2`. Details: `quant-iac`.

  ```hcl
  resource "quant_domain" "www" {
    project = "my-project"
    domain  = "www.example.com"
  }
  ```

  A domain cannot be renamed: change `domain` and Terraform deletes and re-creates it. The resource
  exports `dns_engaged`; read the DNS records from the dashboard or the API.

Rules that apply on both platforms:

- **A host name can belong to only one project** in Quant. Adding it to a second project fails with
  "Domain already exists." Use another host for staging (`staging.example.com`) or the project's
  preview domain, or delete the domain from the first project.
- Every project has a **preview domain** for testing before DNS changes. It sends a `robots.txt`
  that blocks search engines and can be password protected.
- Deleting a domain that has DNS pointed at Quant stops it working at once.
- Quant redirects HTTP to HTTPS. Add HSTS with a custom headers rule if you want it.

## DNS records

Create the records the dashboard Domains page (or `dns_go_live_records`) shows for **your**
project. Do not copy targets from another project, a blog post or another platform.

| Host | QuantCDN | QuantGov |
|---|---|---|
| Subdomain (`www`) | CNAME to the target shown | CNAME to the target shown |
| Apex (`example.com`) | A records with the addresses shown (several) | ALIAS or ANAME (a flattened CNAME) to the target host shown |

- An apex cannot hold a CNAME. On QuantGov the target is a host name, so the apex needs a DNS
  provider that supports ALIAS/ANAME (Quant DNS does). If yours does not, serve the site on `www`
  and redirect the apex at your DNS provider.
- If the zone is hosted in Quant DNS with **CDN integration** enabled, Quant creates the traffic and
  validation records itself. The dashboard shows "Auto-Managed" (QuantCDN) or "DNS & TLS
  automatically configured" (QuantGov).
- Lower the TTL of the old records a day before the cutover so the change spreads fast.

## Certificates

Quant provisions and renews certificates for custom domains at no charge. How it starts differs.

**QuantCDN.** The certificate is requested only after Quant sees your DNS pointing at it.

1. Add the domain. Status "DNS Not Engaged"; a newly added domain can also show "Ready for TLS".
2. Create the CNAME or A records. When Quant detects them, the status becomes "DNS Engaged" and the
   certificate is issued. This normally takes minutes.
3. Right after a cutover, HTTPS can fail until the certificate exists. Press **Renew** on the
   domain (or `POST .../domains/{id}/renew`, which returns 202) to request it now.
4. You can upload your own certificate and key instead ("Custom SSL Certificate" when you add or
   edit the domain). Without one, Quant provisions a free certificate.

**QuantGov.** The certificate needs DNS validation first, so you can finish it **before** you move
traffic.

1. Add the domain. After a short wait the Domains page shows "DNS Validation Pending" and "Required
   CNAME records" (name and value); the API returns them as `dns_validation_records`.
2. Create those CNAME records exactly as shown, at the DNS provider for that zone. Keep them: they
   are also used for renewals.
3. The status moves to "TLS Pending" (shown as "Certificate Pending Issuance", "Certificate Pending
   Deployment" or "Propagating") and then "Active".
4. Only then point traffic (the CNAME or ALIAS above) at Quant. The site has a valid certificate
   from the first request, so the cutover has no certificate error.
5. "Dns Validation Failed" or "Validation Timed Out": the validation record is missing or wrong
   (a common mistake is a provider that appends the zone name, giving `_abc.example.com.example.com`).
   Fix it with `dig CNAME <name>`; if the status does not recover, contact Quant support.

`*.example.com` on QuantGov covers the certificate only. Add each subdomain as its own domain so
it routes.

## How Quant caches

Quant caches each response at the edge by path **including the query string**, and keeps it until it
expires or is purged. A path purge clears that path for every domain of the project. Check what a path sends with `curl -sI https://www.example.com/path`.

| Response | Edge behaviour |
|---|---|
| `Cache-Control: s-maxage=N` | Edge keeps it N seconds; browsers use `max-age` |
| `Cache-Control: public, max-age=N` (no `s-maxage`) | Edge and browsers keep it N seconds |
| `Cache-Control: private` or `no-store` | Not cached at the edge |
| `Surrogate-Control: max-age=N` | QuantCDN only. QuantGov ignores it: use `s-maxage` |
| `Cache-Keys: a b` | Tags the response for purge by key (removed before the browser sees it) |

Defaults when nothing sets `Cache-Control`:

- Deployed static pages and files: Quant applies a long edge lifetime and relies on purges (every
  change through the content API purges the path). Check the actual header with `curl -sI`.
- Files can also be cached by browsers, and **a purge does not reach browsers.** Use fingerprinted
  file names (`app.3f9a1c.js`) for anything that changes.
- Proxied responses: the origin's `Cache-Control` is used. Do not rely on a platform default when
  the origin sends none; set the header, or set the proxy rule's cache lifetime.
- Edge functions: `Cache-Control: private, max-age=0` unless the function sets one
  (`quant-edge-functions-and-kv`).

Proxy rule cache lifetime (`cache_lifetime`, details in `quant-rules-and-routing`): empty or `-1`
keeps the origin header; `"0"` sets `no-store`; `"600"` replaces the origin header with
`public, max-age=600`. Error pages can be cached for up to 5 minutes.

Query strings: `/news` and `/news?page=2` are separate entries. Purging `/news` leaves
`/news?page=2` cached.

## Purge

| Tool | Path | Cache keys | Soft |
|---|---|---|---|
| `quant purge` (project token; gov: endpoint `https://api.quantgov.cloud/v1`) | `quant purge /about`, `quant purge "/*"` | `quant purge --cache-keys "a b"` | `--soft-purge` |
| `quantcdn/purge-action@v7` | `url_pattern: "/*"` | `cache_keys: "a b"` | `soft_purge: true` |
| Content API `POST {content API}/purge` | header `Quant-Url: /about` | header `Cache-Keys: a b` | header `Soft-Purge: true` |
| Dashboard, project, Purge Cache (a role that can edit projects) | URL path field | Cache keys field | toggle (QuantCDN) |

Paths and patterns:

- Give a **path** starting with `/`, no host name. One project's purge never affects another project.
- `/*` purges the whole project on both platforms. Quote it in a shell: `"/*"`.
- **QuantCDN:** `/*` is the only wildcard. `/blog/*` is purged as the literal URL `/blog/*`, which
  clears nothing under `/blog/`, and the command still reports success. (Some older projects show
  "Wildcards are supported" on the Purge Cache page; only those accept prefix patterns.)
- **QuantGov:** a trailing `*` works as a prefix: `/blog/*` purges every path under `/blog/`.
- For a group of pages on either platform, use **cache keys**: the origin (or a custom headers rule)
  sends `Cache-Keys: section:blog env:prod`, then `quant purge --cache-keys "section:blog"`. Keys
  match exactly (no prefixes); there is no API that lists keys.

Soft purge (QuantCDN only; the dashboard toggle is on by default) marks the content stale instead of removing it: Quant fetches a fresh copy
on the next request but can still serve the stale copy if the origin fails. Use a normal purge when
the old content must disappear (legal removal, leaked data). On QuantGov the option is absent or
ignored and every purge removes the content.

Timing: a 200 response means the purge was **accepted**, not finished.
Purges are batched and complete within seconds on QuantCDN and can take a few minutes on QuantGov.
Recheck with `curl -sI` (look at `age`) after a short wait. Errors: 400 without `Quant-Url` and
`Cache-Keys`; 403 when the token does not match the customer and project.

## When to purge

- **Automatic:** `quant deploy`, `quant page`/`quant file`, `quant publish` and `quant unpublish`
  (and the dashboard editor) purge each path they change. Unchanged paths are not purged.
- **After a deploy:** pages that did not change but show changed shared content (menus, footers,
  listings) stay cached. Run `quant purge "/*"` or `purge-action` with `url_pattern: "/*"` after
  the deploy, as Quant templates do. See `quant-static-sites` and `quant-ci-github-actions`.
- **After a rule change:** rules run only on a cache miss and a rule change purges nothing. Purge
  the affected paths (or test with `?cb=$RANDOM`). See `quant-rules-and-routing`.
- **After changing cache headers** at the origin or a proxy cache lifetime: purge, or the old
  lifetime stays in force until it expires.
- **Proxied app content changed** (a CMS publish): purge the paths or keys the change touched. The
  Drupal and WordPress modules do this (`quant-cms-integrations`).

## Cache warming and the crawler

Quant has no cache-warming feature. After a full purge, the first request for each path fetches it
again. To warm the busiest pages, request them yourself at a modest rate, for example:

```bash
curl -s https://www.example.com/sitemap.xml | grep -o '<loc>[^<]*' | sed 's/<loc>//' |
  head -200 | while read -r u; do curl -s -o /dev/null "$u"; sleep 0.2; done
```

Prefer targeted purges (paths or cache keys) to nightly `/*` purges: they keep the rest of the cache warm.

**The Quant crawler is not a cache warmer.** It fetches a website (the domain in its configuration,
usually your origin) and stores each page and asset as static content in the project: a static copy
for archive, failover or static serving. It purges the paths it changes. For a crawler that fills a
**search index**, use `quant-search`.

- Create it in the dashboard (Crawler, Configs), with the API (`POST .../crawlers`) or Terraform
  (`quant_crawler`). Run it from the dashboard, `qc crawler run <uuid>` or `POST .../crawlers/{uuid}/run`
  (optional `urls`); a 409 means a run is already active.
- **Schedules:** dashboard Crawler, Schedules; Terraform `quant_crawler_schedule`; or the API, with a
  5-field cron expression in **UTC** (02:00 in Sydney is `0 16 * * *` under AEST and `0 15 * * *`
  under AEDT):

  ```bash
  curl -s -X POST "$DASH/api/v2/organizations/$ORG/projects/$PROJECT/crawlers/$UUID/schedules" \
    -H "Authorization: Bearer $QUANT_API_KEY" -H "Content-Type: application/json" \
    -d '{"name":"Nightly","schedule_cron_string":"0 16 * * *"}'
  ```
- **Limits** until you verify the domain (DNS TXT record or a file, from the Domain verification
  column of the config): 50 pages per crawl, 20 starting URLs, 2 workers, 4-second delay. Verified:
  up to 20 workers, delay 0 to 10 seconds, page and request limits you set.
- `include` and `exclude` are **regular expressions** (`^/admin`, `\.pdf$`), not globs.

Full field list and API calls: [references/api.md](references/api.md).

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| "Domain already exists" | The host is attached to another project (any organisation) | Use another host, the preview domain, or delete it from the other project |
| QuantGov domain stays "DNS Validation Pending" | Validation CNAME missing or doubled zone name | `dig CNAME <name>` must return the value shown; fix at the DNS provider |
| QuantCDN certificate error after cutover | Certificate is issued only once DNS points at Quant | Check `dig`; wait for "DNS Engaged"; press Renew |
| QuantGov apex will not accept the record | CNAME at the apex | ALIAS/ANAME, or Quant DNS, or redirect the apex to `www` |
| "Wildcard domains are only supported..." on QuantCDN | Wildcards are QuantGov-only | Add each host name |
| `quant purge "/blog/*"` succeeds but nothing changes (QuantCDN) | Only `/*` is a wildcard | Cache keys, `/*`, or each path |
| `/news?page=2` stale after purging `/news` | Query variants are separate entries | Purge the exact URL, use a key, or `/*` |
| Purge "succeeded" but `curl` still shows old content | Purge is asynchronous; or a browser cache | Wait and recheck with `curl -sI`; a purge does not clear browser caches |
| Purge returns 401 or 403 on QuantGov | Public endpoint default | `https://api.quantgov.cloud/v1` (`quant -e`, purge-action `endpoint`) |
| Proxied pages never cached | `Cache-Control: private` or `no-store` from the origin, or cache lifetime `"0"` | Send `public, s-maxage=N`, or set a positive cache lifetime |
| `Surrogate-Control` ignored on QuantGov | Not honoured there | `Cache-Control: s-maxage=N` |
| Rule change has no effect | Cached response; rules run only on a miss | Purge the paths |
| Crawl stops at 50 pages | Domain not verified | Verify the domain in the crawler config |

## Further reading

- Domains: https://docs.quantcdn.io/dashboard/domains/
- Purge with the API, the dashboard and cache keys: https://docs.quantcdn.io/purge/via-api/,
  https://docs.quantcdn.io/purge/via-dashboard/, https://docs.quantcdn.io/purge/using-cache-keys/
- `quant purge`: https://docs.quantcdn.io/content-cli/commands/purge/
- DNS zones and CDN integration: https://docs.quantcdn.io/dns/overview/
- How Quant caches: https://docs.quantcdn.io/purge/cache-behaviour/
- Crawler: https://docs.quantcdn.io/dashboard/crawler/
- Related skills: `quant-platform`, `quant-cli`, `quant-ci-github-actions`, `quant-static-sites`,
  `quant-rules-and-routing`, `quant-edge-functions-and-kv`, `quant-iac`, `quant-search`,
  `quant-cms-integrations`

<!-- checked against npm:@quantcdn/quant-cli 7.0.1 -->
<!-- checked against gh:quantcdn/purge-action 7.0.0 -->
