---
name: quant-cms-integrations
description: Use when connecting Drupal or WordPress to Quant or running either CMS on Quant Cloud, on QuantCDN or QuantGov - installing and configuring the Quant Drupal module (`drupal/quantcdn`, 1.x for Drupal 10, 2.x for Drupal 11) or the QuantCDN WordPress plugin, the connection fields (API endpoint per platform, organisation, project, project token, webserver URL and host header), the first full push (Drupal seed queue and `drush quant:run-queue`, WordPress `wp quant process_queue`), what is pushed on save, unpublish and delete, cron, purge and search submodules, choosing between a static push and running the CMS on Quant Cloud (`app-drupal`, `app-drupal-cms`, `app-wordpress` - database variables, SMTP, uploads on a volume, cron, trusted hosts, `WP_HOME`), editor access after go-live, and the go-live checklist. Also use when a push says "Unable to connect to local webserver", Drupal says "The provided host name is not valid for this server", uploads vanish after a redeploy, or `quant deploy` unpublished CMS pages.
---

# Drupal and WordPress with Quant

There are two ways to use a CMS with Quant. They can be combined.

1. **Static push.** The CMS runs anywhere. A Drupal module or WordPress plugin renders each page and
   pushes it to a Quant project. Visitors get static files from Quant; the CMS serves editors only.
2. **CMS on Quant Cloud.** Drupal or WordPress runs as a container app (`app-drupal`,
   `app-drupal-cms`, `app-wordpress`). A CDN project with a proxy rule puts your domain in front.

For the platform overview and the public/gov split, load `quant-platform` first.

## Applies to

Both platforms: QuantCDN (`https://dashboard.quantcdn.io`) and QuantGov (`https://dash.quantgov.cloud`).
Identify the platform by the dashboard URL only; ask the customer if you do not know it. Checked
2026-10 against the Drupal module 1.7.0 and 2.0.0, the WordPress plugin 1.6.0 (wordpress.org), and
the `app-drupal`, `app-drupal-cms` and `app-wordpress` templates.

| | QuantCDN (public) | QuantGov |
|---|---|---|
| Module/plugin "API Endpoint" | `https://api.quantcdn.io` (default) | `https://api.quantgov.cloud` |
| Content API the module calls | `https://api.quantcdn.io/v1` | `https://api.quantgov.cloud/v1` |
| Credentials | Organisation, project, project token from the Integrations page of `https://dashboard.quantcdn.io` | Same fields from `https://dash.quantgov.cloud` |
| Go-live | CNAME or A records, certificate after DNS | Create the DNS-validation records first (`quant-domains-cache-purge`) |

**The endpoint field takes the host without `/v1`.** The module and the plugin append `/v1` themselves.
Both default to the public host, so on QuantGov you must change it.

## Choose a model

