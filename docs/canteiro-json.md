# canteiro.json

What Canteiro can't learn from the Keystatic config goes in `canteiro.json` at the root of the site's repo. It travels with the site, so another Mac or a fresh clone gets the same setup.

Every block is optional. A site without the file gets plain Canteiro: standard markdown, no inbox, no MP3 import and no uploads. If the file has a mistake, the site still opens and the problem is listed in the sidebar, for example `canteiro.json: inbox: missing "importInto"`.

A full example:

```json
{
  "inbox": {
    "folder": "~/Library/Mobile Documents/27N4MQEA55~pro~writer/Documents/Blog",
    "importInto": "posts",
    "app": "iA Writer"
  },
  "uploads": {
    "bucket": "my-site-media",
    "publicBase": "https://media.example.com",
    "photos": "uploads/{yyyy}/{mm}/",
    "audio": "podcasts/{show}/"
  },
  "podcasts": {
    "collections": ["episodes-*"],
    "fields": {
      "audio": "audioUrl",
      "number": "episodeNumber",
      "guid": "guid",
      "duration": "duration"
    },
    "guid": "{show}-{number}"
  },
  "syntax": ["highlight", "inlineFootnotes", "callouts", "toc"],
  "redirects": "public/_redirects",
  "read": {
    "fonts": [
      "node_modules/@fontsource/noto-serif/files/noto-serif-latin-400-normal.woff2",
      "node_modules/@fontsource/noto-serif/files/noto-serif-latin-700-normal.woff2",
      "node_modules/@fontsource/noto-sans/files/noto-sans-latin-700-normal.woff2"
    ],
    "body": "Noto Serif",
    "headings": "Noto Sans",
    "size": 18,
    "lineHeight": 1.6,
    "headingSizes": [2, 1.625, 1.375, 1.125, 1, 1],
    "width": 675,
    "colors": { "text": "#222", "headings": "#111", "links": "#111", "background": "#fff" },
    "dark": { "text": "#c8c8c8", "headings": "#e8e8e8", "links": "#e8e8e8", "background": "#1c1914" }
  }
}
```

## inbox

| Key | Required | Meaning |
|---|---|---|
| `folder` | yes | The folder to watch. `~` is your home folder, and a relative path (`inbox`) is inside the site. The example is iA Writer's iCloud folder. |
| `importInto` | yes | The key of the collection drafts become entries of. |
| `app` | no | The writing app's name, used in the window's wording ("This draft changed in iA Writer…"). |

## uploads

| Key | Required | Meaning |
|---|---|---|
| `bucket` | yes | The R2 bucket's name. |
| `publicBase` | yes | The address the bucket is served at. Links in your content use it. |
| `photos` | no | The folder for photos. `{yyyy}` and `{mm}` are the year and month, in UTC. Default `uploads/{yyyy}/{mm}/`. |
| `audio` | no | The folder for episode audio. `{show}` is the collection's folder name. Default `podcasts/{show}/`. |

## podcasts

| Key | Required | Meaning |
|---|---|---|
| `collections` | yes | The keys of your episode collections. `*` matches any run of characters, so `episodes-*` covers `episodes-myshow` and `episodes-othershow`. A collection also needs its audio field to count. |
| `fields` | no | Your field names for the `audio` address, episode `number`, `guid` and `duration`. Defaults `audioUrl`, `episodeNumber`, `guid` and `duration`. |
| `guid` | no | The guid a new episode gets, from `{show}` and `{number}`. Default `{show}-{number}`. |

A field that isn't in the collection is skipped, so a show without, say, a duration field still imports.

## syntax

Markdown your site's remark or rehype plugins add, for the editor to style:

| Value | Syntax | In the Read view |
|---|---|---|
| `highlight` | `==text==` | a yellow highlight |
| `inlineFootnotes` | `[^note text]` | the note small and raised |
| `callouts` | `^^^text^^^`, on one line or around several | a shaded box |
| `toc` | `{{TOC}}` | faded |

Only the editor reads this. How the site renders it is up to the site.

## redirects

The site's `_redirects` file, relative to the site, such as `public/_redirects`. Cloudflare Pages and Netlify both read this format.

When you change the slug of an entry that's live (published and not a draft), its address changes and links to the old one would break. With this set, Canteiro adds a line sending the old address to the new one, under a `# Renamed in Canteiro` heading at the end of the file. Rules that already sent somewhere to the old address are pointed straight at the new one, so there's no chain. Addresses come from the collection's `previewUrl` in your Keystatic config.

Without it, Canteiro still warns before renaming a live entry, and the redirect is up to you.

## read

How the Read view looks, copied from your site's CSS so writing looks close to the published page. Markdown view keeps its monospaced look either way. Every key is optional, and anything left out stays as Canteiro's own.

| Key | Meaning |
|---|---|
| `fonts` | Font files to load, relative to the site: TTF, OTF, WOFF or WOFF2. `*` matches in the file name. List one file per weight and style you use: regular, bold, italic and bold italic for the body, bold for headings. Files under `node_modules` need `npm install` first. |
| `body` | The body's font family, as the files name it (`Noto Serif`), or any font installed on the Mac. |
| `headings` | The headings' font family, shown bold. |
| `size` | The body size in points. A CSS pixel is a point, so `font-size: 18px` (or `1.125em` on a 16px root) is `18`. |
| `lineHeight` | The CSS `line-height`, as a multiple of the size: `1.6`. |
| `headingSizes` | `h1` to `h6`, as multiples of the body size, as in the CSS's `em` values. |
| `width` | The reading column in points, so lines wrap where the site's do. A `max-width: 37.5em` column at 18px is `675`. |
| `colors` | Hex colors for `text`, `headings`, `links` and the page `background`. |
| `dark` | The same colors for dark mode. Without them, dark mode keeps Canteiro's own colors, so dark text never lands on a dark window. |

If a font file or family isn't found, or a color isn't hex, Read uses Canteiro's own for that part and the problem is listed in the sidebar, for example `canteiro.json: read: no font named "Noto Serif"`.
