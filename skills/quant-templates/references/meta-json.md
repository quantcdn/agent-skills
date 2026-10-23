# `quant/meta.json`

A template declares what it needs from Quant in `quant/meta.json`. The file is a JSON object, or an
array that holds one object; both are read the same way.

## Who reads it

| Reader | Keys it applies |
|---|---|
| Dashboard template wizard (templates in `quantcdn-templates`) | `requires_db`, `requires_cache`, `requires_s3`, `secrets` (apps); `kv_stores`, `project_settings` (static) |
| Studio publish (the Studio site's own repository) | `kv_stores`, `project_settings` |
| GitHub deploy workflow (`deploy-action`) | None. It reads `quant/edge-functions.json` and `quant/edge-rules.json` |

A repository you copy by hand, or a template in your own organisation, gets nothing from the
wizard: create the database, secrets, KV stores and settings yourself.

## Keys

| Key | Type | Kinds | Meaning |
|---|---|---|---|
| `template_type` | string | all | `"app"` (Quant Cloud), `"ssg"` (static), `"base"` (a base image) |
| `requires_db` | boolean | app | The wizard provisions a managed MySQL or Postgres database. The platform injects `DB_*` |
| `requires_cache` | boolean | app | The wizard pre-selects a managed cache. Attaching injects `REDIS_*` and `CACHE_PREFIX` |
| `requires_s3` | boolean | app | The wizard pre-selects object storage. Attaching injects `S3_*` |
| `secrets` | array | app | Each `{"name", "generate": "random", "length"}` becomes a random secret of `length` characters (default 64) on the `production` environment. Entries without `"generate": "random"` are ignored |
| `kv_stores` | array | static | KV stores to create, seed and link to the project (below) |
| `project_settings` | object | static | Only `enable_inline_fn` (boolean). Setup only turns a setting on; `false` changes nothing. Any other key fails setup |
| `title`, `summary`, `content`, `image`, `categories`, `tags`, `url` | | all | Describe the template. No effect on what is created |

App example:

```json
{
  "title": "Payload CMS",
  "summary": "Payload 3 headless CMS with Next.js and PostgreSQL.",
  "categories": ["javascript", "cms"],
  "template_type": "app",
  "requires_db": true,
  "secrets": [
    { "name": "PAYLOAD_SECRET", "generate": "random", "length": 64 }
  ]
}
```

A generated secret is set once, at creation. Other environments do not get production's secrets:
set them on each new environment. A change to a secret reaches the containers after a redeploy.

## `kv_stores`

A generic example (not any one template's file):

```json
{
  "template_type": "ssg",
  "requires_db": false,
  "kv_stores": [
    {
      "name": "appdata",
      "initial_values": [
        { "key": "settings", "value": { "name": "My site" } },
        { "key": "signing-key", "generate": { "bytes": 32 }, "encrypted": true },
        {
          "key": "auth:{sha256}",
          "generate": { "bytes": 32, "reveal": "once", "label": "Owner access key" },
          "value": { "name": "{user_name}", "role": "owner", "active": true }
        }
      ]
    }
  ],
  "project_settings": { "enable_inline_fn": true }
}
```

- `name`: lowercase, starts with a letter, at most 48 characters, unique in the file. The store ID is
  `<organisation>-<project>-<name>`; functions read the store by that ID (`quant-edge-functions-and-kv`).
- Limits: 10 stores, 100 initial values in total, 16 KiB per value, 64 KiB in total. An invalid
  declaration fails setup before any store is created.
- Setup creates each store, writes the initial values, then links the store to the project. A key
  that already exists is never replaced.

Three kinds of initial value:

| Kind | Declaration | What is stored |
|---|---|---|
| Plain value | `{"key", "value"}`, optional `"encrypted": true` | The value as given |
| Generated secret | `{"key", "generate": {"bytes": 16-64}}`, usually `"encrypted": true` | Random bytes as lowercase hex. Never shown, never rotated |
| One-time credential | `{"key": "...{sha256}...", "generate": {"bytes", "reveal": "once", "label"}, "value"}` | `value` under a key in which `{sha256}` is the SHA-256 hex of a random value. The setup screen shows the random value once; only the hash is stored |

- `{sha256}` appears exactly once, and only in the key of a one-time credential. A one-time credential
  cannot be `encrypted`. At most four per store.
- `{user_name}` in a `value` becomes the name of the person who creates the site (on Studio publish:
  the person who publishes).
- A lost one-time credential cannot be shown again. The template's README must explain how to add a
  new one (write a new record with the hash of a new value) and disable the old one.

Studio publish creates and links declared stores that the project does not link, and writes each
declared key at most once: a key someone deleted stays deleted. It never creates one-time
credentials; use the README steps.
