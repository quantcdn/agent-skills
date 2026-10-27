# quant-rules-and-routing evals

Prompt: Our QuantCDN project (dashboard.quantcdn.io) has one rule today: a proxy rule with URL `*` that sends everything to our origin `https://origin.example.com`. I need to add: (1) every URL under `/blog/` to redirect permanently to the same path under `/news/` (so `/blog/2024/post` goes to `/news/2024/post`), and `/blog` itself to `/news`; (2) `/api/*` proxied to `https://api.example.com` keeping the full path. Tell me exactly what rules to add, the destination values, and where they go in the list.
Platform: public
Must include:
- The new rules must sit above the existing `*` proxy rule: rules are checked in order, the first match wins, and a proxy rule ends processing, so anything below it never runs
- `/blog/*` does not match `/blog` (a `*` needs at least one character), so `/blog` needs its own URL entry or rule
- Redirect destination `/news/$1` for `/blog/*` (`$1` is the text matched by the first `*`)
- For the API proxy, `https://api.example.com$*` (`$*` is the whole matched path, `/api/...`) or an equivalent `/api/$1`; `$1` is not the full path
- The query string is passed on to the redirect target or origin automatically when the pattern has no `?`
Must not include:
- A claim that the most specific rule wins regardless of order
- Regular-expression syntax such as `(.*)` or `^/blog` in the URL field

