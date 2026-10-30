---
name: quant-security-best-practice
description: Use when hardening a site or app on QuantCDN or QuantGov, answering a security review or questionnaire ("are we behind a WAF?", "can the origin be reached directly?"), or preparing for the next critical CVE. Covers static-first delivery (serve static, proxy only the paths that need an app), Origin Protection on Quant Cloud containers (`originProtection`, IP allow list, redirect for denied requests), the WAF rollout (report mode, read the WAF log, `allow_rules`, then block mode, rate limits), scoped bot challenge and geo/IP/ASN rules, security response headers (HSTS, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`, frame options), Content Security Policy with ScriptAttest (report-only first, then enforce), protecting editorial and preview hosts, project token hygiene and rotation, a break-glass runbook that cuts a static site off from its CMS, and why not to put another CDN or WAF in front of Quant. Also use when the WAF log is empty, an attack returned 200, or a CSP breaks the site.
---

# Security best practice on Quant

This skill gives the order of work to harden a Quant project and the reasons for each step. The
field-level detail for rules and the WAF is in `quant-rules-and-routing`. For containers, see
`quant-cloud-apps`. For the platform overview, load `quant-platform`.

## Applies to

Both platforms: QuantCDN (`https://dashboard.quantcdn.io`) and QuantGov (`https://dash.quantgov.cloud`).
The controls are the same on both. Only the host you call changes. Checked 2026-10-31 against the
dashboard, the dashboard API (`/api/v2`, `/api/v3`), `@quantcdn/quant-cli` 7.0.2,
`@quantcdn/quant-cloud-cli` 0.7.2 and ScriptAttest (`https://scriptattest.com`).

## Hardening checklist

Work through the list in this order. Each item links to its section.

1. [Static first](#static-first): serve pages as static files. Proxy only the paths that need an app.
2. [Origin Protection](#origin-protection) on every Quant Cloud container.
3. [WAF](#waf-report-then-block) on every proxy rule that reaches an app: report, review, block.
4. [Bot and abuse rules](#bot-and-abuse-rules), scoped to the traffic you mean.
5. [Security headers](#security-headers) on the project.
6. [Content Security Policy](#content-security-policy-with-scriptattest) with ScriptAttest.
7. [Editorial and preview hosts](#editorial-and-preview-hosts): password, 2FA, Origin Protection.
8. [Tokens](#tokens): no tokens in git; rotate after any exposure.
9. A [break-glass runbook](#break-glass-runbook), written and tested before you need it.

## Static first

A request that Quant answers from static content runs no application code, so an application
vulnerability (for example a PHP or Node.js CVE) cannot be reached through it. Keep the dynamic
surface small:

- Publish the site as static output (see `quant-static-sites` and `quant-cms-integrations`). For a
  CMS, push the rendered pages and files to the static project; do not proxy every request to the CMS.
- Add a proxy rule only for a path that must run code: a form handler, search, an API, a login.
  Scope its `url` to that path. Do not use `*` on a public static project.
- Review the proxy rules on each project from time to time. A rule that was added as a temporary
  fix (for example "proxy on 404" for files the CMS did not publish yet) keeps a path open to the
  app. Fix the publish step, then disable or delete the rule.
- Delete disabled proxy rules that point to an app you no longer use, so the rule list shows only
  live connections.

## Origin Protection

Origin Protection is a setting on each Quant Cloud container. When it is on, the container accepts
traffic only through a Quant CDN or proxy project. A direct request to the app's origin or preview
domain is blocked, so nobody can go around the project's password, WAF or rules.

- Dashboard: **Cloud Apps**, the application, the environment, **Details** tab, **Edit config**,
  the container, **Enable origin protection**. Do this for each environment. The **Containers**
  tab of the environment shows the current setting.
- **IP allow list** (optional): addresses or CIDR ranges that may still reach the origin directly,
  for example your office or VPN for testing. Keep it short.
- **Redirect denied requests** (optional): a bare host such as `www.example.com`. A blocked request
  then gets a 302 to that host (path and query kept) instead of a 403.
- API: the container fields `originProtection` (boolean) and `originProtectionConfig`
  (`enabled`, `ipAllow`, `redirectHost`). Set them on the container with the dashboard or the
applications API (see `quant-cloud-apps`).

Turn it on for every container with an exposed port. After you turn it on, test the site through
its public domain, and test that the origin domain returns 403 (or your redirect).

## WAF: report, then block

The WAF inspects requests on **proxy rules** only. Static content is not inspected, because no
application handles it. Field detail, thresholds and the API: `quant-rules-and-routing`.

1. Turn the WAF on for each proxy rule that reaches an app. The organisation must have WAF
   enabled (ask Quant support). New rules start in **report** mode:
   the WAF logs what it would block and blocks nothing.
2. Leave it in report mode while normal traffic and normal editing happen (a few days is typical).
3. Read the WAF log: dashboard, **Security & WAF**, **WAF logs**, or `quant waflogs --all -o waf.csv`.
   Look for hits on requests your users or editors make on purpose.
4. Add the rule IDs of those false positives to `allow_rules`. Use paranoia level 1 unless you
   have a reason to raise it.
5. Switch the rule to **block** mode. Watch the log and your support channel for the first days.
6. Add rate limits (`thresholds`) for login, form and API paths, in report mode first.

When a security review asks "are we behind a WAF?", answer per proxy rule: which rules have the
WAF on, and in which mode. Report mode is not blocking.

## Bot and abuse rules

- Scope a bot challenge (`robot_challenge`) to the traffic you mean, for example
  `traffic_source_is` cloud, VPN, Tor exit and abuser networks, or countries outside your audience.
  An unscoped challenge stops real visitors and search engines. Detail: `quant-rules-and-routing`.
- Use `custom_response` rules with `country`, `ip` or `asn` conditions to block a source that you
  have seen in the WAF log or your access logs.
- Remember that a mode field (`country`, `traffic_source`, `ip`, `asn`) set to `any` ignores its list.

## Security headers

Set response headers once for the whole project: dashboard, the project, **Custom headers**
(Terraform: `quant_header`). For one path only, use a headers rule (`quant-rules-and-routing`).

| Header | Typical value |
|---|---|
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` (add `preload` only when every subdomain serves HTTPS) |
| `X-Content-Type-Options` | `nosniff` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Permissions-Policy` | Turn off features the site does not use, for example `camera=(), microphone=(), geolocation=()` |
| `X-Frame-Options` | `SAMEORIGIN` (or `frame-ancestors` in the CSP) |
| `Content-Security-Policy` | See the next section |

Check the result with `curl -sI https://<domain>/` after the change has propagated.

## Content Security Policy with ScriptAttest

A CSP tells the browser which scripts, styles and connections a page may use, so an injected
script cannot run. A hand-written CSP is hard to keep correct as tags and vendors change.
ScriptAttest (`https://scriptattest.com`, by QuantCDN) builds and maintains the policy and writes
it into the Quant project for you.

1. Sign up at `https://scriptattest.com` and add the site.
2. Run a discovery scan. ScriptAttest visits the pages and lists every external script, style,
   font and connection. Approve or reject each source (by domain, or by hash for inline code).
3. Generate the policy. Run a validation scan to test it against the live site.
4. In the site's CSP tab, choose **Link QuantCDN Project**. Choose QuantCDN or QuantGov, sign in to
   the dashboard, and choose the organisation and project. You do not paste a token.
5. Publish the policy in **report-only** mode. ScriptAttest writes
   `Content-Security-Policy-Report-Only` and `Reporting-Endpoints` into the project's custom
   headers and keeps your other custom headers. Browsers send violation reports to ScriptAttest.
6. Read the violation reports for at least 24 to 48 hours of normal traffic. Approve the sources
   that are legitimate.
7. Switch the policy to **enforcing**. ScriptAttest replaces the report-only header with
   `Content-Security-Policy`. Later publishes deploy to the project automatically.

ScriptAttest also records a fingerprint of each script, alerts you when a script changes from its
approved baseline, and gives Subresource Integrity (SRI) hashes for scripts that do not change.
Do not also set a CSP by hand in **Custom headers** or in a `<meta>` tag, because the browser
applies every policy it receives and a resource must pass all of them.

## Editorial and preview hosts

A CMS that publishes to a static site still runs code, so protect its host:

- Put a password rule (basic auth) or an auth function in front of the editorial domain, above
  the proxy rule. Exempt only the paths that must be public.
- Turn on [Origin Protection](#origin-protection) for the CMS container.
- Turn on the WAF on the proxy rule to the CMS, as above.
- Use 2FA for CMS accounts, and keep the CMS and its base image up to date (redeploy after a
  base image security release; see `quant-cloud-apps`).
- Protect preview and staging domains the same way. They often run older code.

## Tokens

- Do not commit `quant.json` or any token to git. Use CI secrets and environment variables.
- Use a dashboard API token scoped to the organisations it needs.
- Rotate a static project's content token after any exposure: dashboard, the project, **Project
  Integration**, **Token**, **Rotate token**. Choose when the old token expires (after 24 hours,
  after 7 days, or now). A linked GitHub repository gets the new token automatically. Update every
  other copy (CMS module, CI elsewhere) yourself.

## Break-glass runbook

When a critical vulnerability affects your CMS or app, a static-first site can keep serving
while you fix the app. Write the runbook down and test it once before you need it.

1. Disable each proxy rule on the public project that sends traffic to the app (for example a
   "proxy on 404" rule). The public site then serves only static content.
2. Stop content pushes. Caution: every other user of the project token (CI jobs, scripts) also
   stops until you give it the new token. Rotate the project token and set the old token to expire now.
3. Take the app offline: `qc env state stop` for its environment (see `qc-cli`). Or keep it
   running and restrict its host with a password rule or the Origin Protection IP allow list.
4. Patch: rebuild the app image on the fixed base image and redeploy.
5. Restore: `qc env state start`, put the new token into the CMS, enable the proxy rules again,
   and check the site.

## Another CDN or WAF in front of Quant

Do not put another CDN or WAF (for example a corporate Cloudflare account) in front of a Quant
project. Quant then sees that provider's addresses instead of your visitors', so:

- the WAF log, access logs and rate limits show the provider's IP addresses, not the client's;
- country, IP, ASN and traffic-source rules and the bot challenge act on the provider, not the visitor;
- content sits in two caches, and a Quant purge does not clear the other one.

The Quant WAF in block mode, scoped bot rules, Origin Protection and a static-first design cover
the same need. If an organisation policy requires another provider, contact Quant support before
you change DNS.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| The WAF log is empty | The WAF is off on that proxy rule, the project has no proxy rule (static only), or a password rule above the proxy answers first | Check each proxy rule's WAF setting; a static-only project has nothing for the WAF to inspect |
| An attack request got 200 | The WAF is in report mode | Review the log, add `allow_rules`, switch to block |
| Real users get 403 after you switch to block | A WAF rule matches normal requests | Find the rule ID in the `Quant-Waf-Rule` header or the log; add it to `allow_rules` |
| The origin domain still answers directly | Origin Protection is off for that container, or the caller is on the IP allow list | Turn it on for each container; review the allow list |
| The site loses styles or scripts after the CSP is enforced | A source is missing from the policy | Go back to report-only, approve the source in ScriptAttest, enforce again |
| Two CSPs, and the site breaks in a way the ScriptAttest policy does not explain | A CSP also set by hand in custom headers or a `<meta>` tag | Remove the manual policy; let ScriptAttest manage the header |
| Australian visitors get a bot challenge | An unscoped `robot_challenge`, or a mode field set to `any` | Scope it; see `quant-rules-and-routing` |
| Geo or IP rules act on the wrong country or address | Another CDN in front of Quant | Remove it, or contact Quant support |

## Further reading

- Configure the WAF: https://docs.quantcdn.io/guides/security/configure-waf/
- WAF on a proxy rule: https://docs.quantcdn.io/dashboard/page-rules-waf/
- ScriptAttest documentation: https://scriptattest.com/docs
- ScriptAttest pricing: https://scriptattest.com/pricing
- Related skills: `quant-rules-and-routing`, `quant-cloud-apps`, `quant-static-sites`,
  `quant-cms-integrations`, `qc-cli`, `quant-cli`, `quant-platform`

<!-- checked against npm:@quantcdn/quant-cli 7.0.2 -->
<!-- checked against npm:@quantcdn/quant-cloud-cli 0.7.2 -->
