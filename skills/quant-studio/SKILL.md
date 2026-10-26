---
name: quant-studio
description: Use when creating, editing, publishing or migrating a site with Quant Studio on QuantCDN or QuantGov - what Studio is (a visual editor and CMS for Astro sites kept in a GitHub repository) and when to choose it over a plain static template or a Quant Cloud CMS, creating a project from a Studio template (`ssg-astro-studio`, `ssg-astro-studio-civictheme`) or from an existing repository, editing entries and components, drafts, branches and preview environments, pull-request review, what publish does (GitHub workflow deploy vs Quant Builder "Build & Publish"), the custom 404 (`_quant404`), moving an existing site into Studio, and how redirects behave (Astro `redirects` become meta-refresh pages, not 301s; use Quant redirect rules where search ranking matters; paths match case-insensitively). Also use for Studio roles, permissions and API token scopes, and when a Studio save does not reach the live site, the Deploy button is missing, or a custom 404 does not show.
---

# Quant Studio

Quant Studio is a content management system for Astro sites that live in a GitHub repository. Content is
Markdown and MDX with typed frontmatter. Studio is a visual layer over Git: every edit is a commit, every
review is a pull request, every publish is a deployment. The site is ordinary Astro, so it still builds
without Studio. For the platform overview and the public/gov split, load `quant-platform` first.

## Applies to

Both platforms: QuantCDN (`https://dashboard.quantcdn.io`) and QuantGov (`https://dash.quantgov.cloud`).
Studio has the same features on both. Use the dashboard the customer logs in to. On QuantGov, the
Studio AI assistant uses Australian-resident models only (see `quant-ai`). Checked 2026-10 against the
Studio documentation, the `ssg-astro-studio` and `ssg-astro-studio-civictheme` templates, `deploy-action`
v7.0.1 and the in-browser build.

| | Public | Gov |
|---|---|---|
| Dashboard (wizard, Studio, Team) | `https://dashboard.quantcdn.io` | `https://dash.quantgov.cloud` |
| Studio API base | `https://dashboard.quantcdn.io/api/v2/organizations/{org}/projects/{project}/studio` | `https://dash.quantgov.cloud/api/v2/organizations/{org}/projects/{project}/studio` |
| Content API (deploy and purge steps) | `https://api.quantcdn.io/v1` | `https://api.quantgov.cloud/v1` |

On gov, the deploy and purge steps in the site's workflow need the gov `endpoint`. The Studio template
workflow targets the public content API by default; see `quant-templates`.

## When to use Studio

| Need | Choose |
|---|---|
| Editors change content in a browser, content stays in Git, the site is Astro | **Studio** (start from a Studio template) |
| Developers own the site, no visual editing | A static template (`ssg-*`) with `quant-static-sites` |
| A CMS with a database and server-side logic (Drupal, WordPress, Laravel) | Quant Cloud, see `quant-cloud-apps` and `quant-cms-integrations` |
| Only look around | The Studio demo: **Create Studio Project > Try the Demo**, no GitHub account |

Studio works only on Astro projects with at least one content collection. It does not edit a Drupal or
WordPress database. Content stays portable Markdown, MDX and JSON files in your repository.

## Create a site

In the dashboard open **Create Studio Project**. There are three paths, all needing a GitHub account:

| Path | Use it for |
|---|---|
| **Start from Template** | A new site. Pick a Studio template, authorise the Quant GitHub App once, then set the GitHub organisation, repository name, private or public, and the Quant project name (lowercase letters, numbers, hyphens, at most 32 characters) |
| **Connect Existing Repo** | An Astro repository with a content collection in `src/content/config.ts`. Studio reports what it detects, then opens a pull request that adds a deploy workflow. Merge it for the first deploy |
| **Import from Website** | Migrating a live site (see below) |

Studio templates (both are in `quantcdn-templates`; see `quant-templates`):

