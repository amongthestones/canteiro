# Canteiro

A native Mac editor for an Astro site that uses [Keystatic](https://keystatic.com). It edits the site's markdown, YAML and JSON files in place, makes its forms from the site's own `keystatic.config.ts`, uploads photos and podcast audio to Cloudflare R2, and publishes by committing and pushing with git.

It started as the editor for one site and is in daily use there, but nothing about any site is written into the app. What Canteiro can't learn from the Keystatic config comes from a small `canteiro.json` in the site's repo. Any Keystatic site should open; how well it fits yours depends on how closely your setup matches the requirements below.

- [What it does](#what-it-does)
- [What it needs](#what-it-needs)
- [Install](#install)
- [First run](#first-run)
- [The window](#the-window)
- [Editing](#editing)
- [New entries, search and trash](#new-entries-search-and-trash)
- [Quick asides](#quick-asides)
- [Photos](#photos)
- [Podcast episodes](#podcast-episodes)
- [The inbox: drafts from a writing app](#the-inbox-drafts-from-a-writing-app)
- [Preview](#preview)
- [Publish](#publish)
- [Settings](#settings)
- [canteiro.json](#canteirojson)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [How it works](#how-it-works)
- [Privacy](#privacy)
- [Limits](#limits)
- [Development](#development)

## What it does

- **Forms from your Keystatic config.** Every collection and singleton in `keystatic.config.ts` gets a sidebar row and a form, with Keystatic's labels, help text, options, defaults and length limits. Add a field in Keystatic and it appears in Canteiro the next time it opens the site.
- **Edits the files themselves.** No database and no copy of your content. A save writes the file, and only the lines you changed, so git diffs stay small.
- **Never writes over someone else's change.** If a file changes on disk while it's open (another editor, a `git pull`), Canteiro stops saving it and asks which version to keep.
- **Two views of the body.** Markdown shows the file as it is, with the marks faded. Rich hides the marks and shows the result: headings, bold, italics, links, quotes, lists and tables. Both edit the same text, so the file is always exactly what you typed.
- **Photos to R2.** Drop a photo into the body. It's resized, converted to WebP, stripped of its metadata (location included), uploaded, and linked in place.
- **Podcast episodes from an MP3.** Drop an MP3 on a show's list. It's measured, uploaded, and becomes a draft episode with its number, guid and duration filled in.
- **An inbox for drafts written elsewhere.** Point it at a folder your writing app saves to (iA Writer in iCloud, for example) and drafts written on a phone or another Mac show up, ready to edit and import.
- **Quick asides.** A small window for short posts, from the app or from anywhere with a global shortcut.
- **Preview.** The open entry as your site renders it, from the site's own `astro dev` server.
- **Publish.** Pick the changed files, read their diffs, write a message, and commit and push. Your host deploys from the push.

## What it needs

- **macOS 26** (Tahoe) or later.
- **Xcode 26** or its command line tools, to compile it. There's no signed download yet.
- **An Astro site with a `keystatic.config.ts`** at the root of its repo. Canteiro reads the config, so the site needs its `node_modules` installed (`npm install`).
- **Node.** Homebrew's is fine. Canteiro looks in `/opt/homebrew/bin`, `/usr/local/bin` and `~/.volta/bin`, then asks your login shell.
- **git, already signed in** to your remote (SSH keys or a credential helper). Canteiro never asks for a password: a push that needs one fails with a message instead of hanging.
- For photos: **`cwebp`** (`brew install webp`), since macOS can't write WebP on its own.
- For photos and audio: **a Cloudflare R2 bucket** with a public address, and an R2 API token with Object Read & Write on it. Without these, everything else still works.

## Install

```sh
git clone https://github.com/amongthestones/canteiro.git
cd canteiro
./scripts/package-app.sh               # makes Canteiro.app and installs it in /Applications
./scripts/package-app.sh --no-install  # makes it in dist/ only
```

To run it from the sources without installing:

```sh
swift run
```

The app isn't signed with a Developer ID, so a copy made on one Mac and opened on another will be stopped by Gatekeeper. Make your copy on the Mac you'll use it on.

## First run

1. **Open your site.** File › Open Site… (⌘O) and choose the folder with `keystatic.config.ts`. Canteiro remembers it and opens it next time.
2. **Wait a moment** while it reads the config through your site's own Vite. If that fails, the window says why: usually Node wasn't found or `node_modules` is missing.
3. **Add a `canteiro.json`** if you want uploads, podcast import, the inbox or your site's own markdown extras. See [canteiro.json](#canteirojson).
4. **For uploads,** open Settings (⌘,), enter your Cloudflare account ID and R2 API token, and choose Save and Check.

## The window

Three columns, like Mail.

- **Sidebar:** your collections and singletons, grouped the way your Keystatic config's `ui.navigation` groups them, with a count beside each collection. Anything the navigation leaves out goes in a last "Other" group, so nothing is hidden. Problems reading the site (a file that doesn't parse, a broken `canteiro.json`) are listed at the bottom.
- **List:** a collection's entries, newest first when it has a date field, else by its first number field. Drafts have an orange dot. Each row is the title, the date, and two lines of the text. Drag the divider to resize it.
- **Editor:** the entry's fields on top and the body below. Fields that are empty and optional fold under "More fields", so the top stays short. Singletons skip the list and open straight into their form.
- **Toolbar:** New Entry, the list filter, search, Markdown or Rich, Publish (with a count of changed files) and Preview.

## Editing

### Fields

Each Keystatic field type gets a native control:

| Keystatic field | In Canteiro |
|---|---|
| `text` (one line or multiline), `url` | a text field, with a character count when the field has a maximum length |
| `slug` | a text field with the address it makes shown under it |
| `integer` | a number field |
| `checkbox` | a switch |
| `select` | a menu |
| `multiselect` | the picked choices as tokens, with a menu to add more, or a single menu when only one can be picked |
| `date`, `datetime` | a date picker |
| `relationship` | a picker over the entries of the related collection |
| `array` | a list of items you can add to and remove from |
| `object` | its fields, grouped in a box |
| `conditional` | a menu that swaps in the fields for each choice |
| `file`, `image` | shown, not edited |

A field type Canteiro doesn't know is shown as text and left alone. Unknown keys in a file's frontmatter are kept as they are.

### The body

The body editor grows with its text, so the fields and the body scroll together as one page. Smart quotes and dash substitution are off: markdown is saved as typed.

- **Markdown view:** a monospaced font, with the marks (`#`, `**`, `[`, `](…)`, table pipes) faded but visible.
- **Rich view (⌘R):** a reading font with the marks hidden. Headings are sized, bold and italics shown, links underlined, quotes and list markers set back, and tables laid out in columns with grid lines and `:---:` alignment.

Rich is not a separate editor that converts to and from markdown. It's the same text drawn differently, so the file on disk is what you typed in either view.

Your site's own markdown extras can be styled too, if `canteiro.json` names them: `==highlights==`, iA Writer's `[^inline footnotes]`, `^^^callouts^^^` and `{{TOC}}`.

### Saving

- Changes save themselves a moment after you stop typing, on ⌘S, and when you leave the entry.
- In markdown and YAML files, a field you didn't touch keeps its original text, quoting and comments included. Changed and new fields are written the way Keystatic writes them.
- If the file changed on disk since Canteiro read it, nothing is saved. A bar offers "Use the File on Disk" or "Keep My Version".

## New entries, search and trash

- **New Entry (⌘N)** asks for a title, shows the address it will make, and creates the file with your config's defaults. If the collection has a `draft` checkbox, the new entry starts as a draft so a publish can't put it on the site half-written. In an aside collection, ⌘N opens the quick aside window instead; in a podcast collection, it asks for an MP3.
- **Search** filters the list by title.
- **Filter** shows drafts or published entries, or the entries with a given choice in any select field.
- **Move to Trash** (Delete, or right-click) moves the file to the Finder's Trash, so a slip can be put back from there, or from git until it's published.

## Quick asides

For a collection of short dated posts with no body (Canteiro spots it by shape: a date field and a text field, no content field).

- File › New Aside (⇧⌘A) in the app, or **⌃⌥A from any app**. The global shortcut needs no Accessibility permission.
- Type, pick a language if the collection has a select field whose key starts with `lang`, and press ⌘↩ to save.
- A count shows the characters left, from the text field's maximum length in your config (280 if it has none).
- The file is named from the date and time, like `2026-10-04-1032`.

## Photos

Drop a photo (JPEG, PNG, HEIC and the rest) into the body. Before anything leaves the Mac:

1. it's turned upright and resized to 1400 pixels wide, never wider than the original,
2. converted to WebP at quality 75,
3. stripped of all metadata, GPS location included,
4. uploaded to your bucket, in the photo folder from `canteiro.json` (by default `uploads/YYYY/MM/`), under a web-safe version of its file name.

A placeholder marks the spot while it works, then becomes `![](https://your.public.address/uploads/2026/10/name.webp)`. Add alt text between the brackets. A progress bar shows each upload, and errors appear in the same bar.

## Podcast episodes

For collections `canteiro.json` names as podcasts. Drop an MP3 on the show's list, or choose New Entry and pick one. Canteiro:

1. reads its length,
2. uploads it to the show's audio folder (by default `podcasts/<show>/`, where the show is the collection's folder name),
3. creates a draft episode titled "Episode N", with the next episode number, a guid such as `myshow-5`, the duration as `HH:MM:SS`, the audio address and `audio/mpeg` as its type.

The guid locks once it's set, since podcast apps track an episode by it. Field names and the guid pattern can be changed in `canteiro.json`.

## The inbox: drafts from a writing app

If `canteiro.json` has an `inbox`, a sidebar section lists the drafts in that folder, the newest first. It's meant for a writing app that syncs a folder, such as iA Writer in iCloud: write anywhere, then finish and publish on the Mac.

- **Watching:** the list updates when files are added, changed or removed, and when you switch back to Canteiro. Files iCloud hasn't downloaded yet are fetched.
- **Editing:** select a draft to edit its file in place, with the same body editor as an entry. It saves to the draft's own file. If the file changes elsewhere (your phone saved it) and you have no unsaved edits, the editor reloads; if you do, it asks which version to keep.
- **Import** makes the draft a new entry in the collection `canteiro.json` names, as a draft, and moves the file to an `Imported` folder inside the inbox, so each piece only lives in one place.
- **The title** comes from the draft's frontmatter `title`, else a `# heading` on its first line (taken out of the body, since your site shows the title), else the file name.
- **Frontmatter** in the draft is carried over for keys that match the collection's fields. Anything else stays in the draft. A tag that isn't in your site's tag list can still break the site's deploy, even on a draft.

Plain `.md`, `.markdown` and `.txt` files are listed. Folders and hidden files are skipped. Choose Folder… sets a different folder on this Mac only, over the one in `canteiro.json`.

## Preview

Preview (⌥⌘P) opens a window with the selected entry as your site renders it, using the collection's `previewUrl` from your Keystatic config.

- If an `astro dev` server is already running for this site (from a terminal or another tool), Canteiro uses it.
- If not, it starts one on a free port between 4321 and 4340, and stops it when Canteiro quits.

## Publish

Publish opens a sheet with every changed file and its diff, colored. Untick any you don't want in this commit. Canteiro suggests a message from the titles of what changed ("Edit Morning Walk and Tags", "Add Field Notes"), which you can rewrite.

It commits exactly the files you picked, nothing else that's staged, and pushes to your current branch with the system `git`. If the push is turned down because the remote has newer commits, it offers to pull them first (a rebase that sets any other work in progress aside while it runs) and push again.

## Settings

Settings (⌘,) holds what belongs to your Mac, not your site:

- **Cloudflare account ID.**
- **R2 API token:** the access key ID and secret, stored in your login keychain, never in a file.
- **Save and Check** tries the bucket from the open site's `canteiro.json` with these keys and says whether it worked.

The bucket and public address belong to the site and come from its `canteiro.json`. Settings shows them, read-only.

## canteiro.json

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

### inbox

| Key | Required | Meaning |
|---|---|---|
| `folder` | yes | The folder to watch. `~` is your home folder. The example is iA Writer's iCloud folder. |
| `importInto` | yes | The key of the collection drafts become entries of. |
| `app` | no | The writing app's name, used in the window's wording ("This draft changed in iA Writer…"). |

### uploads

| Key | Required | Meaning |
|---|---|---|
| `bucket` | yes | The R2 bucket's name. |
| `publicBase` | yes | The address the bucket is served at. Links in your content use it. |
| `photos` | no | The folder for photos. `{yyyy}` and `{mm}` are the year and month, in UTC. Default `uploads/{yyyy}/{mm}/`. |
| `audio` | no | The folder for episode audio. `{show}` is the collection's folder name. Default `podcasts/{show}/`. |

### podcasts

| Key | Required | Meaning |
|---|---|---|
| `collections` | yes | The keys of your episode collections. `*` matches any run of characters, so `episodes-*` covers `episodes-myshow` and `episodes-othershow`. A collection also needs its audio field to count. |
| `fields` | no | Your field names for the `audio` address, episode `number`, `guid` and `duration`. Defaults `audioUrl`, `episodeNumber`, `guid` and `duration`. |
| `guid` | no | The guid a new episode gets, from `{show}` and `{number}`. Default `{show}-{number}`. |

A field that isn't in the collection is skipped, so a show without, say, a duration field still imports.

### syntax

Markdown your site's remark or rehype plugins add, for the editor to style:

| Value | Syntax | In the Rich view |
|---|---|---|
| `highlight` | `==text==` | a yellow highlight |
| `inlineFootnotes` | `[^note text]` | the note small and raised |
| `callouts` | `^^^text^^^`, on one line or around several | a shaded box |
| `toc` | `{{TOC}}` | faded |

Only the editor reads this. How the site renders it is up to the site.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘N | New entry in the selected collection |
| ⇧⌘A | New aside |
| ⌃⌥A | New aside, from any app |
| ⌘↩ | Save the aside |
| ⌘S | Save now |
| ⌘R | Switch between Markdown and Rich |
| ⌥⌘P | Show or hide Preview |
| ⌘O | Open a site |
| ⇧⌘R | Reload the site (rereads the config, the files and `canteiro.json`) |
| ⌘, | Settings |
| Delete | Move the selected entry to the Trash |

## How it works

- **Reading the config.** `scripts/schema-dump.mjs` loads `keystatic.config.ts` through the site's own Vite, with the site's own Node, and prints it as JSON: the navigation, every collection and singleton, and every field with its type, label, help text, options, defaults and validation. It takes about a quarter of a second. Canteiro keeps no list of fields of its own.
- **Reading files.** Markdown with YAML frontmatter, YAML, and JSON (read as YAML). Collection paths ending in `*` (files in a folder) and `**` (files in any subfolder) both work.
- **Writing files.** For markdown and YAML, each save rebuilds the YAML from the original text one top-level key at a time: unchanged keys keep their exact text, and changed or new ones are written in Keystatic's style (block lists, two-space indents, quotes only where needed). The body is written exactly as typed. JSON files are written whole, as JSON. An unchanged entry is never rewritten.
- **The editor.** One TextKit 2 text view. Both views are attributes laid over the same text: Rich hides marks by drawing them tiny and clear, and lines table cells up by kerning the hidden pipe before each one. The grid is drawn behind the text.
- **Uploads.** R2's S3-compatible API, signed with AWS Signature V4 in the app (tested against Amazon's published example). No SDK.
- **git.** The system `git`, run as a subprocess, with prompts turned off.
- **Dependencies.** One Swift package, [Yams](https://github.com/jpsim/Yams), for YAML. Photos use ImageIO and `cwebp`; audio length uses AVFoundation.

## Privacy

- Canteiro sends nothing anywhere except your files to your own R2 bucket and your commits to your own git remote. There are no analytics, no crash reporting and no account.
- R2 keys are kept in your login keychain. The Cloudflare account ID and your choices (the open site, the inbox folder, Markdown or Rich) are in the app's preferences.
- Photos lose all their metadata, including location, before they're uploaded.

## Limits

- **Keystatic only.** A site whose content is described only by Astro's own collection schemas won't open. Canteiro needs `keystatic.config.ts`.
- **R2 only** for uploads. Other S3 services aren't wired up, and images can't be saved into the repo.
- **One site at a time**, and one person: no accounts, no sharing, no locking.
- **Mac only.** There's no iPhone or iPad version. The inbox is the way to write on the phone.
- **Not signed or notarized**, so you make your own copy from the sources.
- **Some field types are read-only:** `file`, `image`, and Keystatic's `document` and other rich-content fields. Canteiro shows them and leaves them unchanged.
- **Tables in Rich** use the colons for alignment but have no editing tools: you still type the pipes.
- **Keystatic's `itemLabel` functions** can't be read, so lists use the first text field as the title.

## Development

```sh
swift build
swift test
swift run
```

Most tests stand alone. Some open a real Keystatic site, edit a scratch copy of it and check the results: they run when `CANTEIRO_TEST_SITE` points to one, and are skipped otherwise. They find what they need by shape (a collection with drafts, the asides stream, podcast collections from `canteiro.json`), so any site works, and the site itself is never touched.

```sh
CANTEIRO_TEST_SITE=~/Sites/my-site swift test
```

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
| `BodyTextView.swift`, `MarkdownStyler.swift` | The body editor and its Markdown and Rich views |
| `Autosave.swift` | Saving and the changed-on-disk bar |
| `DraftInbox.swift`, `InboxView.swift` | The inbox |
| `QuickAside.swift` | The aside window and its global shortcut |
| `PhotoProcessor.swift`, `R2.swift` | Photos, R2 and the keychain |
| `PreviewServer.swift`, `PreviewPane.swift` | `astro dev` and the preview window |
| `Git.swift`, `PublishSheet.swift` | Changes, diffs, commit and push |
| `ListFilter.swift`, `NewEntry.swift` | The list filter and new entries |
| `Subprocess.swift` | Running Node, git and `cwebp` |

## License

MIT. See [LICENSE](LICENSE).
