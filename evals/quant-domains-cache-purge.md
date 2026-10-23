# quant-domains-cache-purge evals

Prompt: We are on QuantGov (https://dash.quantgov.cloud). Our Terraform already manages the project. Add `www.example.gov.au` and the apex `example.gov.au` to the project with Terraform, tell me exactly which DNS records we must create at our own DNS provider, and explain why the dashboard says the certificate is pending. We want no downtime when we switch traffic from the old host.
Platform: gov
Must include:
- One `quant_domain` resource per host name (`domain` and `project`), with the provider `base_url` set to the bare dashboard host `https://dash.quantgov.cloud`
- On QuantGov each new domain shows DNS-validation CNAME records (dashboard Domains page, or `dns_validation_records` from the domains API); the certificate is issued only after you create them, and until then the status shows DNS validation pending
- Create the validation records first, before you move traffic: the certificate can be issued while the old host still serves the site, which avoids a certificate error at cutover
- Traffic records: a CNAME for `www` to the target the dashboard (or `dns_go_live_records`) shows, and for the apex an ALIAS/ANAME (flattened) record to that same host name, because the apex cannot be a CNAME
- The status moves through validation and TLS pending to Active; check with `dig` and `curl -sI https://www.example.gov.au/`
Must not include:
- Names a certificate authority, cloud vendor or managed service
- A "Renew" button or uploading your own certificate as the gov fix
- A specific CDN target host name or IP address invented by the answer
- `dashboard.quantcdn.io` or `/api/v2` in the Terraform `base_url`

Prompt: Our static site is on QuantCDN (dashboard.quantcdn.io). After the last deploy, pages under `/blog/` still show old posts, so I ran `quant purge "/blog/*"` and it said "Successfully purged /blog/*", but nothing changed. I also purged `/news` but `/news?page=2` is still old. What is going on, what should I run instead, and should I use soft purge?
Platform: public
Must include:
- On QuantCDN only `/*` (the whole project) is a wildcard; any other path is purged as that exact URL, so `/blog/*` purges nothing under `/blog/` (unless the dashboard Purge page says wildcards are supported for the project)
- To purge a group of pages, tag them with cache keys (a `Cache-Keys` response header) and purge by key (`quant purge --cache-keys`), or purge `/*`; or purge each path
- Each query-string variant is a separate cache entry: purging `/news` does not purge `/news?page=2`; purge that exact URL, use a cache key, or purge `/*`
- A purge is asynchronous: success means the request was accepted, and the cache clears a few seconds later; check again with `curl -sI`
- Soft purge marks content stale instead of removing it, so Quant can still serve the old copy if the origin is down; for content you want gone at once, use a normal purge
Must not include:
- A claim that `/blog/*` purges every page under `/blog/` on QuantCDN
- A claim that a successful purge response means the cache is already empty

Prompt: We run a Next.js app on QuantGov (dash.quantgov.cloud) behind a Quant proxy rule. Pages are either never cached or stale for a long time. Our app sends `Surrogate-Control: max-age=600` and `Cache-Control: no-cache`. Which cache headers does Quant use, what do the defaults look like, how does the proxy rule's cache lifetime interact, and how do I clear the cache after I fix it? We also want soft purges so the site stays up.
Platform: gov
Must include:
- Quant uses `Cache-Control`: `s-maxage` sets how long the edge keeps a response and `max-age` sets browsers (and the edge when there is no `s-maxage`); `private` or `no-store` means not cached at the edge
- Do not rely on `Surrogate-Control`; it is not honoured on QuantGov. Send `Cache-Control: public, s-maxage=600` (or similar) instead
- The proxy rule's cache lifetime: empty or `-1` keeps the origin's `Cache-Control`, `0` sets `no-store`, a positive number sets `public, max-age=N` and replaces the origin header
- A rule change does not purge cached responses; purge after the change (`quant purge` with the gov endpoint `https://api.quantgov.cloud/v1`, purge-action, or the dashboard)
- On QuantGov soft purge is not available: every purge removes the content, and a purge can take a few minutes to complete
Must not include:
- A claim that `Surrogate-Control` is honoured on QuantGov
- `api.quantcdn.io` for this customer
- CDN or cloud vendor names

Prompt: Every night our CI purges `/*` on our QuantCDN project (dashboard.quantcdn.io). Can I use the Quant crawler to warm the cache afterwards? If not, what should I do instead? Separately, we already have a crawler config (UUID in `$UUID`) that keeps a static copy of our old site in the project. Schedule it with the API, not the dashboard, to run at 02:00 Sydney time every day, and tell me why it only ever captures 50 pages.
Platform: public
Must include:
- The crawler fetches a site (the domain in its configuration) and stores the pages as static content in the project (a snapshot); it is not a cache-warming tool, and Quant has no separate cache-warming feature
- To warm after a purge, request the important URLs yourself (for example `curl` over the sitemap URLs); warm only what matters and keep the request rate modest
- Crawler schedules use a 5-field cron expression in UTC: `POST https://dashboard.quantcdn.io/api/v2/organizations/{organization}/projects/{project}/crawlers/{crawler}/schedules` with `schedule_cron_string`, and Bearer API token auth
- 02:00 in Sydney is not a fixed UTC hour because of daylight saving: `0 16 * * *` (UTC) while Sydney is on AEST and `0 15 * * *` while it is on AEDT; change the schedule twice a year or accept a one-hour shift
- Unverified crawler domains are limited (50 pages, 2 workers, 4-second delay); verify the domain with a DNS TXT record or a file to raise the limits
Must not include:
- A claim that the crawler warms the edge cache for visitors
- An invented crawler or warming endpoint
- `api.quantcdn.io/v1` as the crawler API host

Prompt: On QuantCDN I added `shop.example.com` to our production project and set the CNAME the dashboard showed. Two hours later browsers show a certificate error on https://shop.example.com. Also, I tried to add the same `shop.example.com` to a second project for staging and got "Domain already exists". And can I add `*.example.com` so all subdomains work?
Platform: public
Must include:
- On QuantCDN the certificate is issued automatically only after DNS points at Quant; the dashboard shows "DNS Engaged" once Quant sees the record ("DNS Not Engaged" before that)
- Check DNS (`dig shop.example.com`) resolves to the target the dashboard shows; if it does and the error stays, press "Renew" on the domain in the dashboard (or `POST .../domains/{domain}/renew` on `/api/v2`) to request the certificate now
- A host name can belong to only one project in Quant; use a different host name for staging (for example `staging.example.com`), or the project's preview domain, or delete it from the first project
- Wildcard domains such as `*.example.com` cannot be added on QuantCDN; add each host name
Must not include:
- A DNS-validation CNAME step as the cause on QuantCDN
- Advice to add the same host name to two projects
