# quant-ci-runners evals

Prompt: We are on QuantGov (https://dash.quantgov.cloud), Quant organisation `dept-x`. Our private repository `dept-x/portal` builds on `ubuntu-latest` and deploys from `main` with a job in the GitHub environment `production`, which uses the secret `DEPLOY_KEY`. The repository also has the secret `NPM_TOKEN` and the variable `REGION`. We created a Quant CI runner pool called `build` with x64 only. Move the workflow and its secrets to Quant. Nobody on the team has the secret values any more.
Platform: gov
Must include:
- `runs-on: [self-hosted, quant, build, x64]`
- `${{ secrets.DEPLOY_KEY }}` and `${{ secrets.NPM_TOKEN }}` become `${{ env.DEPLOY_KEY }}` and `${{ env.NPM_TOKEN }}`; `${{ vars.REGION }}` becomes `${{ env.REGION }}`
- A one-time export workflow on a temporary branch that reads `toJSON(secrets)`, with a job for the `production` environment, encrypts the values to a public key whose private key stays on the operator's machine, and uploads only ciphertext
- The values API `https://dash.quantgov.cloud/api/v3/organizations/dept-x/ci/values` with `kind: "secret"` and `repo: "dept-x/portal"`
- `DEPLOY_KEY` gets a branch rule `main`, because Quant uses branch rules where GitHub used the environment
- The variable is copied from `gh variable list`, because GitHub returns variable values
- Delete the export branch and its workflow runs afterwards, and delete the GitHub secrets only after the first green run on Quant runners
Must not include:
- Asking the team to type or paste the secret values
- Storing the Quant API token as a GitHub secret
- `dashboard.quantcdn.io`
- Printing a secret value

Prompt: Our job uses `runs-on: [self-hosted, quant, build, arm64]` on a public repository and never starts. What is wrong?
Platform: public
Must include:
- Quant CI runner pools never pick up jobs from public repositories
- Keep the job on GitHub-hosted runners, or make the repository private
Must not include:
- Turning on "Allow public repositories" in the runner group
