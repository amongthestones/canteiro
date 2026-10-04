# Canteiro

A native Mac editor for the Among the Stones site
([amongthestones/among-the-stones](https://github.com/amongthestones/among-the-stones)).
It edits the site's markdown, YAML and JSON in place, builds its forms from
the site's Keystatic config, handles photo and episode uploads to R2, and
commits and pushes to publish.

Status: step 1 of the plan. Browses the whole site with forms built from
the Keystatic config. Edits stay in memory: saving is step 2.

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
