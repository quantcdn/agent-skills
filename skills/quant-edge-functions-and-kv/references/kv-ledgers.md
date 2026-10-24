# KV ledgers

A ledger is a collection of a format 2 store that only accepts new entries: audit trails, consent
logs, credit ledgers. Entries are hash-chained. Nobody can change or delete an entry. Method
table and error codes: [kv-api.md](kv-api.md). Source of truth: https://docs.quantcdn.io/compute/kv-ledgers/

## Declare a ledger

Declare it on the store's **Ledgers** tab: name, collection pattern, `chains` 1 to 64,
`retentionDays`, `lockMode` `governance` or `compliance`, and optional `personalFields` with a
`subjectField`.

- The collection must be empty. A collection name is at most 512 UTF-8 bytes.
- The ledger is `PENDING` for about 75 seconds, then `ACTIVE`. An append before that throws
  `LEDGER_NOT_READY` (retryable) with `activeAfter`.
- `chains`, retention and lock mode can only be raised.
- A store with a `PENDING` or `ACTIVE` ledger cannot be deleted (`LEDGER_PRESENT`), even with
  `force=true`.

## Append

```js
const audit = kvStore.open(AUDIT_STORE);
const receipt = await audit.append(`audit:${tenantId}`, {
  actorId: session.userId,
  action: 'export',
  requestId,
}, { idempotencyKey: `${requestId}-audit` });
// { key, id, shard, seq, at, hash, prevHash, ledger, source?, replayed? }
```

- `value` must be a plain JSON object of at most 350,000 bytes. A top-level `at` field is refused
  (the server sets it).
- `idempotencyKey` is 1 to 64 letters, digits, `-` or `_`. A repeat with the same key within 24
  hours returns the first receipt with `replayed: true`, not a second entry.
- Without a key, Quant generates one for each call. If the call fails, the error carries it in
  `idempotencyKey`. When the outcome is unknown (`UNAVAILABLE`), retry with that key:

  ```js
  try {
    await audit.append('audit:t1', entry);
  } catch (e) {
    if (e instanceof kvStore.KVError && e.retryable && e.idempotencyKey) {
      await audit.append('audit:t1', entry, { idempotencyKey: e.idempotencyKey });
    } else throw e;
  }
  ```

- `append` has an 11 second timeout.
- `set`, `delete`, `increment`, `ttl` and `atomic` on ledger keys fail with `LEDGER_IMMUTABLE`.
- Each entry records `source`: an edge function's entries name the function.
- Personal fields are encrypted per subject and can be shredded for erasure requests; the hash
  chain still verifies.
- `LEDGER_FORKED` and `LEDGER_DROPPED` are never retryable: the store refuses appends.

## Chain order

- `seq` counts from 1 **within one shard**. `prevHash` is the hash of the previous entry in the
  same shard (`null` for the first).
- A ledger with `chains: 1` has one shard, so `seq` is a total order. With more chains there is no
  total order: order across shards by `at`, then `shard`, then `id`.
- There is no read by `seq`. Read entries with `list` (below) or `getEntry(key)`.

## Read a time window

```js
const page = await audit.list({
  collection: `audit:${tenantId}`,
  since: '2026-10-01T00:00:00Z',   // inclusive
  until: Date.now(),               // exclusive
  includeValues: true,
  limit: 100,
});
```

- `since` and `until` need `collection`. They take epoch milliseconds or ISO 8601 with `Z` or an
  offset.
- They cannot be combined with `where`, `pattern`, `startsWith`, `after`, `before` or
  `type: 'encrypted'`.
- Each item holds a `ledger` object with `shard`, `seq`, `hash` and `prevHash`.

## verifyChain

`verifyChain(entries)` checks entries that the function already read. It runs in the function and
makes no request.

```js
const entries = [];
for await (const item of audit.list({ collection: 'audit:t1' }).items({ maxPages: 100 })) entries.push(item);
const report = audit.verifyChain(entries);
// { ok, checked, shards: [{ shard, first, last, count }], problems: [{ problem, shard?, seq?, index? }] }
if (!report.ok) console.log(JSON.stringify(report.problems));
```

- The entries can be list items, `getEntry` results or append receipts. Pass the entries of one
  collection.
- At most 10,000 entries. A larger array, or a value that is not an array, throws `VALIDATION`.
- Two entries with the same `seq` and the same `hash` count as one.

| `problem` | Meaning |
|---|---|
| `gap` | A `seq` is missing between two entries of the shard |
| `fork` | Two different entries have the same `seq` |
| `broken-link` | `prevHash` is not the hash of the previous entry |
| `missing-fields` | The entry has no `shard`, `seq` (a safe integer from 1), `hash` or `prevHash`. `index` is its position in your array |

**What it does not prove.** `verifyChain` finds gaps, reordering and broken links in the entries you
pass. It does not prove that Quant stored them unchanged, and it does not recompute an entry hash
from its content. A clean result for a partial window says nothing about entries outside it; the
first entry of the window is not checked against an earlier one. For evidence that an entry is
authentic, use `ledgerProof`.

## Status and proof

```js
const status = await audit.ledgerStatus('audit');
// { name, state, collection, chains, headSeq, archivedSeq, lag, shards: [...], hasMoreShards, activeAfter?, retainUntil?, lastVerify? }

const proof = await audit.ledgerProof('audit', receipt.key);
// { status: 'pending' } until the entry is archived, then { status: 'archived', hash, period, archiveKey, ... }
```

- Both calls are read-only.
- `lag` is the archive lag in seconds; `archivedSeq` is the highest `seq` in the archive.
- A `pending` proof is normal for recent entries. Ask again after the next archive period.

Verification of archives outside Quant, anchoring, offline proofs and erasure:
https://docs.quantcdn.io/compute/kv-ledgers/
