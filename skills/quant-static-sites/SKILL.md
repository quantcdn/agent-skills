---
name: quant-static-sites
description: Use when building and deploying static output (any static site generator or plain HTML) to a QuantCDN or QuantGov project and keeping it correct - which output directory to deploy (Astro, Hugo, Next.js export, Nuxt, Gatsby, Jekyll, Eleventy, Docusaurus, SvelteKit), `quant deploy` vs `quantcdn/deploy-action`, what the deploy unpublishes and how to stop it (`skip-unpublish`), `enableIndexHtml` and URL shape, a custom 404 (`_quant404`), revisions and rollback, purging after a deploy, and Quant Forms on a static site (exporting submissions with `form_fields=*`). Also use when deciding whether a generator-based site (Hugo, Astro, Next.js export and so on) should be a static site or a container app: if the output is files, it is a static site. Not for server-rendered apps (use `quant-cloud-apps`) or the full CI workflow detail (use `quant-ci-github-actions`).
---

# Static sites on Quant

A static site on Quant is a set of files you build elsewhere and push to a project on the content
API. Quant stores each path with its revisions and serves the published one from the cache.
For the platform overview and the public/gov split, load `quant-platform` first.

## Applies to

Both platforms: QuantCDN (`https://dashboard.quantcdn.io`) and QuantGov (`https://dash.quantgov.cloud`).
The features are the same. The only difference you configure is the content API endpoint.
Checked against `@quantcdn/quant-cli` 7.0.1, `quantcdn/deploy-action` v7.0.1 (runs CLI 7.0.1) and
`quantcdn/purge-action` v7, 2026-10.

| | Public | Gov |
|---|---|---|
| Content API endpoint (with `/v1`) | `https://api.quantcdn.io/v1` (default) | `https://api.quantgov.cloud/v1` |

Ask the customer for the dashboard URL if you do not know it. On gov, **set the endpoint on every
deploy and purge step**; both default to the public API and fail with a gov token.

Use a static project when the output is plain files. If the app needs a server process or a database,
use `quant-cloud-apps`. To start from a ready template, see `quant-templates`.

## Credentials

Deploys use the **project token** (Integrations page of the project), the customer (organisation)
name and the project name. A dashboard API token does not work on the content API. Keep the token in
a CI secret, never in the repository. CLI setup, env vars and precedence are in `quant-cli`.

## Choose the deploy path

| Situation | Use |
|---|---|
| Deploy from a laptop, a script, or any CI that is not GitHub | `quant deploy <dir>` (see `quant-cli`) |
| GitHub Actions | `quantcdn/deploy-action@v7` (runs the same CLI in a pinned container, no Node setup needed) |
| New project from a template or an imported GitHub repo | The dashboard wizard writes the workflow for you |

The action and `quant deploy` do the same work. Differences that bite:

- The action's `dir` is **relative to the workspace** (`dir: public`, not an absolute path). With no
  `dir` it deploys no assets.
- The action's `endpoint` defaults to the public API. On gov set `endpoint: https://api.quantgov.cloud/v1`.
- Inputs are `skip-unpublish`, `skip-unpublish-regex`, `skip-purge`, `force`, `chunk-size`,
  `revision-log`, `enable-index-html`. They map to the CLI flags of the same names.
- `deploy-action@v6` pins CLI 6.x. Use `@v7`. The full workflow, pinning by SHA and secrets
  layout are in `quant-ci-github-actions`.

Workflow fragment (gov shown; delete the two `endpoint` lines for public). It needs a checkout step and
your toolchain setup (for example `actions/checkout`, `actions/setup-node`) before the build. A full
workflow is in `quant-ci-github-actions`. Actions are pinned by commit SHA with the version in a
comment; look up the SHA of the latest release before you change a pin (see `quant-ci-github-actions`).

