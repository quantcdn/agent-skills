# KV API reference

`kvStore` is available in every edge function and auth function. `KVStore` is the same object (not
a constructor). Every method takes the **store ID** first, of a store that belongs to, or is linked
to, the project. A store handle (`kvStore.open`) binds the ID once. Ledgers, `verifyChain`,
`ledgerStatus` and `ledgerProof`: [kv-ledgers.md](kv-ledgers.md). Source of truth:
https://docs.quantcdn.io/compute/kv-stores/ and the `kvstore.d.ts` declarations published with
the edge function documentation.

## Formats

| | Format 1 | Format 2 |
|---|---|---|
| Created by | The platform API and Terraform (no format option), or the dashboard when you choose format 1 | The dashboard (default) and template setup |
| `get`/`set`/`delete` failure | Returns `null` / `false` | Throws `KVError` |
| Listing | Bounded scan, eventually consistent | Collections in id order, strongly consistent reads |
| Conditional writes, `atomic()`, `reverse`, indexes, ledgers | No (`REQUIRES_FORMAT_2`) | Yes |

Upgrade a format 1 store on the store page (Format & upgrade tab): writes pause for at least 40
seconds plus the copy time; reads continue. Limit 100,000 items and 1 GiB. Rollback is possible for 14
days.

## Store handle

```js
const kv = kvStore.open(`${event.quantOrg}-${event.quantProject}-app`);   // no request yet
await kv.set('user:1', { name: 'Ada' }, { ttl: 3600 });
const user = await kv.get('user:1');                  // the object, or null
const text = await kv.get('user:1', { raw: true });   // the stored JSON text, not parsed
```

- The handle has `storeId` and the same methods without the store ID: `get`, `set`, `delete`,
  `getEntry`, `getMany`, `getBy`, `count`, `increment`, `list`, `search`, `append`, `ledgerStatus`,
  `ledgerProof`, `atomic` and `verifyChain`.
- `open` makes no request. A store ID that is not a string throws `VALIDATION`. A store that the
  function may not use fails on the first call (`FORBIDDEN`).
- `kv.get(key, options)` takes nothing, `{ raw: true }` or a boolean (the older `skipDecode`). Any
  other option name, or a `raw` that is not a boolean, throws `VALIDATION`.
- The store-ID-first form (`kvStore.get(id, key)`) keeps working with the same results and errors.

## Methods

Shown in the handle form. The store-ID-first form adds the ID as the first argument.

