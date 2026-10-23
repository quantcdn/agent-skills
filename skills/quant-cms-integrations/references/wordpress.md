# WordPress plugin reference

Plugin: "QuantCDN" on wordpress.org, slug `quantcdn`, stable 1.6.0 (requires PHP 7.4, tested to
WordPress 6.8.2). Source: GitHub `quantcdn/wordpress`; its `develop` branch is 1.5.2 and older than
the release. Admin page: `Settings > QuantCDN`, tabs Seed Settings, Settings, Cron, Cache.

## Settings tab (option `wp_quant_settings`)

| Label | Key | Default at activation | Meaning |
|---|---|---|---|
| Automatic static push | `enabled` | off | Push on change |
| Cache purge on save | `purge_on_save` | on | Purge the saved page. Forced on when Automatic static push is on |
| Disable SSL verify | `disable_tls_verify` | **on** | Ticking it turns TLS verification off for ALL plugin HTTP calls: the Quant API and the fetch from the Webserver URL. Turn it off |
| HTTP request timeout | `http_request_timeout` | 15 | Seconds; raise on slow servers |
| Webserver URL | `webserver_url` | empty (form shows `http://localhost`) | Where the plugin fetches pages from |
| Hostname | `webserver_host` | empty | `Host` header sent to the Webserver URL; the public domain |
| API Endpoint | `api_endpoint` | `https://api.quantcdn.io` | Host only; the plugin adds `/v1`. QuantGov: `https://api.quantgov.cloud` |
| API Customer | `api_account` | empty | The organisation (header `quant-customer`) |
| API Project | `api_project` | empty | Project name (header `quant-project`) |
| API Token | `api_token` | empty | Project token (header `quant-token`) |

For a self-signed local server, set Webserver URL to `http://localhost` (plain HTTP inside the container) and keep the box unticked. The default of "Disable SSL verify" is on after activation, so the form must be saved with the box
cleared. Saving the Settings tab shows "Successfully made a connection to Quant" or one of:
"Unable to connect to the Quant API, please check your configuration values and try again." (API
fields) and "Unable to connect to local webserver. Please check the configuration values for
webserver and host and try again." (Webserver URL or Hostname).

## Seed Settings tab (option `wp_quant_seed`)

| Label | Key | Meaning |
|---|---|---|
| 404 path | `404_route` | Route pushed as the 404 page (default `/404`) |
| Custom routes | `custom_routes` | One content or file route per line (for example `/robots.txt`) |
| Relative rewrite | `domains_strip` | Domains to rewrite as relative links |

## Cron tab (option `wp_quant_cron`)

`cron_enabled`, `cron_schedule` (a WP-Cron schedule name: `hourly`, `twicedaily`, `daily`) and
checkboxes `cron_home`, `cron_posts`, `cron_pages`, `cron_categories`, `cron_tags`, plus
`cron_custom_routes`. It uses the WP-Cron event `quant_cronjob`, so WP-Cron must run (on Quant Cloud
run it from a Cron Job).

## Queues

`wp quant info` lists these queue names. Each is also a "Batch" in the admin UI.

| Queue | Content |
|---|---|
| `pages`, `posts`, `custom_posts` | Pages, posts, other post types |
| `categories`, `tags`, `custom_taxonomies` | Taxonomy archives |
| `home`, `archives` | Home page (with pagination) and date/author archives |
| `theme_assets`, `media_assets` | Theme files and media library files |
| `custom_routes` | The Custom routes list and the 404 path |
| `redirects` | Plain URL redirects from the Redirection plugin |

## WP-CLI

```bash
wp quant info
wp quant reset_queue <queue|all>
wp quant process_queue <queue|all> [--threads=<n>]   # default 5, capped at 20
```

Pass `--url=<site url>` on multisite and `--allow-root` when running as root; `process_queue` forwards
both to its worker processes. In `app-wordpress` the `wp` command maps the database variables first,
so it also works from `qc exec` and Cron Jobs.

## When a request runs

| Action | Hook | Result |
|---|---|---|
| Save a post of any type | `save_<post_type>` | Published: pushed. Any other status: unpublished |
| Trash a post | `wp_trash_post` | Unpublished |
| Create or edit a category or tag | `create_<taxonomy>`, `edit_<taxonomy>` | Pushed |
| Delete a category | `delete_category` | Removed |
| Redirection plugin edits | `redirection_redirect_updated`, `_deleted` | Redirect pushed or removed |
| Automatic push off, purge on save on | `save_<post_type>` | Purge of that path only |

The Cache tab purges `/*` or paths you list, one per line. On QuantCDN only `/*` is a wildcard; a
path such as `/blog/*` is purged as that exact URL (`quant-domains-cache-purge`).

## Environment variables in `app-wordpress`

The template's must-use plugin `quant-env-config.php` copies these into the plugin settings on every
request when they are set and not empty: `QUANT_ENABLED`, `QUANT_DISABLE_TLS_VERIFY`,
`QUANT_HTTP_REQUEST_TIMEOUT`, `QUANT_WEBSERVER_URL`, `QUANT_WEBSERVER_HOST`, `QUANT_API_ENDPOINT`,
`QUANT_CUSTOMER`, `QUANT_PROJECT`, `QUANT_TOKEN`. Keep `QUANT_TOKEN` in a secret. Other variables the
template reads: `QUANT_SMTP_FROM`, `QUANT_SMTP_FROM_NAME` (default From address and name),
`QUANT_DEBUG` / `LOG_DEBUG` (log PHP warnings), `WORDPRESS_TABLE_PREFIX`, `WORDPRESS_DEBUG`,
`WORDPRESS_CONFIG_EXTRA` (extra `wp-config.php` PHP) and the `WORDPRESS_*_KEY` / `*_SALT` values.