```yaml
- uses: actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0 (keeps the revision log between runs)
  with:
    path: .quant-revision
    key: quant-revision-${{ github.ref }}-${{ github.run_id }}
    restore-keys: quant-revision-${{ github.ref }}-
- run: npm ci && npm run build
- uses: quantcdn/deploy-action@9bf8cae8497ab6628d4b248db9eb11464f37e1e5 # v7.0.1
  with:
    customer: ${{ secrets.QUANT_CUSTOMER }}
    project: ${{ secrets.QUANT_PROJECT }}
    token: ${{ secrets.QUANT_TOKEN }}
    endpoint: https://api.quantgov.cloud/v1
    dir: dist
    revision-log: .quant-revision
    skip-purge: true
- uses: quantcdn/purge-action@6010adb4bef33827d7f7d1be8b1d955f693568e4 # v7.0.0
  with:
    customer: ${{ secrets.QUANT_CUSTOMER }}
    project: ${{ secrets.QUANT_PROJECT }}
    token: ${{ secrets.QUANT_TOKEN }}
    endpoint: https://api.quantgov.cloud/v1
    url_pattern: "/*"
```

CLI equivalent: `quant deploy dist` with `QUANT_CLIENT_ID`, `QUANT_PROJECT`, `QUANT_TOKEN` and
`QUANT_ENDPOINT` set (note: `QUANT_CLIENT_ID`, not `QUANT_CUSTOMER`).

## Output directory per framework

Deploy the directory that contains `index.html` for the home page. The directories are verified
against the Quant templates; the Notes column is general framework guidance.

| Framework | Build command | Deploy `dir` | Notes |
|---|---|---|---|
| Astro | `npm run build` | `dist` | `output: 'static'`; `build.format: 'directory'` (default) gives `/about/index.html` |
| Docusaurus | `npm run build` | `build` | |
| Eleventy | `npm run build` | `_site` | |
| Gatsby | `npm run build` | `public` | |
| Hugo | `hugo --minify` | `public` | |
| Jekyll | `bundle exec jekyll build` | `_site` | Use pretty permalinks (`/about/`) so pages become `about/index.html` |
| Next.js | `npm run build` | `out` | Needs `output: 'export'` and `trailingSlash: true`; set `images.unoptimized: true` |
| Nuxt | `npm run generate` | `.output/public` | `nuxt build` makes a server bundle; use `generate` (static preset) |
| SvelteKit | `npm run build` | `build` | `@sveltejs/adapter-static` with `prerender = true` |
| Plain HTML | none | the folder | |

Rules: always deploy the **built** directory, never the project root. Dot-directories such as
`.output/public` work; the CLI walks everything under `dir`. Any path containing `quant.json` (case-insensitive match) is skipped.

## URL shape and `enableIndexHtml`

The CLI publishes each HTML file at a path derived from its file path, **lowercased**:

| File in `dir` | Default URL | With `--enable-index-html` |
|---|---|---|
| `index.html` | `/` | `/index.html` |
| `about/index.html` | `/about` | `/about/index.html` |
| `about.html` | `/about.html` | `/about.html` |

- By default Quant removes `index.html` from the URL. This is what you want for almost every site.
- A generator that writes flat files (`about.html`) gets URLs ending in `.html`. Fix the generator
  (Next.js `trailingSlash: true`, SvelteKit `trailingSlash = 'always'` in the root layout,
  Jekyll pretty permalinks), do not rename files after the build.
- `--enable-index-html` (action input `enable-index-html: true`) keeps `index.html` in the URL.
  Use it only if existing URLs already end in `index.html`.
- **Decide once per project.** The first deploy saves the choice in `quant.json` and the CLI then
  refuses the opposite value. In CI there is usually no `quant.json`, so nothing guards you: keep
  the setting identical in every run, or the same page is published at two URLs.
- Keep file and directory names lowercase. HTML paths are lowercased on upload.

## What a deploy does

Details and edge cases: [references/deploy-behaviour.md](references/deploy-behaviour.md).

1. Walk `dir`, compute each file's MD5, upload files that changed. Each change creates a new
   revision and publishes it.
2. **Unpublish** every published path in the project that is not in `dir` (skipped with
   `--skip-unpublish`).
3. Purge the changed paths (skipped with `--skip-purge`).

### Unpublish is project-wide

