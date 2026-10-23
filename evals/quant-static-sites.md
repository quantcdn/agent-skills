# quant-static-sites evals

Prompt: My Hugo site is in GitHub. We are on QuantGov (https://dash.quantgov.cloud). Write the GitHub Actions workflow that builds the site, deploys it to Quant on every push to main, and purges the cache afterwards. Use the maintained Quant actions and the right hosts. Show the full YAML in your answer.
Platform: gov
Must include:
- Output directory `public` (Hugo) passed as `dir:`
- `quantcdn/deploy-action@v7` with `endpoint: https://api.quantgov.cloud/v1` (the deploy action defaults to the public endpoint)
- `customer`, `project` and `token` inputs, where the token is the project token from the project's Integrations page stored as a secret (not a dashboard API token)
- A purge step with `quantcdn/purge-action@v7`, `url_pattern: "/*"` and the same gov `endpoint` (or `skip-purge: true` on deploy followed by that purge)
Must not include:
- `deploy-action@v6`
- `api.quantcdn.io` or `dashboard.quantcdn.io` for this customer
- `dash.quantgov.cloud/api/v2` as the deploy `endpoint`

Prompt: We build with Eleventy. The site deploys fine, but visitors who hit a missing URL see the generic Quant error page, not our `404.html`. Our build writes `_site/404.html`. A teammate also made a custom 404 in the dashboard editor last year. How do I get our own 404 page served and keep it from breaking?
Platform: public
Must include:
- Quant serves the content at the special `_quant404` route as the 404 page; a file named `404.html` is not special
- Copy the page to `_site/_quant404/index.html` (create the folder) before `quant deploy` / the deploy action
- Error page content can be cached for up to about 5 minutes
- A `_quant404` page created in the dashboard but absent from the build is unpublished by the deploy's unpublish step; include it in the build or use `--skip-unpublish-regex` / `skip-unpublish-regex` to keep it
Must not include:
- A claim that `404.html` becomes the 404 page automatically
- A claim that the dashboard copy is safe from `quant deploy`

Prompt: After our last CI deploy, three pages that editors created in the dashboard and a whole `/legacy/` section disappeared (404). Nobody ran unpublish. Redirects still work. Why, how do we get them back, and how do we stop it? We use quantcdn/deploy-action.
Platform: public
Must include:
- The deploy unpublishes every published path that exists in the project but not in the build directory, including content that was not created by a deploy
- Redirects and edge functions are skipped by that step (which is why the redirects survived)
- Content is only unpublished, not deleted, so revisions remain; restore with `quant publish /path` or "Publish revision" in the dashboard
- Prevent it with `skip-unpublish: true` or `skip-unpublish-regex: '^/legacy/'` on the action (flag `--skip-unpublish` / `--skip-unpublish-regex` on the CLI), or include the content in the build
- If a restored file is skipped on the next deploy because the revision log says it is unchanged, run with `force: true` / `--force` or drop the cached revision log
Must not include:
- That unpublish deletes content permanently
- That redirects are unpublished by a deploy

Prompt: I run `next build` with `output: 'export'` and deploy the `out` directory with `quant deploy out`. My pages appear at `/about.html` instead of `/about`. I also heard about `--enable-index-html`. What should I do, and can I flip that flag later?
Platform: public
Must include:
- Static export directory is `out`
- Set `trailingSlash: true` in `next.config.js` so the export writes `about/index.html`, which Quant publishes at `/about`
- By default Quant strips `index.html` from URLs; `--enable-index-html` (`enable-index-html: true` on the action) keeps `index.html` in the URL
- Choose once per project: after the first deploy `quant.json` records it and the CLI refuses a conflicting value; in CI without `quant.json` nothing guards it, so keep the setting identical in every run
Must not include:
- Advice to rename files by hand after the build
- A claim that the flag can be toggled freely per deploy

Prompt: Our marketing site on QuantGov (https://dash.quantgov.cloud) has a contact form that posts to /contact. Someone ran GET /form-submissions and got back only IDs and dates, no names or emails. Show me how to export every submission to a file.
Platform: gov
Must include:
- Request `https://api.quantgov.cloud/v1/form-submissions` with `form_fields=*` (without it only `form_uuid`, `date_submitted` and `file_count` are returned)
- Headers `Quant-Customer`, `Quant-Project`, `Quant-Token` (project token) and `Quant-Url: /contact`
- `page_size` is capped at 500; read `total_forms` / `total_pages` and loop over `page`
- There is no date filter; filter on `date_submitted` (Unix seconds) after fetching
Must not include:
- `api.quantcdn.io` for this customer
- A dashboard API Bearer token as the credential for this call

Prompt: A deploy pushed a broken /pricing page to production. I use the Quant content CLI. How do I put the previous version back for that page, and what can I not do?
Platform: public
Must include:
- Every changed deploy keeps a revision; list or view revisions in the dashboard (Content, View Revisions) and publish one with "Publish revision" or `quant publish /pricing -r <revision>`
- Rollback is per path; there is no single command that rolls back a whole deploy: redeploy the previous commit's build (use `--force` or discard the revision log so unchanged-looking files are re-sent)
- `quant unpublish` keeps revisions, while `quant delete` removes all revisions of the path
- Purge the cache afterwards (`quant purge /pricing`)
Must not include:
- `quant rollback` or any invented command
- Advice to use `quant delete` to roll back
