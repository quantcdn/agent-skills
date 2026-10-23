# quant-cms-integrations evals

Prompt: Our marketing site runs on Drupal 10 on our own servers. We want to keep Drupal for editors and serve the public site from a Quant project on QuantCDN (https://dashboard.quantcdn.io). Walk me through installing the Quant module, filling in the connection settings, and doing the first full push of about 40,000 nodes. Also say what happens when an editor saves, unpublishes or deletes a node afterwards.
Platform: public
Must include:
- Install with Composer: `composer require drupal/quantcdn` (the 1.x release line is for Drupal 10; the 2.x line is for Drupal 11; Drupal 9 is not supported); enable with `drush en quant` (this also enables the `quant_api` submodule)
- The settings are at `Configuration > Quant` (`/admin/config/quant`) and the API form at `/admin/config/development/quant/api`: API Endpoint, API Organization, API Project (the project "API name", not the display name) and API Token, all from the project's Integrations page in the dashboard (the project token, not a dashboard API token)
- Main page: keep "Track content change" on; set "Webserver URL" to the local web server (`http://localhost`, plain http, or a Docker service name) and "HTTP Host header" to the public domain, because Quant fetches each page from that local server and not from the public domain
- First push: Seed tab, leave "Trigger the batch" off for a large site, click Queue (or `drush quant:seed-queue`), then `drush quant:run-queue --threads=5`; add `$settings['queue_service_quant_seed_worker'] = 'quant.queue_factory';` to `settings.php`
- After the first push, saving a published node pushes it, unpublishing the default revision unpublishes the page in Quant, and deleting a node unpublishes it (drafts are not pushed while "Disable content drafts" is on)
Must not include:
- Drupal 9 as supported
- A claim that the Quant API Endpoint needs `/v1` added by hand
- `dash.quantcdn.io`

Prompt: We are a government agency on QuantGov (https://dash.quantgov.cloud). Our WordPress site is hosted by another supplier. I installed the QuantCDN plugin from wordpress.org and set it up, but I do not know what to put in the API endpoint field for QuantGov, and the field in the Drupal module of our sister agency looks greyed out. What do I enter in each? Then give me the WP-CLI commands for the first full push and tell me which plugin option I should switch off. Finally, how do later edits reach Quant, and how do I purge by hand?
Platform: gov
Must include:
- WordPress: on `Settings > QuantCDN`, tab "Settings", set "API Endpoint" to the QuantGov content API host `https://api.quantgov.cloud` (the plugin adds `/v1` itself); then API Customer (organisation), API Project and API Token from the dashboard Integrations page, and tick "Automatic static push"
- Drupal: the "API Endpoint" field on the API form is read-only; set it with `drush config:set quant_api.settings api_endpoint https://api.quantgov.cloud` or with `$config['quant_api.settings']['api_endpoint']` in `settings.php`
- Switch off "Disable SSL verify" (the plugin turns it on at activation); do not leave TLS verification disabled
- First push with WP-CLI: `wp quant info`, then `wp quant process_queue all --threads=10` (threads default to 5, maximum 20); `wp quant reset_queue <queue|all>` restarts a queue
- The plugin keeps pushing changes on save after that; the Cache tab can purge `/*` by hand
Must not include:
- `https://api.quantcdn.io` as the endpoint for this customer
- `dash.quantcdn.io`
- A claim that the Drupal endpoint field can be edited in the form

Prompt: I want to run a new WordPress site on Quant Cloud (QuantCDN, https://dashboard.quantcdn.io), not push a static copy. Which template, what does it do with the database variables, where must uploads and plugins live so they survive a redeploy, how do I send email, how do I run WP-Cron reliably, and how do I put my own domain in front of it?
Platform: public
Must include:
- Start from `quantcdn-templates/app-wordpress` (an app template; create the application with a managed database); the platform injects `DB_HOST`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` and the template's entrypoint maps them to `WORDPRESS_DB_*`; do not put `DB_*` values in the deployed compose `environment:`
- `wp-content` and the WordPress files are on a volume (`./wp-content` and `wordpress_data`), which on Quant Cloud is persistent storage shared by all tasks; uploads, plugins and themes installed in wp-admin survive a redeploy
- Mail: set `QUANT_SMTP_HOST`, `QUANT_SMTP_PORT`, `QUANT_SMTP_USERNAME`, `QUANT_SMTP_PASSWORD` (a secret) and `QUANT_SMTP_FROM` / `QUANT_SMTP_FROM_NAME` on the environment; the image configures a mail relay from them
- Cron: add a Quant Cloud Cron Job (six-field schedule in UTC) that runs `wp cron event run --due-now`, and turn off the page-view trigger with the environment variable `WORDPRESS_CONFIG_EXTRA=define('DISABLE_WP_CRON', true);` (the official image reads `WORDPRESS_CONFIG_EXTRA`, not `WP_CONFIG_EXTRA`); do not run `crond` in the web container
- Own domain: create a CDN project with a proxy rule to the application URL (see the domains and rules skills); `WP_HOME` and `WP_SITEURL` follow the request host automatically in this template, so no `siteurl` change is needed
Must not include:
- Storing uploads in the container filesystem outside a volume
- `DB_HOST: ${DB_HOST:-db}` or any `DB_*` value in the deployed `environment:`

Prompt: Our Drupal site on Quant Cloud (QuantGov, https://dash.quantgov.cloud) was created from the app-drupal template. It works on the platform hostname. After we put www.agency.gov.au in front of it, every page says "The provided host name is not valid for this server". Editors also report uploaded images vanish after a redeploy, and scheduled publishing never runs. What is wrong and what do we change? How do I check the fixes in the running environment from my laptop?
Platform: gov
Must include:
- Drupal rejects hosts that do not match `$settings['trusted_host_patterns']`; the template lists only the platform hostnames, so add the public host (for example `'^www\.agency\.gov\.au$'`) to `src/settings.php` in the repository, rebuild and redeploy (editing the file inside a running container is lost)
- Uploads vanish when `sites/default/files` is not on a volume: the template mounts `./src/web/sites/default/files:/opt/drupal/web/sites/default/files`; keep that entry in the compose file that Quant Cloud imports and do not move it to the override file; files belong to UID 1000
- Cron: Drupal cron does not run on its own with a cached front end; add a Quant Cloud Cron Job (six-field UTC schedule) that runs `drush cron`
- Check with `qc exec` or `qc ssh` (`drush status`, `drush cr`); on gov log in to `qc` with the gov platform
- The template already sets `reverse_proxy` and trusted forwarded headers for the proxy, so do not turn that off
Must not include:
- `$settings['trusted_host_patterns'] = ['.*']`, or a claim that the host check should be disabled
- `dashboard.quantcdn.io`

Prompt: We run WordPress on our own hosting and push it to a QuantCDN project with the plugin. Next week we cut over DNS. Give me the go-live checklist. Also: our developer ran `quant deploy ./build` last month for a landing page and most of the WordPress pages vanished from the live site, and editors now ask how to keep logging in to wp-admin on the public domain.
Platform: public
Must include:
- Before DNS: finish the full push and check every page on the project's preview domain; check forms, search and redirects; confirm the domain is added to the project and the DNS records come from the dashboard Domains page
- Cutover: lower the TTL a day earlier, create the CNAME (subdomain) or A records (apex) the dashboard shows, wait for "DNS engaged", renew the certificate if HTTPS fails, then purge and re-check
- `quant deploy` unpublishes every published path that is not in its directory, including pages pushed by the plugin; unpublished pages are not deleted and `quant publish /path` or "Publish revision" restores them; use `--skip-unpublish` (or a skip regex) for any deploy that is not the whole site, or push the landing page from WordPress
- Keep editor access with proxy rules to the WordPress origin: `/wp-login*` with cache lifetime `0`, then `*` with "Only with cookie" `wordpress_logged_in_*`; or run the CMS on a separate editorial domain and set `WP_HOME` / `WP_SITEURL` there
- Re-run a full push (`wp quant process_queue all`) after a theme or navigation change; after go-live only the origin handles editors, so protect it (random host name, basic authentication, IP limits)
Must not include:
- A claim that `quant deploy` leaves plugin-pushed pages alone
- `dash.quantcdn.io`