| Situation | Use |
|---|---|
| Public site is mostly pages; editors need the CMS; you want static speed and a small attack surface | **Static push** |
| The CMS is hosted elsewhere and you will not move it | **Static push** |
| Visitors log in, comment, search server-side, add to cart, or submit forms the CMS must process | **CMS on Quant Cloud** (proxy rule) |
| You want the CMS itself hosted by Quant | **CMS on Quant Cloud** |
| Static public site, and the CMS also hosted by Quant | Both: run the CMS on Quant Cloud and push with the module or plugin ([Both together](#both-together)) |

Static push sends only what the module or plugin knows about: nodes or posts, terms, views pages,
redirects, theme assets, media and the routes you list. Anything a visitor does that needs PHP
(server-side search, logins, carts) does not work on the static copy. Quant provides forms and
search for static sites (`quant-static-sites`, `quant-search`).

## Static push: Drupal

Details, every field and the drush commands: [references/drupal.md](references/drupal.md).

1. **Install.** `composer require drupal/quantcdn`, then `drush en quant` (this also enables
   `quant_api`). Release line: **1.x for Drupal 10** (1.7.0), **2.x for Drupal 11** (2.0.0).
   Drupal 9 is not supported by current releases. Drupal 7 has its own `7.x-1.x` release.
2. **Connect.** `Configuration > Quant > API` (`/admin/config/development/quant/api`):
   - **API Endpoint**: shown but read-only. Change it with
     `drush config:set quant_api.settings api_endpoint https://api.quantgov.cloud` or in `settings.php`.
   - **API Organization**, **API Project** (the project "API name", which can differ from the
     display name) and **API Token** (the project token from the Integrations page, not a dashboard
     API token). Saving shows "Successfully connected to project ...", or an error.
   - Keep the token out of the database: in `settings.php` set
     `$config['quant_api.settings']['api_token'] = getenv('QUANT_TOKEN');` (also `api_account`,
     `api_project`, `api_endpoint`). The form then shows an "overridden" warning.
3. **Local web server.** `Configuration > Quant` (`/admin/config/quant`): leave "Track content change"
   on, set **Webserver URL** to the server the module can reach itself on (`http://localhost`, plain
   http; a Docker service such as `http://nginx:8080`), and **HTTP Host header** to the public
   domain (`www.example.com`). Quant fetches every page from the Webserver URL with that `Host`
   header; it does not fetch the public domain. The page shows "Connected successfully" when this works.
4. **Seed.** `/admin/config/quant/seed`: choose what to push (nodes, taxonomy terms, theme assets,
   views pages, redirects, custom routes, file paths, robots.txt). For a large site leave "Trigger
   the batch" off and click **Queue**, then run the queue with threads:

   ```bash
   drush quant:seed-queue                 # same as the Queue button (--reset=true by default)
   drush quant:run-queue --threads=5      # workers; default 5
   ```

   Add `$settings['queue_service_quant_seed_worker'] = 'quant.queue_factory';` to `settings.php`
   first: the core queue driver adds duplicate items.
5. **After the seed** the module tracks changes (below). Re-seed after a site-wide change such as a
   theme update or a new navigation.

**What is pushed and when**

| Event | Result |
|---|---|
| Save a published node, term, or redirect | Pushed at the end of the request (shutdown), if "Track content change" and that entity type are on |
| Save a node whose default revision is unpublished | The page is unpublished in Quant |
| Delete an entity | The page is unpublished in Quant (before the alias is removed) |
| Draft revisions | Not pushed while "Disable content drafts" is on (the default) |
| Cache tags (`quant_purger` with the Purge module) | Pages that share a changed tag are queued; the queue runs on the next cron |
| `quant_cron` | Pushes the entities and routes you select each time cron runs. **Command-line cron only**; web cron does nothing. Settings: `/admin/config/development/quant/cron` |

Submodules: `quant_api` (required), `quant_cron`, `quant_purger` (needs `drupal/purge`),
`quant_search` (needs `drupal/token`), `quant_sitemap` (needs `simple_sitemap`), `quant_tome`,
`quant_webform` (needs `drupal/webform`).

## Static push: WordPress

Details, every field, queue names and WP-CLI: [references/wordpress.md](references/wordpress.md).

1. **Install.** Plugin "QuantCDN" from wordpress.org (slug `quantcdn`), version **1.6.0 or later**,
   from `Plugins > Add New` or `wp plugin install quantcdn --activate`. The GitHub `develop`
   branch (1.5.2) is older; do not install from it.
2. **Connect.** `Settings > QuantCDN`, tab **Settings**:
   - **API Endpoint**: `https://api.quantcdn.io` (default) or `https://api.quantgov.cloud`.
   - **API Customer** (the organisation), **API Project**, **API Token**: from the Integrations page.
   - **Webserver URL** `http://localhost` and **Hostname** = the public domain (`www.example.com`).
     The plugin fetches each page from the Webserver URL with that `Host` header. A WordPress.com
     site uses its `https://yoursite.wordpress.com` address.
   - Untick **Disable SSL verify**: the plugin turns it on at activation. Leave it off, certainly on QuantGov.
   - Tick **Automatic static push** and save. The page shows "Successfully made a connection to Quant."
3. **Seed.** Tab **Seed Settings**: tick "theme assets", add custom routes (for example `/robots.txt`),
   set the 404 path. Then push everything. The admin UI works (`Batches`, then **Start** per batch)
   but is slow. Use WP-CLI:

   ```bash
   wp quant info                                  # queues: items and processed counts
   wp quant process_queue all --threads=10        # default 5, maximum 20
   wp quant reset_queue all                       # start a queue again
   ```

4. **After the seed** the plugin pushes on `save_<post type>` for every post type and taxonomy.
   A post that is not published is unpublished instead; trashing a post unpublishes it. Tab **Cron**
   pushes chosen items (home, posts, pages, categories, tags, custom routes) on a WP-Cron schedule
   (`hourly`, `twicedaily`, `daily`). Tab **Cache** purges `/*` or listed paths by hand. With
   **Cache purge on save** on and **Automatic static push** off, a save purges the page only.

Plugin behaviour to know: Contact Form 7 needs `define('WPCF7_LOAD_JS', false);`; Elementor needs
"CSS Print Method" = "Internal Embedding"; Divi needs minify/combine off; Page Optimize or
Autoptimize can break the static CSS; the Redirection plugin's plain URL redirects are pushed as a
"Redirects" queue (no regex).

## CMS on Quant Cloud

Create the application from the template (`quant-templates`) with a managed database. The compose
contract, variables, volumes and cron are in `quant-cloud-apps`; this section is what is CMS-specific.

| Template | Notes |
|---|---|
| `app-drupal` | Drupal 11, PHP 8.4, Drush. `src/settings.php` is the single source of truth |
| `app-drupal-cms` | Drupal CMS. The whole `/opt/drupal` is on a volume so the UI can install modules; first boot copies the code onto it (a placeholder page shows for a few minutes) |
| `app-wordpress` | WordPress on `app-apache-php`, WP-CLI as `wp`, mu-plugins that read Quant variables |

**Database.** The platform injects `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`.
Drupal's `settings.php` reads them (legacy `MARIADB_*` as a fallback). In WordPress the entrypoint
maps them to `WORDPRESS_DB_*`. Never set `DB_*` in the deployed `environment:`; they replace what
the platform injects. The database connection uses TLS when the platform certificate bundle is present.

**Files on volumes.** Anything an editor writes must be on a volume, or it is lost at the next deploy.

| App | On a volume |
|---|---|
| `app-drupal` | `./src/web/sites/default/files:/opt/drupal/web/sites/default/files` |
| `app-drupal-cms` | `drupal_cms:/opt/drupal` (code, modules, files) |
| `app-wordpress` | `./wp-content:/var/www/html/wp-content` and `wordpress_data:/var/www/html` |

Keep these entries in `docker-compose.yml`, not in the override file (the override is local only).
Volumes are shared by all tasks and owned by UID 1000. On `app-drupal-cms` and `app-wordpress` the
volume keeps its files when you rebuild the image, so code from a new image does not replace the
code already on the volume: update WordPress core, plugins and themes with `wp` or wp-admin, and
Drupal CMS with Composer or the update UI inside the environment.

**Mail.** Set these on the environment (put the password in a secret):
`QUANT_SMTP_HOST`, `QUANT_SMTP_PORT` (587), `QUANT_SMTP_USERNAME`, `QUANT_SMTP_PASSWORD`,
`QUANT_SMTP_FROM`, `QUANT_SMTP_FROM_NAME`. The `app-apache-php` image starts a mail relay when
`QUANT_SMTP_HOST` is set, so PHP `mail()` and WordPress `wp_mail()` go through your SMTP provider.
`QUANT_SMTP_RELAY_ENABLED=true` selects the full Postfix relay; `QUANT_SMTP_FROM_DOMAIN` sets the
domain. The WordPress mu-plugin applies `QUANT_SMTP_FROM` and `QUANT_SMTP_FROM_NAME` as the
default From address and name. Your SMTP provider must allow the From domain.

**Cron.** Do not rely on page views. Create a Quant Cloud **Cron Job** (six-field schedule in UTC, for example `cron(0/5 * * * ? *)`
for every five minutes; see `quant-cloud-apps`):

- Drupal: `drush cron` every few minutes. The WordPress equivalent is below.
- WordPress: `wp cron event run --due-now --allow-root`, and set the environment variable
  `WORDPRESS_CONFIG_EXTRA=define('DISABLE_WP_CRON', true);` so visitors do not trigger it. The
  official image reads `WORDPRESS_CONFIG_EXTRA` (not `WP_CONFIG_EXTRA`, which the template README names).
  It applies only when `wp-config.php` is first created. For an existing environment run
  `qc exec run "wp config set DISABLE_WP_CRON true --raw --allow-root"`.

A cron or `qc exec` container has no web server. A task there that needs the Webserver URL (a Quant
push or seed) fails with "Unable to connect". Run a seed inside the live container (`qc ssh`).

To check a running environment from your laptop (`drush status`, `wp option get home`), use
`qc exec run` or `qc ssh` with `--org --app --env`. On QuantGov, first `qc login` and choose
**QuantGov Cloud**, then confirm with `qc platform current`; `qc` does not take the platform from a
flag. Details: `qc-cli`.

**Hosts behind the proxy.** The edge sends the visitor's host to the app.

- Drupal: `$settings['trusted_host_patterns']` in `src/settings.php` lists only the platform
  hostnames. Add your domain (`'^www\.example\.com$'`), commit, and redeploy. Without it every page
  says "The provided host name is not valid for this server". On `app-drupal-cms` the file was copied
  onto the volume at first boot: edit `/opt/drupal/web/sites/default/settings.php` in the
  environment too. The template already sets `reverse_proxy` and the forwarded headers.
- WordPress: the template's `quant-include.php` sets `WP_HOME` and `WP_SITEURL` from the request host
  and treats `X-Forwarded-Proto: https` as HTTPS, so no URL change is needed per domain.

**Your domain.** Create a CDN project whose proxy rule sends `*` to the application URL (proxy
settings, cache lifetime, timeouts: `quant-rules-and-routing`; DNS and certificate:
`quant-domains-cache-purge`). Let the CMS decide caching: leave "Cache lifetime" empty so its
`Cache-Control` is kept, and use `"0"` for login and admin paths.

### Both together

Run the CMS on Quant Cloud and push a static copy to a second project: install the module or plugin
in the app, set Webserver URL `http://localhost` and the host header to the public domain. In
`app-wordpress` the plugin settings can come from variables instead of the form: `QUANT_ENABLED`,
`QUANT_API_ENDPOINT`, `QUANT_CUSTOMER`, `QUANT_PROJECT`, `QUANT_TOKEN` (secret), `QUANT_WEBSERVER_URL`,
`QUANT_WEBSERVER_HOST`, `QUANT_DISABLE_TLS_VERIFY`, `QUANT_HTTP_REQUEST_TIMEOUT`. They overwrite the
saved settings on every request, so change them there, not in wp-admin.

## Go-live checklist

Applies to a static push; for the Cloud model skip the items about the push.

1. **Push finished.** Seed queues are empty (`wp quant info`, `drush queue:list`); the project lists the pages.
2. **Check the preview domain** of the project: pages, media, menus, search, forms, redirects, the 404 page.
3. **Settings clean.** TLS verification on; token in an environment variable or secret; Webserver
   URL and host header correct; tracking on; the Drupal `trusted_host_patterns` includes the host header.
4. **Domain.** Add every host to the project. QuantGov: create the DNS-validation records first and wait
   for Active. Lower the old records' TTL a day early (`quant-domains-cache-purge`).
5. **Cutover.** Create the records the dashboard shows. Wait for "DNS engaged". If HTTPS fails on
   QuantCDN, press Renew. Purge `/*` and check with `curl -sI https://www.example.com/`.
6. **Editors keep access** ([below](#keep-editors-working)).
7. **Do not deploy over it.** `quant deploy` unpublishes pages that are not in its directory,
   including pages the module or plugin pushed. Use `--skip-unpublish` for any partial deploy
   (`quant-static-sites`). Unpublished pages are not deleted; `quant publish /path` restores them.
8. **After go-live** a change to the theme or navigation needs a new full push.

### Keep editors working

Option 1: proxy editors to the CMS, same domain. Two proxy rules in this order, both to the CMS
origin (`$*` keeps the path; `quant-rules-and-routing`):

| Rule | Match | Settings |
|---|---|---|
| Login | `/wp-login*` (Drupal: `/user/*`) | Cache lifetime `"0"` |
| Editors | `*` | "Only with cookie": `wordpress_logged_in_*` (Drupal: `SSESS*`, or `SESS*` on http) |

Option 2: a separate editorial domain on the CMS. WordPress: `WP_HOME` and `WP_SITEURL` for that host
(`define('WP_HOME', 'https://edit.example.com');`). Drupal: add the host to `trusted_host_patterns`.
Hide the editorial host: an unguessable name, basic authentication, IP limits or a VPN, and 2FA in the CMS.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| "Unable to connect to local webserver" (both CMSs) | Webserver URL not reachable from the PHP process, `https` with a bad certificate, basic authentication or a WAF in front, or in Drupal the host header is not in `trusted_host_patterns` | Use `http://localhost` or the service name; add the host header to `trusted_host_patterns`; pass basic-auth credentials in the URL (`http://user:pass@localhost`); for a self-signed local certificate point the Webserver URL at plain `http://localhost`; WordPress: keep "Disable SSL verify" unticked (ticking it turns verification off for every plugin call); Drupal: "Verify SSL certificates" may be unticked for the local server only |
| "Unable to connect to the Quant API" / "QuantAPI error" | Wrong organisation, project name, token, or endpoint (still the public host on QuantGov) | Copy all four from the Integrations page; use the project "API name"; set the endpoint for your platform |
| Drupal "Seeding bailed. Another seed run is in progress" | A killed `quant:run-queue` left its lock file | `drush quant:unlock-queue`, then run again |
| Seed queue is empty after clicking Queue, or stale items run | The queue was not reset or cleared | `drush quant:clear-queue`, then `drush quant:seed-queue` |
| Nothing is pushed on save | "Track content change" / "Automatic static push" off; for Drupal, the entity type's tracking box off; the node is a draft | Turn on the setting; publish the content |
| `quant_cron` never pushes | It runs only from command-line cron | Run `drush cron` from a Cloud Cron Job |
| Pages pushed with absolute links to the local host | Host header wrong | Set HTTP Host header / Hostname to the public domain; Drupal: enable "Strip host domain from content" |
| Pages vanish from the live site after a deploy | `quant deploy` unpublished paths not in its directory | `quant publish` them or re-push; use `--skip-unpublish` |
| Static copy looks unstyled | CSS/JS aggregation or optimiser plugin writes absolute URLs | Disable Autoptimize or Page Optimize (WordPress), Divi minify; re-push |
| Drupal "The provided host name is not valid for this server" | Domain missing from `trusted_host_patterns` | Add it in `src/settings.php`, redeploy |
| Uploads or plugins disappear after a redeploy | The directory is not on a volume | Mount it as in [Files on volumes](#cms-on-quant-cloud) |
| WordPress admin redirects to the platform host name or loops | Fixed `WP_HOME`/`siteurl` in the database or `wp-config.php` | Remove the fixed values; the template derives them from the request host |
| Mail is not delivered | `QUANT_SMTP_HOST` unset, wrong port, or provider rejects the From domain | Set the variables; check task logs (`qc-cli`) |
| `DB_*` values ignored | `DB_*` set in the deployed `environment:` | Remove them; keep them in the override file |
| "Error establishing a database connection" on a new WordPress app | App created without a managed database | Create the app with a database (`quant-cloud-apps`) |
| Task keeps restarting on first boot of Drupal CMS | The copy to the volume takes minutes; health check too strict | Raise the startup grace period (`quant-cloud-apps`) |

## Further reading

- Drupal: https://docs.quantcdn.io/integrations/drupal/get-started/
- WordPress: https://docs.quantcdn.io/integrations/wordpress/
- Go-live: https://docs.quantcdn.io/integrations/go-live-process/
- Module: https://github.com/quantcdn/drupal and https://www.drupal.org/project/quantcdn
- Plugin: https://wordpress.org/plugins/quantcdn
- Templates: https://github.com/quantcdn-templates
- Related skills: `quant-cloud-apps` (compose, variables, volumes, cron, health), `quant-templates`,
  `quant-static-sites` (deploy and unpublish), `quant-domains-cache-purge` (domains, certificates, purge),
  `quant-rules-and-routing` (proxy rules), `qc-cli`, `quant-search`
