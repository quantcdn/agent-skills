# Drupal module reference

Module: `drupal/quantcdn` (GitHub `quantcdn/drupal`, Drupal.org project `quantcdn`). Checked against
1.7.0 and 2.0.0; the 2.3.0 rows against the 2.3.0 release branches.

| Release line | Drupal core | Notes |
|---|---|---|
| 1.x (1.7.0) | 10 | `core_version_requirement: ^10` |
| 2.x (2.0.0) | 11 | Adds guards for multi-domain sites that use the Domain module: a write is refused when the request host matches no domain, and queue items go to the project of their domain |
| 2.x (2.3.0) | 11 | "Log in to Quant", Quant Forms registration for Webform (multi-page included), "Create a search page" and "Create from a View". The API client sends nothing when no token is set |
| 7.x-1.x (7.x-1.5) | 7 | Separate code base; admin path `/admin/config/services/quant` |

Drupal 9 is not supported by current releases.

## Admin pages

| Page | Path |
|---|---|
| Main settings | `/admin/config/quant` |
| API connection | `/admin/config/development/quant/api` |
| Quant Forms (2.3.0) | `/admin/config/development/quant/forms` |
| Create a search page (2.3.0) | `/admin/config/development/quant/search/pages/create` |
| Create a search page from a View (2.3.0) | `/admin/config/development/quant/search/pages/from-view` |
| Seed | `/admin/config/quant/seed` |
| Metadata | `/admin/config/quant/metadata` |
| Queue info | `/admin/config/quant/queue-info` |
| Tokens | `/admin/config/quant/token` |
| Quant Cron | `/admin/config/development/quant/cron` |
| Validation route (used by the main page) | `/quant/validate` |

## API form (`quant_api.settings`)

| Form label | Config key | Notes |
|---|---|---|
| Platform (2.3.0) | `platform` | `quantcdn` or `quantgov`. Sets the endpoint and the dashboard used by "Log in to Quant" |
| (method, 2.3.0) | `auth_method` | `oauth` after "Log in to Quant", `token` for the token fields |
| API Endpoint | `api_endpoint` | Before 2.3.0 read-only in the form; from 2.3.0 under Advanced, following the platform. Host only, no `/v1` (the client adds it). Default `https://api.quantcdn.io`; QuantGov `https://api.quantgov.cloud` |
| API Organization | `api_account` | Sent as the `Quant-Customer` header |
| API Project | `api_project` | The project "API name". Sent as `Quant-Project` |
| API Token | `api_token` | Project token. Sent as `Quant-Token` |
| Disable TLS verification | `api_tls_disabled` | Do not enable |

Set any of them without the form:

```bash
drush config:set quant_api.settings api_endpoint https://api.quantgov.cloud
```

```php
// settings.php: values from the environment; the form shows an "overridden" warning
$config['quant_api.settings']['api_endpoint'] = getenv('QUANT_API_ENDPOINT') ?: 'https://api.quantcdn.io';
$config['quant_api.settings']['api_account'] = getenv('QUANT_CUSTOMER');
$config['quant_api.settings']['api_project'] = getenv('QUANT_PROJECT');
$config['quant_api.settings']['api_token'] = getenv('QUANT_TOKEN');
```

With "Log in to Quant" the organisation and project are in config, and the tokens are in the
key-value store `quant_api.oauth` (not exported). The login is limited to the chosen project, so
another project needs a new login (**Change project**). A copy of the database (for example on
staging) does not refresh the original site's login; the settings page then asks for a new login on
the copy. Publishing keeps working, because the project write token does not expire.

The form's connection test calls `GET {endpoint}/v1/ping`. A 402 answer reports an invalid
subscription, a 410 a deleted project.

## Main form (`quant.settings`)

| Label | Key | Default | Meaning |
|---|---|---|---|
| Track content change | `quant_enabled` | on | Master switch for push on change |
| Nodes, Taxonomy Terms, Redirects, Views | `quant_enabled_nodes`, `_taxonomy`, `_redirects`, `_views` | on | Which entity types are tracked |
| Links to follow | `xpath_selectors` | pager links | One XPath per line; matching links are queued (for example views pagers) |
| Disable content drafts | `disable_content_drafts` | on | Draft revisions are not pushed |
| Show page information block | `quant_show_page_info_block` | on | Quant info at the top of pages for editors |
| Override existing proxies | `proxy_override` | off | Lets a page push replace a proxy created in the dashboard |
| Webserver URL | `local_server` | `http://localhost` | Where Quant fetches pages from. Plain http; credentials allowed (`http://user:pass@localhost`) |
| HTTP Host header | `host_domain` | empty | Sent as `Host`; set to the public domain |
| Strip host domain from content | `host_domain_strip` | off | Removes the host from generated content and metadata |
| Verify SSL certificates | `ssl_cert_verify` | on | TLS check on the Webserver URL; turn off only for a self-signed certificate |

The module sends a `POST` to `{Webserver URL}{path}` with `Host: {HTTP Host header}`. When drafts are
enabled for push it adds a signed `quant-token` header; tokens are managed at `/admin/config/quant/token`.

