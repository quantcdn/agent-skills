---
name: quant-rules-and-routing
description: Use when writing, ordering or debugging project rules on a QuantCDN or QuantGov project - redirects, proxies to an origin, custom response headers, basic auth, custom responses, serve static content, edge function, auth and content filter rules, bot challenge, error pages and the WAF on a proxy rule. Covers how a request is matched (first match wins, which actions end processing, path-only case-insensitive URL patterns, `*`, `$*` vs `$1`, mode fields such as `country` that make a list count), proxy settings (`cache_lifetime`, `origin_timeout`, `only_proxy_404`, the Quant "502 Proxy Error" page), WAF modes, bot challenge scoping, managing rules from the dashboard, the rules API, `quant rules`/deploy-action and Terraform/Pulumi, and testing a change (propagation, cache-busting). Also use when a rule "never matches", a redirect does not fire, Australians get a bot challenge, or the WAF does not block.
---

# Rules and routing on Quant

Project rules decide, for each request, what Quant does before it serves the project's static content:
redirect, proxy to an origin, add headers, ask for a password, return a fixed response, run a
function, show a bot challenge, or block with the WAF. For the platform overview, load `quant-platform`.

## Applies to

Both platforms: QuantCDN (`https://dashboard.quantcdn.io`) and QuantGov (`https://dash.quantgov.cloud`).
Rules behave the same on both. Only the host you call changes. Checked 2026-10-24 against the dashboard
API (`/api/v2`, specification 4.26.0), the edge runtime, `@quantcdn/quant-cli` 7.0.2,
`quantcdn/deploy-action` v7.0.1 and Terraform `quantcdn/quant` v5.14.

| | Public | Gov |
|---|---|---|
| Rules page | `https://dashboard.quantcdn.io` (project, Rules) | `https://dash.quantgov.cloud` (project, Rules) |
| Rules API base | `https://dashboard.quantcdn.io/api/v2` | `https://dash.quantgov.cloud/api/v2` |

Ask for the dashboard URL if you do not know the platform. The content API (`api.quantcdn.io/v1`,
`api.quantgov.cloud/v1`) does not manage rules.

## How a request is matched

1. Quant reads the project's rules **in list order**: the order on the dashboard Rules page, which is
   the `weight` order (lowest first). Disabled rules are skipped.
2. A rule matches only when **all** its conditions hold (AND): domain, country, traffic source, user
   agent, cookie, method, URL, IP and ASN.
3. The **first matching rule whose action ends processing produces the response**. Nothing below it runs.
   The most specific rule does not win; the first one does.
4. If no rule ends processing, Quant serves the project's static content for the path, with any
   headers that earlier rules added.

| Action | Ends processing? |
|---|---|
| Redirect, Proxy, Custom response, Serve static content, Edge function | Yes, always |
| Basic auth | Only when the credentials are missing or wrong (401). Correct credentials continue |
| Bot challenge | Only while the visitor has not passed (403 challenge page). A passed visitor continues |
| Auth function | When the function answers with any status except 201, or cannot run (503). See `quant-edge-functions-and-kv` |
| Custom response headers | No. Adds headers and continues |
| Content filter | No. Attaches a filter to the final response and continues. If the function cannot run, the filter is skipped |
| Error page | Not checked in normal flow. Used only when Quant builds an error response |

Consequences:

- Put every specific rule **above** a catch-all (`*`) proxy or serve-static rule. A rule below a
  matching proxy rule never runs.
- A headers rule must sit **above** the rule that ends processing, or its headers are never added.
- To make one path always work (for example `/.well-known/*`), put an ending rule for it at the top.

## URL patterns

- The pattern is matched against the **path only**. The query string is ignored, so `/search` matches
  `/search?q=x`. Exception: a pattern that contains `?` is matched against path and query string.
- Matching is **case-insensitive** and covers the **whole path**: `/about` does not match `/about/team`.
- `*` matches **one or more** characters of any kind, including `/`. `/blog/*` matches `/blog/a/b` but
  **not** `/blog` or `/blog/`. Add `/blog` as a second URL on the rule (a rule takes a list of URLs).
