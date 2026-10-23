# KV API reference

`kvStore` is available in every edge function and auth function. `KVStore` is the
same object. The first argument is always the **store ID** of a store that belongs to, or is linked
to, the project. Source of truth: https://docs.quantcdn.io/compute/kv-stores/ and
https://docs.quantcdn.io/compute/kv-ledgers/.

## Formats

| | Format 1 | Format 2 |
|---|---|---|
| Default | API-created stores without `format: 2` | Dashboard-created stores |
| `get`/`set`/`delete` failure | Returns `null` / `false` | Throws `KVError` |
| Listing | Bounded scan, eventually consistent | Collections in id order, strongly consistent reads |
| Conditional writes, `atomic()`, `reverse`, indexes, ledgers | No (`REQUIRES_FORMAT_2`) | Yes |

Upgrade a format 1 store on the store page (Format & upgrade tab): writes pause for at least 40
seconds plus the copy time; reads continue. Limit 100,000 items and 1 GiB. Rollback is possible for 14
days.

## Methods

| Method | Returns | Notes |
|---|---|---|
| `get(id, key)` | Value or `null` | JSON values come back decoded. Secrets come back decrypted |
| `getEntry(id, key)` | `{ key, value, encrypted?, version?, createdAt, updatedAt, expiresAt? }` or `null` | `version` on format 2 only. Throws on failure, any format |
| `getMany(id, keys)` | Array in key order, `null` for missing | 1 to 100 keys; response at most 4 MiB (`LIMIT_EXCEEDED`) |
| `set(id, key, value, opts)` | `true`; `{ version }` with `ifAbsent`/`ifVersion` | Objects are JSON-encoded. Options: `ttl`, `secret`, `ifAbsent`, `ifVersion`; any other option throws `VALIDATION` |
| `delete(id, key, opts)` | `true` | Option: `ifVersion`. A conditional delete of a missing key throws `CONFLICT` (`reason: 'missing'`) |
| `increment(id, key, amount = 1, { ttl })` | The new number | Nonzero safe integer, may be negative. A missing or expired key starts at 0. Strings (including `"1"`), objects, fractions and secrets reject |
| `list(id, opts)` | `{ items, cursor, hasMore, scannedCount, indexed? }` | See options below |
| `search(id, opts)` | Same shape | Needs at least one of `prefix`, `pattern`, `where`, or a non-`all` `type` |
| `getBy(id, index, equals)` | Entry or `null` | Unique index only. Strongly consistent |
| `count(id, { index, equals })` | Number | Count index only. Strongly consistent |
| `atomic(id)` | Builder: `.check(key, version)`, `.set(...)`, `.delete(...)`, `.increment(key, n)`, `.commit({ idempotencyKey })` | 1 to 25 operations, each on a different key; all or none. Returns `{ versions, replayed }` |
| `append(id, collection, value, { idempotencyKey })` | Receipt `{ key, id, shard, seq, at, hash, prevHash, ledger, source }` | Ledgers only (below) |

### List and search options

| Option | Methods | Rule |
|---|---|---|
| `prefix` | both | Literal, 1 to 512 characters |
| `pattern` | `search` | Only `*` is a wildcard (zero or more characters); 1 to 512 characters. Not with `prefix` |
| `where` | `search`; `list` with `collection` or `index` | 1 to 8 top-level field equalities on plaintext JSON objects, AND. Equality only; types must match (`0` is not `"0"`) |
| `type` | both | `all` (default), `plaintext`, `encrypted` |
| `includeValues` | both | Default `false`. Secrets show `"[ENCRYPTED]"` |
| `limit` | both | 1 to 100, default 25. Bounds records **evaluated**, not matched |
| `cursor` | both | From the previous page. Expires after 24 hours. Send the same filters again |
| `collection` | `list` (format 2) | The text before the last `:` of the keys. `''` is the root collection |
| `startsWith`, `after`, `before`, `reverse` | `list` (format 2) | Id bounds (no `:`). `reverse` needs format 2 |
| `index`, `equals` | `list` (format 2) | List by a declared index. Eventually consistent |

Paging rules:

- An empty `items` array with `hasMore: true` is **not** the end. Keep following `cursor` until
  `hasMore` is `false`.
- A page is limited to 1 MiB of scanned data (format 1) or a read budget (format 2), so it can
  hold fewer than `limit` items.
- Do not loop over a whole store in one request. Return the cursor to the client, or advance a
  scheduled function in steps.
- Edge queries time out after 8 seconds and responses over 4 MiB reject. A failure rejects; it is
  never an empty page.

## Limits

| Item | Limit |
|---|---|
| Key | 2,048 bytes. Format 2: must not start or end with `:`; the id after the last `:` at most 1,000 bytes |
| Value (format 2 item) | 400 KB |
| `ttl` | 60 to 31,536,000 seconds (one year), integer |
| `getMany` | 100 keys, 4 MiB response |
| `list`/`search` page | 100 items |
| Transaction | 25 operations; `idempotencyKey` 1 to 64 letters, digits, `-`, `_`; replays for 24 hours |
| Edge request timeout | 8 seconds (`increment` and queries included) |
| Indexes | 20 per store, 5 per collection, 0 to 3 fields |
| Ledgers | 20 per store; entry at most 350,000 bytes |

## Expiry (`ttl`)

- An expired key reads as `null` at once; the row can stay up to 48 hours before removal.
- `set()` without `ttl` removes an existing expiry. `increment()` keeps a live counter's expiry
  and sets `ttl` only when it creates or restarts the counter.
- `ttl` works with `secret: true`. A counted collection refuses `ttl` (`COUNT_WITH_TTL`).

## Secrets

