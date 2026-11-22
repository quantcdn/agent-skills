---
name: quant-ci-runners
description: Use when running GitHub Actions jobs on Quant CI runners on QuantCDN or QuantGov - creating a CI runner pool (Small, Medium, Large; arm64 and x64), connecting the GitHub App to a GitHub organisation, the `runs-on: [self-hosted, quant, <pool>, <arch>]` labels, CI secrets and variables (org scope, repo scope, branch rules, `${{ env.NAME }}` instead of `${{ secrets.NAME }}`), the values API `{dashboard}/api/v3/organizations/{org}/ci/values`, the build cache (`actions/cache`, buildx `type=gha`, cache residency, clear the cache), and migrating workflows and their existing GitHub secrets from GitHub-hosted runners without typing any secret again. Also use when a cache is not restored, a Quant job stays queued, a job on a public repository is refused, a step ends with exit code 137, a value is empty in a job, a pull request from a fork gets no values, or a branch-scoped value is missing on a tag or pull request run.
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
| Small | 2 | 2 vCPU, 6 GiB memory, 50 GB disk |
| Medium | 4 | 4 vCPU, 14 GiB memory, 75 GB disk |
| Large | 8 | 4 vCPU, 14 GiB memory, 75 GB disk |

- A pool has a fixed monthly price (shown on the create form) and a fixed maximum: jobs above the
  concurrent-job limit wait in GitHub's queue, they never add cost. The dashboard shows an alert
  when the pool is at capacity or jobs wait too long, with a link to upsize.
- Choose one or both architectures: `arm64` and `x64`. Both are in the same price.
- Machines start when jobs arrive and stop when the pool is idle. The first job after an idle
  period waits about one minute for a machine.
- **Public repositories.** A pool runs jobs of public repositories only when Quant has enabled
  that for the pool. Otherwise the job is refused before its first step. Contact Quant support to
  enable a pool for public repositories.
- **Memory.** Each job has 6 GiB of memory on the Small tier, and 14 GiB on the Medium and Large
  tiers. The kernel stops a step that needs more, and the step ends with exit code 137.
- **Processes.** Each job may have at most 16,384 processes and threads. A job at that limit
  shows `fork: retry: Resource temporarily unavailable`.
- **Disk.** Jobs on one virtual machine share its disk. When the machine has less than 10 GiB
  free, it takes no new job. When it has less than 3 GiB free, the jobs running on that machine
  are stopped and the machine is replaced. GitHub shows those jobs as a lost runner. To keep disk
  free, clean large build outputs, prune Docker images in long jobs, or use a larger tier.
- **Confirmation.** Every job is confirmed with GitHub before it starts. If GitHub's API has a
  fault, or the confirmation takes longer than 15 seconds, the job fails at set-up. Run the job
  again.
- **Patching.** Runner machines are rebuilt every week from a patched image and replaced when
  idle. A job in progress is never stopped for this.
- A retry or a double click on **Create pool** does not make a second pool.

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
- A pool serves a job only when every label in `runs-on` is one of these: `self-hosted`,
  `linux`, `quant`, the pool name, and at most one architecture label (`x64` or `arm64`) that the
  pool has.
- A job with any other label is not picked up. It stays queued on GitHub, and the pool shows the
  alert **A job asked for labels this pool does not have**. Quant cannot cancel the job. Cancel it
  in GitHub and fix `runs-on`.

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
  a prefix. A value with branch rules is given only to a run whose ref is one of the listed
  branches (`refs/heads/<branch>`) on a `push`, `workflow_dispatch` or `schedule` event. A tag
  run, a `release` event run and a pull request run do not get the value, even when the tag has
  the same name as the branch. In those runs the value is empty in the job. Use a value with no
  branch rule, or run the deploy from the branch. Use branch rules for deploy credentials, the
  way you used GitHub environments.
- **Forks.** A pull request from a fork gets no values at all. A pull request from a fork of a
  private repository also gets no build cache, so its build is cold.
- **Repo-scope saves.** To save a repo-scope value, the repository's GitHub owner must be
  connected to a pool, and GitHub must be reachable. Otherwise the API answers 400 (the owner is
  not connected to a pool) or 503 with a `Retry-After` header (GitHub is unavailable; try again
  after that time).
- **Repository identity.** A repo-scope value is bound to the repository itself, not to its name.
  If a repository is deleted and a new one is created with the same name, the old value is
  withheld, and the value list shows a withheld reason. Save the value again.
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

Jobs on Quant CI runners keep their caches in Australia by default. This covers `actions/cache`,
the `cache:` input of `setup-node`, `setup-python`, `setup-go`, `setup-java` and similar actions,
and Docker buildx `cache-from` and `cache-to` with `type=gha`. You do not change any workflow, with
one exception. Docker buildx `type=gha` needs a `docker/setup-buildx-action` step before
`build-push-action`, because the default Docker driver cannot export a gha cache.