Prompt: We are on QuantGov (https://dash.quantgov.cloud). I want to manage our redirect rules with curl from CI. Yesterday I sent a PATCH to one redirect rule with `"url": ["/promo-2026"]` to add one more path, and the rule stopped matching the three paths it had before. What is the right API call, what credentials, and how do I add a path safely?
Platform: gov
Must include:
- The rules API is under `https://dash.quantgov.cloud/api/v2/organizations/{organization}/projects/{project}/rules/redirect` (and `/rules/redirect/{rule}` for one rule)
- Authenticate with `Authorization: Bearer <token>` using a dashboard API token with rules permissions (not the project `Quant-Token`)
- A PATCH that sends a list field (`url`, `domain`, `country_is`, `ip_is` and the others) replaces that whole list; send the complete list (read the rule first, then write it back with the new entry)
- Fields left out of the PATCH keep their current values
- A 409 response means another change to the project's rules is in progress; retry after a short wait
Must not include:
- `api.quantcdn.io` or `dashboard.quantcdn.io` for this customer
- `https://api.quantgov.cloud/v1` as the rules API base URL

Prompt: I added a redirect rule from `/old-page` to `/new-page` in the dashboard ten seconds ago. When I curl `/old-page` I still get a 200 with the old page. A colleague also says our second rule, a custom response for `/maintenance`, "never matches". The first rule in the list is a serve-static rule with URL `*`. What is going on and how do I test properly?
Platform: public
Must include:
- Rule changes are not instant; wait a few minutes before you judge the result
- A response already in the cache is served without checking the rules again; test with a cache-busting query string (for example `?cb=<random>`) or purge the path
- The query string does not change which rule matches (matching uses the path only), so a cache-busting parameter is safe to add
- The `*` serve-static rule at the top matches every path and ends processing, so every rule below it (the custom response, and the new redirect if it was added below) never runs; move the specific rules above it
Must not include:
- A claim that rules are applied instantly at every edge location
- A claim that the more specific `/maintenance` rule wins automatically

Prompt: We want a bot challenge for visitors from outside Australia who come from VPNs, cloud hosting or Tor. A colleague set up a bot challenge rule with `country_is_not: ["AU"]` and the traffic-source list filled in, but now Australians on home broadband are getting challenged too. Our Terraform for the rule has `country_is_not = ["AU"]`. What is wrong, how should the rule look, and how do I verify it?
Platform: public
Must include:
- `country`, `traffic_source`, `ip`, `method` (and `ua`) are mode fields: with the mode `any` (or unset), the matching list is ignored, so `country_is_not` alone does nothing; set `country = "country_is_not"` as well
- Conditions on one rule are combined with AND: the rule fires only when the country condition and the traffic-source condition both hold
- Terraform cannot set traffic source; set the traffic-source condition in the dashboard or with the rules API (`traffic_source: "traffic_source_is"` with `cloud`, `vpn`, `tor-exit`), or accept country-only scoping in Terraform
- Verify with a cache-busting request: a challenged request gets a 403 challenge page; a passed challenge sets the `quant_bot_verification` cookie
Must not include:
- A claim that filling in the list is enough to scope the rule
- A Terraform `traffic_source` argument presented as supported

Prompt: Our proxy rule sends `/app/*` to a slow origin. Three problems: (1) responses are never cached even though the origin sends `Cache-Control: public, max-age=600`; the rule has `cache_lifetime` set to "0"; (2) long reports fail with a Quant page that says "502 Proxy Error"; we set `origin_timeout` to "90" thinking seconds; (3) we would like Quant to serve the static copy we pushed when it exists and only go to the origin when it does not. How do we fix each one?
Platform: public
Must include:
- `cache_lifetime` "0" sets `Cache-Control: no-store` and replaces the origin header; leave it empty (or `-1`) to keep the origin's cache headers, or set a positive number of seconds
- `origin_timeout` is in milliseconds, so "90" is 90 ms; use "90000" for 90 seconds
- The "502 Proxy Error" page is Quant's own page when the origin does not answer in time or the connection fails; it is not from the origin
- `only_proxy_404` (dashboard "Only on 404") serves the Quant static content when it exists and proxies only when it does not
Must not include:
- A claim that `origin_timeout` is in seconds
- A claim that `cache_lifetime` "0" means "respect the origin headers"

Prompt: I ticked "Enable WAF" on our proxy rule through the API (`waf_enabled: true`) last week, but SQL-injection test requests still reach the origin and get a 200. Why, and how do I make the WAF block? Also, where do I see what it would have blocked?
Platform: public
Must include:
- The WAF runs only on proxy rules and only acts on what `waf_config` sets; `waf_enabled` alone does not block
- With no `waf_config` the WAF checks nothing; with no `mode` (or `mode: report`) it only logs hits
- Set `waf_config.mode` to `block` (start in `report`, review the WAF logs, add false-positive rule IDs to `allow_rules`, then switch)
- A blocked request gets a 403 (or 429 for a rate limit) with a `Quant-Waf-Rule` header; a custom block page goes at `/_quant_waf_403`
- WAF logs are in the dashboard (Security & WAF, WAF logs) or `quant waflogs`
Must not include:
- A claim that the WAF protects static content served without a proxy rule
- A vendor or cloud provider name

Prompt: We manage the WAF on our QuantCDN proxy rule with the rules API. Last month a PATCH that changed `allow_rules` switched off our IP rate limit. Now we want to (1) set the per-IP rate limit to 20 requests per second with a 60 second cooldown in block mode without touching the header rate limit, (2) turn the WAF off for a day and later back on with the same settings, and (3) add a condition so the rule ignores traffic from AS 13335. How do we do each through the API?
Platform: public
Must include:
- A PATCH keeps the stored rate limits unless it sends `waf_config.thresholds`; entries are merged by `type`, so sending only `{"type": "ip", "rps": 20, "cooldown": 60, "mode": "block"}` leaves the `header` and `waf_hit_by_ip` limits unchanged
- To turn one rate limit off, send its type with `mode: "disabled"`; invalid values (for example `rps` 0) return 400
- `waf_enabled: false` keeps `waf_config`; setting `waf_enabled: true` again restores the same settings
- The API takes `asn: "asn_is_not"` with `asn_is_not: ["13335"]` (AS numbers as strings); an invalid mode or value returns 422
Must not include:
- A claim that a PATCH always turns the rate limits off
- A claim that ASN conditions can be set only in the dashboard

