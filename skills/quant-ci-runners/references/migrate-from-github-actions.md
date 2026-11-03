# Migrate GitHub Actions secrets to Quant CI runners

GitHub never returns a secret value through its API. A job can still read every secret it can
see, so a one-time export job copies them. The values leave GitHub only as ciphertext for a key
that exists only on the machine that runs the migration, and the Quant API token never goes to
GitHub.

Do one repository at a time. You need: `gh` (logged in as a repository admin; an organisation
admin to read org secret visibility), `node` 18 or later, `openssl`, `jq`, `curl`, and a Quant
API token with cloud write access for the Quant organisation.

## 1. Inventory the names

```bash
R=acme/web                                   # owner/name
gh secret list -R "$R" --json name                                   # repo secrets
gh api "repos/$R/actions/organization-secrets" --jq '[.secrets[].name]'  # org secrets this repo sees
gh api "repos/$R/environments" --jq '[.environments[].name]'             # environments
gh secret list -R "$R" --env production --json name                  # per environment
gh variable list -R "$R" --json name,value                           # variables: values are readable
grep -rhoE '\$\{\{ *(secrets|vars)\.[A-Za-z0-9_]+' .github/workflows | sort | uniq -c
```

Decide the Quant scope of each secret:

| GitHub | Quant |
|---|---|
| Repo secret | repo scope (`repo: owner/name`) |
| Org secret, visibility `all` or `private` (`gh api orgs/<org>/actions/secrets/<NAME> --jq .visibility`) | org scope, once for the organisation |
| Org secret, visibility `selected` | repo scope in each repository that used it |
| Environment secret | repo scope with branch rules from the environment's deployment branches (see below) |
| Dependabot secret, Codespaces secret | not copied; stays on GitHub |

Environment branch rules: `gh api repos/$R/environments/<env> --jq .deployment_branch_policy`.

- `null`: no branch rule.
- `custom_branch_policies: true`: read the patterns with
  `gh api repos/$R/environments/<env>/deployment-branch-policies --jq '[.branch_policies[] | select(.type != "tag") | .name]'`.
  Quant supports exact names and one trailing `*` (`release/*`). Ask the person about any other
  pattern (`**`, `?`, `*` in the middle).
- `protected_branches: true`: ask the person which branches deploy, usually `main`.

Names that collide: if an environment secret has the same name as a repo secret (or two
environments share a name), GitHub chose per job; Quant has one value per name per repository.
Ask the person which value wins, or rename one and change the workflow.

Names Quant reserves (`GITHUB_*`, `ACTIONS_*`, `RUNNER_*`, `CI`, `PATH` and the others in the
skill) must be renamed, in the workflow too.

Write the decisions to `plan.json` (names and scopes only, never values):

```json
[
  { "name": "NPM_TOKEN", "from": "repo", "scope": "repo" },
  { "name": "SENTRY_DSN", "from": "repo", "scope": "org" },
  { "name": "DEPLOY_KEY", "from": "env:production", "scope": "repo", "branches": ["main"] }
]
```

`from` is `repo` (the job with no environment sees repo and org secrets) or `env:<name>` (the job
in that environment, which also sees repo and org secrets).

## 2. Make a key pair

```bash
mkdir -m 700 quant-export && cd quant-export
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out export.key
openssl pkey -in export.key -pubout -out export.pub
```

`export.key` never leaves this machine. Delete it at the end.

## 3. Run the export workflow

In a clone of the repository, on a new branch:

```bash
git switch -c quant-export
mkdir -p .github/workflows
```

Write `.github/workflows/quant-export.yml`. Put the content of `export.pub` in `QUANT_EXPORT_KEY`,
and one matrix entry per environment from the plan (`""` is the job with no environment):

