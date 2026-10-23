# quant-studio evals

Prompt: My team will run a marketing site with a blog, and two non-developers must edit it and publish changes. I want a visual editor and a Git history. Is Quant Studio the right choice compared with a static site generator template on its own, or a Drupal or WordPress site on Quant Cloud? If Studio fits, tell me how to create the site, how an editor writes a new post without it going live by accident, and what an editor does to publish it.
Platform: public
Must include:
- Studio is for Astro sites stored in a GitHub repository; content stays as Markdown/MDX files in that repository, and Studio is a visual layer over Git (every save is a commit)
- Create it from the dashboard: **Create Studio Project**, then **Start from Template**, using a Studio template (`ssg-astro-studio`, or `ssg-astro-studio-civictheme` for a government design system); this needs a GitHub account and the Quant GitHub App
- The wizard creates the Quant project, a deployment token, the GitHub repository, the repository secrets and variables, and a deploy workflow
- A new entry is created with `draft: true`, and a draft is not built or published; **Save & Publish** sets `draft: false`
- Content reaches the live site by merging to the production branch (`main` by default), for example through the **Review** pull request, or through **Build & Publish** when Quant Builder is on; save alone commits to the branch and does not publish
- A server-rendered CMS (Drupal, WordPress) is a different product on Quant Cloud; choose it when you need a database or server-side logic
Must not include:
- That Studio edits a WordPress or Drupal site
- That Studio stores content in a Quant-hosted database instead of the GitHub repository

Prompt: We are on QuantGov (https://dash.quantgov.cloud). We are moving a 3,000-page Drupal site into Quant Studio. We have a CSV of about 1,200 old-URL to new-URL redirects, and search ranking matters a lot. Put the redirects in `astro.config.mjs` `redirects`? What will visitors and search engines actually get, what should we do for the important ones, and what URL mistakes break pages?
Platform: gov
Must include:
- Astro `redirects` entries are published by Studio as small HTML pages at the old path that use a meta refresh (with a canonical link and `noindex`), not as HTTP 301 responses
- For URLs where search ranking matters, use Quant redirect rules (real HTTP redirects) in the dashboard on `https://dash.quantgov.cloud`, via the rules API, or Terraform or Pulumi; rules are evaluated before static content and first match wins
- A real page at the same path wins over a redirect page in Studio
- Quant matches paths case-insensitively, so an old URL that differs from a live page only in case collides with that page; remove that redirect
- Check chains and loops, and check that every redirect target answers 200, before DNS moves
- The **Import from Website** path (AI-assisted migration) crawls a live URL and generates a Studio project; the **Migration** screen shows coverage and refreshes content from the source
Must not include:
- That Astro `redirects` return a 301 status from Quant
- That regular expressions work in a Quant redirect URL pattern

Prompt: Our Studio site, created from the `ssg-astro-studio` template, deploys with the GitHub workflow in the repository. We have a nice `src/pages/404.astro`, but a missing page still shows the plain generic Quant 404. A colleague says "Studio writes the custom 404 on publish". What is going on and what do we change?
Platform: public
Must include:
- Quant serves the content at the `_quant404` route as the 404 page; a generator's `404.html` is just another file and is not used
- Studio's own build (Build & Publish with Quant Builder) copies the rendered `/404` page to `_quant404`; the GitHub workflow deploy (`npm run build` then `deploy-action` with `dir: dist`) does not, so the colleague's statement holds only for browser publishes
- Fix for the workflow: copy `dist/404.html` to `dist/_quant404/index.html` in the build step before the deploy (or publish with Build & Publish)
- An author-provided `_quant404` file is not overwritten; error page content can be cached up to 5 minutes
- Check with `curl -s https://<site>/a-path-that-does-not-exist | head`
Must not include:
- That `404.html` at the output root becomes the 404 page by itself

Prompt: An editor says: "I saved my changes in Studio, the preview looks right, but the live site did not change, and the Deploy button is missing on the Deployments page." Another editor with the Studio Read Only role says she cannot create a branch. Explain both, and tell me which role and which API token scope a content editor and a reviewer need. We use https://dashboard.quantcdn.io.
Platform: public
Must include:
- Quant Builder (beta) is on in **Settings**; Studio commits are tagged `[skip deploy]` so the GitHub workflow does not deploy, the **Deploy** button is replaced by **Build & Publish**, and the editor must run it (Force republishes every page)
- Turning Quant Builder off restores the **Deploy** button and the workflow deploys on commits
- Preview is the in-browser render and the branch preview environment; publish is a deployment of the production branch
- Studio Read Only has only `browse_studio`; creating a branch needs `edit_studio` (the Studio Editor role)
- Token scopes: `studio:read` (browse), `studio:write` (edit, create branches and pull requests), `studio:delete`, `studio:admin` (environments, schema refresh); the token needs the scope and the user needs the permission
- Roles are assigned under **Team** in the dashboard
Must not include:
- That Studio Read Only can merge pull requests

Prompt: We have a Studio site. Our 4 staging branches each have a preview URL. Explain how branches and preview environments relate to the live site, what Review and merge do, and how we clean up. Also: after I merge, where do I watch the publish, and what do I check when the run fails?
Platform: public
Must include:
- Production branch is `main` unless changed in **Settings > General > Production branch**; pull requests from Studio always target it
- A branch imported as an environment is a separate child project with its own preview URL and deployment; it does not change the live site
- **Review** opens (or reuses) a pull request to the production branch; merging it triggers the deployment workflow
- The Deployments screen shows workflow runs, jobs and step logs, with Cancel and Re-run
- After a merge, **Delete branch** removes the preview environment first, then the Git branch; **Remove** on an environment keeps the Git branch
- A merge can be blocked by a GitHub branch-protection rule
Must not include:
- That removing an environment deletes the Git branch
