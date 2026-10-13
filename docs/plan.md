# Canteiro: plan

Status: idea, sketch stage. 2026-10-04.

Clickable mockup of the main window:
https://claude.ai/artifact/F4cPZstdV3y75Vsw7usWF2

## Why

Keystatic covers the whole site, but it is a web page that only runs under
`astro dev`. iA Writer is a better place to write, but it sees frontmatter as
plain text. Zeku (zeku.dev) sits between the two but only reads markdown
collections. It misses the singletons, the YAML asides and the audio.

One SwiftUI app made for this site alone can do all of it. It only has to fit
one schema, so it stays small. Faro and Caixa already show the pattern: a
native front end over files and command-line tools.

## What it edits

| Content | Files | Format |
|---|---|---|
| Posts, pages, now, projects | `src/content/<type>/*.md` | Markdown + frontmatter |
| Asides | `src/content/asides/*.yaml` | YAML, 280 characters |
| Episodes, one list per show | `src/content/episodes/<show>/*.md` | Markdown + frontmatter |
| Show settings | `src/data/shows/<show>.json` | JSON |
| Fiction parts | `src/content/fiction/<series>/<work>/NN.md` | Markdown + frontmatter |
| Works | `src/data/works/*.yaml` | YAML |
| Tales pages | `src/content/tales-pages/*.md` | Markdown + frontmatter |
| Glossary, Tales settings | `src/data/glossary.yaml`, `src/data/tales.yaml` | YAML |
| Tags | `src/data/tags.json` | JSON |
| Landing page, Elsewhere, Site | `src/data/home.yaml`, `elsewhere-sources.yaml`, `site.json` | YAML, JSON |

## Shape

Three columns, like Mail or Notes.

```
┌────────────────┬──────────────────────┬──────────────────────────────────┐
│ WRITING        │ Posts           [+]  │ Draft ☐            Preview  ⌘P   │
│  Posts      12 │ ──────────────────── │                                  │
│  Asides     40 │ ● Leiras in October  │ Title  [Leiras in October      ] │
│  Pages       6 │   2026-10-02  draft  │ Kind   [Post ▾]  Lang [EN ▾]     │
│  Now         3 │ ○ Notes on CELGA 2   │ Tags   [galicia] [garden] [+]    │
│ PODCASTS       │   2026-09-28         │ Date   [2026-10-02 09:14]        │
│  Corríxeme   4 │ ○ A week in Lugo     │ ▸ More (excerpt, image, link,    │
│  Show settings │   2026-09-20         │   translation of)                │
│ TALES          │                      │ ──────────────────────────────── │
│  Parts      18 │                      │                                  │
│  Works       5 │                      │  The body, plain markdown, in a  │
│  Tales pages 2 │                      │  calm writing view.              │
│  Glossary      │                      │                                  │
│ SITE           │                      │                                  │
│  Tags          │                      │                                  │
│  Landing page  │                      │                                  │
│  Elsewhere     │                      │                                  │
├────────────────┴──────────────────────┴──────────────────────────────────┤
│ 3 changed files                                       [Review & Publish] │
└──────────────────────────────────────────────────────────────────────────┘
```

- **Sidebar:** the groups from the table above, with counts.
- **List:** entries newest first, with date and a draft marker. Singletons
  (Glossary, Tags, Landing page) skip the list and open straight into a form.
- **Editor:** the frontmatter as a form on top, the body below. Rare fields
  fold under "More" so the top stays short.
- **Bottom bar:** how many files changed since the last push, and one button
  to publish.

## The writing view

One text view with a toggle in the toolbar: **Markdown** or **Rich** (⌘R
switches, as in iA Writer).

- **Markdown:** the file as it is, in a mono font. Marks stay visible but
  faded, like iA Writer: `==`, `*`, `[^`, `##`, `^^^`.
- **Rich:** the same text with the marks hidden and the result shown:
  highlights, italics, headings, links, footnote numbers, callout boxes.

Rich is **not a separate editor** that converts to and from markdown. It's
the same text with the marks drawn differently (the way Bear and Obsidian's
live preview work). That's what keeps saves clean: what's on disk is exactly
what you typed, in both modes. A converting rich-text editor would rewrite
your markdown on every save (Keystatic's Markdoc editor already does this:
it drops `---:` table alignment).

Site syntax it must understand, from the site's remark/rehype plugins:

| Syntax | Markdown view | Rich view |
|---|---|---|
| `==text==` | faded `==`, yellow behind the text | yellow highlight |
| `[^note text]` (iA Writer inline footnote) | faded `[^ ]`, note text dimmed | superscript number, notes listed at the end |
| `^^^text^^^` and fenced `^^^` | faded `^^^` | callout box |
| `![alt](img "caption")` | as typed | image with caption under it |
| `[caption]…[/caption]` (old WordPress) | as typed | image with caption |
| `{{TOC}}` | as typed | a "Contents" placeholder chip |
| `## Transcript` (or Transcrición, Transcripción) | as typed | transcript section set apart |
| Tables | as typed, pipes and `\|---\|` faded | columns lined up, `:---:` alignment, grid lines |

How: TextKit 2 with styling from a markdown parse (Apple's swift-markdown,
which is cmark-gfm) plus small passes for the site-only syntax above. Those
passes copy what the remark/rehype plugins do. They're small and rarely
change, and the Preview pane shows the real site render if one ever drifts.

