# Drupal module reference

Module: `drupal/quantcdn` (GitHub `quantcdn/drupal`, Drupal.org project `quantcdn`). Checked against
1.7.0 and 2.0.0.

| Release line | Drupal core | Notes |
|---|---|---|
| 1.x (1.7.0) | 10 | `core_version_requirement: ^10` |
| 2.x (2.0.0) | 11 | Adds guards for multi-domain sites that use the Domain module: a write is refused when the request host matches no domain, and queue items go to the project of their domain |
| 7.x-1.x (7.x-1.5) | 7 | Separate code base; admin path `/admin/config/services/quant` |

Drupal 9 is not supported by current releases.

## Admin pages

| Page | Path |
|---|---|
| Main settings | `/admin/config/quant` |
| API connection | `/admin/config/development/quant/api` |
| Seed | `/admin/config/quant/seed` |
| Metadata | `/admin/config/quant/metadata` |
| Queue info | `/admin/config/quant/queue-info` |
| Tokens | `/admin/config/quant/token` |
| Quant Cron | `/admin/config/development/quant/cron` |
| Validation route (used by the main page) | `/quant/validate` |

## API form (`quant_api.settings`)

| Form label | Config key | Notes |
|---|---|---|
| API Endpoint | `api_endpoint` | Read-only in the form. Host only, no `/v1` (the client adds it). Default `https://api.quantcdn.io`; QuantGov `https://api.quantgov.cloud` |
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
| `quant_webform` | `drupal/webform` | Quant Forms support for Webform |
