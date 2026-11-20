---
name: quant-ci-runners
description: Use when running GitHub Actions jobs on Quant CI runners on QuantCDN or QuantGov - creating a CI runner pool (Small, Medium, Large; arm64 and x64), connecting the GitHub App to a GitHub organisation, the `runs-on: [self-hosted, quant, <pool>, <arch>]` labels, CI secrets and variables (org scope, repo scope, branch rules, `${{ env.NAME }}` instead of `${{ secrets.NAME }}`), the values API `{dashboard}/api/v3/organizations/{org}/ci/values`, the build cache (`actions/cache`, buildx `type=gha`, cache residency, clear the cache), and migrating workflows and their existing GitHub secrets from GitHub-hosted runners without typing any secret again. Also use when a cache is not restored, a Quant job stays queued, a job on a public repository never starts, a value is empty in a job, a pull request from a fork gets no values, or a branch-scoped value is missing on a tag or pull request run.
---

# Quant CI runners

Quant CI runners run GitHub Actions jobs on Quant, in the same platform as your Quant Cloud
apps. Each pool is single tenant: your jobs never share a machine with another customer. Jobs
have Docker (including `docker build`, `docker compose` and nested containers), `sudo`, and the
common build tools. For the workflows that deploy to Quant (deploy-action, the Quant Cloud
actions), use `quant-ci-github-actions`; this skill covers where those jobs run and where their
secrets live.

## Applies to

Both platforms: QuantCDN (`https://dashboard.quantcdn.io`) and QuantGov (`https://dash.quantgov.cloud`).
GitHub Actions only. CI runner pools must be enabled for your Quant organisation; if the
dashboard does not show **Cloud → CI runners**, contact support.
Checked 2026-11-21 against the dashboard, the values API and the GitHub Actions runner 2.338.

## Pools

Create and manage pools under **Cloud → CI runners → Pools**.

| Tier | Concurrent jobs | Each job gets |
|---|---|---|
| Small | 2 | 2 vCPU, 7 GB memory, 50 GB disk |
| Medium | 4 | 4 vCPU, 14 GB memory, 75 GB disk |
| Large | 8 | 4 vCPU, 14 GB memory, 75 GB disk |

- A pool has a fixed monthly price (shown on the create form) and a fixed maximum: jobs above the
  concurrent-job limit wait in GitHub's queue, they never add cost. The dashboard shows an alert
  when the pool is at capacity or jobs wait too long, with a link to upsize.
- Choose one or both architectures: `arm64` and `x64`. Both are in the same price.
- Machines start when jobs arrive and stop when the pool is idle. The first job after an idle
  period waits about one minute for a machine.
- A pool serves **private repositories only**. Jobs from public repositories are never picked
  up (anyone can open a pull request on a public repository).

### Connect GitHub

1. Create the pool, then select **Connect GitHub** on it.
2. Install the Quant GitHub App on your GitHub organisation. Choose **All repositories** or
   select the repositories that may use the pool.
3. In your GitHub organisation's runner group settings, keep **Allow public repositories** off.

One pool serves one GitHub organisation.

### Cache residency

