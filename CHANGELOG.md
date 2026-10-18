# Changelog

What changed in each version of Canteiro, newest first. Downloads are on [Releases](https://github.com/amongthestones/canteiro/releases).

## Unreleased

- File › Open Recent lists the sites you've opened, with ⌘1 to ⌘9 on the first ones. Switching back to a site lands on the section and entries you left it at. The inbox folder chosen with Choose Folder… now belongs to one site, and the preview server Canteiro started stops when you switch.
- An upload never replaces a file already on R2. If the name is taken, the new file goes up beside it as `-v2`, `-v3` and so on, so a feed can't end up listing a size that podcast apps don't get.
- A Sort menu beside Filter: Last Edited, Date Added or Title, as well as each list's usual order. Each list remembers its choice, and the rows show the date it sorts by.
- Image and file fields can be edited: choose, replace or remove a file, or drop one on the field. Images show a preview. The file is saved into the repo where Keystatic puts it, so either one can edit the entry.
- Moving an entry to the Trash takes its images and files with it, as Keystatic does.
- Settings has a General tab that checks the open site, its `keystatic.config.ts` and `canteiro.json`, where Publish pushes, the inbox folder, and the tools Canteiro runs (Node, git, cwebp, the site's packages), with a fix for anything missing.
- Settings › Uploads says when the Keychain won't save a key, trims spaces and quotes from pasted keys, warns about keys of the wrong length, and remembers the last check.
- A file that won't read no longer empties its whole list. The other entries still show, and Problems names the file.
- A Format menu with iA Writer's shortcuts: bold, italic, code, headings, lists, tasks and more. ⌘K turns the selected words into a link to the URL on the clipboard.
- Changing a conditional field's menu starts the fields under it fresh, as Keystatic does, so a value from the old choice can't stay behind. A choice with no fields under it no longer shows an empty row, and a small field under it (a menu, switch or number) sits on the same line as the menu.

## 0.1.0 (2026-10-13)

- First release, signed with a Developer ID and notarized by Apple.