Step 2 compares the whole project, not just what earlier deploys created. Pages made in the
dashboard editor, by a CMS, by `quant page` or by Studio are unpublished if they are not in the
build. Redirects and edge functions are never touched. Unpublished content is **not deleted**:
revisions remain and `quant publish /path` (or "Publish revision" in the dashboard) brings it back.

Pick one:

- Make the build the single source of truth for every path (best for pure static sites). If you
  move content that a deploy unpublished into the build, a cached revision log may still call the
  file unchanged and skip it, so the path stays unpublished: deploy once with `force: true`
  (`--force`) or drop the cached log.
- `--skip-unpublish` / `skip-unpublish: true`: never unpublish. Removed pages then stay live until
  you run `quant unpublish /path`.
- `--skip-unpublish-regex '^/legacy/'` / `skip-unpublish-regex: '^/legacy/'`: keep matching paths.
  The regex is tested against the stored URL (leading slash, lowercase).

**Safety:** a wrong or partial `dir` (for example a failed build that left a near-empty folder)
unpublishes every project page not in it. Make the build step fail the job on error so the deploy
never runs after a failed build. Run `quant scan --diff-only` before the first CI deploy of a
project and after any change to `dir`.

### Failure behaviour to know

- A file that fails to upload prints `Warning: Failed to deploy <file>` and the command **still
  finishes and continues to the unpublish step**. A green CI job does not prove every file arrived.
  Search the log for `Failed to deploy`.
- The revision log (default file `quant-revision-log_<project>` in the working directory, or
  `--revision-log <path>`) records `path + MD5` locally and skips matching files **without asking
  Quant**. It never forgets a path. If a page was unpublished and later returns with identical
  content, or someone changed a path in the dashboard, a cached log makes the deploy skip it. Use
  `--force` (`force: true`) for a full re-send, or delete the log.
- In CI keep the log in a cache with a unique key per run (as in the workflow above), otherwise
  every deploy re-sends every file.

## Custom 404

Quant serves the content at the `_quant404` route as the 404 page. A generator's `404.html` is just
another file at `/404.html`; it is **not** used automatically. Copy it into place before deploying:

```bash
mkdir -p dist/_quant404 && cp dist/404.html dist/_quant404/index.html
```

- Do this in the build step, in CI too (the Astro edge template does).
- A `_quant404` page created in the dashboard but missing from `dir` is unpublished by the next
  deploy. Ship it in the build or add `skip-unpublish-regex: '_quant404'`.
- Error page content can be cached for up to 5 minutes. Check with
  `curl -s https://example.com/no-such-page | head`.
- Studio's **Build & Publish** (Quant Builder) writes `_quant404` from the rendered `/404` page. A Studio
  site deployed by its GitHub workflow does not: copy the file as above (see `quant-studio`).
- WAF block pages use `_quant_waf_403` and `_quant_waf_429` (see `quant-rules-and-routing`).

## Revisions and rollback

Every changed upload creates a revision; the newest is published. See them in the dashboard
(Content, View Revisions), where you can publish an older one or delete a revision.

```bash
quant publish /pricing -r 12       # make revision 12 live
quant publish /pricing             # publish the newest revision
quant unpublish /pricing           # offline, revisions kept
quant delete /pricing --force      # removes ALL revisions (not a rollback)
```

- Rollback is per path. To roll back a whole deploy, check out the previous commit, rebuild and
  deploy with `--force` so files are re-sent even if the revision log thinks they are unchanged.
- Use the path as Quant stores it (`/pricing`, no `index.html`, unless the project uses
  `enable-index-html`).
- Purge after changing what is live: `quant purge /pricing`.

## Purge after deploy

The deploy purges the paths it changed. Every template runs a `purge-action` step with
`url_pattern: "/*"` after the deploy (some also set `skip-purge: true` on the deploy), so no stale
shared page survives. Quote `"/*"` in a shell. Soft purge, cache keys and domains: `quant-domains-cache-purge`.

## Forms

Quant Forms receives a POST from a plain HTML form. No server code is needed.

1. Build the form with `action="/contact" method="POST"`. In the dashboard Forms section, add a form
   for that same path and tick **Enable Quant Forms**.
