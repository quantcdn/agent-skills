# quant-ci-github-actions evals

Prompt: Write the GitHub Actions workflow for my Hugo site on QuantCDN (dashboard.quantcdn.io). Every push to `main` builds with `hugo --minify` and deploys to the Quant project `marketing` in organisation `acme`, then clears the cache. Our security team requires every third-party action to be pinned to a commit SHA, not a tag. Tell me which values go in repository secrets and which in variables, and why each choice.
Platform: public
Must include:
- `quantcdn/deploy-action@9bf8cae8497ab6628d4b248db9eb11464f37e1e5` with the comment `# v7.0.1`
- `quantcdn/purge-action@5c2a85f5318917ef12b9099cf101fe6bd75d0d06` with the comment `# v7.1.0`, `url_pattern: "/*"`
- `dir: public` (relative to the workspace)
- The project token (from the project's Integrations page) is a secret; customer and project names are not sensitive and can be variables
- If the build fails, the job stops before the deploy step, because a deploy of a partial or empty directory unpublishes every page that is not in it
- Keep the version in a comment next to each SHA, and let Dependabot (`github-actions` ecosystem) update pinned SHAs
- Third-party actions such as `actions/checkout` are pinned with a SHA that comes from a lookup (the skill's reference files, `gh api repos/actions/checkout/commits/<tag> --jq .sha` or `git ls-remote`) or a clearly marked placeholder, and the answer says not to recall SHAs from memory
Must not include:
- `deploy-action@v6`
- A dashboard API key (`QUANT_API_KEY`) as the deploy token
- An absolute path for `dir`

Prompt: We are on QuantGov (https://dash.quantgov.cloud). Our Quant Cloud app `intranet` (organisation `dept-x`) has one compose service named `web`, a managed MySQL database, and deploys from `main` with the Quant Cloud GitHub actions. Write a second workflow that gives each pull request its own preview environment: same configuration as production, a copy of production's database, updated on each push to the PR, and removed when the PR is closed or merged.
Platform: gov
Must include:
- Every Quant Cloud action sets `base_url` to the gov dashboard (`https://dash.quantgov.cloud/api/v3` or `https://dash.quantgov.cloud`)
- The init action names a pull request's environment `pr-<number>` and its image suffix `pr-<number>`; the image tag is `web-${{ steps.init.outputs.image_suffix_clean }}`
- `quantcdn/quant-cloud-environment-action` with `from_environment: production` when the environment is created
- `quantcdn/quant-cloud-environment-sync-action` with `source: production`, `type: database` and `wait: true`
- A job for `pull_request` `closed` that runs the environment action with `operation: delete` for `pr-<number>`
- Pull requests from forks get no secrets, so the preview job must skip them
Must not include:
- `dashboard.quantcdn.io`
- `quant-cloud-ecr-action` or a separate `docker/login-action` step for the Quant registry
- An action that is not one of the published `quantcdn/*-action` repositories

Prompt: Three problems with our Quant Cloud GitHub workflow (public dashboard). 1) Every run is green, but yesterday the site kept serving the old release for an hour. 2) We set the production environment to 2-6 tasks in the dashboard, and after every deploy it is back to 1. 3) We added `quantcdn/quant-cloud-environment-var-action@v1` with `base_url: https://dashboard.quantcdn.io/api/v3` and it fails with "The route api/v3/api/v3/organizations/... could not be found." Our deploy uses init, compose, environment (create or update) and state redeploy, all `@v4`. Explain each problem and the fix.
Platform: public
Must include:
- The actions ask the platform to deploy and return; they do not wait for the new containers to become healthy, so a green run does not prove the release is live
- Confirm the release with `qc env list` (running vs desired), `qc env logs`, and the dashboard Deployments tab (or the environment's `deploymentStatus` from the API)
- Environment action v4.0.0 and earlier send `minCapacity` and `maxCapacity` (default 1) on every create and update, which replaces the scaling set in the dashboard; v4.1.0 sends them only when `min_capacity`/`max_capacity` are set, so pin v4.1.0 by SHA (or pass both inputs)
- `quant-cloud-environment-var-action` v1.0.2 and earlier do not strip `/api/v3`, so a value ending `/api/v3` doubles the path; v1.0.3 strips it, so pin v1.0.3 by SHA, or use the bare host `https://dashboard.quantcdn.io` (or omit `base_url`; the default is the bare public host)
Must not include:
- A claim that a green run proves the new version is live
- Names a cloud vendor or managed service

Prompt: We use GitLab CI, not GitHub, and our dashboard is https://dash.quantgov.cloud. One job must deploy the static site in `dist/` to our Quant project and clear the cache. Another job must redeploy the Quant Cloud environment `production` of application `intranet` (organisation `agency`) after we push a new image. Can we use `qc` in the pipeline with a token? Show both jobs.
Platform: gov
Must include:
- The static job runs `quant` (the `quantcdn/cli:7.0.1` image with its entrypoint cleared, or `npm install -g @quantcdn/quant-cli`) with `QUANT_CLIENT_ID`, `QUANT_PROJECT`, `QUANT_TOKEN` and `QUANT_ENDPOINT=https://api.quantgov.cloud/v1`
- `quant deploy dist` followed by `quant purge "/*"`
- `qc` logs in with a browser (OAuth) and has no token option for unattended use, so the pipeline calls the platform API with `curl` instead
- `PUT https://dash.quantgov.cloud/api/v3/organizations/agency/applications/intranet/environments/production/state` with `{"action": "redeploy"}` and `Authorization: Bearer <API token>`
- Keep the tokens in masked CI/CD variables, not in the repository
Must not include:
- `qc login --token`, `QC_TOKEN` or any other invented non-interactive `qc` login
- `QUANT_CUSTOMER` as the variable that `quant` reads
- `dashboard.quantcdn.io` or `api.quantcdn.io`

Prompt: QuantGov customer (dash.quantgov.cloud). In our GitHub workflow we want to (a) store our payment provider key `STRIPE_SECRET` on the `production` environment of app `shop` with `quantcdn/quant-cloud-environment-var-action`, so it is not visible to people who open the dashboard, and (b) push search records from `search/*.json` to our Quant project with `quantcdn/search-action@v2`. Write the steps.
Platform: gov
Must include:
- The environment variable action sets plain environment variables, not secrets; anyone with access to the environment can read the value. Put `STRIPE_SECRET` in the environment's secrets in the dashboard instead
- Changed variables or secrets reach the containers only after a redeploy (state action `action: redeploy`)
- The variable action's `base_url` is the gov dashboard: the bare host `https://dash.quantgov.cloud` (v1.0.3 also accepts `/api/v3`)
- `search-action` v2.1.0 takes the gov `endpoint` with `/v1` (`https://api.quantgov.cloud/v1`), and `path` is one JSON file per step (a directory indexes nothing), so the files are indexed one step each or merged into one file first
Must not include:
- A claim that the environment variable action stores secrets or hides the value
- `endpoint: https://api.quantgov.cloud` without `/v1` on search-action v2.1.0
