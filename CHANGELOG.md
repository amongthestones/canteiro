# Changelog

What changed in each version of Canteiro, newest first. Downloads are on [Releases](https://github.com/amongthestones/canteiro/releases).

## Unreleased

- Sites on Astro 5 or later (Vite 8, Zod 4, `src/content.config.ts`) keep the extra rules from the Astro schema, such as a list capped at one item.
- Coming back to Canteiro after `keystatic.config.ts`, `canteiro.json` or the branch changed elsewhere reloads the site, so a form can't save a file in its old format.
- A branch menu in the toolbar shows the branch Publish commits to and switches the site to another one, including branches only on GitHub. It won't switch while committed files have unpublished edits. Make a Staging Branch starts a `staging` branch from `main` and pushes it, for trying things on a preview before they go live.
- A field you fill in no longer jumps from More fields to the top of the form while you type. The form keeps the layout it opened with.
- Rich is now called Read, the view for reading what you've written as it will look. ⌘R still switches to it.
- Read no longer adds extra space between paragraphs. Its lines are as tall as Markdown's, so switching views (⌘R) doesn't move the text.
- An entry's slug has its own row under the title and can be changed. Its file, image folders and image paths move with it. Renaming a live entry asks first and adds a redirect from the old address when `canteiro.json` names a `redirects` file.
- The sidebar's sections can be put in another order with View › Arrange Sections…, also on a heading's right-click menu. Each site keeps its own order.
- After Publish, the bar at the bottom of the window shows the site's build until it's live, or why it failed, from the checks Cloudflare Pages or Netlify report to GitHub. It uses the GitHub CLI (`gh`) you're signed in to.
- Publish is a sheet in the same style as the editor, tall enough to read the changes without much scrolling. Each file opens to a word-by-word diff that wraps instead of scrolling sideways, with removed words struck through.
- Discard Changes… in Publish puts a file back to the last commit. Your version goes to the Trash first.
- Preview is now Open in Browser (⌥⌘P): the entry opens in your browser from the site's dev server, drafts included, which Canteiro starts if need be. Read, with your site's look, is the reading view.
- Read shows photos. A `![](https://…)` on a line of its own shows as its photo, loaded in the background and kept for the session.
- Links in Read no longer leave a gap after them where their address is hidden.
- Read can look like your site: a `read` block in `canteiro.json` gives it the site's fonts, size, line height, reading width and colors, with separate colors for dark mode.
- The New Aside window's cursor lines up with the hint and starts in the right font, and its language menu no longer opens blank while the site is loading.
- An inbox folder in `canteiro.json` can be relative to the site, such as `inbox`.
- A demo site in `demo/` to try Canteiro on, with posts, asides, a podcast, pages and an inbox.
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
