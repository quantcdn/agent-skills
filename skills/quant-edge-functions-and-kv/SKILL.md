---
name: quant-edge-functions-and-kv
description: Use when writing, deploying or debugging Quant edge functions on QuantCDN or QuantGov - request functions, auth functions (auth middleware), content filters, inline functions (`{{QUANT_FN:uuid}}`) and scheduled functions - or when a function reads or writes a KV store, keeps a secret, counts with `kvStore.increment`, or appends to a KV ledger. Covers the function body contract (`event.request`, `event.geo`, the `quant-client-ip` header, returning a `Response`, `fetch`), auth functions returning 201 to continue, `quant/edge-functions.json` and `quant/edge-rules.json` (UUID identity, `function_ref`, `weight`), deploying with `quantcdn/deploy-action` (`functions`, `rules`, `api-token`, `api-base-url`), KV store IDs and linking, KV limits and errors. Also use when an auth-protected path returns 503, an auth rule lets everyone through, a function sees the wrong path, a KV call says "Access to KV store ... is not allowed", or an inline token is not replaced.
---

# Edge functions and KV on Quant

Edge functions run your JavaScript on Quant's edge for each matching request. KV stores keep
data that functions read and write. For the platform overview, load `quant-platform`. For the
rules that run functions, see `quant-rules-and-routing`. For the `quant functions` and
`quant rules` commands, see `quant-cli`.

## Applies to

Both platforms: QuantCDN (`https://dashboard.quantcdn.io`) and QuantGov (`https://dash.quantgov.cloud`).
Functions and KV behave the same on both. Checked 2026-10 against `@quantcdn/quant-cli` 7.0.1,
`quantcdn/deploy-action` v7.0.1 and the public docs.

| | Public | Gov |
|---|---|---|
| Dashboard (Compute section) | `https://dashboard.quantcdn.io` | `https://dash.quantgov.cloud` |
| Content API (function uploads, `endpoint`) | `https://api.quantcdn.io/v1` | `https://api.quantgov.cloud/v1` |
| Platform API (rules, KV, `api-base-url`) | `https://dashboard.quantcdn.io/api/v2` | `https://dash.quantgov.cloud/api/v2` |

Ask for the dashboard URL if you do not know the platform.

## Function types

| Type (manifest `type`) | Runs when | Must return | Dashboard |
|---|---|---|---|
| `function` (`edge` is the same) | A function rule matches, or an inline token, or a schedule | A `Response` | Compute, Functions |
| `auth` | An auth rule matches | `Response` with status **201** to continue; any other response goes to the visitor | Compute, Auth Middleware |
| `filter` | A content filter rule matches; transforms the final response | A `contentFilter` class (below) | Compute, Content filters |

- **Inline** and **scheduled** are ways to run a `function`-type function, not separate types.
- Auth and filter functions run only through a rule.

## The function body

A function file is the **body of an async function**, not a module. Quant provides `event` and
`kvStore`. Use top-level `await` and `return`. Do not write `export default`, `addEventListener`
or a `fetch(request, env)` handler: they do not run.

```js
// quant/edge-functions/whoami.js
const KV = `${event.quantOrg}-${event.quantProject}-stats`; // store ID, see "KV stores"
const ip = event.request.headers.get('quant-client-ip');     // true client IP
const path = new URL(event.request.url).pathname;           // the path the visitor asked for
const visits = await kvStore.increment(KV, 'visits:whoami');

return new Response(JSON.stringify({
  ip,
  country: event.geo.country_code,
  path,
  visits,
}), {
  status: 200,
  headers: { 'Content-Type': 'application/json', 'Cache-Control': 'private, no-store' },
});
```

| Value | Meaning |
|---|---|
| `event.request` | The visitor's request (`Request`): `method`, `headers.get()`, `url`, `json()`, `text()`. Its `url` keeps the requested path |
| `event.url` | A `URL` with the public host name. It can differ from the URL the browser sent; for the URL the visitor requested, use `event.request.url` |
| `event.geo` | `country_code`, `country_name`, `city`, `region`, `continent`, `latitude`, `longitude`, `postal_code`, `as_name`, `as_number`, `proxy_type`, `utc_offset` and more |
| `quant-client-ip` header | The visitor's IP address, set by Quant. Do not read `X-Forwarded-For` |
| `event.quantOrg`, `event.quantProject` | The organization and project machine names |
| `fetch`, `Request`, `Response`, `Headers`, `URL`, `crypto.subtle`, `TextEncoder` | Web APIs. Return `fetch(...)` directly to stream an origin response without buffering |

