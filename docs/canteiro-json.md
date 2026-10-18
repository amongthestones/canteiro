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
  "syntax": ["highlight", "inlineFootnotes", "callouts", "toc"]
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

| Value | Syntax | In the Rich view |
|---|---|---|
| `highlight` | `==text==` | a yellow highlight |
| `inlineFootnotes` | `[^note text]` | the note small and raised |
| `callouts` | `^^^text^^^`, on one line or around several | a shaded box |
| `toc` | `{{TOC}}` | faded |

Only the editor reads this. How the site renders it is up to the site.