```js
await kvStore.set(STORE_ID, 'payments-api-key', apiKey, { secret: true });   // once, or in the dashboard
const apiKey = await kvStore.get(STORE_ID, 'payments-api-key');              // decrypted at run time
```

- Set secrets in the dashboard (Compute, K/V Stores), the platform API (`"secret": true`), Terraform
  `quant_kv_item` (`secret = true`, see `quant-iac`) or `kvStore.set`.
- Reads through the dashboard, the API, `list`, `search` and exports show `[ENCRYPTED]`. Only a
  function's `get`, `getEntry` or `getMany` returns the plain value. Apply your own
  authorization before you use it for a visitor.
- `search` with `where` skips secrets. An indexed collection refuses secrets
  (`INDEX_FIELD_ENCRYPTED`).

## Conditional writes (format 2)

```js
const entry = await kvStore.getEntry(STORE_ID, `order:${id}`);
await kvStore.set(STORE_ID, `order:${id}`, { ...entry.value, status: 'paid' }, { ifVersion: entry.version });
await kvStore.set(STORE_ID, `lock:${job}`, { owner: run }, { ifAbsent: true, ttl: 300 });
```

A failed condition throws `CONFLICT` with `reason` (`exists`, `version`, `missing`, `expired`,
`not_numeric`, `range`) and `currentVersion`. Read again and decide; do not retry blindly.

## Counters

- `increment()` is atomic: concurrent adds are not lost.
- It is **not exactly-once**. A timeout or lost response can happen after the write. The error
  then has code `UNAVAILABLE`, `retryable: false`. Do not retry automatically.
- For exact counts (credits, billing), use `atomic()...increment(key, n).commit({ idempotencyKey })`
  and retry only with the same key. A transaction does not return the counter value; `get()` it.

## Errors (format 2, `increment`, `getEntry`, `getMany`, ledgers)

Errors are `KVError` with `code`, `retryable` and `status`. Invalid `list`/`search` options throw a
plain `Error`.

| Code | Retry | Meaning |
|---|---|---|
| `VALIDATION` | No | Bad key, option or value |
| `LIMIT_EXCEEDED` | No | Size limit (400 KB item, 4 MiB response) |
| `REQUIRES_FORMAT_2` | No | Option needs format 2 |
| `CURSOR_INVALID` | No | Restart without a cursor |
| `STORE_NOT_FOUND` | No | Wrong store ID |
| `CONFLICT` | No | Condition failed; read again |
| `UNIQUE_VIOLATION` | No | Value owned by `existingKey` in a unique index |
| `INDEX_NOT_READY` | Yes | Index still building |
| `CONTENTION` | Yes | Concurrent writes; retry after a short delay |
| `STORE_MIGRATING` | Yes | Upgrade in progress; retry after a few seconds |
| `UNAVAILABLE` | Check `retryable` | Outcome may be unknown; for a conditional write, `getEntry()` before you retry |

A store that the function may not use throws a plain `Error`: `Access to KV store <id> is not allowed`.

## Ledgers

A ledger is a collection of a format 2 store that only accepts new entries: audit trails, consent
logs, credit ledgers. Declare it on the store's **Ledgers** tab (name, collection pattern,
`chains` 1 to 64, `retentionDays`, `lockMode` `governance` or `compliance`, optional
`personalFields` with a `subjectField`). The collection must be empty. The ledger is `PENDING` for
about 75 seconds, then `ACTIVE`. `chains`, retention and lock mode can only be raised.

```js
const receipt = await kvStore.append(AUDIT_STORE, `audit:${tenantId}`, {
  actorId: session.userId,
  action: 'export',
  requestId,
}, { idempotencyKey: `${requestId}-audit` });

const page = await kvStore.list(AUDIT_STORE, {
  collection: `audit:${tenantId}`,
  since: '2026-10-01T00:00:00Z',
  until: Date.now(),
  includeValues: true,
  limit: 100,
});
```

- `value` must be a JSON object. A top-level `at` field is refused (the server sets it).
- Pass an `idempotencyKey` (1 to 64 letters, digits, `-`, `_`; unique in the store) so a retry
  after `CONTENTION`, `LEDGER_NOT_READY` or a retryable `UNAVAILABLE` returns the first receipt
  instead of a second entry.
- `set`, `delete`, `increment`, `ttl` and `atomic` on ledger keys fail with `LEDGER_IMMUTABLE`.
- Each entry records `source`: an edge function's entries name the function.
- Personal fields are encrypted per subject and can be shredded for erasure requests; the hash
  chain still verifies.
- A store with an `ACTIVE` ledger cannot be deleted until retention ends.

Verification, anchoring, offline proofs and erasure: https://docs.quantcdn.io/compute/kv-ledgers/

## Platform API for stores and items

Base: `{dashboard}/api/v2/organizations/{organization}/projects/{project}`, with
`Authorization: Bearer <platform API token>`.

| Call | Does |
|---|---|
| `GET /kv`, `POST /kv` (`{ "name": ... }`) | List or create stores |
| `GET /kv/{store_id}`, `DELETE /kv/{store_id}[?force=true]` | Read or delete a store. Without `force`, a store with keys is refused |
| `POST /kv/{store_id}/link` (`{ "project_id": <id> }`) | Share the store with another project |
| `DELETE /kv/{store_id}/link` | Remove a linked store from this project |
| `GET /kv/{store_id}/items?cursor=&limit=&search=&include_values=` | List keys |
| `POST /kv/{store_id}/items` (`{ "key", "value", "secret" }`) | Add an item. `value` is a string; send JSON as a string |
| `GET`, `PUT`, `DELETE /kv/{store_id}/items/{key}` | Read, update or delete an item |
| `DELETE /kv/{store_id}/items?prefix=&older_than=` | Delete many items |
