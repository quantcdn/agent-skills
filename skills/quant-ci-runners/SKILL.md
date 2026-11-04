---
name: quant-ci-runners
description: Use when running GitHub Actions jobs on Quant CI runners on QuantCDN or QuantGov - creating a CI runner pool (Small, Medium, Large; arm64 and x64), connecting the GitHub App to a GitHub organisation, the `runs-on: [self-hosted, quant, <pool>, <arch>]` labels, CI secrets and variables (org scope, repo scope, branch rules, `${{ env.NAME }}` instead of `${{ secrets.NAME }}`), the values API `{dashboard}/api/v3/organizations/{org}/ci/values`, and migrating workflows and their existing GitHub secrets from GitHub-hosted runners without typing any secret again. Also use when a Quant job stays queued, a job on a public repository never starts, a value is empty in a job, a pull request from a fork gets no values, or a branch-scoped value is missing on a tag or pull request run.
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
dashboard does not show **CI runner pools** on the organisation's Resources page, contact support.
Checked 2026-11-03 against the dashboard, the values API and the GitHub Actions runner 2.338;
OIDC checked 2026-11-04 on arm64 and x64 runners.

## Pools

Create a pool on the organisation's **Resources** page, under **CI runner pools**.

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
**Secrets and variables** card under **CI runner pools**, or with the values API.

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

## Cloud credentials: use OIDC

For AWS, Azure or Google Cloud, use GitHub OIDC, not stored keys. The job asks GitHub for a
short-lived token and exchanges it for cloud credentials that expire with the job. Nothing
long-lived is stored, on GitHub or in Quant.

OIDC works unchanged on Quant runners: GitHub issues the token, not the runner. Keep
`permissions: id-token: write` and your existing login action:

```yaml
permissions:
  id-token: write
  contents: read
jobs:
  deploy:
    runs-on: [self-hosted, quant, build, x64]
    environment: production
    steps:
      - uses: aws-actions/configure-aws-credentials@v6
        with:
          role-to-assume: ${{ vars.AWS_DEPLOY_ROLE }}   # the role's ARN, as a repository variable
          aws-region: ap-southeast-2
```

The cloud role trusts the token's `sub` claim. Get the trust right:

- **Read your repository's subject format first.** It differs between repositories:
  `gh api repos/<owner>/<repo>/actions/oidc/customization/sub`. Use the `sub_claim_prefix` it
  returns. With `"use_immutable_subject": false` it is `repo:<owner>/<repo>`; with `true` it
  includes the IDs, for example `repo:<owner>@<owner-id>/<repo>@<repo-id>`.
- **Trust an environment, not a branch.** Match the whole subject with `StringEquals`, for
  example `<sub_claim_prefix>:environment:production`. A subject such as
  `<sub_claim_prefix>:ref:refs/heads/main` trusts every workflow and job on that branch.
- **Protect the environment before you create the role.** In the repository settings, give it
  deployment branches (for example `main` only) and, for production, required reviewers. If a
  workflow names an environment that does not exist, GitHub creates it with no rules, and the
  role then trusts a job from any branch.
- **Check the audience.** AWS expects `aud` = `sts.amazonaws.com`, the default of
  `aws-actions/configure-aws-credentials`.
- To stop repository administrators from skipping a production approval, set
  `can_admins_bypass` to `false` on that environment.

Use Quant secrets only for what OIDC cannot replace: third-party API tokens, signing keys, and
credentials for systems without OIDC support.

## Migrate from GitHub-hosted runners

Full procedure, the export workflow and the import script:
[references/migrate-from-github-actions.md](references/migrate-from-github-actions.md).

1. **Inventory.** List each repository's workflows, the jobs' `runs-on`, and the secret and
   variable names (`gh secret list`, `gh secret list --org`, `gh secret list --env <name>`,
   `gh variable list`). Secret values cannot be read from the GitHub API. Mark the cloud keys
   (for example `AWS_ACCESS_KEY_ID`): replace them with OIDC (above) instead of copying them.
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
  build-essential, AWS CLI v2, jq) but not every tool of `ubuntu-latest`. Use the `setup-*`
  actions (`actions/setup-node`, `setup-python`, `setup-java`, `setup-go`) or `sudo apt-get install`.
- A job starts in a fresh, empty environment every time. Use `actions/cache` as on GitHub.

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| Job stays "Waiting for a runner" | Label typo, the App is not installed on that repository, or the pool is at its concurrent-job limit | Copy the `runs-on` line from the dashboard; check the App's repository access; check the pool alerts |
| Job on a public repository never starts | Public repositories are refused | Make the repository private, or keep the job on GitHub-hosted runners |
| Job with `arm64` never starts | The pool has only `x64` | Edit the pool to add `arm64`, or change the label |
| First job after a quiet period takes about a minute | Machines start on demand | Expected; later jobs start at once while the pool is warm |
| `${{ env.NAME }}` is empty | Value not saved for this repository, a branch rule does not match, a `pull_request` or tag run with a branch-ruled value, or a fork pull request | List the values with `?repo=owner/name`; check the branch rules and the event |
| `${{ secrets.NAME }}` is empty on Quant runners | The secret moved to Quant, or was never on GitHub | Use `${{ env.NAME }}` |
| Job fails before its first step with a values error | Quant could not confirm the job | Re-run the job; if it repeats, contact support with the run URL |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | The role's trusted `sub` does not match the token: a different subject format, a different environment name, or the job has no `environment:` | Read the prefix with `gh api repos/<owner>/<repo>/actions/oidc/customization/sub`; match the exact `<prefix>:environment:<name>` |
| PUT returns 400 with a reserved name | Name is reserved or has a reserved prefix | Rename it, and change the workflow to match |
| A secret value has lost its last newline | `gh secret set` removes a trailing newline from stdin, so GitHub held the trimmed value | Expected; the export copies what GitHub holds |

## Further reading

- GitHub self-hosted runner labels: https://docs.github.com/actions/hosting-your-own-runners/managing-self-hosted-runners/using-self-hosted-runners-in-a-workflow
- GitHub runner groups: https://docs.github.com/actions/hosting-your-own-runners/managing-self-hosted-runners/managing-access-to-self-hosted-runners-using-groups
- Related skills: `quant-ci-github-actions` (deploy workflows and action versions), `quant-platform`
  (API hosts and tokens)

<!-- checked against gh:actions/runner 2.338.2 -->