- Every other character is literal. Do not use regular expressions (`(.*)`, `^`, `$`).
- `*` alone matches every path.
- Domains: `any`, or a list of exact host names (case-insensitive). List each host; `*.example.com`
  is not a wildcard.

## Destinations: `$*` and `$1`

Redirect and proxy destinations take placeholders. Quant uses the destination **exactly as written**;
it does not append the request path for you.

| Placeholder | Value for `/api/*` and request `/api/v1/users?page=2` |
|---|---|
| `$*` | The whole matched path: `/api/v1/users` |
| `$1` to `$5` | The text matched by the 1st to 5th `*`: `$1` = `v1/users` (no leading slash) |

- The query string is added to the destination automatically (`?page=2` above), unless the URL
  pattern itself contains `?`.
- A pattern with no `*` has no `$1`. `$1` then stays in the destination as the literal text `$1`.
  For exact paths, or several URL patterns on one rule, use `$*`.
- A proxy `to` with no placeholder (`https://origin.example.com`) sends every matched request to the
  origin's `/`. To keep the path: `https://origin.example.com$*`.
- Examples: `/blog/*` to `/news/$1`; `/blogs/*/category/*` to `/categories/$2/$1`; `*` to `https://origin.example.com$*`.

## Mode fields: the list counts only when the mode names it

`country`, `traffic_source`, `ua`, `ip`, `asn` and `method` are **mode fields**. Each is `any` or the name of
the list to test. With `any` (or unset), the list is **ignored**.

| You want | Set |
|---|---|
| Only visitors outside Australia | `country: "country_is_not"`, `country_is_not: ["AU"]` |
| Only GET and HEAD | `method: "method_is"`, `method_is: ["GET", "HEAD"]` |
| Everyone except an office network | `ip: "ip_is_not"`, `ip_is_not: ["<CIDR>"]` |

`country: "any"` with `country_is_not: ["AU"]` matches **every** country. A filled-in list with mode
`any` usually means someone meant to scope the rule and did not set the mode.

- Country, traffic source and user agent conditions make Quant cache per value (`Vary`). An IP
  or ASN condition makes the response `Cache-Control: private`, so it is not cached. Use IP rules on
  small areas such as admin paths.
- `only_with_cookie` matches a cookie **name**; `*` is allowed (`SSESS*`, `wordpress_logged_in_*`).
  Through the API, write it as `cookie_name` (an empty string clears it); GET returns `only_with_cookie`.
- The rules API sets `traffic_source`, `ua` and `asn` on **every** rule type, with the same mode
  rule (`any`, `<name>_is`, `<name>_is_not`). Traffic source values: `cloud`, `vpn`, `tor-exit`,
  `abuser`, `crawler`. AS numbers are positive integers up to 4294967295, sent as strings. User agent
  entries are at most 255 characters. An invalid value returns **422**.
- Terraform and Pulumi do not take traffic source or user agent. Manage a rule that needs them in the
  dashboard or with the rules API, not in Terraform.

## Bot challenge scoping

A challenge rule with no conditions challenges **everyone**. To challenge only suspicious traffic
from outside Australia, set both conditions on the one rule (they are combined with AND):

- Traffic source: mode "is one of" with cloud / hosting providers, VPN services, Tor exit nodes and
  known abusers (dashboard).
- Country: `country: "country_is_not"`, `country_is_not: ["AU"]`.

Through the rules API the same rule is `traffic_source: "traffic_source_is"`,
`traffic_source_is: ["cloud", "vpn", "tor-exit", "abuser"]`, `country: "country_is_not"`,
`country_is_not: ["AU"]`. Terraform and Pulumi cannot set traffic source, so keep this rule in the
dashboard or the API, not in Terraform. If Terraform must own it, scope it by country only.

With only the traffic-source condition, Australian visitors on a VPN or a corporate cloud network are
challenged too. A challenged request gets a **403** challenge page (`Cache-Control: no-store`). The page
needs JavaScript: the browser solves a short computation, with no interaction for the `invisible` type.
A passed visitor continues to the next rule and gets the `quant_bot_verification` cookie for the
verification TTL (default 10800 s).

