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
- `append` has an 11 second timeout.
- Retries and idempotency: [Retry after a timeout](#retry-after-a-timeout).
- `set`, `delete`, `increment`, `ttl` and `atomic` on ledger keys fail with `LEDGER_IMMUTABLE`.
- Each entry records `source`: an edge function's entries name the function.
- Personal fields are encrypted per subject and can be shredded for erasure requests; the hash
  chain still verifies.
- `LEDGER_FORKED` and `LEDGER_DROPPED` are never retryable: the store refuses appends.

## Retry after a timeout

An append that times out or loses its response can still have been written. Make every append
retry-safe with an `idempotencyKey`:

- 1 to 64 letters, digits, `-` or `_` (no `:`). The key is unique within the **store**, across all
  ledgers and collections, so derive one key per logical event, for example `${requestId}-audit`.
- A retry with the same key, the **same collection and the same value** within 24 hours returns
  the first receipt with `replayed: true` and adds no entry.
- The same key with another collection or value throws `VALIDATION` ("already used for a different
  entry"). The same key from another writer (another function or token) also throws `VALIDATION`.
- After 24 hours the key is free again: a retry then appends a second entry.
- If you erase the subject of a personal-data entry within the 24 hours, a retry with its key throws
  a dedicated `VALIDATION`. Use a new key.
- An edge function that sends no key gets one generated per call (`q_` and 32 hex characters). It is
  on the error as `e.idempotencyKey`. A retry without a key is a **new** append.

```js
const entry = { action: 'export', actorId: session.userId, requestId };
const key = `${requestId}-audit`;
for (let attempt = 1; ; attempt++) {
  try {
    const receipt = await audit.append('audit:t1', entry, { idempotencyKey: key });
    break;                                    // receipt.replayed === true when an earlier try had written it
  } catch (e) {
    if (!(e instanceof kvStore.KVError) || !e.retryable || attempt === 3) throw e;
    await new Promise((r) => setTimeout(r, 200 * attempt));   // same key, same collection, same value
  }
}
```

Keep retries inside one request short: the request also has a time limit. If the outcome is still
unknown, record the key and retry later (a scheduled function or the next request) within 24 hours.

## Ledgers and ordinary KV writes

An append is its own transaction. It is **not atomic** with `set`, `delete`, `increment` or an
`atomic()` transaction, and `atomic()` cannot contain an append (an `atomic()` operation on a ledger
key throws `LEDGER_IMMUTABLE`). Design for one write to succeed while the other fails:

- Give the KV write and the append keys derived from the same request ID: the `atomic()`
  `idempotencyKey` and the append `idempotencyKey`. Then you can retry each one safely and on its own.
- Choose an order and repair forward. For example, commit the state change first, then append; if
  the append fails, retry it with the same key until it succeeds (from a later run if necessary).
- To find state changes without a ledger entry, keep the request ID in both records and compare.

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
first entry of the window is not compared with an earlier one. For evidence that an entry is
authentic, use `ledgerProof`.

## Errors for ledgers

| Code | HTTP | Retry | When |
|---|---|---|---|
| `LEDGER_NOT_READY` | 409 | Yes, after `activeAfter` | The ledger is still `PENDING` (about 75 seconds after you declare it) |
| `CONTENTION` | 409 | Yes, same key | A concurrent append on the same shard or key |
| `UNAVAILABLE` | 503 | Read `retryable`; retry with the same key | Timeout or busy store. The message says whether nothing was written or the outcome is unknown |
| `VALIDATION` | 400 | No | Value not a plain object, a top-level `at`, a bad collection, or a key reused for a different entry, another writer or an erased subject |
| `LIMIT_EXCEEDED` | 400 | No | The value is larger than 350,000 bytes |
| `LEDGER_SUBJECT_REQUIRED` | 400 | No | A personal field is present but the `subjectField` is empty |
| `LEDGER_IMMUTABLE` | 400 | No | `set`, `delete`, `increment`, `ttl` or `atomic()` on a ledger key, or an append to a dropped ledger |
| `LEDGER_FORKED` | 409 | Never | The store table no longer matches its archive. Reads, proofs and exports still work. Contact Quant support |
| `LEDGER_NOT_FOUND` | 404 | No | No ledger with this name (status, proof) |
| `LEDGER_RETAINED` | 409 | No | Drop refused: retention runs until `retainUntil`, or entries are not archived yet |
| `LEDGER_PRESENT` | 409 | No | Store delete or format rollback refused while a ledger exists |

## Retention

- `retentionDays` (1 to 36,500) is how long each archive copy is locked. `lockMode` is `governance`
  or `compliance`. Both can only be raised; a lower value throws `LEDGER_DIRECTION`.
- Live entries never change and are never deleted by `ttl` or a purge.
- An `ACTIVE` ledger can be dropped only when every shard is archived and its retention has ended.
- A store with a `PENDING` or `ACTIVE` ledger cannot be deleted. After a store is deleted, its
  archive keeps the store name reserved (`STORE_NAME_RETAINED`) until the archive is gone.
- Details of the lock modes: https://docs.quantcdn.io/compute/kv-ledgers/

## Status and proof

```js
const status = await audit.ledgerStatus('audit');
// { name, state, collection, chains, headSeq, archivedSeq, lag, shards: [...], hasMoreShards, activeAfter?, retainUntil?, lastVerify? }

const proof = await audit.ledgerProof('audit', receipt.key);
// { status: 'pending' } until the entry is archived, then { status: 'archived', hash, period, archiveKey, ... }
```

- Both calls are read-only.
- `lag` is the archive lag in seconds; `archivedSeq` is the highest `seq` in the archive.

**Proof readiness is delayed.** An archive job runs about every 5 minutes on 5-minute periods, so an
entry reaches the archive about 6 minutes after the append, plus the job run time. The proof stays
`pending` until the entry is archived and the signed digest of its period exists, which can take up
to about an hour. `pending` is not a failure.

- Do not wait for a proof inside the request that appended (8 second call limit). Save
  `receipt.key` and ask for the proof later: a scheduled function, or the next request.
- Poll no more often than every 5 minutes. Start about 6 minutes after the append.
- If a proof is still `pending` after an hour, read `ledgerStatus`: a large `lag` or a shard with
  `broken` set means the archive job is behind or stopped. Contact Quant support for `broken`.

## Conformance example

One path that checks the whole contract: append, retry, status, proof, chain check. Run the append
part in one request and the proof part at least 6 minutes later (for example in a scheduled
function).

```js
// Request 1: append twice with the same key; the second call must replay.
const audit = kvStore.open(AUDIT_STORE);
const kv = kvStore.open(STATE_STORE);                          // an ordinary store for test state
const entry = { action: 'conformance', run: RUN_ID };
const first = await audit.append('audit:conformance', entry, { idempotencyKey: `${RUN_ID}-1` });
const again = await audit.append('audit:conformance', entry, { idempotencyKey: `${RUN_ID}-1` });
if (again.replayed !== true || again.key !== first.key || again.seq !== first.seq) throw new Error('no replay');
await kv.set(`conformance:${RUN_ID}`, { key: first.key, at: first.at });   // remember the key (any store)

// Request 2, 6 minutes or more later.
const saved = await kv.get(`conformance:${RUN_ID}`);
const status = await audit.ledgerStatus('audit');              // the ledger name, not the collection
if (status.state !== 'ACTIVE') throw new Error(`ledger ${status.state}`);
const proof = await audit.ledgerProof('audit', saved.key);
if (proof.status === 'pending') return new Response('pending, try later', { status: 202 });

const entries = [];
for await (const item of audit.list({ collection: 'audit:conformance', since: saved.at }).items({ maxPages: 10 })) entries.push(item);
const report = audit.verifyChain(entries);
return new Response(JSON.stringify({ proof: proof.status, ok: report.ok, problems: report.problems }), {
  headers: { 'Content-Type': 'application/json', 'Cache-Control': 'private, no-store' },
});
```

Expected: the second append replays the first receipt, the ledger is `ACTIVE`, the proof is
`archived` (or `pending` within the first hour), and `verifyChain` reports `ok: true`. A
`pending` result is a retry later, not a failure.

Verification of archives outside Quant, anchoring, offline proofs and erasure:
https://docs.quantcdn.io/compute/kv-ledgers/
