# Deploy behaviour reference

Checked against `@quantcdn/quant-cli` 7.0.1 source. Return to [SKILL.md](../SKILL.md).

## Order of work in `quant deploy`

1. Ping the API (fails with `Unable to connect to Quant`). Wrong customer, project, token or endpoint stops here.
2. If the project has no saved `enableIndexHtml`, save the current choice to `quant.json`.
3. Load the revision log, list all files under `dir` (every file, including dot-files), upload in
   batches of `--chunk-size` (default 10).
4. Save the revision log.
5. Unless `--skip-unpublish`: fetch the project's published records (500 per page), compare, unpublish
   the difference in batches.

## Per-file rules

- HTML files are sent as markup at a lowercased URL. Everything else is sent as a file at its path.
- A file already published with the same MD5 is skipped (`unchanged, md5 match`).
- With the revision log, a file whose path and MD5 are in the log is skipped locally, with no API call.
- `--force` ignores the log; the server still ignores an identical published file.
- Failed uploads print a warning, are not written to the log, and do not fail the command.

## What the unpublish step skips

- Paths present in `dir` after normalising (`index.html` stripped, lowercased, trailing slash ignored).
- Records of type redirect, edge function, edge auth and edge filter.
- Paths matching `--skip-unpublish-regex` (tested against the stored URL).
- If fetching the published records fails, the deploy ends "with warnings" and unpublishes nothing.

## Local files

| File | Written by | Notes |
|---|---|---|
| `quant.json` | `quant init`, first deploy with a project-level choice | Holds the token. Never commit it |
| `quant-revision-log_<project>` | Every `quant deploy` (or the path from `--revision-log`) | Safe to delete; the next deploy re-sends everything not already matching on the server |

## Export form submissions to CSV

```bash
#!/bin/sh
# Usage: ORG=... PROJECT=... TOKEN=... ENDPOINT=https://api.quantgov.cloud/v1 FORM=/contact ./export.sh > out.csv
page=1; tmp=$(mktemp)
while :; do
  curl -sf "$ENDPOINT/form-submissions?form_fields=*&page=$page&page_size=500" \
    -H "Quant-Customer: $ORG" -H "Quant-Project: $PROJECT" \
    -H "Quant-Token: $TOKEN" -H "Quant-Url: $FORM" > "$tmp.$page" || exit 1
  pages=$(jq .total_pages "$tmp.$page")
  [ "$page" -ge "$pages" ] && break
  page=$((page + 1))
done
jq -rs '[.[].forms[] | .form_data + {form_uuid, date_submitted, file_count}] as $rows
  | ($rows | map(keys) | add | unique) as $cols
  | $cols, ($rows[] | [ .[$cols[]] | if type=="array" then tostring else . end ]) | @csv' "$tmp".*
rm -f "$tmp" "$tmp".*
```

Compare the row count with `total_forms` before you send the file. `date_submitted` is Unix seconds (UTC).