### Branch rules

The rules match GitHub's.

- A run restores caches from its own branch or tag. A pull request then restores from the base
  branch. Last, a run restores from the default branch.
- A run saves only to its own branch. A pull request saves to `refs/pull/<number>/merge`.
- A `pull_request_target` run uses the base branch.
- A pull request from a fork gets no cache. A `pull_request_target` run that a fork started also
  gets no cache.
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
| **Australia only** (default) | Cache data never leaves Australia. If the pool's cache service is not available, cache and artifact steps fail rather than fall back to GitHub's storage. |
| **Allow GitHub fallback** | If the pool's cache service is not available, cache and artifact steps fall back to GitHub's storage. |

A change applies to the next job each runner machine starts.

### What still goes to GitHub

Artifacts (`actions/upload-artifact` and `download-artifact`) and job logs still go to GitHub.

### Manage the cache

Open **Cloud → CI runners → Pools** and find the **Build cache** section on the pool. The section
loads when you choose **Show build cache**. It shows:

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

If **Delete entry** or **Clear branch** is not available for a ref, use **Clear repository**.

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

Keep these on GitHub-hosted runners: macOS and Windows jobs, and jobs in public repositories
unless Quant has enabled the pool for public repositories. Their secrets stay on GitHub.

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
| Job stays queued and the pool shows **A job asked for labels this pool does not have** | A label in `runs-on` is not one of `self-hosted`, `linux`, `quant`, the pool name, and at most one architecture label (`x64` or `arm64`) that the pool has | Cancel the job in GitHub and fix `runs-on`. Quant cannot cancel the job |
| Job of a public repository is refused before its first step | A pool runs jobs of public repositories only when Quant has enabled that for the pool | Contact Quant support to enable the pool for public repositories, or keep the job on GitHub-hosted runners |
| Job fails at set-up, before its first step | Every job is confirmed with GitHub before it starts. GitHub's API had a fault, or the confirmation took longer than 15 seconds | Run the job again |
| A step ends with exit code 137 | The step needed more memory than the job has (6 GiB on Small, 14 GiB on Medium and Large), and the kernel stopped it | Lower the memory the step uses, for example with fewer parallel workers. On the Small tier, you can also move the pool to a larger tier |
| `fork: retry: Resource temporarily unavailable` | The job reached its limit of 16,384 processes and threads | Lower the number of processes and threads the job starts at one time |
| Job stops and GitHub shows a lost runner | The machine had less than 3 GiB of disk free. Jobs on one virtual machine share its disk. With less than 10 GiB free, the machine takes no new job | Run the job again. Clean large build outputs, prune Docker images in long jobs, or use a larger tier |
| Job with `arm64` never starts | The pool has only `x64` | Edit the pool to add `arm64`, or change the label |
| First job after a quiet period takes about a minute | Machines start on demand | Expected; later jobs start at once while the pool is warm |
| `${{ env.NAME }}` is empty | Value not saved for this repository, a branch rule does not match, or one of the next three rows | List the values with `?repo=owner/name`; check the branch rules and the event |
| A value with a branch rule is empty on a tag run, a `release` event run or a pull request run | The value is given only to a run whose ref is one of the listed branches (`refs/heads/<branch>`) on a `push`, `workflow_dispatch` or `schedule` event. A tag with the same name as the branch does not count | Use a value with no branch rule, or run the deploy from the branch |
| The value list shows a withheld reason and the value is empty in the job | A repo-scope value is bound to the repository itself, not to its name. The repository was deleted and a new one was created with the same name | Save the value again |
| A pull request from a fork has empty values and a cold build | A pull request from a fork of a private repository gets no Quant values and no build cache | Expected. A job that runs for a fork pull request must work without Quant values and without a cache |
| PUT of a repo-scope value returns 400 (not connected) | The repository's GitHub owner is not connected to a pool | Connect the owner to a pool, then save the value |
| PUT of a repo-scope value returns 503 with `Retry-After` | GitHub is unavailable | Try again after that time |
| A cache is not restored | The branch rules do not reach that cache, the run is a pull request from a fork or a `pull_request_target` run that a fork started, or the entry is older than 14 days | Check the branch rules in [Build cache](#build-cache); save the cache again on the base branch |
| A cache or artifact step fails | The pool is **Australia only** and its cache service is not available, so the steps fail rather than fall back to GitHub's storage | Run the job again later. If the steps must fall back to GitHub's storage, choose **Allow GitHub fallback** on the pool |
| buildx `type=gha` export fails | The default Docker driver does not support the gha cache | Add `docker/setup-buildx-action` before `build-push-action` |
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
