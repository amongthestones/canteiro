# Development

```sh
swift build
swift test
swift run    # runs it from the sources without installing
```

To make the app: `./scripts/package-app.sh` installs it in /Applications, and `--no-install` leaves it in `dist/`. A copy made this way is signed with your Developer ID if your keychain has one, so macOS treats each new build as the same app, and ad-hoc otherwise. Either way it isn't notarized, so Gatekeeper will stop it on another Mac.

`./scripts/package-app.sh --release` makes a signed, notarized `dist/Canteiro-<version>.zip`, with the version from the latest `v*` tag. It needs a Developer ID Application certificate and notarytool credentials saved once (the script's header shows the command).

## Tests

Most tests stand alone. Some open a real Keystatic site, edit a scratch copy of it and check the results: they run when `CANTEIRO_TEST_SITE` points to one, and are skipped otherwise. They find what they need by shape (a collection with drafts, the asides stream, podcast collections from `canteiro.json`), so any site works, and the site itself is never touched.

```sh
CANTEIRO_TEST_SITE=~/Sites/my-site swift test
```

## How it works

- **Reading the config.** `scripts/schema-dump.mjs` loads `keystatic.config.ts` through the site's own Vite, with the site's own Node, and prints it as JSON: the navigation, every collection and singleton, and every field with its type, label, help text, options, defaults and validation. It takes about a quarter of a second. Canteiro keeps no list of fields of its own.
- **Reading files.** Markdown with YAML frontmatter, YAML, and JSON (read as YAML). Collection paths ending in `*` (files in a folder) and `**` (files in any subfolder) both work.
- **Writing files.** For markdown and YAML, each save rebuilds the YAML from the original text one top-level key at a time: unchanged keys keep their exact text, and changed or new ones are written in Keystatic's style (block lists, two-space indents, quotes only where needed). The body is written exactly as typed. JSON files are written whole, as JSON. An unchanged entry is never rewritten.
- **The editor.** One TextKit 2 text view. Both views are attributes laid over the same text: Rich hides marks by drawing them tiny and clear, and lines table cells up by kerning the hidden pipe before each one. The grid is drawn behind the text.
- **Uploads.** R2's S3-compatible API, signed with AWS Signature V4 in the app (tested against Amazon's published example). No SDK.
- **git.** The system `git`, run as a subprocess, with prompts turned off.
- **Dependencies.** One Swift package, [Yams](https://github.com/jpsim/Yams), for YAML. Photos use ImageIO and `cwebp`; audio length uses AVFoundation.

Keystatic's `itemLabel` functions can't be read from the config, so lists use the first text field as each item's title.

## Source files

| File | What it does |
|---|---|
| `CanteiroApp.swift` | The app, its windows and menus |
| `SiteStore.swift` | The open site: its schema, entries, saves, new entries, uploads, episodes |
| `SiteConfig.swift` | Reads `canteiro.json` |
| `SchemaLoader.swift`, `Schema.swift` | Runs `schema-dump.mjs` and models the Keystatic config |
| `Content.swift`, `FieldValue.swift` | Reads entries and holds their values |
| `FileWriter.swift` | Writes entries back with the smallest change |
| `ContentView.swift`, `CollectionView.swift` | The sidebar, lists and layout |
| `EntryEditor.swift`, `FieldControl.swift`, `SettingsForm.swift` | Forms and field controls |
| `AssetField.swift` | Image and file fields, and where their files go |
| `BodyTextView.swift`, `MarkdownStyler.swift` | The body editor and its Markdown and Rich views |
| `FormatCommands.swift`, `MarkdownFormat.swift` | The Format menu and the edits it makes |
| `Autosave.swift` | Saving and the changed-on-disk bar |
| `DraftInbox.swift`, `InboxView.swift` | The inbox |
| `QuickAside.swift` | The aside window and its global shortcut |
| `PhotoProcessor.swift`, `R2.swift` | Photos, R2 and the keychain |
| `PreviewServer.swift`, `PreviewPane.swift` | `astro dev` and the preview window |
| `Git.swift`, `PublishSheet.swift` | Changes, diffs, commit and push |
| `ListFilter.swift`, `ListSort.swift`, `NewEntry.swift` | The list filter, the list order and new entries |
| `Subprocess.swift` | Running Node, git and `cwebp` |

## The icon

`Resources/AppIcon.icon` is in Icon Composer's format: a stone fill with a tau cut into it like a mason's mark. `scripts/make-icon.py` draws it, and `package-app.sh` compiles it with Xcode's `actool`, so macOS 26 can show it in its light, dark and tinted styles. Change the script and run it again rather than editing the icon by hand.
