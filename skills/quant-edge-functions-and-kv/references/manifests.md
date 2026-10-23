# Function and rule manifests

Quant templates, Quant Studio, `quant` 7.0.1 and `quantcdn/deploy-action` v7.0.1 read the same two
files. Keep them in the repository; paths are relative to the repository root.

| Path | Holds |
|---|---|
| `quant/edge-functions.json` | The function manifest |
| `quant/edge-functions/*.js` | The function bodies |
| `quant/edge-rules.json` | The rules that run the functions |

The CLI and the action take the manifest paths as inputs, so other paths also work. Studio also
reads its earlier path `edge-functions/functions.json`; if both exist, `quant/edge-functions.json`
wins.

## `quant/edge-functions.json`

A JSON array. A manifest that is not an array (for example `{}`) is refused.

| Field | Required | Rule |
|---|---|---|
| `uuid` | Yes | `8-4-4-4-12` hex, unique in the manifest. The function's identity in the project |
| `path` | Yes | The function body file |
| `type` | Yes | `function`, `auth` or `filter`. `edge` means `function` |
| `description` | Yes | Not blank. Shown in the dashboard |
| `id` | No | `^[a-z][a-z0-9-]{0,47}$`, unique. The name that rules use in `function_ref` |

```json
[
  {
    "type": "function",
    "id": "whoami",
    "uuid": "00000000-0000-4000-8000-0000000000a1",
    "path": "quant/edge-functions/whoami.js",
    "description": "Who am I API. Bind to /api/whoami."
  },
  {
    "type": "auth",
    "id": "members-auth",
    "uuid": "00000000-0000-4000-8000-0000000000a2",
    "path": "quant/edge-functions/members-auth.js",
    "description": "Members session check"
  }
]
```

The UUIDs above are placeholders. Create real entries with `quant functions-add`, which writes a
new version 4 UUID.

UUID rules:

- No tool derives a UUID from `id`, the project or anything else. The committed `uuid` is used
  as written.
- Never change a `uuid` after the first deploy. A new UUID deploys a new function; the old one
  stays deployed, and rules or `{{QUANT_FN:...}}` tokens that name it keep running it.
- A UUID is scoped to its project, so every site created from one template can commit the same
  UUIDs, and Studio branch environments share them.
- `id` is only a name. Rename it freely, and update the rules that reference it.
- A function that a rule references needs an RFC 4122 UUID (version 1 to 5), because the rules
  API requires one. The manifest check alone accepts any `8-4-4-4-12` hex shape.

If any entry is invalid, `quant functions` and the deploy action list every problem and upload
nothing. Studio publish skips only the invalid entries and names them on its Deployments page.

## `quant/edge-rules.json`

```json
{
  "version": 1,
  "namespace": "site",
  "rules": [
    { "id": "members-auth", "type": "auth", "urls": ["/members/*"], "weight": -10, "function_ref": "members-auth" },
    { "id": "whoami", "type": "function", "urls": ["/api/whoami"], "weight": 10, "function_ref": "whoami" }
  ]
}
```

| Field | Rule |
|---|---|
| `version` | `1` |
| `namespace` | `^[a-z][a-z0-9-]{0,47}$`. A stable name for this set of rules. Do not change it |
| `rules[].id` | `^[a-z][a-z0-9-]{0,47}$`, unique in the file. The rule's identity in the namespace |
| `rules[].type` | `function`, `auth` (auth function) or `filter` (content filter) |
| `rules[].urls` | URL patterns, as for any rule (`*` matches one or more characters; see `quant-rules-and-routing`) |
| `rules[].weight` | Number from -100000 to 100000. Lower runs first. A negative weight runs before every rule added in the dashboard or API |
| `rules[].function_ref` | The `id` of a manifest entry with the same type |
| `rules[].function_uuid` | A raw UUID, only for a function the manifest does not define. Use `function_ref` or `function_uuid`, not both |
| Optional | `name`, `domains`, `methods`, `disabled` |

Limits: at most 100 rules and 64 KiB.

Behaviour of a deploy (`quant rules`, deploy-action `rules`, Studio publish):

- It changes only the rules with this `namespace` and an `id` from the file. Other rules stay.
- Removing a rule from the file does **not** delete it. Set `"disabled": true` to retire it.
- Deployed rules are read-only in the dashboard and the rules API (409 on edit). If someone
  changed one, the deploy writes nothing, exits non-zero and lists the changed fields.
  `--force` (action: `rules-force: true`) overwrites them; it never takes over a rule that the
  file did not create.
- Give an auth rule a lower `weight` than the function or content rules it protects.
- Deploy functions before rules, so that every UUID exists and is published. The deploy action
  does this for you.

## Credentials

| Step | Token | Base URL |
|---|---|---|
| Functions (`quant functions`, action `functions`) | Content token (`QUANT_TOKEN`, action `token`) | Content API: `https://api.quantcdn.io/v1` or `https://api.quantgov.cloud/v1` (action `endpoint`) |
| Rules (`quant rules`, action `rules`) | Project-scoped platform token with `projects:read`, `rules:read`, `rules:write` (`QUANT_API_TOKEN`, action `api-token`) | `{dashboard}/api/v2`: `https://dashboard.quantcdn.io/api/v2` or `https://dash.quantgov.cloud/api/v2` (`QUANT_BASE_URL`, action `api-base-url`) |

`quant rules` ignores `QUANT_TOKEN`. The rules base URL must be HTTPS and end in `/api/v2`.
Sites created from a Quant template get `QUANT_API_TOKEN` and `QUANT_BASE_URL` from template setup.
