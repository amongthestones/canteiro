# Canteiro

A native Mac editor for the Among the Stones site
([amongthestones/among-the-stones](https://github.com/amongthestones/among-the-stones)).
It edits the site's markdown, YAML and JSON in place, builds its forms from
the site's Keystatic config, handles photo and episode uploads to R2, and
commits and pushes to publish.

Status: in daily use. Browse and edit the whole site with forms built from the
Keystatic config; new entries (⌘N) and Move to Trash; a filter for drafts, published and each choice field; autosave with clean diffs; Markdown and Rich views (⌘R);
quick asides (⇧⌘A, or ⌃⌥A from any app); photo and MP3 drops that upload to
R2; drafts from iA Writer's Blog folder in iCloud, imported as posts; a preview
window (⌥⌘P); Publish (commit and push).

Uploads need an R2 account ID and API token in Settings (⌘,), and `cwebp` for
WebP (`brew install webp`).

## The site's canteiro.json

Canteiro builds its forms from the site's Keystatic config. What it can't
learn there goes in `canteiro.json` at the site's root. Every block is
optional: a site without the file gets standard markdown, no inbox and no
MP3 import.

- `inbox`: a writing app's folder to import drafts from (`folder`, with `~`
  for home), the collection they become (`importInto`), and the app's name
  for the window (`app`).
- `uploads`: the R2 `bucket` and `publicBase` address, and the `photos` and
  `audio` folders, with `{yyyy}`, `{mm}` and `{show}`. The account and keys
  stay in Settings.
- `podcasts`: the episode `collections` (`*` matches anything), their
  `fields` (`audio`, `number`, `guid`, `duration`), and the `guid` a new
  episode gets, from `{show}` and `{number}`.
- `syntax`: markdown the site's plugins add: `highlight` (`==text==`),
  `inlineFootnotes` (`[^note]`), `callouts` (`^^^text^^^`) and `toc`
  (`{{TOC}}`).

Among the Stones' file is the full example.

## Run it

```sh
swift run                          # from the sources
./scripts/package-app.sh           # build Canteiro.app, install to /Applications
./scripts/package-app.sh --no-install
swift test                         # includes a read of the real site, if present
```

Needs Node (Homebrew's is fine) and the site's `node_modules`: the app reads
`keystatic.config.ts` through the site's own Vite.

- [docs/plan.md](docs/plan.md): what it does, how it's made, order of work
- [scripts/schema-dump.mjs](scripts/schema-dump.mjs): reads the Keystatic
  config as JSON (tested against the site)
- Clickable mockup of the main window:
  https://claude.ai/artifact/F4cPZstdV3y75Vsw7usWF2