Each pool has a **Cache residency** setting. It decides what happens when the pool's cache is
unavailable. See [Build cache](#build-cache).

### Labels

The dashboard shows the exact `runs-on` line for each architecture of the pool:

```yaml
runs-on: [self-hosted, quant, build, arm64]   # pool "build", arm64
runs-on: [self-hosted, quant, build, x64]     # pool "build", x64
```

- `quant` and the pool name select the pool. The architecture label selects the machine type.
- Without an architecture label, the job runs on the pool's only architecture, or on `x64` when
  the pool has both.
- A job that asks for an architecture the pool does not have is not picked up.

## Secrets and variables

Quant gives each job its secrets and variables when the job starts. Manage them on the
**Cloud → CI runners → Secrets and variables**, or with the values API.

| | Secret | Variable |
|---|---|---|
| Readable after save | No (replace only) | Yes |
| Masked in job logs | Yes, each line of a multi-line value | No |
| In the job | `${{ env.NAME }}` or `$NAME` | `${{ env.NAME }}` or `$NAME` |

- **Scope.** An org-scope value goes to every repository the App can see. A repo-scope value
  (`owner/name`) goes to that repository only and wins over an org value with the same name.
- **Branch rules.** Optional, up to 20 per value. `main` matches one branch; `release/*` matches
  a prefix. A value with branch rules goes only to `push`, `workflow_dispatch`, `schedule` and
  `release` runs on a matching branch. It never goes to `pull_request` runs or tag pushes. Use
  branch rules for deploy credentials, the way you used GitHub environments.
- **Forks.** A pull request from a fork gets no values at all.
- **Names.** `A-Z`, `0-9` and `_`, not starting with a digit, at most 100 characters. Reserved:
  `CI`, `HOME`, `PATH`, `IFS`, `ENV`, `BASH_ENV`, `PS4`, `SHELLOPTS`, `BASHOPTS`,
  `PROMPT_COMMAND`, and names that start with `GITHUB_`, `ACTIONS_`, `RUNNER_`, `QUANT_CI_`,
  `LD_` or `BASH_FUNC_`.
- **Limits.** 48 KB per value, 200 org values, 100 values per repository, 256 KB per scope.
- **Fail closed.** If Quant cannot confirm which job is running, the job stops before its first
  step instead of running without its values.
- `${{ secrets.GITHUB_TOKEN }}` does not change. GitHub still issues it to every job.

The values are environment variables for the whole job, like `env:` at job level. A step can read
them; a value is in the job's environment file until the job ends. Treat every action you run in
the job as able to read them, exactly as with GitHub secrets.

### Values API

Use an API token from the dashboard profile. Reads need cloud read access; writes need cloud
write access.

```bash
API=https://dashboard.quantcdn.io/api/v3/organizations/$ORG/ci/values   # gov: https://dash.quantgov.cloud/...

# List (secrets come back without a value)
curl -sS -H "Authorization: Bearer $QUANT_API_TOKEN" "$API?repo=acme/web"

# Create or replace a repo secret with a branch rule; read the value from a file, not argv
jq -n --rawfile v deploy-key.pem '{kind:"secret", value:$v, repo:"acme/web", branches:["main"]}' |
  curl -sS -X PUT -H "Authorization: Bearer $QUANT_API_TOKEN" -H 'Content-Type: application/json' \
    --data-binary @- "$API/DEPLOY_KEY"

# Org variable
curl -sS -X PUT -H "Authorization: Bearer $QUANT_API_TOKEN" -H 'Content-Type: application/json' \
  -d '{"kind":"var","value":"ap-southeast-2"}' "$API/AWS_REGION"

# Delete (add ?repo=owner/name for a repo value)
curl -sS -X DELETE -H "Authorization: Bearer $QUANT_API_TOKEN" "$API/DEPLOY_KEY?repo=acme/web"
```

## Build cache

Jobs on Quant CI runners keep their caches in Australia. This covers `actions/cache`, the `cache:`
input of `setup-node`, `setup-python`, `setup-go`, `setup-java` and similar actions, and Docker
buildx `cache-from` and `cache-to` with `type=gha`. You do not change any workflow.

### Branch rules

The rules match GitHub's.

- A run restores caches from its own branch or tag. A pull request then restores from the base
  branch. Last, a run restores from the default branch.
- A run saves only to its own branch. A pull request saves to `refs/pull/<number>/merge`.
- A `pull_request_target` run uses the base branch.
- A pull request from a fork gets no cache.
- Each pool's caches are separate from every other pool's. Repositories never share caches.

### Limits

| Limit | Value |
|---|---|
| Save to an existing key | Refused, as on GitHub. Use a new key. |
| Entry life | 14 days after the save |
| Entry size | Up to 10 GiB |

### Cache residency setting

Set **Cache residency** on each pool.

| Option | What happens |
|---|---|
| **Australia only** (default) | Cache data never leaves Australia. If the pool's cache is unavailable, jobs run without a cache. |
| **Allow GitHub fallback** | If the pool's cache is unavailable, jobs use GitHub's cache. |

A change applies to the next job each runner machine starts.

### What still goes to GitHub

Artifacts (`actions/upload-artifact` and `download-artifact`) and job logs still go to GitHub.

### Manage the cache

Open **Cloud → CI runners → Pools** and find the **Build cache** section on the pool. It shows:

- the storage used
- the hit rate for the last 7 days (hits / (hits + misses))
- the entries by repository and branch

Use these actions to delete cache data:

| Action | Deletes |
|---|---|
| **Delete entry** | One entry |
| **Clear branch** | The caches of one branch |
| **Clear repository** | The caches of one repository |
| **Clear cache** | The whole cache of the pool |

Users who can edit the pool can delete cache entries. Every delete asks for confirmation and is
permanent. A later job saves a new entry. If you delete a pool, its cache is deleted too.

## Migrate from GitHub-hosted runners

Full procedure, the export workflow and the import script:
[references/migrate-from-github-actions.md](references/migrate-from-github-actions.md).

1. **Inventory.** List each repository's workflows, the jobs' `runs-on`, and the secret and
   variable names (`gh secret list`, `gh secret list --org`, `gh secret list --env <name>`,
   `gh variable list`). Secret values cannot be read from the GitHub API.
2. **Move jobs without secrets first.** Change `runs-on: ubuntu-latest` to the pool's line.
   Nothing else changes.
3. **Copy the secrets with the export workflow.** A one-time workflow on a temporary branch reads
   the secrets the job can see, encrypts them to a key that only your machine has, and uploads the
   ciphertext. Your machine decrypts it and writes each value to the values API with the right
   scope. Nobody types a secret, and your Quant API token never goes to GitHub.
4. **Copy the variables** from `gh variable list --json name,value` to the values API with
   `kind: "var"`.
5. **Rewrite the workflows.** `${{ secrets.NAME }}` becomes `${{ env.NAME }}` (not
   `secrets.GITHUB_TOKEN`), `${{ vars.NAME }}` becomes `${{ env.NAME }}`, and `runs-on` becomes the
   pool's line. A job that used `environment: production` for its secrets uses branch rules
   instead; keep `environment:` only if you still want GitHub's approval gate.
6. **Run, then delete.** After the first green run of each workflow, delete the GitHub secrets
   it used.

Keep these on GitHub-hosted runners: macOS and Windows jobs, and jobs in public repositories.
Their secrets stay on GitHub.

### Differences from `ubuntu-latest`

- The image has the common tools (git, Docker with buildx and compose, Node.js LTS, Python 3,
  build-essential, AWS CLI v2, jq, yq, gh) but not every tool of `ubuntu-latest`. Use the `setup-*`
  actions (`actions/setup-node`, `setup-python`, `setup-java`, `setup-go`) or `sudo apt-get install`.
- PHP 8.3 (the default, as on `ubuntu-latest`) and PHP 8.4 are installed with the same extensions
  as on `ubuntu-latest`, and Composer is on the `PATH`. `shivammathur/setup-php` switches between
  these two versions in a few seconds; another version installs as on GitHub and takes longer.
  As on GitHub, Xdebug is on and PCOV is off: set `coverage: none` or `coverage: pcov` to change this.
- A job starts in a fresh, empty environment every time. Caches work as on GitHub; see [Build cache](#build-cache).

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| Job stays "Waiting for a runner" | Label typo, the App is not installed on that repository, or the pool is at its concurrent-job limit | Copy the `runs-on` line from the dashboard; check the App's repository access; check the pool alerts |
| Job on a public repository never starts | Public repositories are refused | Make the repository private, or keep the job on GitHub-hosted runners |
| Job with `arm64` never starts | The pool has only `x64` | Edit the pool to add `arm64`, or change the label |
| First job after a quiet period takes about a minute | Machines start on demand | Expected; later jobs start at once while the pool is warm |
| `${{ env.NAME }}` is empty | Value not saved for this repository, a branch rule does not match, a `pull_request` or tag run with a branch-ruled value, or a fork pull request | List the values with `?repo=owner/name`; check the branch rules and the event |
| A cache is not restored | The branch rules do not reach that cache, the run is a pull request from a fork, the entry is older than 14 days, or the pool is **Australia only** and its cache is unavailable | Check the branch rules in [Build cache](#build-cache); save the cache again on the base branch; for the last case, choose **Allow GitHub fallback** on the pool |
| `Unable to reserve cache` | The key already exists, and a save to an existing key is refused | Use a new key, or select **Delete entry** and run again |
| `${{ secrets.NAME }}` is empty on Quant runners | The secret moved to Quant, or was never on GitHub | Use `${{ env.NAME }}` |
| Job fails before its first step with a values error | Quant could not confirm the job | Re-run the job; if it repeats, contact support with the run URL |
| PUT returns 400 with a reserved name | Name is reserved or has a reserved prefix | Rename it, and change the workflow to match |
| A secret value has lost its last newline | `gh secret set` removes a trailing newline from stdin, so GitHub held the trimmed value | Expected; the export copies what GitHub holds |

## Further reading

- GitHub self-hosted runner labels: https://docs.github.com/actions/hosting-your-own-runners/managing-self-hosted-runners/using-self-hosted-runners-in-a-workflow
- GitHub runner groups: https://docs.github.com/actions/hosting-your-own-runners/managing-self-hosted-runners/managing-access-to-self-hosted-runners-using-groups
- Related skills: `quant-ci-github-actions` (deploy workflows and action versions), `quant-platform`
  (API hosts and tokens)

<!-- checked against gh:actions/runner 2.338.2 -->