Response handling:

- If the function sets no `Cache-Control`, Quant sends `Cache-Control: private, max-age=0`. Set a
  cache header yourself only when the output is the same for every visitor.
- Headers that the function sets replace the same headers from rules (a few Quant headers,
  such as `age`, are protected).
- An uncaught exception fails the request with a server error. Catch errors and return your own
  `Response` with a clear status.

## Auth functions

```js
const STORE_ID = `${event.quantOrg}-${event.quantProject}-sessions`;
const token = event.request.headers.get('Cookie')?.match(/session=([^;]+)/)?.[1];
const ok = token && await kvStore.get(STORE_ID, `session:${token}`);
if (!ok) {
  return new Response(null, { status: 302, headers: { Location: '/login' } });
}
return new Response(null, { status: 201 }); // 201 = continue to the next rule
```

- **201 continues** to the next rule. Every other status, **including 200**, is sent to the
  visitor and the request stops. A function that returns 200 on success shows its own body
  instead of the page.
- On 201, the headers the function returns (except `Content-Type`) are added to the final
  response, so a refreshed `Set-Cookie` reaches the visitor. If the function sets no
  `Cache-Control`, Quant sets `private, max-age=0`.
- Chain several auth rules on the same URLs; each must return 201 for the next one to run.

**Note: an auth rule fails closed when its function is unavailable.** If the function is
missing, has no published revision (it was never published, or it was unpublished or deleted in
the dashboard or Studio), is not an auth function, or is invalid, Quant returns HTTP 503
with `Cache-Control: no-store` and a generic body. The request does not reach the content.

1. Deploy and publish the function **before** you attach the auth rule.
2. Give the auth rule a **lower weight** (earlier position) than every rule that serves or
   proxies the protected paths. A rule above it that ends processing means it never runs.
3. Purge the protected paths. A response already in the cache is served without running rules.
4. Test with no credentials: `curl -sI "https://www.example.com/members/x?cb=$RANDOM"` must
   return your refusal (401, 403 or 302), not 200.

## Content filters

```js
class contentFilter extends TransformStream {
  constructor(event, responseHeaders) {
    responseHeaders.set('x-filtered', '1');
    super({
      transform: (chunk, controller) => {
        const text = this.decoder.decode(chunk, { stream: true }).replaceAll('Intranet', 'Portal');
        controller.enqueue(this.encoder.encode(text));
      },
    });
    this.decoder = new TextDecoder();
    this.encoder = new TextEncoder();
  }
}
```

- Name the class `contentFilter`. The body is changed as it streams, chunk by chunk, so a
  word split across two chunks is not replaced.
- Where a filter runs:

  | Response | Filter runs? |
  |---|---|
  | Static HTML pages | Yes |
  | Edge function responses (function rules) | Yes, **whatever the content type** |
  | Proxy, custom response and other rule responses | Only when `Content-Type` is `text/html` |
  | Static files (CSS, JS, images, PDFs) | No; header changes do not apply either |

- **Warning:** a filter rule with broad URLs (for example `*`) in front of a function rule that
  returns JSON or CSS rewrites that output too. Scope filter rules to the HTML paths, or check
  `responseHeaders.get('content-type')` in the constructor and pass chunks through unchanged.
- The filter rule continues to later rules. If several filter rules match, only the **last**
  one applies.

## Inline functions

Put `{{QUANT_FN:<uuid>}}` in HTML. Quant replaces the token with the output of that published
`function`-type function, while the rest of the page can stay cached.

- Static content: turn on **Enable Inline Functions** on the project (dashboard, project, Edit).
- Proxied content: turn on **Allow Inline Functions** on the proxy rule. Only HTML is processed.
- The token must hold a full UUID. Other text stays in the page as it is.
- Unless the function sets `Cache-Control`, the whole page is sent with
  `Cache-Control: private, max-age=0`.

## Scheduled functions

Dashboard, Compute, Scheduled Execution: pick a `function`-type function, a schedule (preset or
six-field `cron(...)` expression) and the HTTP method, headers and body that the function
receives as `event.request`. Runs and their status codes appear in the dashboard; a "run now"
button tests the setup.

## Function identity and deploy