## The flows that matter

**New aside.** ⌘N from anywhere, or a global hotkey. A small window with a
text box, a live count to 280, and a language picker. Save writes the YAML
file. This should take five seconds.

**New episode.** Drag an MP3 onto the show's list or its empty editor. Three
steps show as chips while they run:

1. **Read length and size** with AVFoundation (what `npm run audio-info`
   does now with ffprobe, so no ffmpeg needed),
2. **Upload to R2** under `podcasts/<show>/`, with a progress bar,
3. **Fill in number and guid**: the next episode number, a guid like
   `corrixeme-5` (then locked), the date, and the feed link through OP3
   (`https://op3.dev/e/media.amongthestones.com/podcasts/<show>/<file>`).

The title field is then focused for you, with show notes under it. An
optional row takes a `.vtt` transcript the same way. A non-MP3 drop is
refused with a one-line message.

**Photos.** Drop a photo into a body (or onto the featured image field, or
use the toolbar's photo button). Before anything leaves the Mac, the app
applies the README's rules for R2:

1. resizes it to 1400px wide (never upscales),
2. encodes it as WebP at quality 75 (ImageIO),
3. strips all metadata, GPS location included,
4. checks it against the 200 KB target and says so (a green "Under 200 KB",
   or an orange "Over the target" for detailed landscapes),
5. uploads it to `uploads/YYYY/MM/<clean-name>.webp`.

A card shows each step as it runs, with before and after (for example
4032×3024 · 3.4 MB → 1400×1050 · 180 KB). Then the photo appears in place,
with fields for the caption and the alt text right under it. In Markdown
view it is the line `![alt](https://media.amongthestones.com/uploads/… "caption")`,
which is the caption form `rehype-figure-captions` expects. This replaces the
planned Mac script and iOS Shortcut (#61) for the Mac side, and it is the
step Keystatic can't do today (its image button is off for this reason).

**Tags.** A picker fed by `tags.json`. Typing a new tag asks "Add to the tag
list?" and writes it there too, so the build never fails on an unknown tag.

**Preview.** Start `astro dev` (Faro's code) and show the entry's page in a
web view beside the editor. Keystatic's `previewUrl` patterns give the
addresses.

**Publish.** A sheet with the changed files and a diff, a commit message
field, then commit and push with the system `git`. Cloudflare Pages builds
from the push as it does now.

## How it's made

- SwiftUI, macOS 26, Swift 6. One window plus the quick aside panel.
- Files read and written directly in the repo folder. No database, no cache
  beyond what's on screen.
- Forms built at run time from the Keystatic config (see below). Needs `node`
  and the repo's `node_modules`, which the site needs anyway.
- Frontmatter: a YAML library (Yams) for reading and writing. It must keep
  key order and leave unknown keys alone.
- R2: its S3-compatible API with keys in the Keychain. Or shell out to
  `rclone` if that turns out simpler.
- `git` and `ffprobe` through `Process`, as Faro and Caixa do.

## No copy of the schema: read Keystatic's config

The app holds no field list of its own. It reads `keystatic.config.ts`, the
same way Zeku reads Astro's schema, and builds every form from it.

`keystatic.config.ts` is the better source, not `src/content/config.ts`. It
already has everything a form needs: the singletons, the YAML and JSON data
files, labels, the help text under each field, select options, length limits,
paths and preview URLs. Astro's schema has types only.

**Tested 2026-10-04, works.** `scripts/schema-dump.mjs` (in this
repo) loads the config through the site's own Vite and prints it as JSON. It
reads all 10 collections and 8 singletons and gives every field its type.
It runs in about a quarter second.

How the app uses it:

1. On opening the site, and whenever `keystatic.config.ts` changes, the app
   runs the script with the repo's `node` and reads the JSON.
2. Each field type maps to one SwiftUI control: text (one line or multiline,
   with a counter if it has a max), integer, checkbox, select, multiselect,
   date, datetime, url, relationship (a picker over that collection), array,
   object, conditional (a select that swaps the fields under it), markdoc
   (the body).
3. Add a field in Keystatic and it shows up in the app on the next launch,
   with no app change.

What's left that the app knows by name, on purpose:

- **Site-specific actions:** filling the audio fields from an MP3, R2 upload
  for images, locking the guid, adding a tag to `tags.json`. These attach to
  field names (`audioUrl`, `guid`, `tags`). If one is renamed, the action
  stops and the plain field still works.
- **List labels.** Keystatic's `itemLabel` functions can't cross into JSON.
  The app shows the first text field instead (the term, the title).

One more benefit: Keystatic stays as the fallback because it has to. The app
needs its config, so the two can't drift apart.

## Not in v1

- Anything multi-user or iOS.
- Focus mode and syntax highlighting (iA Writer's nouns and verbs). Nice
  later, not needed first.

## Order of work

1. Read-only browser: sidebar, lists, and forms built from the Keystatic
   config. Proves the schema reading and the YAML round trip.
2. Editing and saving, then Publish. The Markdown view comes first; Rich
   follows once saves are proven byte-for-byte clean.
3. Quick aside window.
4. Photo drop: resize, WebP, strip metadata, upload to R2.
5. Episode drop with audio upload.
6. Preview pane.

Keystatic stays in the repo the whole time, as the fallback.

## Open questions

- Does the quick aside panel need to work from the menu bar, like Faro?