```yaml
name: quant-export
on:
  push:
    branches: [quant-export]
permissions:
  contents: read
jobs:
  export:
    strategy:
      fail-fast: false
      matrix:
        environment: ["", "production"]
    runs-on: ubuntu-latest
    environment: ${{ matrix.environment }}
    steps:
      - name: Encrypt secrets
        env:
          QUANT_EXPORT_SECRETS: ${{ toJSON(secrets) }}
          QUANT_EXPORT_KEY: |
            -----BEGIN PUBLIC KEY-----
            (content of export.pub)
            -----END PUBLIC KEY-----
        run: |
          node -e '
          const c = require("crypto"), fs = require("fs");
          const s = JSON.parse(process.env.QUANT_EXPORT_SECRETS || "{}");
          delete s.github_token; delete s.GITHUB_TOKEN;
          const key = c.randomBytes(32), iv = c.randomBytes(12);
          const aes = c.createCipheriv("aes-256-gcm", key, iv);
          const data = Buffer.concat([aes.update(JSON.stringify(s), "utf8"), aes.final()]);
          const wrapped = c.publicEncrypt({ key: process.env.QUANT_EXPORT_KEY,
            padding: c.constants.RSA_PKCS1_OAEP_PADDING, oaepHash: "sha256" }, key);
          fs.writeFileSync("export.json", JSON.stringify({ v: 1, key: wrapped.toString("base64"),
            iv: iv.toString("base64"), tag: aes.getAuthTag().toString("base64"), data: data.toString("base64") }));
          console.log("encrypted " + Object.keys(s).length + " secrets");'
      - uses: actions/upload-artifact@v4
        with:
          name: quant-export-${{ matrix.environment || 'repo' }}
          path: export.json
          retention-days: 1
```

Pin `actions/upload-artifact` by SHA if your organisation requires it (see `quant-ci-github-actions`).

```bash
git add .github/workflows/quant-export.yml && git commit -m "quant export" && git push -u origin quant-export
gh run watch -R "$R" "$(gh run list -R "$R" -b quant-export -L1 --json databaseId --jq '.[0].databaseId')"
```

- The `push` trigger on the temporary branch means the default branch never changes.
- The job runs on GitHub-hosted runners, where the secrets already are.
- An environment with required reviewers waits for approval: approve it in the run.
- An environment whose deployment branches exclude `quant-export` cannot run the job. Add
  `quant-export` to its deployment branches for the export, and remove it afterwards.
- Each job prints only a count. The artifact is ciphertext and expires after one day.

## 4. Decrypt and import

```bash
RUN=$(gh run list -R "$R" -b quant-export -L1 --json databaseId --jq '.[0].databaseId')
gh run download "$RUN" -R "$R" -D artifacts
```

Save as `quant-import.mjs` next to `plan.json`:

```js
// node quant-import.mjs <artifacts-dir> <export.key> <plan.json> [--apply]
// Env: QUANT_API_TOKEN, QUANT_DASHBOARD (https://dashboard.quantcdn.io or https://dash.quantgov.cloud),
//      QUANT_ORG, GITHUB_REPO (owner/name). Without --apply it prints the plan and writes nothing.
import { createDecipheriv, privateDecrypt, constants } from "node:crypto";
import { readFileSync } from "node:fs";

const [dir, keyFile, planFile, flag] = process.argv.slice(2);
const apply = flag === "--apply";
const { QUANT_API_TOKEN, QUANT_DASHBOARD, QUANT_ORG, GITHUB_REPO } = process.env;
if (!QUANT_API_TOKEN || !QUANT_DASHBOARD || !QUANT_ORG || !GITHUB_REPO) throw new Error("set the env vars");

function decrypt(source) {
  const e = JSON.parse(readFileSync(`${dir}/quant-export-${source}/export.json`, "utf8"));
  const key = privateDecrypt({ key: readFileSync(keyFile), padding: constants.RSA_PKCS1_OAEP_PADDING, oaepHash: "sha256" },
    Buffer.from(e.key, "base64"));
  const d = createDecipheriv("aes-256-gcm", key, Buffer.from(e.iv, "base64"));
  d.setAuthTag(Buffer.from(e.tag, "base64"));
  return JSON.parse(Buffer.concat([d.update(Buffer.from(e.data, "base64")), d.final()]).toString("utf8"));
}

const plan = JSON.parse(readFileSync(planFile, "utf8"));
const exports = new Map();
const api = `${QUANT_DASHBOARD}/api/v3/organizations/${QUANT_ORG}/ci/values`;
let failed = 0;
for (const item of plan) {
  const source = item.from === "repo" ? "repo" : item.from.slice(4);
  if (!exports.has(source)) exports.set(source, decrypt(source));
  const value = exports.get(source)[item.name];
  const where = item.scope === "org" ? "org" : GITHUB_REPO;
  const rules = item.branches ? ` branches=${item.branches.join(",")}` : "";
  if (value === undefined) { console.log(`MISSING ${item.name} (not visible to the ${source} job)`); failed++; continue; }
  if (!apply) { console.log(`PLAN ${item.name} -> ${where}${rules}`); continue; }
  const body = { kind: "secret", value, ...(item.scope === "repo" ? { repo: GITHUB_REPO } : {}),
    ...(item.branches ? { branches: item.branches } : {}) };
  const res = await fetch(`${api}/${item.name}`, { method: "PUT", body: JSON.stringify(body),
    headers: { Authorization: `Bearer ${QUANT_API_TOKEN}`, "Content-Type": "application/json", Accept: "application/json" } });
  const msg = res.ok ? "" : ` ${(await res.json().catch(() => ({}))).message ?? ""}`;
  console.log(`${res.ok ? "OK" : "FAIL"} ${res.status} ${item.name} -> ${where}${rules}${msg}`);
  if (!res.ok) failed++;
}
process.exit(failed ? 1 : 0);
```

