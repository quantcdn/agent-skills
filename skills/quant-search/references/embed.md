# AI Search embed reference

Copy the snippet from the dashboard (Search, embed section) and use the host it contains; the site ID
is filled in. `EMBED-HOST` below stands for that host. Preview all variants in the
dashboard (Search, Preview) in light and dark themes before you put them on the site.

## Chat widget (floating button)

```html
<script src="https://EMBED-HOST/v1/widget.js" data-site-id="YOUR_SITE_ID"
        data-position="bottom-right" data-theme="light"></script>
```

| Attribute | Notes |
|---|---|
| `data-site-id` | Required |
| `data-position` | `bottom-right` (default) or `bottom-left` |
| `data-theme` | `light` (default) or `dark` |
| `data-color` | Accent colour, hex (dashboard) |
| `data-context-url` | Override the context URL for the chat (dashboard) |

Place the tag before `</body>`.

## Search page (inline)

```html
<div id="quant-search"></div>
<script src="https://EMBED-HOST/v1/search-page.js" data-site-id="YOUR_SITE_ID"
        data-container="quant-search" data-theme="auto"
        data-show-ai-answer="true" data-results-limit="10"></script>
```

| Attribute | Default | Notes |
|---|---|---|
| `data-site-id` | none | Required |
| `data-container` | `quant-search` | ID of the container element (required in the docs) |
| `data-theme` | `auto` in the dashboard snippet (docs: `light`) | `light`, `dark`, `auto` |
| `data-show-ai-answer` | `true` | `false` makes it a plain results page |
| `data-results-limit` | `10` | Results shown |

Style with CSS variables on the container: `--qs-bg-primary`, `--qs-bg-secondary`, `--qs-bg-card`,
`--qs-accent`, `--qs-accent-hover`, `--qs-text`, `--qs-text-secondary`, `--qs-border`,
`--qs-font-family`, `--qs-border-radius`.

## Modal search

```html
<div id="quant-search"></div>
<script src="https://EMBED-HOST/v1/modal-widget.js" data-site-id="YOUR_SITE_ID"
        data-container="quant-search" data-theme="auto" async></script>
```

Renders a trigger; opens on click or Cmd/Ctrl+K. Attributes: `data-site-id`, `data-container`
(default `quant-search`), `data-theme` (`light`, `dark`, `auto`), `data-color` (hex, default
`#00d4aa`), `data-placeholder` (default `Search...`), `data-show-ai-answer`, `data-results-limit`.
Open or close from script with `window.quantSearchModal.open()` and `.close()`.

## Iframe and direct link

`https://EMBED-HOST/v1/search.html?site=YOUR_SITE_ID` works in an `<iframe>` (width 100%, height 800)
or as a link. No style customisation.

## What the widget needs to work

- Public access on and the page host in Allowed domains (Search, Settings). Otherwise calls return 403.
- A non-empty index (Search, Index tab).
- Rate limits not exceeded; the widget then asks the visitor to try again shortly.