## Drush commands

| Command | Alias | Effect |
|---|---|---|
| `quant:seed-queue` | `quant-queue-seed` | Fills the queue from the Seed settings. `--reset=true` (default) empties the queue first |
| `quant:run-queue --threads=5` | `quant-queue-run` | Forks that many `queue:run quant_seed_worker` processes and waits. Needs a lock file in the temp directory |
| `quant:unlock-queue` | `quant-queue-unlock` | Deletes a stale lock file |
| `quant:clear-queue` | `quant-queue-clear` | Removes every queue item |
| `quant:tome:deploy` | | `quant_tome` submodule: deploy Tome static output |
| `quant:auth-status` | | 2.3.0: platform, organisation, project, connection method, login expiry. Never prints a token |
| `quant:webform-register [id]` | | 2.3.0, `quant_webform`: publishes the page of each Webform (or one) with its Quant Forms settings, and prints what is not supported |

`quant:run-queue` finds drush through `DRUSH_PATH`, `PATH`, or `vendor/bin/drush`. Set `DRUSH_PATH`
if it reports "Unable to find a valid drush binary". For a site with many threads keep the thread count
within what the database and web server can serve.

The queue worker is `quant_seed_worker`; it also runs on core cron (60 seconds per run).

## Submodules

| Module | Needs | Purpose |
|---|---|---|
| `quant_api` | | Connection and the API client (enabled with `quant`) |
| `quant_cron` | | Push selected entities and routes on every command-line cron run. Run more often with `*/30 * * * * drush php-eval 'quant_cron_cron();'` |
| `quant_purger` | `drupal/purge` | Maps cache tags to seeded paths (table `purge_queuer_quant`); a tag change queues the pages that carry it. Tag and path blocklists: `/admin/config/development/performance/purge` (with `purge_ui`) or `drush config:get quant_purger.settings tag_blocklist` |
| `quant_search` | `drupal/token` | Quant search pages and an autocomplete block (`quant-search`) |
| `quant_sitemap` | `simple_sitemap` | Pushes the sitemap |
| `quant_tome` | `tome_static` | Deploys Tome output to Quant |
| `quant_webform` | `drupal/webform` | Quant Forms for Webform. From 2.3.0 it registers each form on publish (below) |

## Quant Forms with Webform (2.3.0)

A Webform's settings go to Quant inline with the push of the page that takes its submissions. That
page is the Webform's own page, also when the form is embedded elsewhere (a block, a footer, a
node). A Webform without its own page posts to the node page that shows it.

| Webform | Quant Forms setting |
|---|---|
| Elements that are always required (no `#states` on them or a parent) | `mandatory_fields`. A composite counts by its parts that are marked required (`address[city]`) |
| Drupal's own fields (`form_build_id`, `form_token`, `form_id`, `op`) and file id fields | `remove_fields` |
| Honeypot module field | `honeypot_fields` |
| reCAPTCHA v2 element | `recaptcha_secret_key` |
| Confirmation message (tokens removed) or the per-form static message | `success_message` (plain text, at most 256 characters) |
| First enabled email handler on "completed": to, cc, from (`default` is the site mail), subject, reply-to | `notifications.email`. `[webform_submission:values:KEY]` becomes `{{KEY}}`; addresses with tokens are left out |
| Slack webhook on the Forms page (kept outside config) | `notifications.slack` |
| AI spam check on the Forms page | `spam_threshold`, `spam_detect_action` |

Closing or deleting a Webform turns Quant Forms off for its page; the submissions stay in Quant.

On the static page a script runs multi-page Webforms (one step at a time, a check per step, a
review step) and posts once with `Accept: application/json`. Confirmation types message, inline,
page and modal show in place; url types redirect. Without JavaScript all pages show and the form
posts once. With a multi-file field and no JavaScript, Quant keeps only the last file.

Not supported on the static site: AJAX submit (the form is not registered until "Use Ajax" is off),
drafts, submission limits, handlers other than email, computed elements, CAPTCHA other than
reCAPTCHA v2, and submission tokens such as `[webform_submission:serial]`.

## Search pages (`quant_search`)

| Action | Result |
|---|---|
| Create a search page (2.3.0) | Saves an enabled search page at a free address (`search`, `site-search`, ...), registers its facets, publishes it, and can place the search box block. Adds content types to the index settings when the page needs them (then re-index) |
| Create from a View (2.3.0) | Proposes the page from a View page: fixed content type filter, exposed content type, language and taxonomy filters as facets, a fixed term filter as a filter on term names, keyword filters as the search box, the pager. Lists sorts, contextual filters and other fields as not converted |
| Add a search page (all settings) | The full form: manual filters, display options, facet order |

Index keys: `content_type`, `content_type_{langcode}`, `language_{langcode}`, `lang_code` and
`{vocabulary}_{langcode}` for terms. QuantGov projects use Typesense (`https://search.quantgov.cloud`),
QuantCDN projects Algolia. Filters use the Algolia syntax (`content_type:"article"`); the module
converts it for Typesense.