```bash
export QUANT_DASHBOARD=https://dash.quantgov.cloud QUANT_ORG=dept-x GITHUB_REPO="$R"
read -rs QUANT_API_TOKEN && export QUANT_API_TOKEN     # paste the token; it stays out of history
node quant-import.mjs artifacts export.key plan.json            # dry run: names and scopes only
node quant-import.mjs artifacts export.key plan.json --apply
curl -sS -H "Authorization: Bearer $QUANT_API_TOKEN" \
  "$QUANT_DASHBOARD/api/v3/organizations/$QUANT_ORG/ci/values?repo=$R" | jq '[.values[] | {name, kind, repo, branches}]'
```

The script never prints a value. An org-scope item imported from several repositories is written
again with the same value; import it from one repository only.

Variables: GitHub returns their values, so no export is needed:

```bash
gh variable list -R "$R" --json name,value | jq -c '.[]' | while read -r v; do
  jq -n --argjson v "$v" --arg r "$R" '{kind:"var", value:$v.value, repo:$r}' |
    curl -sS -X PUT -H "Authorization: Bearer $QUANT_API_TOKEN" -H 'Content-Type: application/json' \
      --data-binary @- "$QUANT_DASHBOARD/api/v3/organizations/$QUANT_ORG/ci/values/$(jq -r .name <<<"$v")"
  echo
done
```

## 5. Clean up the export

```bash
git push origin --delete quant-export
for id in $(gh run list -R "$R" -w quant-export --json databaseId --jq '.[].databaseId'); do
  gh api -X DELETE "repos/$R/actions/runs/$id"      # deletes the run and its artifacts
done
cd .. && rm -rf quant-export                         # private key and decrypted data
```

Remove `quant-export` from any environment's deployment branches that you changed.

## 6. Rewrite the workflows

For each job that moves:

```diff
-    runs-on: ubuntu-latest
+    runs-on: [self-hosted, quant, build, x64]
-    environment: production
     steps:
       - run: ./deploy.sh
         env:
-          DEPLOY_KEY: ${{ secrets.DEPLOY_KEY }}
-          REGION: ${{ vars.REGION }}
+          DEPLOY_KEY: ${{ env.DEPLOY_KEY }}
+          REGION: ${{ env.REGION }}
```

- `${{ secrets.GITHUB_TOKEN }}` stays.
- Keep `environment:` only for GitHub's approval gate or deployment history; it no longer
  supplies the secrets.
- Remove the `env:` mapping entirely where the name is the same: the value is already in the
  job's environment. Keep the mapping for `with:` inputs of actions (`token: ${{ env.NPM_TOKEN }}`).
- A job that stays on GitHub-hosted runners (macOS, Windows, public repository) keeps
  `${{ secrets.NAME }}`; do not delete those GitHub secrets.

## 7. Verify, then delete the GitHub secrets

1. Run each changed workflow on Quant runners: push to a branch, or `gh workflow run`.
2. Confirm each step that uses a value works. A masked value shows as `***` in the log.
3. Delete the GitHub secrets that no remaining workflow uses:
   `gh secret delete NAME -R "$R"` (add `--env <name>` or `--org <org>` for those scopes).