2. Configure mandatory fields, fields to remove, honeypot fields, optional reCAPTCHA v2, email or
   Slack notifications and the success/failure messages.
3. Add `<div id="quant-form-result"></div>` where the result message should appear.
4. The form's configuration is separate from content, so a deploy does not unpublish it.

Export submissions with the content API (not the dashboard API). **`form_fields=*` is required**:
without it each row has only `form_uuid`, `date_submitted` and `file_count`.

```bash
curl -s "https://api.quantgov.cloud/v1/form-submissions?form_fields=*&page=1&page_size=500" \
  -H "Quant-Customer: $ORG" -H "Quant-Project: $PROJECT" \
  -H "Quant-Token: $PROJECT_TOKEN" -H "Quant-Url: /contact"
```

- `Quant-Url` is the path the form is attached to. On public, use `https://api.quantcdn.io/v1`.
- `page_size` is capped at 500. Read `total_forms` and `total_pages` and loop over `page`.
- No date filter exists. `date_submitted` is Unix seconds; filter after download.
- Other filters: `form_uuid`, `form_search` (slow), `has_files`, `sort_form_field`, `sort_direction`.
- Submissions hold personal data. Write exports outside the repository and do not paste rows into tickets.

A paginated CSV export is in [references/deploy-behaviour.md](references/deploy-behaviour.md#export-form-submissions-to-csv).

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| Pages added in the dashboard vanish after a deploy | Unpublish step compares the whole project | `skip-unpublish`, `skip-unpublish-regex`, or put the content in the build; restore with `quant publish /path`. If a restored file is then skipped because the revision log calls it unchanged, deploy once with `force: true` (`--force`) or drop the cached log |
| Pages live at `/about.html` | Generator wrote flat files | `trailingSlash` / pretty permalinks / directory format, rebuild, redeploy |
| Same page at `/about` and `/about/index.html` | `enable-index-html` changed between runs | Keep one setting; unpublish the unwanted duplicates |
| Generic Quant error page instead of ours | `404.html` is not the 404 route, or the dashboard copy was unpublished | Copy to `_quant404/index.html`, ship it in the build, wait up to 5 minutes |
| Deploy is green but files are missing | Upload failures only warn | Search the log for `Failed to deploy`, rerun with `--force` |
| Restored or edited page not updated by the next deploy | Cached revision log says unchanged | `--force` or clear the log |
| Deploy re-uploads everything every time | No cached revision log | Cache `.quant-revision` and set `revision-log` |
| 401/403 or 404 on every call on gov | Public endpoint default, or missing `/v1` | `https://api.quantgov.cloud/v1` on every deploy and purge step |
| Action deploys nothing | `dir` empty, or absolute | Set `dir` to a path relative to the workspace |
| Old content still served after deploy | Cache not purged (`skip-purge` without a purge step) | Run `purge-action` or `quant purge "/*"` |
| Form export has IDs and dates only | `form_fields` omitted | Add `form_fields=*` |
| Form export returns 400 | Wrong customer or project, or no form at the `Quant-Url` path | Check the three headers and the form path |
| Nuxt deploy has a server bundle | Ran `nuxt build` | Run `npm run generate`, deploy `.output/public` |

## Further reading

- Deploy a static site: https://docs.quantcdn.io/guides/getting-started/deploy-static-site/
- `quant deploy`: https://docs.quantcdn.io/content-cli/commands/deploy/
- Custom error pages: https://docs.quantcdn.io/custom-error-pages/
- Content and revisions: https://docs.quantcdn.io/dashboard/content/
- Forms and the export API: https://docs.quantcdn.io/dashboard/forms/
- Deploy action: https://github.com/quantcdn/deploy-action
- Related skills: `quant-platform`, `quant-cli`, `quant-ci-github-actions`, `quant-domains-cache-purge`,
  `quant-templates`, `quant-cms-integrations`, `quant-edge-functions-and-kv`, `quant-rules-and-routing`

<!-- checked against npm:@quantcdn/quant-cli 7.0.1 -->
<!-- checked against gh:quantcdn/deploy-action 7.0.1 -->
<!-- checked against gh:quantcdn/purge-action 7.0.0 -->