A function's **UUID is its identity**, scoped to the project. Keep it in the repository and never
change it: a new UUID creates a new function, and rules and inline tokens that name the old UUID
keep running the old one. Full schemas: [references/manifests.md](references/manifests.md).

```bash
# Once per function: add an entry with a new UUID (uploads nothing). Commit the result.
quant functions-add quant/edge-functions.json quant/edge-functions/whoami.js \
  --description "Who am I API" --id whoami
```

`quant/edge-rules.json`:

```json
{
  "version": 1,
  "namespace": "site",
  "rules": [
    { "id": "whoami", "type": "function", "urls": ["/api/whoami"], "weight": 10, "function_ref": "whoami" }
  ]
}
```

GitHub Actions (gov values shown; public: `https://api.quantcdn.io/v1` and
`https://dashboard.quantcdn.io/api/v2`):

```yaml
- uses: quantcdn/deploy-action@9bf8cae8497ab6628d4b248db9eb11464f37e1e5 # v7.0.1
  with:
    customer: ${{ vars.QUANT_CUSTOMER }}
    project: ${{ vars.QUANT_PROJECT }}
    token: ${{ secrets.QUANT_TOKEN }}             # content token: uploads only
    endpoint: https://api.quantgov.cloud/v1       # default is the public content API
    dir: dist
    functions: quant/edge-functions.json
    rules: quant/edge-rules.json
    api-token: ${{ secrets.QUANT_API_TOKEN }}     # project-scoped: projects:read, rules:read, rules:write
    api-base-url: https://dash.quantgov.cloud/api/v2
```

- The action checks rules access first (dry run), then deploys functions, then `dir`, then rules.
- `rules` needs `api-token` and `api-base-url`; the content token never works for rules.
- Functions deployed by the CLI or the action are published at once.
- Rules from the file are read-only in the dashboard. A rule changed there makes the next deploy
  fail with a drift report; `rules-force: true` overwrites it.
- Without CI: `quant functions quant/edge-functions.json`, then `quant rules ...` (`quant-cli`).
  Workflow details: `quant-ci-github-actions`. Terraform and Pulumi: `quant-iac`.

## KV stores

Create a store in the dashboard (Compute, K/V Stores), the platform API, Terraform
(`quant_kv_store`) or template setup. Format 2 (the dashboard default) adds indexes,
conditional writes, transactions and ledgers.

- The first argument of every `kvStore` method is the **store ID**, not the display name. The
  dashboard shows it. Stores that the dashboard and templates create use
  `<organization>-<project>-<name>`, so `${event.quantOrg}-${event.quantProject}-<name>` builds it.
- A function can use only stores that belong to, or are **linked** to, its project. Any other
  ID throws `Access to KV store <id> is not allowed`. Link a store to another project in
  Compute, K/V Stores, or with `POST {dashboard}/api/v2/organizations/{org}/projects/{project}/kv/{store_id}/link`.
- Values are JSON-encoded for you: `set` an object, `get` returns the object. A missing key
  returns `null`.

| Method | Use |
|---|---|
| `get(id, key)`, `getEntry(id, key)`, `getMany(id, keys)` | Read; `getEntry` adds timestamps and the `version` |
| `set(id, key, value, { ttl, secret, ifAbsent, ifVersion })` | Write. `ttl` 60 to 31,536,000 s |
| `delete(id, key, { ifVersion })` | Delete |
| `increment(id, key, amount = 1, { ttl })` | Atomic add; returns the new number |
| `list(id, opts)`, `search(id, opts)` | Pages of keys, 1 to 100 per call, with a `cursor` |
| `atomic(id)...commit({ idempotencyKey })` | 1 to 25 operations, all or none (format 2) |
| `append(id, collection, value, { idempotencyKey })` | Add an entry to a ledger |

Full signatures, limits and error codes: [references/kv-api.md](references/kv-api.md).

**Secrets.** Never put API keys in function code or in a manifest. Store them as KV secrets:
`secret: true` in `kvStore.set`, the dashboard's encrypted option, the API (`"secret": true`)
or Terraform `quant_kv_item` with `secret = true`. The function reads the plain value with
`kvStore.get`. The dashboard, the API, `list`, `search` and exports show `[ENCRYPTED]`. An API
update cannot change whether an existing key is encrypted.