- `ssg-astro-studio`: blog and pages, Tailwind, MDX with a `Callout` component, dark mode, RSS, sitemap, OG images, 404 page.
- `ssg-astro-studio-civictheme`: the CivicTheme design system (77 components, news, events, publications) for government sites.

**Create & Deploy** creates the Quant project, a deployment token, the GitHub repository, the repository
secrets and variables (`QUANT_TOKEN`, `QUANT_CUSTOMER`, `QUANT_PROJECT`) and a deploy workflow, then builds
and deploys. Ask for the dashboard URL before you tell a customer which wizard to open.

## Edit content

- **Collections** (the home screen) list entries from `src/content/config.ts`. **New entry** writes a file
  to the current branch with `draft: true`, so it does not ship until you publish it.
- The **visual editor** shows a form generated from the Zod schema beside a live preview. Click an element
  in the preview to jump to its field. This needs `data-quant-field` attributes in the Astro template
  (Studio falls back to auto-annotation). The body is edited in a Markdown/MDX editor.
- **Save** commits to the current branch. **Save & Publish** sets `draft: false` and saves. Neither one
  makes the live site change by itself (see Preview and publish).
- Components and layouts are `.astro` files. Edit them in the **code editor** or **file browser**. The
  template's `quant.studio.json` lists the components that Studio offers when you insert one in MDX.
- Other screens: media browser, schema editor (add collections and fields), Settings (production branch,
  languages, brand and tone for the AI assistant), Forms and Search panels (enable them on the project
  first), and an edge function editor (files in `quant/edge-functions/`; see `quant-edge-functions-and-kv`).
- The **AI assistant** (Cmd/Ctrl+J) creates and edits entries and files, and can raise pull requests.

A draft entry is not built into the site. The template excludes drafts from listings, the feed and static
pages, and Studio still previews them. Set `draft: false` (or **Save & Publish**) to ship.

## Branches, preview and review

- The production branch is `main` unless you change it in **Settings > General > Production branch**.
  Studio pull requests always target it.
- Every other branch is a working branch. **New branch** creates it in GitHub and, by default, imports it as
  a preview environment: a separate child project with its own preview URL and deployment. It does not
  change the live site.
- **Review** opens (or reuses) a pull request to the production branch. The detail view shows diffs (content
  or code view), inline comments and **Merge**. A GitHub branch-protection rule can block the merge.
- After a merge, **Delete branch** removes the preview environment and then the Git branch. **Remove** on a
  branch under **Branches** deletes the environment and keeps the Git branch.

## Preview and publish

Preview is the in-browser render and the branch preview URL. Nothing is live until the production branch is
deployed. There are two ways to deploy, chosen in **Settings > General > Use Quant Builder (beta)**.

| | Quant Builder off | Quant Builder on |
|---|---|---|
| What publishes | A commit or merge on the production branch starts the GitHub workflow: `npm run build`, then `deploy-action` uploads `dist`, then a purge | **Deployments > Build & Publish** builds the site in your browser and uploads the pages to the project, and syncs media |
| Studio commits | Plain commits | Tagged `[skip deploy]`, so the workflow does not also run |
| Deploy button | **Deploy** (dispatches the workflow) | **Build & Publish**, plus **Force** (clear the revision log and re-send every page) |

- Watch runs on the **Deployments** screen (status, jobs, step logs, **Cancel**, **Re-run**). After a merge the
  collection browser shows the latest deployment state.
- Build & Publish reports pages published, unchanged, skipped and failed. A route that needs a native
  dependency the browser cannot run (for example OG images built with `satori` and `resvg`) is skipped with a
  warning. The workflow deploy produces those assets.
- After a clean, complete Build & Publish, any route that an earlier Studio publish created and the new build
  no longer produces is unpublished. A build with failures never unpublishes.
- Studio publish also creates declared KV stores and project settings from `quant/meta.json`, deploys
  `quant/edge-functions.json` entries, then applies `quant/edge-rules.json` (see `quant-templates`,
  `quant-edge-functions-and-kv`). Each part needs a permission of the person who publishes; without it
  the Deployments page shows that part as `skipped`, with the permission it needs.