| Method | Returns | Notes |
|---|---|---|
| `get(key)` | Value or `null` | JSON values come back decoded. Secrets come back decrypted |
| `getEntry(key)` | `{ key, value, encrypted?, version?, createdAt, updatedAt, expiresAt?, ledger? }` or `null` | `version` on format 2 only. Throws on failure, any format |
| `getMany(keys)` | Array of entries (same shape as `getEntry`) in key order, `null` for missing | 1 to 100 keys; response at most 4 MiB (`LIMIT_EXCEEDED`). Read `result[i]?.value` |
| `set(key, value, opts)` | `true`; `{ version }` with `ifAbsent`/`ifVersion` | Objects are JSON-encoded. Options: `ttl`, `secret`, `ifAbsent`, `ifVersion` (see [Unknown options](#unknown-options)) |
| `delete(key, opts)` | `true` | Option: `ifVersion`. A conditional delete of a missing key throws `CONFLICT` (`reason: 'missing'`) |
| `increment(key, amount = 1, { ttl })` | The new number | Nonzero safe integer, may be negative. A missing or expired key starts at 0. Strings (including `"1"`), objects, fractions and secrets reject |
| `list(opts)`, `search(opts)` | A page `{ items, cursor, hasMore, scannedCount, pageEnd, indexed? }`; also async-iterable | See [List, search and iteration](#list-search-and-iteration) |
| `getBy(index, equals)` | Entry or `null` | Unique index only. Strongly consistent |
| `count({ index, equals })` | Number | Count index only. Strongly consistent |
| `atomic()` | Builder: `.check(key, version)`, `.set(...)`, `.delete(...)`, `.increment(key, n)`, `.commit({ idempotencyKey })` | 1 to 25 operations, each on a different key; all or none. Returns `{ versions, replayed }`. `commit` works once; a second call throws `VALIDATION`. Any unknown `set`/`delete` option in the builder throws |
| `append(collection, value, { idempotencyKey })` | Receipt `{ key, id, shard, seq, at, hash, prevHash, ledger, source?, replayed? }` | Ledgers only ([kv-ledgers.md](kv-ledgers.md)) |
| `ledgerStatus(name)`, `ledgerProof(name, key)` | Ledger state; archive proof of one entry | Read-only ([kv-ledgers.md](kv-ledgers.md)) |
| `verifyChain(entries)` | `{ ok, checked, shards, problems }` | Runs in the function, no request ([kv-ledgers.md](kv-ledgers.md#verifychain)) |

### Unknown options

`set()` and `delete()` check their option names:

| Option name | Result |
|---|---|
| `ttl`, `secret`, `ifAbsent`, `ifVersion` (`delete`: `ifVersion` only) | Used |
| Looks like a condition or secret (starts with `if`, or contains `absent`, `version`, `condition`, `exists`, `secret` or `encrypt`) | Throws `VALIDATION`, so a misspelt condition never becomes an unconditional write |
| Expiry-like: `expiration`, `expirationTtl`, `expires`, `expiresAt`, `expiresIn`, `ttlSeconds`, `maxAge` | Throws `VALIDATION` with `hint: 'use ttl (seconds)'` |
| Any other name | Ignored and logged today. Quant plans to make these throw too: do not pass them |

## List, search and iteration

`list` and `search` resolve to **one page**, as before. The returned promise is also
async-iterable, so one loop reads every page:

```js
for await (const item of kv.list({ prefix: 'user:' })) console.log(item.key);          // items, up to 10 pages

for await (const page of kv.list({ prefix: 'user:' }).pages({ maxPages: 20 })) {        // pages
  console.log(page.items.length, page.pageEnd);
}

for await (const item of kv.search({ pattern: 'order:*' }).items({ maxPages: 50 })) { /* ... */ }
```

- **Page cap.** One iteration fetches at most 10 pages. `maxPages` is an integer from 1 to 100. Each
  page is one request to the store. When more pages remain, the iterator throws `KVError`
  `LIMIT_EXCEEDED` (`retryable: false`) with `cursor` set to the next cursor. Resume with it:

  ```js
  let cursor;
  for (;;) {
    try {
      for await (const item of kv.list({ prefix: 'user:', cursor })) handle(item);
      break;
    } catch (e) {
      if (e instanceof kvStore.KVError && e.code === 'LIMIT_EXCEEDED' && e.cursor) cursor = e.cursor;
      else throw e;
    }
  }
  ```

- An unknown iteration option, or a `maxPages` outside 1 to 100, throws `VALIDATION`.
- Do not loop over a whole large store in one request. Return the cursor to the client, or advance
  a scheduled function in steps.

### Options

| Option | Methods | Rule |
|---|---|---|
| `limit` | both | Items per page, 1 to 1000, default 25 |
| `cursor` | both | From the previous page (or `LIMIT_EXCEEDED`). Valid for 24 hours, for the same query only |
| `includeValues` | both | Default `false`. Secrets show `"[ENCRYPTED]"` |
| `type` | both | `all` (default), `plaintext`, `encrypted` |
| `prefix` | both | Literal, 1 to 512 characters. Not with `pattern`, `collection` or `index` |
| `pattern` | `search` | Only `*` is a wildcard (zero or more characters); 1 to 512 characters. Not with `prefix` |
| `where` | `search`; `list` with `collection` or `index` | 1 to 8 top-level field equalities on plaintext JSON objects, AND. Types must match (`0` is not `"0"`). Not with `type: 'encrypted'` |
| `collection` | both | The text before the last `:` of the keys. `''` is the root collection. Not with `prefix`, `pattern` or `index`. Format 2 reads it in id order; format 1 scans (`indexed: false`). A ledger collection name is at most 512 UTF-8 bytes |
| `startsWith`, `after`, `before`, `reverse` | both, with `collection` (`after`, `before`, `reverse` also with `index`) | Id bounds (no `:`, 1 to 1000 characters). `startsWith` is not used with `after` or `before`. `reverse` needs format 2 |
| `since`, `until` | with a ledger `collection` | Time window ([kv-ledgers.md](kv-ledgers.md#read-a-time-window)) |
| `index`, `equals` | `list` only (format 2) | List by a declared index; `equals` has up to 3 fields. Not with `collection`, `prefix`, `startsWith`, `since` or `until`. `search` refuses these options |

`search` needs at least one of `prefix`, `pattern`, `where`, a non-`all` `type`, or `collection`.

### Short and empty pages

One call stops filling a page at the first of these limits. `pageEnd` says which:

| `pageEnd` | Meaning |
|---|---|
| `limit` | `limit` items found |
| `bytes` | The page reached 4 MiB |
| `budget` | The call read 10,000 rows (with `where` or `type` filters most rows can be non-matches) |
| `end` | No more data |

A page with `pageEnd` `bytes` or `budget` can hold fewer than `limit` items, or none, and still have
`hasMore: true`. It is **not** the end: follow `cursor` until `hasMore` is `false`. The iterator does
this for you. `scannedCount` is the number of rows read, not the number of matches. A failed call
throws; it is never an empty page.

## Limits

| Item | Limit |
|---|---|
| Key | 2,048 bytes. Format 2: must not start or end with `:`; the id after the last `:` at most 1,000 bytes |
| Item (format 2) | 400 KB: key, value and metadata together |
| `ttl` | 60 to 31,536,000 seconds (one year), integer. `set` and `increment` only |
| `getMany` | 1 to 100 keys, 4 MiB response |
| `list`/`search` page | `limit` 1 to 1000; 4 MiB; 10,000 rows read per call |
| Pages per iteration | Default 10, `maxPages` 1 to 100 |
| Transaction | 1 to 25 operations; `idempotencyKey` 1 to 64 of `A-Z a-z 0-9 _ -`; replays for 24 hours |
| Time per call | 8 seconds. `append`: 11 seconds. Format 1 `get`, `set`, `delete`: 30 seconds |
| `prefix`, `pattern` | 1 to 512 characters |
| `where` | 1 to 8 fields; index `equals` 3 fields at most |
| Cursor | 24 hours |
| Indexes | 20 per store, 5 per collection, 0 to 3 fields |
| Ledgers | 20 per store; collection name 512 UTF-8 bytes; entry a plain object of at most 350,000 bytes; `verifyChain` 10,000 entries |
| Stores a function may use | Its project's own stores and linked stores |

## Expiry (`ttl`)

- An expired key reads as `null` at once; the row can stay up to 48 hours before removal.
- `set()` without `ttl` removes an existing expiry. `increment()` keeps a live counter's expiry
  and sets `ttl` only when it creates or restarts the counter.
- `ttl` works with `secret: true`. A counted collection refuses `ttl` (`COUNT_WITH_TTL`).
- There is no other expiry option. `expiration`, `expiresIn`, `maxAge` and similar names throw
  `VALIDATION` with the hint `use ttl (seconds)`.

## Secrets

```js
await kv.set('payments-api-key', apiKey, { secret: true });   // once, or in the dashboard
const apiKey = await kv.get('payments-api-key');              // decrypted at run time
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
const entry = await kv.getEntry(`order:${id}`);
await kv.set(`order:${id}`, { ...entry.value, status: 'paid' }, { ifVersion: entry.version });
await kv.set(`lock:${job}`, { owner: run }, { ifAbsent: true, ttl: 300 });
```

`ifAbsent` (only `true`) and `ifVersion` cannot be used together. A failed condition throws
`CONFLICT` with `reason` (`exists`, `version`, `missing`, `expired`, `not_numeric`, `range`) and
`currentVersion`. Read again and decide; do not retry blindly.

## Counters

- `increment()` is atomic: concurrent adds are not lost.
- It is **not exactly-once**. A timeout or lost response can happen after the write. The error
  then has code `UNAVAILABLE`, `retryable: false`. `increment` has no `idempotencyKey`, so a retry
  can count twice. Do not retry automatically.
- For exact counts (credits, billing), use `kv.atomic().increment(key, n).commit({ idempotencyKey })`
  and retry only with the same key. A transaction does not return the counter value; `get()` it.

## Errors

Every error that a method throws is a `kvStore.KVError` (`name` `'KVError'`). Test with
`instanceof`, not with the message:

```js
try {
  await kv.set('lock', 1, { ifAbsent: true });
} catch (e) {
  if (!(e instanceof kvStore.KVError)) throw e;
  if (e.code === 'CONFLICT') return new Response('Busy', { status: 409 });
  if (e.retryable) { /* retry with backoff; for append or commit, with the same idempotencyKey */ }
  throw e;
}
```

Exception: on a format 1 store, `get`, `set` and `delete` return `null` or `false` on a store failure
and do not throw. On format 2 they throw.

Fields: `code`, `message`, `retryable` (always read it; the table shows the usual value), `status`
(HTTP status, when the store reports one) and, when present, `key`, `currentVersion`, `reason`,
`operation`, `index`, `existingKey`, `state`, `activeAfter`, `collection`, `shard`, `retainUntil`,
`hint`, `idempotencyKey`, `ledger`, `retryAfter` and `cursor`.

| Code | Usually retryable | Meaning |
|---|---|---|
| `VALIDATION` | No | Bad key, value, option, store ID (`Invalid KV store identifier`) or iteration option |
| `FORBIDDEN` | No | The function may not use this store: `Access to KV store <id> is not allowed` |
| `INTERNAL` | No | Unexpected failure in the edge runtime |
| `RESPONSE_INVALID` | No | The store answered with a body the runtime cannot read |
| `UNAVAILABLE` | Yes (not from `increment`) | No answer in time, or busy. After a write the outcome can be unknown: retry `append` and `commit` only with the same `idempotencyKey`; `getEntry()` before you retry a conditional write |
| `NOT_FOUND`, `KEY_NOT_FOUND`, `STORE_NOT_FOUND` | No | Resource, key or store does not exist |
| `LIMIT_EXCEEDED` | No | Size or count limit (400 KB item, 4 MiB response), or the iteration page cap (with `cursor`) |
| `CURSOR_INVALID` | No | Cursor malformed, older than 24 hours, or from a different query. Restart without it |
| `REQUIRES_FORMAT_2` | No | The call needs a format 2 store |
| `CONFLICT` | No | `ifAbsent`, `ifVersion` or a transaction check failed. Read again first |
| `CONTENTION` | Yes | Another writer is busy on the same key; retry after a short delay |
| `STORE_MIGRATING` | Yes | Upgrade in progress. Wait `retryAfter` seconds when present |
| `UNIQUE_VIOLATION` | No | A unique index already holds the value; `existingKey` names the holder |
| `INDEX_NOT_READY` | Yes | The index is still building |
| `INDEX_FIELD_ENCRYPTED` | No | An index or `where` field covers an encrypted value |
| `COUNT_WITH_TTL` | No | A count index cannot cover a key with a `ttl` |
| `LEDGER_IMMUTABLE` | No | A ledger entry cannot be changed or deleted |
| `LEDGER_NOT_READY` | Yes | The ledger is declared but not active yet; `activeAfter` gives the time |
| `LEDGER_NOT_FOUND` | No | No ledger with this name |
| `LEDGER_RETAINED` | No | Under retention until `retainUntil` |
| `LEDGER_FORKED`, `LEDGER_DROPPED` | Never | The chain has forked, or the ledger was dropped. The store refuses appends |
| `LEDGER_COLLECTION_NOT_EMPTY`, `LEDGER_INDEX_KIND`, `LEDGER_SUBJECT_REQUIRED`, `LEDGER_PRESENT`, `LEDGER_DIRECTION`, `SUBJECT_NOT_FOUND`, `STORE_NAME_RETAINED`, `VERIFICATION_NOT_FOUND`, `SHRED_NOT_FOUND`, `UPGRADE_CONFLICT`, `EXPORT_IN_PROGRESS`, `EXPORT_NOT_FOUND` | No | Ledger and store management conditions, passed through unchanged |

## Platform API for stores and items

Base: `{dashboard}/api/v2/organizations/{organization}/projects/{project}`, with
`Authorization: Bearer <platform API token>`. The token needs the `kv:read` scope for reads and
`kv:write` for writes, and your role needs the matching KV permission; otherwise the API returns 403.

| Call | Does |
|---|---|
| `GET /kv`, `POST /kv` (`{ "name": ... }`) | List or create stores. The new store ID is `<organization>-<project>-<name>`, **format 1** |
| `GET /kv/{store_id}`, `DELETE /kv/{store_id}[?force=true]` | Read or delete a store. Without `force`, a store with keys is refused. A store with a `PENDING` or `ACTIVE` ledger is refused even with `force` (`LEDGER_PRESENT`) |
| `POST /kv/{store_id}/link` (`{ "project_id": <id> }`) | Share the store with another project |
| `DELETE /kv/{store_id}/link` | Remove a linked store from this project (403 for the project that owns the store) |
| `GET /kv/{store_id}/items?cursor=&limit=&search=&include_values=` | List keys |
| `POST /kv/{store_id}/items` (`{ "key", "value", "secret" }`) | Add an item. `value` is a string; send JSON as a string |
| `GET`, `PUT`, `DELETE /kv/{store_id}/items/{key}` | Read, update or delete an item |
| `DELETE /kv/{store_id}/items?prefix=&older_than=` | Delete many items |

This API has no format 2 features (versions, conditional writes, indexes, ledgers, upgrades,
exports). Use the dashboard store page and edge functions for those today.

## TODO: KV v2 REST API and SDKs (not available yet)

<!-- TODO(W5/W6): replace this section when the public KV v2 routes ship in the platform API spec. -->

Quant is building a public REST API and SDKs for format 2 stores. **None of it exists yet.** Do not
guess route names or SDK methods; use the dashboard and edge functions until the API specification
lists them. Planned scope:

- A `format` option when you create a store through the API and Terraform.
- Ledger status, entry proofs, the archive public key, archive downloads and verification reports,
  for checks outside Quant.
- Cursor listing with the query options above, entries with versions, conditional writes and `ttl`.
- Index, upgrade and export management.
- Generated SDKs for the new routes.
