# Changelog

What changed in each version of Canteiro, newest first. Downloads are on [Releases](https://github.com/amongthestones/canteiro/releases).

## Unreleased

- Image and file fields can be edited: choose, replace or remove a file, or drop one on the field. Images show a preview. The file is saved into the repo where Keystatic puts it, so either one can edit the entry.
- Moving an entry to the Trash takes its images and files with it, as Keystatic does.
- Settings has a General tab that checks the open site, its `keystatic.config.ts` and `canteiro.json`, where Publish pushes, the inbox folder, and the tools Canteiro runs (Node, git, cwebp, the site's packages), with a fix for anything missing.
- Settings › Uploads says when the Keychain won't save a key, trims spaces and quotes from pasted keys, warns about keys of the wrong length, and remembers the last check.
- A file that won't read no longer empties its whole list. The other entries still show, and Problems names the file.

## 0.1.0 (2026-10-13)

- First release, signed with a Developer ID and notarized by Apple.