- Page `<script>` blocks get `import.meta.env` replaced at build time, as in `astro build`: `MODE`,
  `DEV` (false), `PROD`, `SSR` (false), `BASE_URL` (from `base`), `SITE` and `PUBLIC_*` variables from
  `.env` files. Other variables never reach the browser. `import.meta.url` is left to the browser.
- **Edge functions are synced as committed source.** For each manifest entry, Studio reads the file at
  `path` from the branch and uploads its text unchanged. Studio publish does not run `npm` scripts,
  package build hooks or a bundler for function files, and the site build does not feed them. A
  missing file is reported as `file not found in branch`; a function sync failure does not stop the
  site publish, so read the publish summary.
- If your function code is generated (TypeScript, bundled imports, templated values), use one of:
  1. Build it locally or in a pre-commit step and **commit the output file** that the manifest names.
  2. Build it in CI and deploy with `quant functions` or `deploy-action` `functions:` (see
     `quant-ci-github-actions`). Then keep the entry out of the Studio-synced manifest, or commit the same
     built file, so two sources do not overwrite each other on the same UUID.
  Do not assume a package script ran before the manifest sync. Test any other build path yourself first.
- Quant purges a path when the content API changes it. For a custom domain, TLS and extra purges, see
  `quant-domains-cache-purge`.

## Custom 404

Quant serves the content at `/_quant404` as the 404 page; `404.html` alone is not used.

- **Build & Publish** copies the rendered `/404` page (`src/pages/404.astro`) to `/_quant404` and
  `/_quant404/index.html` on every publish. It never overwrites a `_quant404` that you provide.
- The **GitHub workflow** deploy does not do this. `astro build` writes `dist/404.html`, and the template
  workflow uploads `dist` as it is. Add this to the build step before the deploy, or use Build & Publish:

```bash
npm run build && mkdir -p dist/_quant404 && cp dist/404.html dist/_quant404/index.html
```

A `_quant404` that you provide (as above) is never overwritten by
Build & Publish, so the same fix is safe if you later switch to browser publishes. Error page content
can be cached for up to 5 minutes. Check with
`curl -s https://example.com/no-such-page | head`. More in `quant-static-sites`.

## Migrate an existing site

**Import from Website** takes a live URL and generates a Studio-ready Astro project: content detection,
schemas and a Tailwind replica. Projects made this way get a **Migration** screen with the source URL, pages
crawled, entries saved, and coverage per collection (under 90% is flagged). Use **Refresh Content** to
re-crawl all pages, selected pages or typed URLs from the source. Check unmapped pages by hand.

Plan the URL map before go-live. The old sitemap is the contract: each old URL must answer 200 on the new
site, or redirect to a page that does.

### Redirects

| Mechanism | What a visitor and a crawler get | Use for |
|---|---|---|
| Astro `redirects` in `astro.config.*` (both `'/from': '/to'` and `{ status, destination }`, including maps imported from a module) | A small HTML page at the old path with a meta refresh, a canonical link and `noindex`. The HTTP response is 200. The `status` value is not sent as an HTTP status; it only sets the refresh delay: `status: 302` waits 2 seconds before the refresh, other values refresh at once | Minor and internal moves |
| Quant **redirect rule** (dashboard **Rules**, rules API, Terraform, Pulumi) | A real HTTP redirect with the code you set (`redirect_code` 301, 302, ...) | URLs with traffic, backlinks or ranking; non-HTML files |

- Where search ranking matters, create Quant redirect rules and not Astro `redirects`. Rules are evaluated
  before the published page, in order, and the first matching redirect rule wins and ends processing. Field names, ordering and bulk edits:
  `quant-rules-and-routing`. Purge the old paths after you change a redirect rule.