**Counters.** `kvStore.increment(id, key, amount)` adds atomically and returns the new number; a
missing key starts at 0. It never loses a concurrent add. It is not exactly-once: if it times
out (the edge waits 8 seconds), the add may already have applied. Do not retry it
automatically. Use an `atomic()` transaction with an `idempotencyKey` when a double count is not
acceptable.

**Ledgers.** A ledger is an append-only, hash-chained collection of a format 2 store. Declare it
on the store's Ledgers tab; functions `append()` and read with `list()` and `getEntry()`. Entries
can never change: `set`, `delete`, `increment` and `ttl` on ledger keys fail with
`LEDGER_IMMUTABLE`. See [references/kv-api.md](references/kv-api.md#ledgers).

## Common problems

| Symptom | Cause | Fix |
|---|---|---|
| An auth-protected path returns 503 | The auth function is missing or unpublished, or the rule names the wrong function UUID | Publish the function, or fix the rule's function UUID |
| Auth rule lets everyone through | A rule above it ends processing, or a cached page | Lower the auth rule's weight; purge; test without credentials |
| Members see "ok" or "Authenticated" instead of the page | Auth function returns 200 | Return 201 to continue |
| Function sees a different path than the visitor requested | Read from `event.url` | Use `new URL(event.request.url).pathname` |
| `SyntaxError` or the function never runs | Module syntax (`export`, `import`, `addEventListener`) | Write a function body that returns a `Response` |
| `Access to KV store <id> is not allowed` | Store name instead of ID, or store not linked to this project | Use the full ID; link the store to the project |
| `kvStore.get` returns `null` for a key that exists | Format 1 store returns `null` on a failed read; wrong store ID | Check the ID; upgrade to format 2, where failures throw `KVError` |
| `{{QUANT_FN:...}}` shows in the page | Inline functions off, or the token is not a full UUID | Enable inline functions on the project or proxy rule; use the full UUID |
| Page shows `Invalid edge function.` | The function in the token is not published | Publish the function (deploy it again) |
| Page shows `Unable to find edge function with uuid: <uuid>` | No function with that UUID in this project | Check the UUID in `quant/edge-functions.json`; deploy the function |
| Filter changes nothing on a static CSS or JS file, or on a JSON proxy response | Filters skip static files and non-HTML rule responses | Use a function rule for those types |
| JSON or CSS from a function comes back altered | A filter rule also matches the function's URL; filters run on all function output | Narrow the filter rule's URLs, or skip non-HTML in the filter |
| Second filter rule ignored | Only the last matching filter applies | Combine the filters into one |
| A new function appeared after a deploy | The manifest `uuid` changed | Restore the old UUID; delete the extra function in the dashboard |
| Deploy fails: rules need `api-token` | `rules` set without the platform token | Add `api-token` and `api-base-url` (`{dashboard}/api/v2`) |
| Rules deploy refused with drift | A managed rule was edited in the dashboard | Change the file, or deploy with `rules-force: true` |
| Gov deploy uploads to the wrong place | `endpoint` not set | `endpoint: https://api.quantgov.cloud/v1` |
| Counter off by one after a retry | `increment()` retried after a timeout | Do not retry automatically; use a transaction with `idempotencyKey` |
| `VALIDATION: Unknown set option` | Misspelt `set()` option | Use `ttl`, `secret`, `ifAbsent` or `ifVersion` |

## Further reading

- Edge functions: https://docs.quantcdn.io/compute/functions/
- Auth middleware: https://docs.quantcdn.io/compute/auth-middleware/
- Content filters: https://docs.quantcdn.io/compute/content-filters/
- Inline functions: https://docs.quantcdn.io/compute/inline-functions/
- Scheduled functions: https://docs.quantcdn.io/compute/scheduled-functions/
- KV stores: https://docs.quantcdn.io/compute/kv-stores/
- KV ledgers: https://docs.quantcdn.io/compute/kv-ledgers/
- `quant functions` and `quant rules`: https://docs.quantcdn.io/content-cli/commands/functions/
- Manifests: [references/manifests.md](references/manifests.md); KV API: [references/kv-api.md](references/kv-api.md)
- Related skills: `quant-platform`, `quant-cli`, `quant-rules-and-routing`, `quant-ci-github-actions`,
  `quant-templates`, `quant-iac`

<!-- checked against npm:@quantcdn/quant-cli 7.0.1 -->
<!-- checked against gh:quantcdn/deploy-action 7.0.1 -->