- The pass counts only for the host and project where the visitor passed, and only from the same
  network: the same IPv4 address, or the same IPv6 /64. A visitor who changes network is challenged
  again. Do not copy the cookie between hosts or clients; it does not work there.
- Cookies issued before the 2026-10 bot challenge update are not accepted. Visitors who passed
  earlier see the challenge one more time.

## Proxy rules

The full field list is in [references/rule-types.md](references/rule-types.md#proxy).

| Field | Behaviour |
|---|---|
| `to` | Origin URL with protocol, plus a placeholder (`$*` or `$1`) to keep the path |
| `host` | Host header sent to the origin. Empty sends the visitor's host name |
| `cache_lifetime` | String, in seconds. Empty or `-1`: the origin's `Cache-Control` is kept. `"0"`: Quant sets `Cache-Control: no-store` (nothing cached). `"600"`: `Cache-Control: public, max-age=600` |
| `origin_timeout` | String, in **milliseconds**. Unset uses 30 seconds. `"90"` is 90 ms; 90 seconds is `"90000"` |
| `only_proxy_404` | Dashboard "Only on 404". Serves Quant's static content when the path exists and proxies only when it does not. Proxied responses carry `quant-404-proxied: true` |
| `inject_headers` | Headers added to the request **sent to the origin** (for example a shared secret) |
| `proxy_strip_headers` / `proxy_strip_request_headers` | Headers removed from the response / from the request to the origin |
| `waf_enabled`, `waf_config` | The WAF for this rule (below) |

**Origin failures.** If the origin does not answer within `origin_timeout`, or the connection fails,
Quant returns its own **502 page titled "Proxy Error"** ("An error occurred when communicating with a
backend origin service."). This page comes from Quant, not from your origin. A timed-out request is
not retried. After repeated failures in a short time, Quant returns the 502 for a short cool-down
without contacting the origin. To show your own page: enable "Use static error pages" on the proxy
rule, list `502`, and publish a page at `/_quant502`.

## WAF

The WAF runs **only on proxy rules**. Static content served without a proxy rule is not inspected.
The organisation must have WAF enabled (ask Quant support).

- An unset `mode` means **report only**: the WAF logs hits and blocks nothing. The dashboard and the
  API default new rules to `report`. `waf_enabled: true` on its own therefore blocks nothing.
- Edge case: a rule with `waf_enabled: true` and no `waf_config` at all is not inspected.
- `waf_config.mode: "block"` turns blocking on. Start with `report`, read the WAF logs, add
  false-positive rule IDs to `allow_rules`, then switch to `block`.
- `allow_ip` skips the WAF for those addresses. Paranoia level 1 is the recommended default.
- A block returns **403** (rate limit: **429**) with a `Quant-Waf-Rule` header naming the rule. Custom
  pages: publish content at `/_quant_waf_403` and `/_quant_waf_429`.
- Rate limits are `waf_config.thresholds` (below). A PATCH keeps them unless it sends `thresholds`.
- Turning the WAF off (dashboard, or `waf_enabled: false`) keeps its configuration. Turning it on
  again restores the same settings.
- Logs: dashboard, Security & WAF, WAF logs; or `quant waflogs` (see `quant-cli`).
- Request bodies of 20 MB or more are passed to the origin without body inspection.

**Rate limits through the API.** Each `thresholds` entry has a `type`: `ip` (`rps`), `header`
(`rps`, `value` = header name) or `waf_hit_by_ip` (`hits` in `minutes`), plus `cooldown` (seconds) and
`mode` (`disabled`, `report`, `block` or `bot_challenge`). A PATCH merges entries by `type`: only the
types you send change, and an empty list changes nothing. To turn one off, send its type with
`mode: "disabled"`. `rps`, `hits` and `minutes` are integers of 1 or more; `cooldown` is 0 or more.
An invalid value returns **400**.

```bash
BASE=https://dashboard.quantcdn.io/api/v2/organizations/$ORG/projects/$PROJECT   # gov: dash.quantgov.cloud
curl -s -X PATCH -H "Authorization: Bearer $QUANT_API_TOKEN" -H 'Content-Type: application/json' \
  "$BASE/rules/proxy/$RULE" --data '{"waf_config": {"thresholds": [
    {"type": "ip", "rps": 20, "cooldown": 60, "mode": "block"}]}}'
```

The other threshold types and the rest of `waf_config` stay as they were.

## Three ways to manage rules

| Tool | Use for | Notes |
|---|---|---|
| Dashboard, project Rules page | Any rule | Drag rules to reorder |
| Rules API (`{dashboard}/api/v2/organizations/{org}/projects/{project}/rules/{type}`) | Scripts and CI, one rule at a time | `Authorization: Bearer <token>`, a dashboard API token with `projects:read`, `rules:read` and `rules:write` |
| `quant rules` or deploy-action `rules` input | Function, auth function and content filter rules kept in the repo | Changes only the rules in its own manifest namespace. See `quant-cli` |
| Terraform `quant_rule_*`, Pulumi `@quantcdn/pulumi-quant` | Rules declared as code | `base_url` = bare dashboard host. See `quant-iac` |

API types: `redirect`, `proxy`, `headers`, `auth` (basic auth), `auth-function`, `custom-response`,
`serve-static`, `function`, `content-filter`, `bot-challenge`, `error-page`. GET lists, POST creates,
`/rules/{type}/{rule}` takes GET, PATCH and DELETE. A write sends the action fields at the top level
(for example `redirect_to`); GET returns them inside `action_config`. Field names per type are in
[references/rule-types.md](references/rule-types.md).

**Writes replace lists.** A PATCH changes only the fields you send, but each list you send replaces
the stored list: `url`, `domain`, `country_is`, `country_is_not`, `ip_is`, `ip_is_not`, `method_is`,
`method_is_not`. Sending `"url": ["/new"]` removes every other URL. Read the rule first (GET), add your
entry, and send the complete list. Values inside the action settings (for example the `headers` map)
are merged with the stored ones instead, so a PATCH cannot remove an entry there; delete the rule
and create it again.

```bash
BASE=https://dash.quantgov.cloud/api/v2/organizations/$ORG/projects/$PROJECT
curl -s -H "Authorization: Bearer $QUANT_API_TOKEN" "$BASE/rules/redirect/$RULE" > rule.json
jq '{url: (.url + ["/promo-2026"] | unique)}' rule.json |
  curl -s -X PATCH -H "Authorization: Bearer $QUANT_API_TOKEN" -H 'Content-Type: application/json' \
    --data @- "$BASE/rules/redirect/$RULE"
```

- A **409** means another change to this project's rules is in progress (or the rule is managed by
  `quant rules`). Retry after a few seconds; for a managed rule, change the manifest instead.
- Through the API, `weight` must be 0 or more. A new rule without `weight` goes to the end of the list.
- Pick one tool per rule. A dashboard edit to a Terraform rule shows as drift on the next plan. Rules
  that need traffic source or user agent conditions belong to the dashboard or the API, not Terraform.
- **400** means an invalid WAF value (`thresholds`, `notify_slack_hits_rpm`). **422** means an invalid
  field: a condition mode or list (`asn`, `ua`, `traffic_source`), or an `fn_uuid` the rule type
  cannot run. The response names the field.
- In `quant rules` manifests, `type: auth` is an **auth function** (API type `auth-function`). In the
  API and Terraform, `auth` is **basic auth** (`auth_user`, `auth_pass`).

## Test a change

1. Wait. A rule change is not instant: allow a few minutes before you judge it.
2. Bypass the cache. A response already in the cache is served **without checking the rules again**,
   and a rule change does not purge it. Add a cache-busting query string; it does not change which
   rule matches, because matching uses the path:

   ```bash
   curl -sI "https://www.example.com/old-page?cb=$RANDOM"
   ```

3. Or purge the affected paths (`quant-domains-cache-purge`).
4. Read the headers: `Location` for redirects, `Quant-Waf-Rule` for WAF blocks, `quant-404-proxied` for
   only-on-404 proxies, a `Set-Cookie: quant_bot_verification` after a passed challenge.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| A rule never matches | A rule above it matches the same request and ends processing (often a `*` proxy or serve-static rule) | Move the rule above the catch-all |
| Headers rule has no effect | It sits below the rule that answered | Move it above the proxy, redirect or serve-static rule |
| `/blog/*` rule misses `/blog` and `/blog/` | `*` needs at least one character | Add `/blog` (and `/blog/` if used) to the rule's URLs |
| Redirect goes to `/news/$1` literally | The pattern has no `*` | Use `$*`, or add `*` to the pattern |
| Proxy sends everything to the origin home page | `to` has no placeholder | `https://origin.example.com$*` |
| Rule scoped by country challenges everyone | Mode field is `any`, so the list is ignored | Set `country: "country_is_not"` (or `country_is`) |
| Australians on VPN or corporate networks get a bot challenge | Rule scoped by traffic source only | Add `country_is_not: ["AU"]` with mode `country_is_not`; keep the rule out of Terraform |
| Visitors are challenged again after they passed | They changed network (new IPv4 address or IPv6 /64), opened another host, or hold a cookie from before the 2026-10 update | Expected. One pass covers one host, project and network |
| Change "not working" right after saving | Propagation, or a cached response | Wait a few minutes; test with `?cb=$RANDOM`; purge |
| Proxied responses never cached | `cache_lifetime` is `"0"` (no-store), or an IP condition (private) | Empty or `-1` to keep origin headers, or a positive number |
| "502 Proxy Error" page from Quant | Origin timeout or connection failure; `origin_timeout` set in seconds | `origin_timeout` is milliseconds; fix the origin; custom page at `/_quant502` |
| WAF enabled but attacks get 200 | Mode is `report` (the default when unset) | Set `waf_config.mode: "block"` after tuning in report mode |
| WAF blocks real users | False positives | Add the rule ID from `Quant-Waf-Rule` or the WAF log to `allow_rules` |
| PATCH removed other URLs or countries | List fields are replaced, not appended | GET, merge, PATCH the full list |
| Removed header still sent after a PATCH | Action settings are merged | Delete and recreate the rule |
| 409 from the rules API | Concurrent rules change, or a rule managed in code | Retry; change managed rules through `quant rules` |
| A rate limit changed after an API PATCH | The PATCH sent that `thresholds` type (merged by `type`) | GET the rule; send only the types you mean to change |
| 400 from a proxy rule PATCH | Invalid `thresholds` value (zero `rps`, `hits` or `minutes`) or `notify_slack_hits_rpm` | Send integers of 1 or more; `notify_slack_hits_rpm` 0 turns it off |
| 422 with `asn`, `ua` or `traffic_source` | Mode not `any`, `<name>_is` or `<name>_is_not`; unknown traffic source; AS number out of range | Fix the field the response names |
| Auth-protected path returns 503 | The auth function is missing, unpublished or not an auth function | Deploy and publish the function; check the rule's function UUID |
| `*.example.com` domain rule never matches | Domains are exact host names | List each host name, or `any` |

## Further reading

- Page rules: https://docs.quantcdn.io/dashboard/page-rules/
- CDN proxy: https://docs.quantcdn.io/dashboard/page-rules-proxy/
- WAF on a proxy rule: https://docs.quantcdn.io/dashboard/page-rules-waf/
- Configure the WAF: https://docs.quantcdn.io/guides/security/configure-waf/
- Custom error pages: https://docs.quantcdn.io/custom-error-pages/
- `quant rules`: https://docs.quantcdn.io/content-cli/commands/rules/
- Rule fields per type: [references/rule-types.md](references/rule-types.md)
- Related skills: `quant-platform`, `quant-cli`, `quant-edge-functions-and-kv`, `quant-iac`,
  `quant-domains-cache-purge`, `quant-static-sites`

<!-- checked against npm:@quantcdn/quant-cli 7.0.2 -->
