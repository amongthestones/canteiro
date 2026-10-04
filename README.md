# Canteiro

A native Mac editor for the Among the Stones site
([amongthestones/among-the-stones](https://github.com/amongthestones/among-the-stones)).
It edits the site's markdown, YAML and JSON in place, builds its forms from
the site's Keystatic config, handles photo and episode uploads to R2, and
commits and pushes to publish.

Status: planning. No app code yet.

- [docs/plan.md](docs/plan.md): what it does, how it's made, order of work
- [scripts/schema-dump.mjs](scripts/schema-dump.mjs): reads the Keystatic
  config as JSON (tested against the site)
- Clickable mockup of the main window:
  https://claude.ai/artifact/F4cPZstdV3y75Vsw7usWF2
