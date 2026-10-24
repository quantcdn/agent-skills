# Rule types and fields

Field names are the rules API names (`{dashboard}/api/v2/organizations/{org}/projects/{project}/rules/{type}`).
A POST or PATCH sends the action fields at the top level. GET returns them inside `action_config`,
with the stored name where a row says so. Terraform `quant_rule_*` resources use the same names
unless a row says otherwise. The dashboard shows the same settings as form fields.

## Fields on every rule

| Field | Type | Meaning |
|---|---|---|
| `name` | string | Label only |
| `url` | list | URL patterns. Path only, case-insensitive, whole path, `*` = one or more characters. A pattern with `?` also matches the query string |
| `domain` | list | `["any"]` or exact host names. API default `any` |
| `disabled` | bool | `true` skips the rule |
| `weight` | integer | Order, lowest first. API: 0 or more; a new rule without it goes to the end. `quant rules` manifests may use negative weights to run before dashboard rules |
| `country` | mode | `any`, `country_is` or `country_is_not` |
| `country_is`, `country_is_not` | list | Two-letter country codes. Used only when `country` names the list |
| `method` | mode | `any`, `method_is` or `method_is_not` |
| `method_is`, `method_is_not` | list | `GET`, `POST` and so on |
| `ip` | mode | `any`, `ip_is` or `ip_is_not` |
| `ip_is`, `ip_is_not` | list | Addresses or CIDR ranges. Makes the response `Cache-Control: private` |
| `only_with_cookie` (write: `cookie_name`) | string | Cookie name the request must carry; `*` allowed. The API writes it as `cookie_name`; `""` clears it. Read-only in Terraform |
| `traffic_source` | mode | `any`, `traffic_source_is` or `traffic_source_is_not`. Not in Terraform |
| `traffic_source_is`, `traffic_source_is_not` | list | `cloud` (cloud and hosting providers), `vpn`, `tor-exit`, `abuser` (known abusers), `crawler` (known crawlers) |
| `ua` | mode | `any`, `ua_is` or `ua_is_not`. Splits the cache by user agent. Not in Terraform |
| `ua_is`, `ua_is_not` | list | User agent strings, each at most 255 characters |
| `asn` | mode | `any`, `asn_is` or `asn_is_not`. A PATCH that omits it keeps the current value |
| `asn_is`, `asn_is_not` | list | AS numbers as strings (`"15169"`), positive integers up to 4294967295. Makes the response `Cache-Control: private` |

The API takes `traffic_source`, `ua`, `asn` and `cookie_name` on every rule type. An invalid mode or
list value returns 422.

Rules for writing lists through the API: a PATCH replaces each list field it sends (`url`, `domain`,
`country_is`, `country_is_not`, `ip_is`, `ip_is_not`, `method_is`, `method_is_not`, `asn_is`,
`asn_is_not`, `ua_is`, `ua_is_not`, `traffic_source_is`, `traffic_source_is_not`). Lists and maps
inside the action settings are merged with the stored value, so a PATCH cannot remove entries there.

## Redirect

API type `redirect`, Terraform `quant_rule_redirect`. Ends processing.

| Field | Meaning |
|---|---|
| `redirect_to` | Destination, relative (`/news/$1`) or absolute. `$*` and `$1` to `$5` allowed. Query string added unless the pattern has `?`. GET returns it as `action_config.to` |
| `redirect_code` | `301`, `302`, `303`, `307` or `308` (API default `301`). GET returns it as `action_config.status_code` |

Changing the rule does not purge cached redirects; purge the source paths.
For single path-to-path redirects stored as content, `quant redirect` is the alternative (see `quant-cli`).

## Proxy

API type `proxy`, Terraform `quant_rule_proxy`. Ends processing.