- A real page at the same path wins over an Astro redirect page. Redirect pages stay out of the sitemap.
- **Paths match case-insensitively.** `/About` and `/about` are the same path. If an old URL differs from
  a live page only by case, the redirect page replaces the live page. Remove that redirect.
- Template URLs have no trailing slash (`trailingSlash: 'never'`, directory output). Write old and new paths
  without one to avoid a second redirect.
- Remove chains and loops, and check every target with `curl -sI` before DNS moves. Test the new site on its
  project domain before you move DNS. DNS and TLS: `quant-domains-cache-purge`.

## Roles and API

Assign roles under **Team** in the dashboard. A call to the Studio API needs the user permission and a token
scope.

| Permission | Token scope | Allows |
|---|---|---|
| `browse_studio` | `studio:read` | Read collections, entries, media, branches, pull requests, deployments |
| `edit_studio` | `studio:write` | Create and update entries, upload media, create branches, create and merge pull requests, use the AI assistant |
| `delete_studio` | `studio:delete` | Delete entries and media |
| `manage_studio` | `studio:admin` | Create and delete preview environments, refresh the cached schema |

Built-in roles: **Organisation Owner** and **Organisation Admin** (all), **Studio Editor** (browse, edit,
delete), **Studio Read Only** (browse). The API sends `Authorization: Bearer <token>`. Most calls take a
`branch` query parameter; without it the API uses `main`, even if your production branch is different.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| Saved in Studio, the live site did not change | Quant Builder is on: commits are tagged `[skip deploy]` and nothing deploys | Run **Deployments > Build & Publish**. If the entry is `draft: true`, use **Save & Publish** |
| No **Deploy** button on Deployments | Quant Builder is on; **Build & Publish** replaces it | Use it, or turn Quant Builder off in **Settings > General** |
| New entry is not on the live site | New entries are `draft: true`, and drafts are not built | **Save & Publish**, then deploy |
| Custom 404 not shown on a workflow-deployed Studio site | The workflow uploads `dist/404.html`; nothing creates `_quant404` | Copy it to `dist/_quant404/index.html` in the build, or use Build & Publish; wait up to 5 minutes |
| An old URL shows a blank page then jumps, or ranking drops after the move | The redirect is a meta-refresh page with a 200 status | Use a Quant redirect rule with a 301 for those URLs |
| A live page disappeared after adding redirects | A redirect source equals the page path in another case | Remove the redirect |
| Read Only user cannot create a branch | `browse_studio` only | Give **Studio Editor** (`edit_studio`) |
| API call returns 403 | Token lacks the scope, or the user lacks the permission | Use a token with the matching `studio:*` scope |
| API call edits the wrong branch | `branch` defaults to `main` | Pass `?branch=<name>` |
| Merge is rejected | GitHub branch protection | Satisfy the rule in GitHub (reviews, checks) and merge again |
| Edge function from Studio publish is stale, empty or a source file | The manifest `path` names a file that a build step generates; Studio uploads the committed file as is | Commit the built file, or build in CI and deploy with `quant functions` |
| Route missing after Build & Publish, with a warning | It needs a native dependency the browser cannot run | Deploy with the workflow for those assets |

## Further reading

- Studio overview: https://docs.quantcdn.io/studio/overview/
- Creating a project: https://docs.quantcdn.io/studio/creating-a-project/
- Review and publishing: https://docs.quantcdn.io/studio/review-publishing/
- Deployments and Quant Builder: https://docs.quantcdn.io/studio/deployments/
- Migration: https://docs.quantcdn.io/studio/migration/
- Permissions and roles: https://docs.quantcdn.io/studio/permissions/
- Custom error pages: https://docs.quantcdn.io/custom-error-pages/
- Related skills: `quant-templates`, `quant-static-sites`, `quant-rules-and-routing`,
  `quant-domains-cache-purge`, `quant-edge-functions-and-kv`, `quant-ai`, `quant-ci-github-actions`

<!-- checked against gh:quantcdn/deploy-action 7.0.1 -->