| Field | Meaning |
|---|---|
| `to` | Origin URL with protocol. Used as written: add `$*` (whole path) or `$1` to keep the path |
| `host` | Host header to the origin. Empty: the visitor's host |
| `auth_user`, `auth_pass` | Basic auth sent to the origin (replaces any client `Authorization`) |
| `disable_ssl_verify` | Accept an invalid origin certificate |
| `cache_lifetime` | String, seconds. Empty or `-1`: keep origin `Cache-Control`. `"0"`: `no-store`. Positive: `public, max-age=N` |
| `origin_timeout` | String, milliseconds. Unset: 30 seconds. Timeouts are not retried |
| `only_proxy_404` | Serve Quant static content when the path exists, else proxy. Proxied responses carry `quant-404-proxied: true` |
| `inject_headers` | Map of headers added to the request to the origin |
| `proxy_strip_request_headers` | Headers removed from the request to the origin |
| `proxy_strip_headers` | Headers removed from the origin response |
| `proxy_alert_enabled` | Inject the site-wide alert banner into HTML responses. API default `true` for a new rule |
| `static_error_page`, `static_error_page_status_codes` | Dashboard "Use static error pages". A non-empty `static_error_page` turns it on. For each listed origin status (and for Quant's own 502), Quant serves the published page at `/_quant<status>`, for example `/_quant502`; the text in the field itself is not served. Without that page the origin's error body is passed through |
| `failover_mode`, `failover_origin_ttfb` (ms), `failover_origin_status_codes`, `failover_lifetime` (s) | Static failover: serve Quant's static copy when the origin is slow or returns an unexpected status |
| `notify`, `notify_config` | Slack notifications |
| `application_proxy`, `application_name`, `application_environment`, `application_container`, `application_port` | Proxy to a Quant Cloud application; `to` and `host` are then computed (see `quant-cloud-apps`) |
| `waf_enabled`, `waf_config` | WAF (below) |

Origin failure (timeout or connection error): Quant's 502 page titled "Proxy Error", unless a
`/_quant502` static error page is configured. Repeated failures in a short time make Quant answer
with the 502 for a short cool-down without contacting the origin.

### `waf_config`

| Field | Meaning |
|---|---|
| `mode` | `report` (log only; used when unset) or `block` |
| `paranoia_level` | 1 to 4. 1 is recommended |
| `allow_rules` | Rule IDs never applied (false positives) |
| `allow_ip` | Addresses that skip the WAF |
| `block_ip`, `block_ua`, `block_referer`, `block_asn` | Always block these |
| `block_lists` | Built-in lists: `user_agent`, `referer`, `ip`, `ai` (AI crawlers) |
| `httpbl` | Project Honeypot Http:BL settings (`httpbl_key` is the key) |
| `thresholds` | Rate limits: list of `{ type, rps, hits, minutes, cooldown, mode, value, notify_slack }`. `type` `ip` (`rps`), `header` (`rps`, `value` = header name) or `waf_hit_by_ip` (`hits` in `minutes`). `mode` `disabled`, `report`, `block` or `bot_challenge`. A PATCH merges entries by `type` and keeps types it does not send; a request without `thresholds` keeps them all; send `mode: "disabled"` to turn one off. `rps`, `hits`, `minutes` 1 or more; `cooldown` 0 or more; invalid values return 400 |
| `notify_slack` | Slack webhook URL. A request that sets it copies it into each threshold in the same request that has no `notify_slack` of its own |
| `notify_slack_hits_rpm` | Hits per minute before a Slack message: a positive integer. `0`, `null` or `""` turns it off (reads back `null`). Other values return 400 |
| `notify_email` | Email addresses |

An unset `mode` means report only (the dashboard and API default). Edge case: `waf_enabled: true` with
no `waf_config` inspects nothing. `waf_enabled: false` keeps `waf_config`, so the WAF comes back with
the same settings. A block is a 403 (429 for a rate limit) with header `Quant-Waf-Rule`. Custom pages:
`/_quant_waf_403`, `/_quant_waf_429`.

Older write names are still accepted but deprecated: `ip_ratelimit_*`, `header_ratelimit_*` and
`hit_ratelimit_*` (use `thresholds`; `thresholds` wins when both set a value), `notify_slack_webhook`
(use `notify_slack`), `notify_slack_rpm` (use `notify_slack_hits_rpm`) and `api_key` (use `httpbl_key`).

## Custom response headers

API type `headers`, Terraform `quant_rule_headers`. Continues to the next rule.

| Field | Meaning |
|---|---|
| `headers` | Map of header name to value. Applied to the final response, static or proxied, and replaces an origin header of the same name |

`set-cookie` values are added, not replaced. `surrogate-key` and `cache-keys` add cache keys. Quant's own
headers (`quant-server`, `age`, `quant-project`, `quant-url-hash`, `quant-orig-host`) cannot be set. The
rule must be above the rule that answers the request.

## Basic auth

API type `auth`, Terraform `quant_rule_auth`. Ends processing with 401 when credentials are wrong or
missing; continues when they are correct.

| Field | Meaning |
|---|---|
| `auth_user`, `auth_pass` | The username and password |

Not the same as `type: auth` in a `quant rules` manifest, which runs an auth function.

## Custom response

API type `custom-response`, Terraform `quant_rule_custom_response`. Ends processing.

| Field | Meaning |
|---|---|
| `custom_response_status_code` | Status. Always set it |
| `custom_response_body` | Body. Content type is `text/html; charset=utf-8` unless a headers rule above sets `Content-Type` |

## Serve static content

API type `serve-static`, Terraform `quant_rule_serve_static`. Ends processing.

| Field | Meaning |
|---|---|
| `static_file_path` | Published path to serve, for example `/about`. `/$*` serves the same path as the request |

If nothing is published at that path, the visitor gets the 404 page. Check that the content exists
(for example `robots.txt` and `sitemap.xml`) before routing traffic to static.

## Edge function, auth function, content filter

| Rule | API type, Terraform | Field | Behaviour |
|---|---|---|---|
| Edge function | `function`, `quant_rule_function` | `fn_uuid` | Runs the function; ends processing |
| Content filter | `content-filter`, `quant_rule_content_filter` | `fn_uuid` | Runs the function over the final response; continues |
| Auth function | `auth-function` (no Terraform resource); `quant rules` manifest `type: auth` | `fn_uuid`; in a manifest `function_ref` or `function_uuid` | Continues when the function returns 201, else returns its response |

The API refuses (422) a new `fn_uuid` that names a function this rule type cannot run. If the
function of an auth function rule cannot run at request time (missing, unpublished, not an auth
function), Quant fails closed: **503** with `Cache-Control: private, no-store`. A content filter
whose function cannot run is skipped.

Function code, UUIDs and manifests: `quant-edge-functions-and-kv` and `quant-cli`.

## Bot challenge

API type `bot-challenge`, Terraform `quant_rule_bot_challenge`. Ends processing until the visitor
passes.

| Field | Meaning |
|---|---|
| `robot_challenge_type` | `invisible` (JavaScript, no interaction) or `checkbox` (used when not `invisible`) |
| `robot_challenge_verification_ttl` | Seconds a pass is valid. Default 10800 |
| `robot_challenge_challenge_ttl` | Seconds the visitor has to complete a challenge. Default 30 |

Challenge page: 403, `Cache-Control: no-store, must-revalidate`. It needs JavaScript in the browser.
A pass sets the `quant_bot_verification` cookie. The pass counts only for that host and project and
the visitor's network (the same IPv4 address, or the same IPv6 /64); a visitor on another network is
challenged again. Cookies from before the 2026-10 update are not accepted, so earlier visitors see
one more challenge. Scope with country and traffic source. Terraform cannot set traffic source, so
keep such a rule in the dashboard or the API.

## Error page

API type `error-page` (no Terraform resource). Used only when Quant builds an error response (for
example a 404 for a path with no content) and for a proxy rule's static error pages. The first
matching rule that lists the status wins; its conditions (domain, URL, country and so on) apply.

| Field | Meaning |
|---|---|
| `status_codes` | Statuses this page is for, for example `["404"]` |
| `error_page_path` | Published path of the page, for example `/fr/_quant404` |

Without an error page rule, or when nothing is published at `error_page_path`, Quant uses
`/_quant<status>`, for example `/_quant404` (see `quant-static-sites`).
